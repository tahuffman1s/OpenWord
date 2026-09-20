// Turns USFX source files into the .bib files the app ships with.
//
//   dart run tool/build_assets.dart <dir-with-usfx-files>
//
// Every translation listed in lib/src/data/translations.dart is expected to
// have <id>.usfx.xml in that directory. The output goes to assets/bible/.
import 'dart:io';

import 'package:openword/src/data/translations.dart';
import 'package:openword/src/data/usfx_parser.dart';
import 'package:openword/src/model/bib_file.dart';

void main(List<String> args) {
  final source = Directory(args.isEmpty ? '.' : args.first);
  final outputDir = Directory('assets/bible')..createSync(recursive: true);

  for (final translation in Translations.all) {
    final input = File('${source.path}/${translation.id}.usfx.xml');
    if (!input.existsSync()) {
      stderr.writeln('missing ${input.path}');
      exitCode = 1;
      continue;
    }
    final started = DateTime.now();
    final bible = UsfxParser.parse(input.readAsStringSync(), translation);
    final bytes = BibFile.encode(bible);
    final output = File(
      '${outputDir.path}/${translation.id}${Translations.assetExtension}',
    )..writeAsBytesSync(bytes);

    // Decoding here is a build-time check that what ships can be read back —
    // both the header a shelf lists from and the Scripture behind it.
    final roundTripped = BibFile.decode(bytes);
    if (roundTripped.verseCount != bible.verseCount ||
        BibFile.readInfo(bytes).id != translation.id) {
      stderr.writeln('round trip mismatch for ${translation.id}');
      exitCode = 1;
    }

    stdout.writeln(
      '${translation.id.padRight(14)} '
      'books=${bible.books.length.toString().padLeft(3)} '
      'verses=${bible.verseCount.toString().padLeft(6)} '
      'bib=${_mb(bytes.length)} '
      '(${DateTime.now().difference(started).inMilliseconds} ms) '
      '-> ${output.path}',
    );
  }
}

String _mb(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB'.padLeft(8);
