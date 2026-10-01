import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/memory_exercise.dart';

void main() {
  const john =
      'For God so loved the world, that he gave his only born Son, that '
      'whoever believes in him should not perish, but have eternal life.';

  group('tiles', () {
    test('a short verse is its words', () {
      expect(VerseTiles.of('God said, "Let there be light."'), [
        'God',
        'said,',
        '"Let',
        'there',
        'be',
        'light."',
      ]);
    });

    test('a long verse is cut into phrases, at most twelve', () {
      final tiles = VerseTiles.of(john);
      expect(tiles.length, lessThanOrEqualTo(VerseTiles.maxTiles));
      expect(tiles.length, greaterThan(4));
      expect(tiles.join(' '), john);
      // Runs end at clause breaks where one comes along.
      expect(tiles, contains('loved the world,'));
      for (final tile in tiles) {
        expect(tile.split(' ').length, greaterThanOrEqualTo(2));
      }
    });

    test('the order is checked against the verse itself', () {
      final tiles = VerseTiles.of(john);
      expect(VerseTiles.inOrder(tiles, john), isTrue);
      expect(VerseTiles.inOrder(tiles.reversed.toList(), john), isFalse);
      expect(VerseTiles.inOrder(tiles.sublist(1), john), isFalse);
    });
  });

  group('blanks', () {
    test('keep the punctuation around a word', () {
      final word = VerseWord.parse('"world,"');
      expect(word.lead, '"');
      expect(word.core, 'world');
      expect(word.trail, ',"');
      expect(VerseWord.parse('don’t').core, 'don’t');
    });

    test('one word in five goes, the bank holds it and a wrong one', () {
      final cloze = Cloze.make(john, Random(1));
      expect(cloze.words.length, 25);
      expect(cloze.blanks.length, 5);
      expect(cloze.blanks, cloze.blanks.toList()..sort());
      expect(cloze.bank.length, 10);
      for (var i = 0; i < cloze.blanks.length; i++) {
        expect(cloze.bank, contains(cloze.answer(i)));
        expect(cloze.answer(i).length, greaterThanOrEqualTo(3));
      }
      // Every wrong word is from the verse too.
      final cores = cloze.words.map((w) => w.core).toSet();
      expect(cores.containsAll(cloze.bank), isTrue);
    });

    test('is right only with every blank right', () {
      final cloze = Cloze.make(john, Random(2));
      final right = [
        for (var i = 0; i < cloze.blanks.length; i++) cloze.answer(i),
      ];
      expect(cloze.check(right), isTrue);
      expect(cloze.check([...right.reversed]), right.first == right.last);
      expect(cloze.check(right.sublist(1)), isFalse);
      expect(cloze.check([null, ...right.sublist(1)]), isFalse);
    });

    test('a short verse has one blank and a short bank', () {
      final cloze = Cloze.make('Jesus wept.', Random(3));
      expect(cloze.blanks.length, 1);
      expect(cloze.bank.length, 2);
    });
  });

  group('written out', () {
    test('case and punctuation are set aside', () {
      expect(TypedVerse.matches('jesus wept', 'Jesus wept.'), isTrue);
      expect(
        TypedVerse.matches(
          'for god so loved the world',
          'For God so loved the world,',
        ),
        isTrue,
      );
    });

    test('a slip of one letter in a long word is forgiven', () {
      expect(TypedVerse.matches('Jesus wepd.', 'Jesus wept.'), isFalse);
      expect(
        TypedVerse.matches('whoever beleives', 'whoever believes'),
        isTrue,
      );
      expect(TypedVerse.matches('whoever belives', 'whoever believes'), isTrue);
      expect(TypedVerse.matches('whoever belies', 'whoever believes'), isFalse);
    });

    test('a word missing or added is wrong', () {
      expect(TypedVerse.matches('Jesus wept a lot.', 'Jesus wept.'), isFalse);
      expect(TypedVerse.matches('Jesus', 'Jesus wept.'), isFalse);
      expect(TypedVerse.matches('', 'Jesus wept.'), isFalse);
    });

    test('curly apostrophes are straight ones', () {
      expect(TypedVerse.matches("don't", 'don’t'), isTrue);
    });
  });

  group('the exercise for a rung', () {
    test('climbs from copying to writing out', () {
      expect(
        MemoryExercise.forRung(0, canListen: true),
        MemoryExercise.arrangeShown,
      );
      expect(
        MemoryExercise.forRung(1, canListen: true),
        MemoryExercise.fillBlanks,
      );
      expect(
        MemoryExercise.forRung(2, canListen: true),
        MemoryExercise.listenArrange,
      );
      expect(
        MemoryExercise.forRung(2, canListen: false),
        MemoryExercise.arrange,
      );
      expect(
        MemoryExercise.forRung(3, canListen: true),
        MemoryExercise.arrange,
      );
      expect(
        MemoryExercise.forRung(4, canListen: true),
        MemoryExercise.typeOut,
      );
      expect(
        MemoryExercise.forRung(5, canListen: true),
        MemoryExercise.listenArrange,
      );
      expect(
        MemoryExercise.forRung(5, canListen: false),
        MemoryExercise.arrange,
      );
      expect(
        MemoryExercise.forRung(8, canListen: true),
        MemoryExercise.typeOut,
      );
    });

    test('only the first two show the text', () {
      expect(MemoryExercise.values.where((e) => e.showsText), [
        MemoryExercise.arrangeShown,
        MemoryExercise.fillBlanks,
      ]);
    });
  });
}
