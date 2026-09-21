// Writes the .bib conformance corpus.
//
//   dart run tool/build_bib_corpus.dart
//
// A format nobody else can implement is a private encoding with extra steps.
// These files are the fixed point another implementation can test itself
// against, and what this app's own test/bib_corpus_test.dart reads: each one
// is named for what a reader is supposed to do with it.
//
// They are small on purpose — two books, a handful of verses — so they can
// live in the repository and be read by hand.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/bible_codec.dart';
import 'package:openword/src/model/book_meta.dart';
import 'package:openword/src/model/byte_io.dart';

const String outputDir = 'test/corpus';

void main() {
  final dir = Directory(outputDir)..createSync(recursive: true);
  final bible = _sample();
  final valid = BibFile.encode(bible);

  final written = <String, String>{};
  void write(String name, List<int> bytes, String what) {
    File('${dir.path}/$name').writeAsBytesSync(bytes);
    written[name] = what;
    stdout.writeln(
      '${name.padRight(28)} ${bytes.length.toString().padLeft(6)}'
      '  $what',
    );
  }

  write('valid-v2.bib', valid, 'reads; two books, seekable');
  write(
    'valid-v2-stored.bib',
    BibFile.encode(bible, compress: false),
    'reads; the same, with the books left uncompressed',
  );
  write('valid-v1.bib', _v1(bible), 'reads; the older single-stream format');

  write(
    'ancillary-unknown.bib',
    _withChunk(valid, 'zzzz', utf8.encode('something a later version added')),
    'reads; an unknown lower-case chunk must be skipped',
  );
  write(
    'critical-unknown.bib',
    _withChunk(valid, 'ZZZZ', utf8.encode('something a reader must know')),
    'refused; an unknown upper-case chunk must stop the read',
  );

  final badCrc = Uint8List.fromList(valid);
  // Flip a bit inside the TEXT payload, leaving its checksum as it was.
  badCrc[badCrc.length - 20] ^= 0x01;
  write('damaged-crc.bib', badCrc, 'refused when verifying: TEXT is damaged');

  final future = Uint8List.fromList(valid);
  future[3] = BibFile.version + 1;
  write('future-version.bib', future, 'refused; a version this cannot read');

  write(
    'truncated.bib',
    Uint8List.sublistView(valid, 0, valid.length ~/ 2),
    'refused; stops in the middle of a chunk',
  );
  write(
    'header-only.bib',
    Uint8List.sublistView(valid, 0, 6),
    'refused as Scripture; carries no chunks at all',
  );
  write(
    'not-a-bib.bib',
    Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0]),
    'refused; this is a zip',
  );

  File('${dir.path}/README.md').writeAsStringSync(_readme(written));
  stdout.writeln('\n-> ${dir.path}/README.md');
}

/// Two books, a few verses, every block kind the format can carry.
Bible _sample() => Bible(
  translation: const TranslationInfo(
    id: 'xx-corpus',
    name: 'Conformance Corpus',
    abbreviation: 'COR',
    license: 'CC0',
    sourceUrl: 'https://example.invalid/corpus',
    language: 'en',
    script: 'Latn',
    versification: Versification.english,
    attribution: 'Nobody in particular.',
  ),
  books: [
    Book(
      meta: BookMeta.lookup('GEN')!,
      chapters: [
        Chapter(
          number: 1,
          blocks: [
            const Block(
              style: BlockStyle.paragraph,
              segments: [
                VerseSegment(
                  verse: 1,
                  startsVerse: true,
                  text: 'In the beginning.',
                ),
                VerseSegment(
                  verse: 2,
                  startsVerse: true,
                  text: 'And there was a second verse.',
                ),
              ],
            ),
            const Block(
              style: BlockStyle.poetry,
              indent: 1,
              segments: [
                VerseSegment(verse: 3, startsVerse: true, text: 'A line,'),
              ],
            ),
            const Block(
              style: BlockStyle.poetry,
              indent: 2,
              segments: [
                VerseSegment(verse: 3, startsVerse: false, text: 'indented.'),
              ],
            ),
          ],
          notes: const ['A footnote.'],
        ),
        Chapter(
          number: 2,
          blocks: [
            const Block(
              style: BlockStyle.heading,
              segments: [
                VerseSegment(verse: 0, startsVerse: false, text: 'A heading'),
              ],
            ),
            const Block(
              style: BlockStyle.paragraph,
              segments: [
                VerseSegment(
                  verse: 1,
                  startsVerse: true,
                  text: 'The second chapter.',
                ),
              ],
            ),
          ],
          notes: const [],
        ),
      ],
    ),
    Book(
      meta: BookMeta.lookup('JHN')!,
      chapters: [
        Chapter(
          number: 1,
          blocks: [
            const Block(
              style: BlockStyle.paragraph,
              segments: [
                VerseSegment(
                  verse: 1,
                  startsVerse: true,
                  text: 'In the beginning was the Word.',
                ),
              ],
            ),
          ],
          notes: const [],
        ),
      ],
    ),
  ],
);

/// The version 1 layout, which this app still reads and no longer writes.
Uint8List _v1(Bible bible) {
  final payload = const GZipEncoder().encodeBytes(BibleCodec.encode(bible));
  final metadata = utf8.encode(
    jsonEncode({
      'id': bible.translation.id,
      'name': bible.translation.name,
      'abbreviation': bible.translation.abbreviation,
      'license': bible.translation.license,
      'source': bible.translation.sourceUrl,
    }),
  );
  return (ByteWriter()
        ..bytes(BibFile.magic)
        ..byte(1)
        ..byte(0x01) // gzip
        ..byte((metadata.length >> 8) & 0xff)
        ..byte(metadata.length & 0xff)
        ..bytes(metadata)
        ..bytes(payload))
      .takeCopy();
}

/// The same file with one more chunk on the end.
Uint8List _withChunk(Uint8List file, String tag, List<int> payload) =>
    (ByteWriter()
          ..bytes(file)
          ..bytes(ascii.encode(tag))
          ..uint32(payload.length)
          ..uint32(getCrc32(payload))
          ..bytes(payload))
        .takeCopy();

String _readme(Map<String, String> written) {
  final rows = written.entries
      .map((e) => '| `${e.key}` | ${e.value} |')
      .join('\n');
  return '''
# `.bib` conformance corpus

Generated by `dart run tool/build_bib_corpus.dart`. Do not edit by hand.

Every file holds the same two-book sample — Genesis 1–2 and John 1, with
prose, poetry at two indents, a heading and a footnote — so that a reader
can be judged on what it does rather than on what it is given. The format
itself is specified in [`docs/bib-format.md`](../../docs/bib-format.md).

A conforming reader must behave as the last column says.

| File | A reader must |
|---|---|
$rows

The three that read hold identical Scripture: `valid-v2.bib`,
`valid-v2-stored.bib` and `valid-v1.bib` must all come back with two books,
four chapters and five verses, and with Genesis 1:3 reading `A line,
indented.`
''';
}
