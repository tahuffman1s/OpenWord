// Turns USFX source files into the .bib files the app ships with.
//
//   dart run tool/build_assets.dart <dir-with-usfx-files>
//
// Every translation listed in lib/src/data/translations.dart needs its USFX
// in that directory, in whatever shape it arrived: eBible.org hands out
// `eng-web_usfx.zip` holding `eng-web_usfx.xml`, so the zip, the xml inside
// it, and a renamed `eng-web.usfx.xml` are all read without unpacking or
// renaming anything by hand. The output goes to assets/bible/.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:openword/src/data/translations.dart';
import 'package:openword/src/data/usfx_parser.dart';
import 'package:openword/src/model/bib_file.dart';

/// The USFX for a translation, however the source it came from names it.
///
/// A rebuild is rare and the sources are fetched by hand, so the one thing
/// this must not do is fail with "missing" over a file that is sitting
/// right there under the name its publisher gave it.
String? _usfxFor(Directory source, String id) {
  if (!source.existsSync()) return null;
  final wanted = [
    '$id.usfx.xml',
    '${id}_usfx.xml',
    '$id.xml',
    '$id.usfx.zip',
    '${id}_usfx.zip',
    '$id.zip',
  ];
  final byName = <String, File>{};
  for (final entry in source.listSync()) {
    if (entry is File) {
      byName[entry.uri.pathSegments.last.toLowerCase()] = entry;
    }
  }
  for (final name in wanted) {
    final file = byName[name.toLowerCase()];
    if (file == null) continue;
    if (!name.endsWith('.zip')) return file.readAsStringSync();
    // The zip an eBible download arrives as: take the one XML inside it.
    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    for (final member in archive.files) {
      if (member.isFile && member.name.toLowerCase().endsWith('.xml')) {
        return String.fromCharCodes(member.content as List<int>);
      }
    }
  }
  return null;
}

void main(List<String> args) {
  final source = Directory(args.isEmpty ? '.' : args.first);
  final outputDir = Directory('assets/bible')..createSync(recursive: true);

  for (final translation in Translations.all) {
    final usfx = _usfxFor(source, translation.id);
    if (usfx == null) {
      stderr.writeln(
        'missing USFX for ${translation.id} in ${source.path} — looked for '
        '${translation.id}.usfx.xml, ${translation.id}_usfx.xml and the '
        'zip either comes in',
      );
      exitCode = 1;
      continue;
    }
    final started = DateTime.now();
    final bible = UsfxParser.parse(usfx, translation);
    final bytes = BibFile.encode(bible);
    final output = File(
      '${outputDir.path}/${translation.id}${Translations.assetExtension}',
    )..writeAsBytesSync(bytes);

    // Decoding here is a build-time check that what ships can be read back:
    // every chunk's checksum, the header a shelf lists from, and the
    // Scripture behind it, book by book down to the words.
    final roundTripped = BibFile.decode(bytes, verify: true);
    if (roundTripped.verseCount != bible.verseCount ||
        BibFile.readInfo(bytes).id != translation.id) {
      stderr.writeln('round trip mismatch for ${translation.id}');
      exitCode = 1;
    }
    for (final book in bible.books) {
      final other = roundTripped.bookByCode(book.code);
      if (other == null || other.chapterCount != book.chapterCount) {
        stderr.writeln('${translation.id}: ${book.code} did not survive');
        exitCode = 1;
        continue;
      }
      for (var c = 1; c <= book.chapterCount; c++) {
        final before = book.chapter(c)!;
        final after = other.chapter(c)!;
        for (var v = 1; v <= before.verseCount; v++) {
          if (before.verseText(v) != after.verseText(v)) {
            stderr.writeln(
              '${translation.id}: ${book.code} $c:$v came back different',
            );
            exitCode = 1;
          }
        }
      }
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
