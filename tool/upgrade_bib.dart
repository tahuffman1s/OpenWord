// Rewrites a .bib file in the current format.
//
//   dart run tool/upgrade_bib.dart <file.bib> [more.bib ...]
//
// Version 1 files stay readable, so this is never required. It is worth
// doing anyway: version 2 is seekable, so the app opens a book rather than a
// whole Bible, and it carries what version 1 could not say — the language,
// the script, the verse numbering, the text's own checksum.
//
// Nothing is written until the new file has been read back and compared
// with the old one verse by verse.
import 'dart:io';

import 'package:openword/src/data/translations.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/upgrade_bib.dart <file.bib> ...');
    exitCode = 2;
    return;
  }
  for (final path in args) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('$path: no such file');
      exitCode = 1;
      continue;
    }
    if (!_upgrade(file)) exitCode = 1;
  }
}

bool _upgrade(File file) {
  final before = file.readAsBytesSync();
  final Bible old;
  try {
    old = BibFile.decode(before, verify: true);
  } on Object catch (error) {
    stderr.writeln('${file.path}: unreadable — $error');
    return false;
  }

  // A version 1 file said nothing about its language or its verse numbering.
  // Where the app ships this translation itself, those are known.
  final declared = Translations.all
      .where((t) => t.id == old.translation.id)
      .firstOrNull;
  final info = declared == null
      ? old.translation
      : old.translation.copyWith(
          language: declared.language,
          script: declared.script,
          direction: declared.direction,
          versification: declared.versification,
          attribution: declared.attribution,
        );

  final after = BibFile.encode(
    Bible(
      translation: info,
      // Reading every book here is the point: the upgrade is only sound if
      // all of it comes out.
      books: [
        for (final book in old.books)
          Book(meta: book.meta, chapters: book.chapters),
      ],
    ),
  );

  final check = BibFile.decode(after, verify: true);
  final complaint = _compare(old, check);
  if (complaint != null) {
    stderr.writeln('${file.path}: $complaint — left alone');
    return false;
  }

  file.writeAsBytesSync(after);
  final delta = (after.length / before.length - 1) * 100;
  stdout.writeln(
    '${file.path}: ${_mb(before.length)} -> ${_mb(after.length)} '
    '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%), '
    '${check.books.length} books, ${check.verseCount} verses, '
    '${info.language}/${info.versification}',
  );
  return true;
}

/// Null when the two hold the same Scripture.
String? _compare(Bible before, Bible after) {
  if (before.books.length != after.books.length) {
    return '${before.books.length} books in, ${after.books.length} out';
  }
  if (before.verseCount != after.verseCount) {
    return '${before.verseCount} verses in, ${after.verseCount} out';
  }
  for (final book in before.books) {
    final other = after.bookByCode(book.code);
    if (other == null) return '${book.code} went missing';
    if (other.chapterCount != book.chapterCount) {
      return '${book.code} changed length';
    }
    for (var c = 1; c <= book.chapterCount; c++) {
      final a = book.chapter(c)!;
      final b = other.chapter(c)!;
      if (a.number != b.number) return '${book.code} $c was renumbered';
      if (a.notes.length != b.notes.length) {
        return '${book.code} $c lost a footnote';
      }
      for (var v = 1; v <= a.verseCount; v++) {
        if (a.verseText(v) != b.verseText(v)) {
          return '${book.code} $c:$v came back different';
        }
      }
    }
  }
  return null;
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
