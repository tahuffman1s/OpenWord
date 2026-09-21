import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';

import 'fixtures.dart';

void main() {
  final original = parseFixture();

  group('what a .bib file holds', () {
    test('a whole translation, verse for verse', () {
      final restored = BibFile.decode(BibFile.encode(original));

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

    test('its footnotes and its poetry, not only its words', () {
      final restored = BibFile.decode(BibFile.encode(original));
      final before = original.bookByCode('PSA')!.chapter(1)!;
      final after = restored.bookByCode('PSA')!.chapter(1)!;

      expect(after.notes, before.notes);
      expect(after.blocks.length, before.blocks.length);
      for (var i = 0; i < before.blocks.length; i++) {
        expect(after.blocks[i].style, before.blocks[i].style);
        expect(after.blocks[i].indent, before.blocks[i].indent);
        expect(
          after.blocks[i].segments.map((s) => s.text),
          before.blocks[i].segments.map((s) => s.text),
        );
      }
    });

    test('what it says about itself, read from the metadata alone', () {
      const described = TranslationInfo(
        id: 'heb-test',
        name: 'A Right-to-Left Edition',
        abbreviation: 'RTL',
        license: 'CC BY 4.0',
        sourceUrl: 'https://example.invalid/rtl',
        language: 'he',
        script: 'Hebr',
        direction: ReadingDirection.rtl,
        versification: Versification.english,
        attribution: 'Somebody, CC BY 4.0.',
      );
      final bytes = BibFile.encode(
        Bible(translation: described, books: original.books),
      );
      final info = BibFile.readInfo(bytes);

      expect(info.id, 'heb-test');
      expect(info.language, 'he');
      expect(info.script, 'Hebr');
      expect(info.direction, ReadingDirection.rtl);
      expect(info.versification, Versification.english);
      expect(info.attribution, 'Somebody, CC BY 4.0.');
    });

    test('a checksum of the Scripture, so two copies can be told apart', () {
      final metadata = _metadata(BibFile.encode(original));
      expect(metadata['contentHash'], startsWith('sha256:'));
      expect(metadata['verses'], original.verseCount);
      expect(metadata['books'], original.books.length);
    });
  });

  group('reading a book costs that book', () {
    test('opening a translation unpacks none of it', () {
      final bible = BibFile.decode(BibFile.encode(original));

      expect(bible.books.every((book) => !book.isLoaded), isTrue);
    });

    test('navigating the whole Bible still unpacks none of it', () {
      final bible = BibFile.decode(BibFile.encode(original));

      // Everything the book, chapter and verse pickers ask for.
      var chapters = 0;
      var verses = 0;
      for (final book in bible.books) {
        chapters += book.chapterCount;
        for (final number in book.chapterNumbers) {
          verses += book.verseCountAt(number);
        }
      }

      expect(chapters, greaterThan(0));
      expect(verses, bible.verseCount);
      expect(bible.books.every((book) => !book.isLoaded), isTrue);
    });

    test('reading one verse unpacks one book', () {
      final bible = BibFile.decode(BibFile.encode(original));

      bible.bookByCode('GEN')!.chapter(1)!.verseText(1);

      expect(bible.bookByCode('GEN')!.isLoaded, isTrue);
      expect(bible.books.where((book) => book.isLoaded).map((b) => b.code), [
        'GEN',
      ]);
    });

    test('the outline agrees with the text it stands for', () {
      final bible = BibFile.decode(BibFile.encode(original));

      for (final book in bible.books) {
        for (var i = 1; i <= book.chapterCount; i++) {
          final fromOutline = book.verseCountAt(i);
          final fromText = book.chapter(i)!.verseCount;
          expect(fromText, fromOutline, reason: '${book.code} chapter $i');
        }
      }
    });
  });

  group('refusing what it cannot read', () {
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
            allOf(
              contains('version ${BibFile.version + 1}'),
              contains('reads'),
            ),
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

    test('damage is caught when the file is checked', () {
      final bytes = BibFile.encode(original);
      // A bit flipped in the Scripture, with its checksum left as it was.
      bytes[bytes.length - 30] ^= 0x01;

      expect(
        () => BibFile.decode(bytes, verify: true),
        throwsA(
          isA<BibFormatException>().having(
            (error) => error.message,
            'message',
            contains('damaged'),
          ),
        ),
      );
    });
  });

  group('growing without breaking older readers', () {
    test('an unknown lower-case chunk is walked past', () {
      final bytes = _append(BibFile.encode(original), 'zzzz', [1, 2, 3]);

      expect(BibFile.decode(bytes).verseCount, original.verseCount);
      expect(BibFile.tags(bytes), contains('zzzz'));
      expect(BibFile.chunk(bytes, 'zzzz'), [1, 2, 3]);
    });

    test('an unknown upper-case chunk stops the read', () {
      final bytes = _append(BibFile.encode(original), 'ZZZZ', [1, 2, 3]);

      expect(
        () => BibFile.decode(bytes),
        throwsA(
          isA<BibFormatException>().having(
            (error) => error.message,
            'message',
            contains('ZZZZ'),
          ),
        ),
      );
    });

    test('the tags held for later are ancillary, so files stay readable', () {
      for (final tag in BibFile.reservedTags) {
        expect(
          tag,
          equals(tag.toLowerCase()),
          reason: '$tag would break every reader written before it',
        );
      }
    });
  });

  test('gzip is a choice, not a requirement', () {
    final plain = BibFile.encode(original, compress: false);
    final zipped = BibFile.encode(original);

    expect(zipped.length, lessThan(plain.length));
    expect(BibFile.decode(plain).verseCount, original.verseCount);
    expect(
      BibFile.decode(plain).bookByCode('GEN')!.chapter(1)!.verseText(1),
      BibFile.decode(zipped).bookByCode('GEN')!.chapter(1)!.verseText(1),
    );
  });
}

Map<String, Object?> _metadata(Uint8List file) =>
    (jsonDecode(utf8.decode(BibFile.chunk(file, BibFile.tagMeta)!)) as Map)
        .cast<String, Object?>();

/// The file with one more chunk on the end.
Uint8List _append(Uint8List file, String tag, List<int> payload) {
  final crc = _crc32(payload);
  return Uint8List.fromList([
    ...file,
    ...ascii.encode(tag),
    (payload.length >> 24) & 0xff,
    (payload.length >> 16) & 0xff,
    (payload.length >> 8) & 0xff,
    payload.length & 0xff,
    (crc >> 24) & 0xff,
    (crc >> 16) & 0xff,
    (crc >> 8) & 0xff,
    crc & 0xff,
    ...payload,
  ]);
}

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
