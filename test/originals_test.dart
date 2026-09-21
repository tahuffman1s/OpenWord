import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/originals.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/strongs_codec.dart';

import 'fixtures.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.bytes);

  final Uint8List bytes;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    if (key != Originals.assetPath) throw StateError('no $key');
    return ByteData.sublistView(bytes);
  }
}

Future<Originals> loaded() async {
  final originals = Originals(bundle: _Bundle(FixtureBundle.packOriginals()));
  await originals.load();
  return originals;
}

void main() {
  group('a Strong\'s number', () {
    test('is a language and a number, and reads both ways', () {
      const number = StrongsNumber('H', 430);
      expect(number.label, 'H430');
      expect(number.isHebrew, isTrue);
      expect(StrongsNumber.fromKey(number.key), number);

      const greek = StrongsNumber('G', 2316);
      expect(greek.isHebrew, isFalse);
      expect(StrongsNumber.fromKey(greek.key), greek);
      // The two spaces must not collide: H2316 is not G2316.
      expect(greek.key == const StrongsNumber('H', 2316).key, isFalse);
    });

    test('is parsed from what a reader would type', () {
      expect(StrongsNumber.parse('H7225'), const StrongsNumber('H', 7225));
      expect(StrongsNumber.parse('g2316'), const StrongsNumber('G', 2316));
      expect(StrongsNumber.parse(' H 430 '), const StrongsNumber('H', 430));
      expect(StrongsNumber.parse('H0430'), const StrongsNumber('H', 430));
      expect(StrongsNumber.parse('430'), isNull);
      expect(StrongsNumber.parse('Hello'), isNull);
      expect(StrongsNumber.parse('H0'), isNull);
    });
  });

  group("Strong's usage lists", () {
    StrongsEntry entry(String usage) => StrongsEntry(
      number: const StrongsNumber('H', 1),
      lemma: '',
      transliteration: '',
      pronunciation: '',
      derivation: '',
      definition: '',
      kjvUsage: usage,
    );

    test('are read past their editorial marks', () {
      // Strong's writes "God (gods) (-dess, -ly)"; splitting on the comma
      // inside the brackets would give "god -dess", which matches nothing.
      expect(
        entry('angels, [idiom] exceeding, God (gods) (-dess, -ly), judges.')
            .renderings,
        containsAll(<String>['angels', 'god', 'judges']),
      );
      expect(
        entry('angels, God (gods) (-dess, -ly).').renderings,
        isNot(contains('god -dess')),
      );
      // A bare X means "not rendered literally" and is not a word.
      expect(entry('X exceeding, God').renderings, ['exceeding', 'god']);
      expect(entry('(be-) love(-ed).').renderings, ['love']);
    });
  });

  group('the original behind a verse', () {
    test('is found under any translation, by reference', () async {
      final originals = await loaded();

      final words = originals.wordsFor(const Reference('GEN', 1, 1));
      expect(words, hasLength(3));
      expect(words.first.text, 'בְּרֵאשִׁית');
      expect(words.first.strongs, const StrongsNumber('H', 7225));
      expect(words.first.morphology, 'Noun common feminine singular absolute');
      expect(words[2].strongs, const StrongsNumber('H', 430));

      final greek = originals.wordsFor(const Reference('MAT', 1, 1));
      expect(greek.single.text, 'βίβλος');
      expect(greek.single.strongs, const StrongsNumber('G', 976));
    });

    test('is absent where there is none, without complaint', () async {
      final originals = await loaded();

      expect(originals.wordsFor(const Reference('GEN', 1, 2)), isEmpty);
      expect(originals.hasOriginal(const Reference('GEN', 1, 2)), isFalse);
      expect(originals.hasOriginal(const Reference('GEN', 1, 1)), isTrue);
      // The deuterocanon is neither Hebrew Bible nor Greek New Testament.
      expect(originals.wordsFor(const Reference('TOB', 1, 1)), isEmpty);
      // A chapter reference is not a verse.
      expect(originals.wordsFor(const Reference('GEN', 1)), isEmpty);
    });

    test('a missing asset leaves the app working, quietly', () async {
      final originals = Originals(bundle: _Bundle(Uint8List(0)));
      await originals.load();

      expect(originals.isLoaded, isFalse);
      expect(originals.wordsFor(const Reference('GEN', 1, 1)), isEmpty);
      expect(originals.entryFor(const StrongsNumber('H', 430)), isNull);
      expect(originals.occurrences(const StrongsNumber('H', 430)), isEmpty);
    });

    test('is read once, however many times it is asked for', () async {
      final bundle = _Bundle(FixtureBundle.packOriginals());
      final originals = Originals(bundle: bundle);

      await Future.wait([originals.load(), originals.load()]);
      await originals.load();

      expect(bundle.loads, 1);
    });
  });

  group('the dictionary', () {
    test('gives what Strong\'s says, not a summary of it', () async {
      final originals = await loaded();

      final entry = originals.entryFor(const StrongsNumber('H', 430))!;
      expect(entry.lemma, 'אֱלֹהִים');
      expect(entry.transliteration, 'ʼĕlôhîym');
      expect(entry.definition, contains('supreme God'));
      expect(entry.derivation, contains('H433'));
      expect(entry.kjvUsage, contains('judges'));
      expect(originals.entryFor(const StrongsNumber('H', 9999)), isNull);
    });
  });

  group('the concordance', () {
    test('lists every verse a word is in, in order', () async {
      final originals = await loaded();

      const god = StrongsNumber('H', 430);
      expect(originals.occurrenceCount(god), 2);
      expect(originals.occurrences(god).map((r) => r.label), [
        'Genesis 1:1',
        'Genesis 1:3',
      ]);

      // A word in one verse is counted once, not once per word.
      expect(originals.occurrenceCount(const StrongsNumber('H', 7225)), 1);
      expect(originals.occurrenceCount(const StrongsNumber('G', 976)), 1);
      expect(originals.occurrenceCount(const StrongsNumber('H', 9999)), 0);
    });
  });

  group('tying an English word to the original', () {
    test('matches through the King James renderings', () async {
      final originals = await loaded();
      final words = originals.wordsFor(const Reference('GEN', 1, 1));

      // "God" is among the KJV renderings of H430, which is the third word.
      expect(originals.matchesFor(words, 'God'), [2]);
      expect(originals.matchesFor(words, 'god'), [2]);
      expect(originals.matchesFor(words, 'beginning'), [0]);
      // "created" stems to "create", which is how H1254 is rendered.
      expect(originals.matchesFor(words, 'created'), [1]);
    });

    test('answers nothing rather than something plausible', () async {
      final originals = await loaded();
      final words = originals.wordsFor(const Reference('GEN', 1, 1));

      expect(originals.matchesFor(words, 'the'), isEmpty);
      expect(originals.matchesFor(words, 'heavens'), isEmpty);
      expect(originals.matchesFor(words, ''), isEmpty);
      expect(originals.matchesFor(words, 'a'), isEmpty);
    });
  });

  test('the asset that ships holds both testaments', () async {
    final file = File(Originals.assetPath);
    expect(file.existsSync(), isTrue, reason: '${file.path} is missing');

    final reader = decodeOriginals(file.readAsBytesSync());
    expect(reader.verseCount, greaterThan(30000));
    expect(reader.entryCount, greaterThan(14000));

    // Genesis 1:1, word for word.
    final genesis = reader.wordsAt(StrongsCodec.verseKey(0, 1, 1));
    expect(genesis, hasLength(7));
    expect(genesis.first.strongs, const StrongsNumber('H', 7225));
    expect(genesis.first.morphology, contains('Noun'));
    expect(genesis[2].strongs, const StrongsNumber('H', 430));

    // John 3:16 — book 42 in the canon, and the Greek is accented.
    final john = reader.wordsAt(StrongsCodec.verseKey(42, 3, 16));
    expect(john.length, greaterThan(20));
    expect(john.first.text, 'Οὕτως');
    expect(
      john.any((word) => word.strongs == const StrongsNumber('G', 2316)),
      isTrue,
    );

    // The versification map did its work: Malachi 4 is Hebrew 3, and the
    // English chapter 4 must still have its words.
    expect(reader.wordsAt(StrongsCodec.verseKey(38, 4, 1)), isNotEmpty);
    // Joel 2:28 is Hebrew 3:1.
    expect(reader.wordsAt(StrongsCodec.verseKey(28, 2, 28)), isNotEmpty);
    // Psalm 51:1 is Hebrew 51:3 — the superscription is counted there.
    expect(reader.wordsAt(StrongsCodec.verseKey(18, 51, 1)), isNotEmpty);

    final god = reader.entryFor(const StrongsNumber('H', 430))!;
    expect(god.lemma, 'אֱלֹהִים');
    expect(god.renderings, contains('god'));
    expect(
      reader.occurrenceCount(const StrongsNumber('H', 430)),
      greaterThan(2000),
    );

    final theos = reader.entryFor(const StrongsNumber('G', 2316))!;
    expect(theos.lemma, 'θεός');
    expect(theos.transliteration, isNotEmpty);
  });
}
