import 'package:flutter/foundation.dart';

import 'bible.dart';
import 'book_meta.dart';
import 'local_date.dart';

/// One verse a reader is learning by heart, and when it is next due.
///
/// The schedule is a Leitner ladder: a verse starts on the bottom rung and
/// is due at once; each time the reader recalls it the verse climbs a rung
/// and waits longer — a day, then three, a week, a fortnight, a month, two,
/// four — and a verse not recalled drops to the bottom and is asked again
/// the same day. Nothing is timed and nothing is scored; the only question
/// ever asked is whether the reader had it or not.
@immutable
class MemoryVerse {
  const MemoryVerse({
    required this.reference,
    required this.added,
    required this.due,
    required this.updated,
    this.rung = 0,
    this.recalled = 0,
  });

  /// Days to wait after a successful recall on each rung, bottom first.
  static const List<int> intervals = [1, 3, 7, 14, 30, 60, 120];

  /// The rung at which a verse is counted as learnt: it has been recalled
  /// after a month away, which is as good a test as an app can set.
  static const int learntRung = 5;

  final Reference reference;

  /// The local date the verse was added, as [LocalDate.only] gives it.
  final DateTime added;

  /// The local date it is next due, the same way.
  final DateTime due;

  final DateTime updated;

  /// How many rungs up the ladder the verse is, from 0.
  final int rung;

  /// Times it has been recalled, ever.
  final int recalled;

  String get key => reference.encode();

  bool get isLearnt => rung >= learntRung;

  bool isDueOn(DateTime today) => !due.isAfter(LocalDate.only(today));

  /// Days until the verse is due, negative when it is overdue.
  int daysUntilDueOn(DateTime today) =>
      due.difference(LocalDate.only(today)).inDays;

  /// A new verse, due today.
  factory MemoryVerse.start(Reference reference, DateTime today) {
    final day = LocalDate.only(today);
    return MemoryVerse(
      reference: reference,
      added: day,
      due: day,
      updated: DateTime.now(),
    );
  }

  /// The verse after a practice: up a rung and due after that rung's
  /// interval when it was recalled, back to the bottom and due today when
  /// it was not.
  MemoryVerse reviewed({required bool remembered, required DateTime today}) {
    final day = LocalDate.only(today);
    if (!remembered) {
      return copyWith(rung: 0, due: day);
    }
    final wait = intervals[rung.clamp(0, intervals.length - 1)];
    return copyWith(
      rung: rung + 1,
      due: day.add(Duration(days: wait)),
      recalled: recalled + 1,
    );
  }

  MemoryVerse copyWith({
    DateTime? due,
    int? rung,
    int? recalled,
    DateTime? updated,
  }) => MemoryVerse(
    reference: reference,
    added: added,
    due: due ?? this.due,
    updated: updated ?? DateTime.now(),
    rung: rung ?? this.rung,
    recalled: recalled ?? this.recalled,
  );

  Map<String, Object?> toJson() => {
    'b': reference.bookCode,
    'c': reference.chapter,
    'v': reference.verse,
    'added': LocalDate.format(added),
    'due': LocalDate.format(due),
    't': updated.millisecondsSinceEpoch,
    if (rung > 0) 'rung': rung,
    if (recalled > 0) 'recalled': recalled,
  };

  static MemoryVerse? fromJson(Map<String, Object?> json) {
    final book = json['b'];
    final chapter = json['c'];
    final verse = json['v'];
    if (book is! String || chapter is! int || verse is! int) return null;
    if (BookMeta.lookup(book) == null || chapter < 1 || verse < 1) {
      return null;
    }
    final added = LocalDate.parse(json['added']);
    final due = LocalDate.parse(json['due']);
    if (added == null || due == null) return null;
    final rung = json['rung'];
    final recalled = json['recalled'];
    return MemoryVerse(
      reference: Reference(book, chapter, verse),
      added: added,
      due: due,
      updated: DateTime.fromMillisecondsSinceEpoch(
        json['t'] is int ? json['t']! as int : 0,
      ),
      rung: rung is int && rung > 0 ? rung : 0,
      recalled: recalled is int && recalled > 0 ? recalled : 0,
    );
  }
}

/// How much of a verse a practice shows before the reader says it.
enum MemoryPrompt {
  /// The whole verse: reading it over.
  read,

  /// The first letter of every word, the rest blanked: enough of a hint
  /// to keep a half-known verse moving.
  firstLetters,

  /// The reference alone.
  fromMemory;

  String get label => switch (this) {
    MemoryPrompt.read => 'Read',
    MemoryPrompt.firstLetters => 'First letters',
    MemoryPrompt.fromMemory => 'From memory',
  };

  /// The prompt a verse on [rung] is ready for: read it over while it is
  /// new, then the first letters, then nothing at all.
  static MemoryPrompt forRung(int rung) => rung == 0
      ? MemoryPrompt.read
      : rung < 3
      ? MemoryPrompt.firstLetters
      : MemoryPrompt.fromMemory;

  /// [text] as this prompt shows it.
  String apply(String text) => switch (this) {
    MemoryPrompt.read => text,
    MemoryPrompt.firstLetters => hint(text),
    MemoryPrompt.fromMemory => '',
  };

  /// Every word cut to its first letter, the rest of its letters each
  /// shown as a blank, with the punctuation and spacing left where they
  /// were: "For God so loved the world," becomes "F__ G__ s_ l____ t__
  /// w____,".
  static String hint(String text) {
    final out = StringBuffer();
    var inWord = false;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (_isLetter(char)) {
        out.write(inWord ? '_' : char);
        inWord = true;
      } else {
        // An apostrophe inside a word — don't, Lord's — is part of it: the
        // letters after it stay blank rather than starting a new word.
        if (!(inWord && _isWordJoiner(char))) inWord = false;
        out.write(char);
      }
    }
    return out.toString();
  }

  static final RegExp _letter = RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true);

  static bool _isLetter(String char) => _letter.hasMatch(char);

  static bool _isWordJoiner(String char) =>
      char == '’' || char == "'" || char == '‘';
}
