// Puts the Hebrew and Greek inside a .bib file.
//
//   dart run tool/attach_originals.dart <file.bib> <originals.ows.gz>
//
// A translation that carries its own original-language layer is better off
// than one relying on the app's bundled asset in both ways that matter: it
// is keyed to that translation's own verse numbering, so it is right even
// where the bundled layer would hand back a neighbouring verse's words, and
// it travels with the file — anything that reads the format has the Hebrew
// and Greek without a four-megabyte asset of its own.
//
// The layer is cut down to the verses the Bible actually has, so a New
// Testament carries the Greek and not the whole Hebrew Bible with it.
//
// The chunk is ancillary, so a file gains it without becoming unreadable to
// anything written before this.
import 'dart:io';
import 'dart:typed_data';

import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/strongs_codec.dart';
import 'package:openword/src/model/strongs_scope.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/attach_originals.dart <file.bib> '
      '<originals.ows.gz>',
    );
    exitCode = 2;
    return;
  }
  final target = File(args[0]);
  final source = File(args[1]);
  for (final file in [target, source]) {
    if (!file.existsSync()) {
      stderr.writeln('${file.path}: no such file');
      exitCode = 1;
      return;
    }
  }

  // Read the layer here, so a bad file is caught before anything is
  // written.
  final StrongsReader whole;
  try {
    whole = StrongsCodec.unpack(
      Uint8List.fromList(source.readAsBytesSync()),
    );
    if (whole.verseCount == 0) {
      throw const FormatException('no verses in it');
    }
  } on Object catch (error) {
    stderr.writeln('${source.path}: not a readable layer — $error');
    exitCode = 1;
    return;
  }

  final Bible bible;
  try {
    bible = BibFile.decode(
      Uint8List.fromList(target.readAsBytesSync()),
      verify: true,
    );
  } on Object catch (error) {
    stderr.writeln('${target.path}: $error');
    exitCode = 1;
    return;
  }

  if (!Versification.mayAnchorEnglish(bible.translation.versification)) {
    stderr.writeln(
      '${target.path}: this Bible is marked as numbering its verses '
      'differently, so this layer would hand back the wrong words. '
      'Attach one keyed to its own numbering instead.',
    );
    exitCode = 1;
    return;
  }

  final trimmed = trimOriginalsTo(whole, originalsKeysOf(bible));
  final read = StrongsReader.parse(trimmed);
  if (read.verseCount == 0) {
    stderr.writeln(
      '${target.path}: none of this Bible has Hebrew or Greek behind it',
    );
    exitCode = 1;
    return;
  }

  final packed = StrongsCodec.deflate(trimmed);
  final out = BibFile.encode(
    bible,
    carry: {...bible.extras, StrongsCodec.chunkTag: packed},
  );

  // Read back before replacing anything.
  final check = BibFile.decode(out, verify: true);
  final attached = check.extras[StrongsCodec.chunkTag];
  if (attached == null ||
      StrongsCodec.unpack(attached).verseCount != read.verseCount) {
    stderr.writeln(
      '${target.path}: the layer did not survive — left alone',
    );
    exitCode = 1;
    return;
  }

  target.writeAsBytesSync(out);
  stdout.writeln(
    '${target.path}: ${read.verseCount} verses of Hebrew and Greek and '
    '${read.entryCount} dictionary entries '
    '(${(packed.length / 1024).round()} kB) attached, keyed to '
    '${bible.translation.versification} numbering',
  );
  if (read.verseCount < whole.verseCount) {
    stdout.writeln(
      '  cut from ${whole.verseCount} verses to the ones this Bible has',
    );
  }
  stdout.writeln('  chunks now: ${BibFile.tags(out).join(', ')}');
}
