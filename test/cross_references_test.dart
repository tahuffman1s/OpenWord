import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/cross_references.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/xref_codec.dart';

/// A fixture in the real shape: two anchors on Genesis 1:1.
List<XrefEntry> fixtureEntries() => [
  XrefEntry(
    book: 0,
    chapter: 1,
    verse: 1,
    anchors: [
      XrefAnchor(
        phrase: 'beginning',
        ranges: const [
          XrefRange(book: 42, chapter: 1, verse: 1, endVerse: 3),
          XrefRange(book: 57, chapter: 1, verse: 10, endVerse: 10),
        ],
      ),
      XrefAnchor(
        phrase: 'God',
        ranges: const [XrefRange(book: 18, chapter: 19, verse: 1, endVerse: 1)],
      ),
    ],
  ),
  XrefEntry(
    book: 42,
    chapter: 3,
    verse: 16,
    anchors: [
      XrefAnchor(
        phrase: 'loved',
        ranges: const [XrefRange(book: 44, chapter: 5, verse: 8, endVerse: 8)],
      ),
    ],
  ),
];

Uint8List packed(List<XrefEntry> entries) =>
    Uint8List.fromList(gzip.encode(XrefCodec.encode(entries)));

class _Bundle extends CachingAssetBundle {
  _Bundle(this.bytes);

  final Uint8List bytes;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    if (key != CrossReferences.assetPath) throw StateError('no $key');
    return ByteData.sublistView(bytes);
  }
}

void main() {
  group('the binary the references ship in', () {
    test('survives a round trip', () {
      final restored = XrefCodec.decode(XrefCodec.encode(fixtureEntries()));

      expect(restored, hasLength(2));
      final genesis = restored.first;
      expect(genesis.book, 0);
      expect(genesis.chapter, 1);
      expect(genesis.verse, 1);
      expect(genesis.anchors.map((a) => a.phrase), ['beginning', 'God']);
      expect(genesis.passages, 3);

      final first = genesis.anchors.first.ranges.first;
      expect(first.book, 42);
      expect(first.verse, 1);
      expect(first.endVerse, 3);
      expect(first.isRange, isTrue);
      expect(genesis.anchors.first.ranges[1].isRange, isFalse);
    });

    test('a phrase repeated across verses is stored once', () {
      // The table of phrases is what keeps 300,000 references to a megabyte.
      final many = [
        for (var verse = 1; verse <= 200; verse++)
          XrefEntry(
            book: 0,
            chapter: 1,
            verse: verse,
            anchors: [
              XrefAnchor(
                phrase: 'the LORD God of Israel',
                ranges: const [
                  XrefRange(book: 1, chapter: 2, verse: 3, endVerse: 3),
                ],
              ),
            ],
          ),
      ];

      final bytes = XrefCodec.encode(many);
      expect(bytes.length, lessThan(200 * 'the LORD God of Israel'.length));
      expect(
        XrefCodec.decode(bytes).last.anchors.first.phrase,
        'the LORD God of Israel',
      );
    });

    test('something that is not the asset is refused', () {
      expect(
        () => XrefCodec.decode(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<FormatException>()),
      );
    });

    test('a future version is refused by number', () {
      final bytes = XrefCodec.encode(fixtureEntries());
      bytes[3] = XrefCodec.version + 1;
      expect(() => XrefCodec.decode(bytes), throwsA(isA<FormatException>()));
    });
  });

  group('looking them up', () {
    test(
      'a verse finds its anchors, and one without them finds none',
      () async {
        final xrefs = CrossReferences(
          bundle: _Bundle(packed(fixtureEntries())),
        );
        await xrefs.load();

        expect(xrefs.isLoaded, isTrue);
        final anchors = xrefs.forVerse(const Reference('GEN', 1, 1));
        expect(anchors.map((a) => a.phrase), ['beginning', 'God']);
        expect(xrefs.countFor(const Reference('GEN', 1, 1)), 3);
        expect(xrefs.forVerse(const Reference('GEN', 1, 2)), isEmpty);
        expect(xrefs.countFor(const Reference('GEN', 1, 2)), 0);
        expect(xrefs.forVerse(const Reference('JHN', 3, 16)), hasLength(1));
      },
    );

    test('a chapter reference with no verse asks for nothing', () async {
      final xrefs = CrossReferences(bundle: _Bundle(packed(fixtureEntries())));
      await xrefs.load();

      expect(xrefs.forVerse(const Reference('GEN', 1)), isEmpty);
    });

    test('nothing is read twice', () async {
      final bundle = _Bundle(packed(fixtureEntries()));
      final xrefs = CrossReferences(bundle: bundle);

      await Future.wait([xrefs.load(), xrefs.load()]);
      await xrefs.load();

      expect(bundle.loads, 1);
    });

    test('a missing asset leaves the app working, quietly', () async {
      final xrefs = CrossReferences(bundle: _Bundle(Uint8List(0)));
      await xrefs.load();

      expect(xrefs.forVerse(const Reference('GEN', 1, 1)), isEmpty);
    });

    test('the deuterocanon is not in the numbering', () {
      // The asset numbers the sixty-six, so Tobit has no index and asking
      // for it must not answer with some other book's references.
      expect(CrossReferences.indexOfBook('GEN'), 0);
      expect(CrossReferences.indexOfBook('MAL'), 38);
      expect(CrossReferences.indexOfBook('MAT'), 39);
      expect(CrossReferences.indexOfBook('REV'), 65);
      expect(CrossReferences.indexOfBook('TOB'), -1);
      expect(CrossReferences.bookAt(65), 'REV');
      expect(CrossReferences.bookAt(66), isNull);
      expect(CrossReferences.bookAt(-1), isNull);
    });
  });

  test('the asset that ships is readable and covers the canon', () async {
    final file = File(CrossReferences.assetPath);
    expect(file.existsSync(), isTrue, reason: '${file.path} is missing');

    final entries = decodeCrossReferences(file.readAsBytesSync());
    expect(entries.length, greaterThan(20000));

    final byKey = {for (final entry in entries) entry.key: entry};
    final genesis = byKey[XrefCodec.keyOf(0, 1, 1)]!;
    expect(genesis.anchors, isNotEmpty);
    expect(genesis.anchors.first.phrase, isNotEmpty);

    // John 3:16 is the best-known verse in the book; it has references.
    expect(byKey[XrefCodec.keyOf(42, 3, 16)]!.passages, greaterThan(0));

    // Every range points somewhere inside the canon.
    for (final entry in entries.take(2000)) {
      for (final anchor in entry.anchors) {
        for (final range in anchor.ranges) {
          expect(range.book, inInclusiveRange(0, 65));
          expect(range.chapter, greaterThan(0));
          expect(range.verse, greaterThan(0));
          expect(range.endVerse, greaterThanOrEqualTo(range.verse));
        }
      }
    }
  });
}
