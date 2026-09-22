import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/bib_export.dart';
import 'package:openword/src/data/cross_references.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/book_meta.dart';
import 'package:openword/src/model/strongs_codec.dart';
import 'package:openword/src/model/strongs_scope.dart';
import 'package:openword/src/model/xref_codec.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<Settings> loadSettings() async {
  SharedPreferences.setMockInitialValues({});
  return Settings.load();
}

void main() {
  _theOriginalsInAFile();
  final references = FixtureBundle.packXrefs(fixtureXrefs);
  StudyLayers refsOnly() => StudyLayers(crossReferences: references);

  group('a .bib saved with its cross-references in it', () {
    late Uint8List plain;
    late Uint8List withRefs;

    setUpAll(() {
      plain = BibFile.encode(parseFixture());
      withRefs = attachStudyLayers((plain, refsOnly())).bytes;
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
      expect(attachStudyLayers((plain, refsOnly())).bytes, withRefs);
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
      final out = attachStudyLayers((carrying, refsOnly())).bytes;
      expect(BibFile.tags(out), containsAll([XrefCodec.chunkTag, 'zzzz']));
      expect(BibFile.decode(out).extras['zzzz'], [1, 2, 3]);
    });
  });

  group('and refused rather than written wrong', () {
    test('an empty set of references is not attached', () {
      expect(
        () => attachStudyLayers((
          BibFile.encode(parseFixture()),
          StudyLayers(crossReferences: FixtureBundle.packXrefs(const [])),
        )),
        throwsA(isA<BibFormatException>()),
      );
    });

    test('nor is anything that is not a set of references', () {
      expect(
        () => attachStudyLayers((
          BibFile.encode(parseFixture()),
          StudyLayers(crossReferences: Uint8List.fromList(List.filled(64, 7))),
        )),
        throwsA(anything),
      );
    });

    test('and a file that is not a .bib is not rewritten', () {
      expect(
        () => attachStudyLayers((
          Uint8List.fromList(List.filled(64, 7)),
          refsOnly(),
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

/// The Hebrew and Greek travelling inside a `.bib`, which is what lets a
/// file stand on its own and what lets a differently-numbered Bible have
/// them at all.
void _theOriginalsInAFile() {
  final originals = FixtureBundle.packOriginals();

  group('a .bib saved with its Hebrew and Greek in it', () {
    late Uint8List plain;
    late Uint8List withOriginals;
    late AttachedLayers written;

    setUpAll(() {
      plain = BibFile.encode(parseFixture());
      written = attachStudyLayers((plain, StudyLayers(originals: originals)));
      withOriginals = written.bytes;
    });

    test('gains the chunk, and says what went in', () {
      expect(BibFile.tags(plain), isNot(contains(StrongsCodec.chunkTag)));
      expect(BibFile.tags(withOriginals), contains(StrongsCodec.chunkTag));
      expect(written.verses, greaterThan(0));
      expect(written.entries, greaterThan(0));
      // Nothing was asked of the references, so nothing was written.
      expect(written.references, 0);
      expect(BibFile.tags(withOriginals), isNot(contains(XrefCodec.chunkTag)));
    });

    test('and the words read back, pointing and parsing and all', () {
      final chunk = BibFile.decode(withOriginals).extras[StrongsCodec.chunkTag];
      expect(chunk, isNotNull);
      final layer = StrongsCodec.unpack(chunk!);

      final genesis = originalsCanon.indexOf('GEN');
      final words = layer.wordsAt(StrongsCodec.verseKey(genesis, 1, 1));
      expect(words.map((w) => w.text), ['בְּרֵאשִׁית', 'בָּרָא', 'אֱלֹהִים']);
      expect(words.first.strongs, const StrongsNumber('H', 7225));
      expect(words.first.morphology, 'Noun common feminine singular absolute');

      // The dictionary came too, or a number would be a number and
      // nothing else.
      final entry = layer.entryFor(const StrongsNumber('H', 7225));
      expect(entry, isNotNull);
      expect(entry!.renderings, isNotEmpty);
    });

    test('and the concordance names only verses the file has', () {
      final layer = StrongsCodec.unpack(
        BibFile.decode(withOriginals).extras[StrongsCodec.chunkTag]!,
      );
      final everywhere = layer.occurrences(const StrongsNumber('H', 430));
      expect(everywhere, isNotEmpty);
      for (final key in everywhere) {
        expect(
          layer.hasVerse(key),
          isTrue,
          reason: 'the concordance points at a verse the layer dropped',
        );
      }
    });

    test('and the Scripture is untouched', () {
      final before = BibFile.decode(plain);
      final after = BibFile.decode(withOriginals, verify: true);
      expect(after.books.map((b) => b.code), before.books.map((b) => b.code));
      expect(
        after.bookByCode('GEN')!.chapter(1)!.verseText(1),
        before.bookByCode('GEN')!.chapter(1)!.verseText(1),
      );
    });

    test('both layers can sit in the same file', () {
      final both = attachStudyLayers((
        plain,
        StudyLayers(
          crossReferences: FixtureBundle.packXrefs(fixtureXrefs),
          originals: originals,
        ),
      ));
      expect(
        BibFile.tags(both.bytes),
        containsAll([XrefCodec.chunkTag, StrongsCodec.chunkTag]),
      );
      expect(both.references, greaterThan(0));
      expect(both.verses, greaterThan(0));
    });
  });

  group('a layer is cut to the verses the file has', () {
    late StrongsReader whole;

    setUpAll(() => whole = StrongsCodec.unpack(originals));

    test('a New Testament carries no Hebrew', () {
      final full = parseFixture();
      final newTestament = Bible(
        translation: full.translation,
        books: full.books
            .where((book) => book.section == BookSection.newTestament)
            .toList(),
      );
      expect(newTestament.books, isNotEmpty);

      final trimmed = StrongsReader.parse(
        trimOriginalsTo(whole, originalsKeysOf(newTestament)),
      );

      final genesis = originalsCanon.indexOf('GEN');
      final matthew = originalsCanon.indexOf('MAT');
      expect(
        trimmed.hasVerse(StrongsCodec.verseKey(genesis, 1, 1)),
        isFalse,
        reason: 'Genesis is not in this Bible, so its Hebrew is dead weight',
      );
      expect(trimmed.hasVerse(StrongsCodec.verseKey(matthew, 1, 1)), isTrue);

      // And the dictionary shrinks with it: an entry nothing left reaches
      // is carried for nobody.
      expect(trimmed.entryCount, lessThan(whole.entryCount));
      expect(
        trimmed.entryFor(const StrongsNumber('H', 7225)),
        isNull,
        reason: 'no word left in the file uses it',
      );
      expect(trimmed.entryFor(const StrongsNumber('G', 976)), isNotNull);
    });

    test(
      'and a Bible with nothing behind it is refused, not written empty',
      () {
        final full = parseFixture();
        final deutero = Bible(
          translation: full.translation,
          books: full.books
              .where((book) => book.section == BookSection.deuterocanon)
              .toList(),
        );
        if (deutero.books.isEmpty) return;
        expect(
          () => attachStudyLayers((
            BibFile.encode(deutero),
            StudyLayers(originals: originals),
          )),
          throwsA(isA<BibFormatException>()),
        );
      },
    );
  });

  test('nothing asked for is nothing written', () {
    expect(
      () => attachStudyLayers((
        BibFile.encode(parseFixture()),
        const StudyLayers(),
      )),
      throwsA(isA<BibFormatException>()),
    );
  });
}
