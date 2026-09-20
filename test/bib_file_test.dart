import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible_codec.dart';

import 'fixtures.dart';

void main() {
  final original = parseFixture();

  test('a .bib file holds a whole translation', () {
    final bytes = BibFile.encode(original);
    final restored = BibFile.decode(bytes);

    expect(restored.translation.id, original.translation.id);
    expect(
      restored.books.map((book) => book.code),
      original.books.map((book) => book.code),
    );
    expect(restored.verseCount, original.verseCount);
    expect(
      restored.bookByCode('GEN')!.chapter(1)!.verseText(1),
      original.bookByCode('GEN')!.chapter(1)!.verseText(1),
    );
  });

  test('what it holds can be read from the header alone', () {
    final bytes = BibFile.encode(original);
    // A shelf lists files without decoding them, so the header has to stand
    // on its own — here, without the Scripture behind it at all.
    final header = Uint8List.sublistView(bytes, 0, 200);
    final info = BibFile.readInfo(header);

    expect(info.id, original.translation.id);
    expect(info.name, original.translation.name);
    expect(info.abbreviation, 'TST');
    expect(info.license, original.translation.license);
    expect(info.sourceUrl, original.translation.sourceUrl);
  });

  test('gzip is a flag, not a requirement', () {
    final plain = BibFile.encode(original, compress: false);
    final zipped = BibFile.encode(original);

    expect(plain[4] & BibFile.gzipFlag, 0);
    expect(zipped[4] & BibFile.gzipFlag, BibFile.gzipFlag);
    expect(zipped.length, lessThan(plain.length));
    expect(BibFile.decode(plain).verseCount, original.verseCount);
  });

  test('the magic tells a .bib from anything else', () {
    expect(BibFile.looksLikeBib(BibFile.encode(original)), isTrue);
    expect(
      BibFile.looksLikeBib(Uint8List.fromList([0x50, 0x4b, 3, 4])),
      isFalse,
    );
    expect(BibFile.looksLikeBib(Uint8List(2)), isFalse);
  });

  test('a file that is not one says so rather than half-reading it', () {
    expect(
      () => BibFile.decode(Uint8List.fromList([0x50, 0x4b, 3, 4, 0, 0, 0])),
      throwsA(
        isA<BibFormatException>().having(
          (error) => error.message,
          'message',
          contains('not a .bib'),
        ),
      ),
    );
  });

  test('a newer version is refused by number', () {
    final bytes = BibFile.encode(original);
    bytes[3] = BibFile.version + 1;

    expect(
      () => BibFile.decode(bytes),
      throwsA(
        isA<BibFormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('version ${BibFile.version + 1}'), contains('reads')),
        ),
      ),
    );
  });

  test('a truncated file is refused, not decoded into nonsense', () {
    final bytes = BibFile.encode(original);

    expect(
      () => BibFile.decode(Uint8List.sublistView(bytes, 0, 40)),
      throwsA(isA<BibFormatException>()),
    );
    expect(
      () => BibFile.readInfo(Uint8List.sublistView(bytes, 0, 9)),
      throwsA(isA<BibFormatException>()),
    );
  });

  test('the payload is the encoding the app already reads', () {
    // The header is a wrapper, not a new encoding: the bytes behind it are
    // exactly what a bundled asset holds.
    final bytes = BibFile.encode(original, compress: false);
    final payload = Uint8List.sublistView(
      bytes,
      bytes.length - BibleCodec.encode(original).length,
    );

    expect(BibleCodec.decode(payload).verseCount, original.verseCount);
  });
}
