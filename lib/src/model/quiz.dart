import 'dart:math';

import 'package:flutter/foundation.dart';

import 'bible.dart';
import 'book_meta.dart';

/// The kinds of question a round can ask.
enum QuizKind {
  whichBook('Which book?', 'A verse; say which book it is from.'),
  finishVerse(
    'Finish the verse',
    'The first half of a verse; pick how it goes on.',
  ),
  bookOrder('Books in order', 'Which book comes before or after another.'),
  mixed('A bit of everything', 'All three kinds, shuffled together.');

  const QuizKind(this.label, this.description);

  final String label;
  final String description;

  /// The kinds a round of this kind draws on.
  List<QuizKind> get parts =>
      this == mixed ? const [whichBook, finishVerse, bookOrder] : [this];
}

/// One question: what is shown, the choices, which is right, and where
/// the answer is to be read.
@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.kind,
    required this.stem,
    required this.prompt,
    required this.options,
    required this.answer,
    required this.reference,
  });

  final QuizKind kind;

  /// The question in words: "Which book is this from?"
  final String stem;

  /// Scripture shown under the stem, or empty when the stem is the whole
  /// question.
  final String prompt;

  final List<String> options;

  /// Index into [options] of the right one.
  final int answer;

  /// Where the answer is found: the verse, or the first chapter of the
  /// book.
  final Reference reference;

  String get correct => options[answer];
}

/// Makes questions from a translation. Nothing is stored: a round is
/// drawn afresh each time, at random, so no two rounds are alike.
class QuizMaker {
  QuizMaker(this.bible, {List<Book>? books, Random? random})
    : books = books ?? bible.books,
      _random = random ?? Random();

  final Bible bible;

  /// The books questions are drawn from, in canonical order — the reader's
  /// choice of whether the deuterocanon is among them.
  final List<Book> books;

  final Random _random;

  /// A verse shorter than this says too little to place.
  static const int minWhichBookLength = 30;

  /// A verse shorter than this has no second half worth guessing.
  static const int minFinishLength = 80;

  static const int optionCount = 4;

  /// [count] questions of [kind], or as many as the text allows: a small
  /// translation cannot ask ten different questions about three verses.
  List<QuizQuestion> make(QuizKind kind, {int count = 10}) {
    final parts = [...kind.parts]..shuffle(_random);
    final questions = <QuizQuestion>[];
    final used = <Reference>{};
    var misses = 0;
    while (questions.length < count && misses < count * 4) {
      final part = parts[(questions.length + misses) % parts.length];
      final question = switch (part) {
        QuizKind.whichBook => _whichBook(),
        QuizKind.finishVerse => _finishVerse(),
        QuizKind.bookOrder => _bookOrder(),
        QuizKind.mixed => null,
      };
      if (question == null || !used.add(question.reference)) {
        misses++;
        continue;
      }
      questions.add(question);
    }
    return questions;
  }

  // --- which book? -----------------------------------------------------

  QuizQuestion? _whichBook() {
    final verse = _randomVerse(minWhichBookLength);
    if (verse == null) return null;
    final book = bible.bookByCode(verse.reference.bookCode)!;
    final others = books
        .where((b) => b.code != book.code && b.section == book.section)
        .toList();
    if (others.isEmpty) {
      others.addAll(books.where((b) => b.code != book.code));
    }
    if (others.isEmpty) return null;
    final options = _withDistractors(
      book.name,
      (others..shuffle(_random)).map((b) => b.name),
    );
    return QuizQuestion(
      kind: QuizKind.whichBook,
      stem: 'Which book is this from?',
      prompt: verse.text,
      options: options.items,
      answer: options.answer,
      reference: verse.reference,
    );
  }

  // --- finish the verse ------------------------------------------------

  QuizQuestion? _finishVerse() {
    final verse = _randomVerse(minFinishLength);
    if (verse == null) return null;
    final split = splitPoint(verse.text);
    final ending = verse.text.substring(split).trim();
    final endings = <String>[];
    var tries = 0;
    while (endings.length < optionCount - 1 && tries++ < 12) {
      final other = _randomVerse(minFinishLength);
      if (other == null || other.reference == verse.reference) continue;
      final candidate = other.text.substring(splitPoint(other.text)).trim();
      if (candidate == ending || endings.contains(candidate)) continue;
      endings.add(candidate);
    }
    if (endings.isEmpty) return null;
    final options = _withDistractors(ending, endings);
    return QuizQuestion(
      kind: QuizKind.finishVerse,
      stem: 'How does it go on?',
      prompt: '${verse.text.substring(0, split).trimRight()} …',
      options: options.items,
      answer: options.answer,
      reference: verse.reference,
    );
  }

  /// Where to cut a verse in two: at the clause break nearest its middle,
  /// or at the space nearest its middle where it has no clause breaks in
  /// the middle three fifths.
  static int splitPoint(String text) {
    final middle = text.length ~/ 2;
    int? best;
    for (final match in _clauseBreak.allMatches(text)) {
      final at = match.end;
      if (at < text.length * 0.2 || at > text.length * 0.8) continue;
      if (best == null || (at - middle).abs() < (best - middle).abs()) {
        best = at;
      }
    }
    if (best != null) return best;
    for (final match in RegExp(' ').allMatches(text)) {
      final at = match.end;
      if (best == null || (at - middle).abs() < (best - middle).abs()) {
        best = at;
      }
    }
    return best ?? middle;
  }

  static final RegExp _clauseBreak = RegExp(r'[,;:.!?]["”’]? ');

  // --- books in order --------------------------------------------------

  QuizQuestion? _bookOrder() {
    if (books.length < 2) return null;
    final after = _random.nextBool();
    // The book asked about has a neighbour on the side asked.
    final index = after
        ? _random.nextInt(books.length - 1)
        : 1 + _random.nextInt(books.length - 1);
    final book = books[index];
    final answer = books[after ? index + 1 : index - 1];
    final near = <Book>[];
    for (var d = 1; near.length < optionCount * 2 && d < books.length; d++) {
      for (final i in [index - d, index + d]) {
        if (i < 0 || i >= books.length) continue;
        final other = books[i];
        if (other == book || other == answer) continue;
        near.add(other);
      }
    }
    final options = _withDistractors(
      answer.name,
      (near..shuffle(_random)).map((b) => b.name),
    );
    return QuizQuestion(
      kind: QuizKind.bookOrder,
      stem: after
          ? 'Which book comes after ${book.name}?'
          : 'Which book comes before ${book.name}?',
      prompt: '',
      options: options.items,
      answer: options.answer,
      reference: Reference(answer.code, answer.outline.first.number),
    );
  }

  // --- helpers ---------------------------------------------------------

  /// The right answer among up to three wrong ones, in random order.
  ({List<String> items, int answer}) _withDistractors(
    String correct,
    Iterable<String> distractors,
  ) {
    final items = [correct, ...distractors.take(optionCount - 1)]
      ..shuffle(_random);
    return (items: items, answer: items.indexOf(correct));
  }

  List<({Book book, int position})>? _chapterPool;

  /// A verse of at least [minLength] characters, chosen so that every
  /// chapter is as likely as any other, from a translation that has one.
  ({Reference reference, String text})? _randomVerse(int minLength) {
    final pool = _chapterPool ??= [
      for (final book in books)
        for (var position = 1; position <= book.chapterCount; position++)
          (book: book, position: position),
    ];
    if (pool.isEmpty) return null;
    for (var attempt = 0; attempt < 24; attempt++) {
      final pick = pool[_random.nextInt(pool.length)];
      final chapter = pick.book.chapter(pick.position);
      if (chapter == null || chapter.verseCount == 0) continue;
      final verse = 1 + _random.nextInt(chapter.verseCount);
      if (chapter.isOmitted(verse)) continue;
      final text = chapter.verseText(verse);
      if (text.length < minLength) continue;
      return (
        reference: Reference(pick.book.code, chapter.number, verse),
        text: text,
      );
    }
    return null;
  }
}

/// The books a quiz may draw on: the canon, and the deuterocanon only when
/// the reader has it shown.
List<Book> quizBooks(Bible bible, {required bool deuterocanon}) => [
  for (final book in bible.books)
    if (deuterocanon || book.section != BookSection.deuterocanon) book,
];
