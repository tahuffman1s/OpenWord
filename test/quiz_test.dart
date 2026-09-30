import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/translations.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/book_meta.dart';
import 'package:openword/src/model/quiz.dart';

import 'fixtures.dart';

void main() {
  // The whole World English Bible: a question set drawn from three
  // fixture verses would prove little.
  late Bible web;
  late List<Book> canon;
  setUpAll(() {
    web = BibFile.decode(
      File(Translations.assetFor(Translations.fallback.id)).readAsBytesSync(),
    );
    canon = quizBooks(web, deuterocanon: false);
  });

  void checkShape(List<QuizQuestion> questions, QuizKind kind) {
    expect(questions, hasLength(10));
    final references = <Reference>{};
    for (final question in questions) {
      if (kind != QuizKind.mixed) expect(question.kind, kind);
      expect(question.options, hasLength(QuizMaker.optionCount));
      expect(question.options.toSet(), hasLength(QuizMaker.optionCount));
      expect(question.answer, inInclusiveRange(0, 3));
      expect(question.stem, isNotEmpty);
      expect(references.add(question.reference), isTrue);
      final book = web.bookByCode(question.reference.bookCode)!;
      expect(book.section, isNot(BookSection.deuterocanon));
      final chapter = book.chapter(question.reference.chapter)!;
      if (question.reference.verse case final verse?) {
        expect(chapter.verseText(verse), isNotEmpty);
      }
    }
  }

  test(
    'which book: the verse is from the book, the options its neighbours',
    () {
      final questions = QuizMaker(
        web,
        books: canon,
        random: Random(1),
      ).make(QuizKind.whichBook);
      checkShape(questions, QuizKind.whichBook);
      for (final question in questions) {
        final book = web.bookByCode(question.reference.bookCode)!;
        expect(question.correct, book.name);
        expect(
          question.prompt,
          book
              .chapter(question.reference.chapter)!
              .verseText(question.reference.verse!),
        );
        expect(question.prompt.length, greaterThanOrEqualTo(30));
        for (final option in question.options) {
          final other = canon.firstWhere((b) => b.name == option);
          expect(other.section, book.section);
        }
      }
    },
  );

  test('finish the verse: the halves make the verse again', () {
    final questions = QuizMaker(
      web,
      books: canon,
      random: Random(2),
    ).make(QuizKind.finishVerse);
    checkShape(questions, QuizKind.finishVerse);
    for (final question in questions) {
      expect(question.prompt, endsWith(' …'));
      final head = question.prompt.substring(0, question.prompt.length - 2);
      final whole = web
          .bookByCode(question.reference.bookCode)!
          .chapter(question.reference.chapter)!
          .verseText(question.reference.verse!);
      expect('$head ${question.correct}', whole);
      expect(whole.length, greaterThanOrEqualTo(80));
    }
  });

  test('a verse is cut at the clause break nearest its middle', () {
    const text =
        'For God so loved the world, that he gave his only born Son, '
        'that whoever believes in him should not perish, but have eternal life.';
    final at = QuizMaker.splitPoint(text);
    expect(text.substring(0, at).trimRight(), endsWith('only born Son,'));
    // No clause break in the middle: the space nearest the middle.
    const plain = 'one two three four five six seven eight nine ten';
    final plainAt = QuizMaker.splitPoint(plain);
    expect(plain.substring(0, plainAt).trimRight(), 'one two three four five');
  });

  test('books in order: the answer is the neighbour asked for', () {
    final questions = QuizMaker(
      web,
      books: canon,
      random: Random(3),
    ).make(QuizKind.bookOrder);
    checkShape(questions, QuizKind.bookOrder);
    final names = canon.map((b) => b.name).toList();
    for (final question in questions) {
      expect(question.prompt, isEmpty);
      final match = RegExp(r'^Which book comes (after|before) (.+)\?$')
          .firstMatch(question.stem)!;
      final asked = names.indexOf(match.group(2)!);
      final expected = names[match.group(1) == 'after' ? asked + 1 : asked - 1];
      expect(question.correct, expected);
      expect(question.reference.bookCode, canon[names.indexOf(expected)].code);
      expect(question.reference.verse, isNull);
    }
  });

  test('a bit of everything has all three kinds', () {
    final questions = QuizMaker(
      web,
      books: canon,
      random: Random(4),
    ).make(QuizKind.mixed);
    checkShape(questions, QuizKind.mixed);
    expect(questions.map((q) => q.kind).toSet(), {
      QuizKind.whichBook,
      QuizKind.finishVerse,
      QuizKind.bookOrder,
    });
  });

  test('the same seed draws the same round; another draws another', () {
    List<String> draw(int seed) => QuizMaker(
      web,
      books: canon,
      random: Random(seed),
    ).make(QuizKind.whichBook).map((q) => q.reference.encode()).toList();
    expect(draw(7), draw(7));
    expect(draw(7), isNot(draw(8)));
  });

  test('the deuterocanon is asked about only when shown', () {
    final shown = quizBooks(web, deuterocanon: true);
    expect(shown.length, greaterThan(canon.length));
    expect(canon.any((b) => b.section == BookSection.deuterocanon), isFalse);
  });

  test('a small translation gets what questions it can', () {
    final small = parseFixture();
    final maker = QuizMaker(small, random: Random(5));
    // Three books: whichever is asked about, one is the answer and the
    // other the only wrong choice.
    final order = maker.make(QuizKind.bookOrder);
    expect(order, isNotEmpty);
    for (final question in order) {
      expect(question.options, hasLength(2));
      expect(question.options, contains(question.correct));
    }
    // Eight verses long enough to place, and no round asks one twice.
    final which = maker.make(QuizKind.whichBook);
    expect(which, isNotEmpty);
    expect(which.length, lessThanOrEqualTo(8));
    expect(which.map((q) => q.reference).toSet(), hasLength(which.length));
    // No verse long enough to finish: none at all, and no error.
    expect(maker.make(QuizKind.finishVerse), isEmpty);
  });
}
