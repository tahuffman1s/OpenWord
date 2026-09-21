// Checks a .bib file, thoroughly.
//
//   dart run tool/bib_lint.dart <file.bib> [more.bib ...]
//
// Written to be useful to anyone implementing the format, not only to this
// app: it says what it checked and what it found, and exits non-zero on the
// first file that is wrong. The format is specified in docs/bib-format.md.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/bib_lint.dart <file.bib> ...');
    exitCode = 2;
    return;
  }
  var bad = 0;
  for (final path in args) {
    if (!_check(path)) bad++;
  }
  if (args.length > 1) {
    stdout.writeln('\n${args.length - bad} of ${args.length} files are sound.');
  }
  if (bad > 0) exitCode = 1;
}

bool _check(String path) {
  stdout.writeln(path);
  final file = File(path);
  if (!file.existsSync()) {
    _bad('no such file');
    return false;
  }
  final bytes = Uint8List.fromList(file.readAsBytesSync());
  _note('${_kb(bytes.length)} on disk');

  if (!BibFile.looksLikeBib(bytes)) {
    _bad('does not begin with BIB');
    return false;
  }
  final version = bytes[3];
  _note('format version $version');

  var sound = true;

  // Chunks. A version 1 file has none, and that is not a fault.
  if (version >= 2) {
    final List<String> tags;
    try {
      tags = BibFile.tags(bytes);
    } on Object catch (error) {
      _bad('the chunk stream is broken: $error');
      return false;
    }
    _note('chunks: ${tags.join(', ')}');
    for (final tag in tags) {
      if (tag != BibFile.tagMeta &&
          tag != BibFile.tagText &&
          !BibFile.reservedTags.contains(tag)) {
        final critical = tag.codeUnitAt(0) >= 0x41 && tag.codeUnitAt(0) <= 0x5a;
        if (critical) {
          _bad('$tag is critical and unknown, so no reader may open this');
          sound = false;
        } else {
          _note('$tag is unknown, and may be skipped');
        }
      }
    }
    for (final required in const ['META', 'TEXT']) {
      if (!tags.contains(required)) {
        _bad('the $required chunk is missing');
        sound = false;
      }
    }
  }

  // Checksums.
  try {
    BibFile.decode(bytes, verify: true);
    _ok(version >= 2 ? 'every chunk matches its checksum' : 'reads');
  } on Object catch (error) {
    _bad('$error');
    return false;
  }

  final Bible bible;
  try {
    bible = BibFile.decode(bytes);
  } on Object catch (error) {
    _bad('$error');
    return false;
  }
  final info = bible.translation;
  _note('${info.name} (${info.abbreviation}), ${info.id}');
  _note(
    '${info.language}${info.script.isEmpty ? '' : '/${info.script}'}, '
    '${info.direction.key}, versification ${info.versification}',
  );
  if (info.id.isEmpty) {
    _bad('the file gives no id, so nothing can refer to it');
    sound = false;
  }
  if (info.versification == Versification.unknown && version >= 2) {
    _warn(
      'no versification named: anything anchored to a verse — '
      'cross-references, an interlinear — cannot know this lines up',
    );
  }
  if (info.license.isEmpty) _warn('no licence named');

  // The outline has to agree with the text it stands for, or navigation
  // will point at verses that are not there.
  var chapters = 0;
  var verses = 0;
  for (final book in bible.books) {
    chapters += book.chapterCount;
    for (var c = 1; c <= book.chapterCount; c++) {
      final outlined = book.verseCountAt(c);
      verses += outlined;
      final actual = book.chapter(c)!.verseCount;
      if (actual != outlined) {
        _bad(
          '${book.code} chapter $c: the outline says $outlined verses, '
          'the text has $actual',
        );
        sound = false;
      }
    }
  }
  _ok(
    '${bible.books.length} books, $chapters chapters, $verses verses, '
    'and the outline agrees with all of it',
  );

  // What the metadata claims about the text.
  if (version >= 2) {
    final meta = BibFile.chunk(bytes, BibFile.tagMeta);
    final text = BibFile.chunk(bytes, BibFile.tagText);
    if (meta != null && text != null) {
      final claimed = (jsonDecode(utf8.decode(meta)) as Map)
          .cast<String, Object?>();
      final hash = 'sha256:${sha256.convert(text)}';
      if (claimed['contentHash'] != null && claimed['contentHash'] != hash) {
        _bad('the metadata\'s contentHash is not this Scripture\'s');
        sound = false;
      } else if (claimed['contentHash'] != null) {
        _ok('contentHash matches the Scripture');
      }
      for (final entry in {
        'books': bible.books.length,
        'verses': verses,
      }.entries) {
        final said = claimed[entry.key];
        if (said != null && said != entry.value) {
          _bad(
            'the metadata says ${entry.value} ${entry.key} '
            'but claims $said',
          );
          sound = false;
        }
      }
    }
  }

  if (sound) _ok('sound');
  stdout.writeln('');
  return sound;
}

void _ok(String message) => stdout.writeln('  ok    $message');
void _note(String message) => stdout.writeln('        $message');
void _warn(String message) => stdout.writeln('  warn  $message');
void _bad(String message) => stdout.writeln('  BAD   $message');

String _kb(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} kB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
