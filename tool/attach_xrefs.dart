// Puts a set of cross-references inside a .bib file.
//
//   dart run tool/attach_xrefs.dart <file.bib> <xrefs.owx.gz>
//
// A translation that carries its own references is better off than one
// relying on the app's bundled English set in every way that matters: they
// are anchored to its own verse numbering, so they are right even where the
// bundled set would land on the wrong verse, and they travel with the file.
//
// The chunk is ancillary, so a file gains it without becoming unreadable to
// anything written before this.
import 'dart:io';
import 'dart:typed_data';

import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/xref_codec.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/attach_xrefs.dart <file.bib> <xrefs.owx.gz>',
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

  final refs = Uint8List.fromList(source.readAsBytesSync());
  // Read them here, so a bad file is caught before anything is written.
  final int count;
  try {
    count = XrefCodec.unpack(refs).length;
    if (count == 0) throw const FormatException('no references in it');
  } on Object catch (error) {
    stderr.writeln('${source.path}: not a readable set — $error');
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

  final out = BibFile.encode(
    bible,
    carry: {...bible.extras, XrefCodec.chunkTag: refs},
  );

  // Read back before replacing anything.
  final check = BibFile.decode(out, verify: true);
  final attached = check.extras[XrefCodec.chunkTag];
  if (attached == null || XrefCodec.unpack(attached).length != count) {
    stderr.writeln(
      '${target.path}: the references did not survive — left alone',
    );
    exitCode = 1;
    return;
  }

  target.writeAsBytesSync(out);
  stdout.writeln(
    '${target.path}: $count verses of cross-references '
    '(${(refs.length / 1024).round()} kB) attached, anchored to '
    '${bible.translation.versification} numbering',
  );
  stdout.writeln('  chunks now: ${BibFile.tags(out).join(', ')}');
}
