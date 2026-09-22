import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/bib_export.dart';
import 'package:openword/src/data/cross_references.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/xref_codec.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<Settings> loadSettings() async {
  SharedPreferences.setMockInitialValues({});
  return Settings.load();
}

void main() {
  final references = FixtureBundle.packXrefs(fixtureXrefs);

  group('a .bib saved with its cross-references in it', () {
    late Uint8List plain;
    late Uint8List withRefs;

    setUpAll(() {
      plain = BibFile.encode(parseFixture());
      withRefs = attachCrossReferences((plain, references));
    });

    test('gains the chunk, and the Scripture is untouched', () {
      expect(BibFile.tags(plain), isNot(contains(XrefCodec.chunkTag)));
      expect(BibFile.tags(withRefs), contains(XrefCodec.chunkTag));

      final before = BibFile.decode(plain);
      final after = BibFile.decode(withRefs, verify: true);
      expect(after.translation.id, before.translation.id);
      for (var i = 0; i < before.books.length; i++) {
        expect(after.books[i].code, before.books[i].code);
        expect(
          after.books[i].chapters.map((c) => c.verseText(1)),
          before.books[i].chapters.map((c) => c.verseText(1)),
        );
      }
    });

    test('and the references read back as the app would read them', () {
      final chunk = BibFile.decode(withRefs).extras[XrefCodec.chunkTag];
      expect(chunk, isNotNull);
      final read = CrossReferences.fromChunk(chunk!);
      expect(read, isNotNull);
      expect(read!.forVerse(const Reference('GEN', 1, 1)), isNotEmpty);
    });

    test('is bigger by about what the references weigh', () {
      expect(withRefs.length, greaterThan(plain.length));
      // The chunk is stored as it came, so the growth is its own size and
      // a chunk header, not a multiple of it.
      expect(withRefs.length - plain.length, lessThan(references.length + 64));
    });

    test('and is the same bytes every time, as encoding is', () {
      expect(attachCrossReferences((plain, references)), withRefs);
    });

    test('keeps whatever chunks the file already carried', () {
      // A rewrite that dropped a translation's own references would be the
      // worst kind of bug to find.
      final carrying = BibFile.encode(
        parseFixture(),
        carry: {
          'zzzz': Uint8List.fromList([1, 2, 3]),
        },
      );
      final out = attachCrossReferences((carrying, references));
      expect(BibFile.tags(out), containsAll([XrefCodec.chunkTag, 'zzzz']));
      expect(BibFile.decode(out).extras['zzzz'], [1, 2, 3]);
    });
  });

  group('and refused rather than written wrong', () {
    test('an empty set of references is not attached', () {
      expect(
        () => attachCrossReferences((
          BibFile.encode(parseFixture()),
          FixtureBundle.packXrefs(const []),
        )),
        throwsA(isA<BibFormatException>()),
      );
    });

    test('nor is anything that is not a set of references', () {
      expect(
        () => attachCrossReferences((
          BibFile.encode(parseFixture()),
          Uint8List.fromList(List.filled(64, 7)),
        )),
        throwsA(anything),
      );
    });

    test('and a file that is not a .bib is not rewritten', () {
      expect(
        () => attachCrossReferences((
          Uint8List.fromList(List.filled(64, 7)),
          references,
        )),
        throwsA(isA<BibFormatException>()),
      );
    });
  });

  group('the setting that overrules the numbering check', () {
    test(
      'offers the layers only where the numbering allows, or is asked',
      () async {
        final settings = await loadSettings();
        final english = testTranslation;
        final other = testTranslation.copyWith(
          id: 'other',
          versification: Versification.other,
        );

        expect(settings.offersVerseKeyedLayers(english), isTrue);
        expect(settings.offersVerseKeyedLayers(other), isFalse);

        settings.setAnchoredAnyway(other.id, true);
        expect(settings.offersVerseKeyedLayers(other), isTrue);
        expect(settings.anchoredAnyway, {other.id});

        settings.setAnchoredAnyway(other.id, false);
        expect(settings.offersVerseKeyedLayers(other), isFalse);
        expect(settings.anchoredAnyway, isEmpty);
      },
    );

    test('and says so to whoever is listening', () async {
      final settings = await loadSettings();
      var told = 0;
      settings.addListener(() => told++);

      settings.setAnchoredAnyway('other', true);
      expect(told, 1);
      // Setting it again changes nothing, so nobody is told again.
      settings.setAnchoredAnyway('other', true);
      expect(told, 1);
    });
  });
}
