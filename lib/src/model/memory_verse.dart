import 'package:flutter/foundation.dart';

import 'bible.dart';
import 'book_meta.dart';
import 'local_date.dart';

/// Which timing a new verse was allotted: learnt in the evening with its
/// first recall next morning, or learnt by day with its recall a few
/// hours on.
enum TrialArm { night, day }

/// Where a verse is on its way onto the ladder.
enum MemoryStage {
  /// Added, not yet learnt.
  waiting,

  /// Learnt once, its first recall still to come.
  introduced,

  /// First recall done: on the ladder proper.
  onLadder,
}

/// One recall that the trial records: when, whether it was right, and
/// whether the reader had slept since the verse was learnt.
@immutable
class TrialRecall {
  const TrialRecall({required this.at, required this.right, this.slept});

  final DateTime at;
  final bool right;

  /// Whether a night's sleep came between the learning and this recall,
  /// as the reader said; null where the question was not asked.
  final bool? slept;

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'right': right,
    if (slept != null) 'slept': slept,
  };

  static TrialRecall? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    final right = raw['right'];
    if (at is! int || right is! bool) return null;
    final slept = raw['slept'];
    return TrialRecall(
      at: DateTime.fromMillisecondsSinceEpoch(at),
      right: right,
      slept: slept is bool ? slept : null,
    );
  }
}

/// One verse a reader is learning by heart, and when it is next due.
///
/// Each verse carries a memory of its own: how stable it is, in days
/// until the chance of recalling it falls to nine in ten, and how hard
/// it has proved. A recall makes it more stable, by more the easier the
/// verse and the longer it was left; a miss sets it back and marks it
/// harder. The due date is where the chance of recall is about to drop
/// below the target. The rungs remain as the count of recalls in a row,
/// for what the exercises and the words on screen go by: a new verse
/// climbs much as it always did, a day, then three, a week, a fortnight,
/// a month, two, four, but a verse that is easy, or a reader who keeps
/// things well, moves faster, and the reverse slower. The only question
/// ever asked is whether the reader had it or not, and how long that
/// took.
@immutable
class MemoryVerse {
  const MemoryVerse({
    required this.reference,
    required this.added,
    required this.due,
    required this.updated,
    this.rung = 0,
    this.recalled = 0,
    this.arm,
    this.introduced,
    this.recallAt,
    this.firstRecall,
    this.laterRecall,
    this.confidentMisses = 0,
    this.stability,
    this.difficulty = defaultDifficulty,
    this.hook = '',
  });

  /// Days after learning at which a recall counts as the later one.
  static const int laterRecallDays = 6;

  /// How hard a verse is taken to be until it shows otherwise, 0 to 1.
  static const double defaultDifficulty = 0.3;

  /// The chance of recall a verse is let fall to before it is due.
  static const double targetRecall = 0.9;

  /// Stability at which a verse counts as learnt: a month.
  static const double learntStability = 30;

  /// The longest a verse is left between recalls, in days: a year, so a
  /// verse well known is still met now and then.
  static const double maxStability = 365;

  /// Seconds a word may take in a right answer before it counts as slow,
  /// which says the memory is weaker than a right answer alone suggests.
  static const double slowSecondsPerWord = 2.5;

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

  /// The timing this verse was allotted when added, or null for none.
  final TrialArm? arm;

  /// When it was first learnt: the moment its first exercise was done.
  final DateTime? introduced;

  /// From when its first recall is offered.
  final DateTime? recallAt;

  /// Its first recall, once made, and its first recall six days or more
  /// after learning, once made.
  final TrialRecall? firstRecall;
  final TrialRecall? laterRecall;

  /// Times it was missed while the reader was sure of it.
  final int confidentMisses;

  /// Days until the chance of recalling the verse falls to nine in ten,
  /// or null for a verse that has not yet been recalled and so is due
  /// by the day it was last set.
  final double? stability;

  /// How hard the verse has proved, 0 easy to 1 hard.
  final double difficulty;

  /// The reader's own word for what the verse is about, their hook for
  /// it; empty until given.
  final String hook;

  /// The chance of recalling the verse at [now], from its stability and
  /// how long since it was last recalled: nine in ten at one stability's
  /// worth of days, and falling slowly after.
  double retrievability(DateTime now) {
    final s = stability;
    if (s == null) return 1;
    final since = now.difference(_lastRecall).inSeconds / 86400;
    if (since <= 0) return 1;
    return 1 / (1 + since / (9 * s));
  }

  /// The day the verse was last recalled: [due] less the wait that the
  /// stability set.
  DateTime get _lastRecall => stability == null
      ? due
      : due.subtract(Duration(days: stability!.round().clamp(1, 1 << 20)));

  String get key => reference.encode();

  MemoryStage get stage => firstRecall != null || recalled > 0
      ? MemoryStage.onLadder
      : introduced != null
      ? MemoryStage.introduced
      : MemoryStage.waiting;

  /// Whether the next practice is the first recall after learning.
  bool get awaitsFirstRecall => stage == MemoryStage.introduced;

  bool get isLearnt =>
      rung >= learntRung || (stability ?? 0) >= learntStability;

  /// Days the verse waits after its next recall, as it stands: what the
  /// screen says comes next.
  int get nextWaitDays => _waitAfterSuccess(
    retrievability: 1,
    slow: false,
    personal: 1,
  ).round().clamp(1, 1 << 20);

  bool isDueOn(DateTime today) => !due.isAfter(LocalDate.only(today));

  /// Whether the first recall is offered at [now]: from [recallAt] on.
  bool recallOfferedAt(DateTime now) =>
      awaitsFirstRecall && recallAt != null && !now.isBefore(recallAt!);

  /// Days until the verse is due, negative when it is overdue.
  int daysUntilDueOn(DateTime today) =>
      due.difference(LocalDate.only(today)).inDays;

  /// A new verse, due today, allotted to [arm].
  factory MemoryVerse.start(
    Reference reference,
    DateTime today, {
    TrialArm? arm,
  }) {
    final day = LocalDate.only(today);
    return MemoryVerse(
      reference: reference,
      added: day,
      due: day,
      updated: DateTime.now(),
      arm: arm,
    );
  }

  /// The verse once first learnt at [at]: a rung up, its first recall
  /// offered from [recallAt].
  MemoryVerse introducedAt(DateTime at, DateTime recallAt) => copyWith(
    rung: 1,
    due: LocalDate.only(recallAt),
    introduced: at,
    recallAt: recallAt,
  );

  /// The verse after its first recall at [at], and after a later one.
  MemoryVerse firstRecalled(DateTime at, {required bool right, bool? slept}) =>
      reviewed(remembered: right, today: at).copyWith(
        firstRecall: TrialRecall(at: at, right: right, slept: slept),
      );

  MemoryVerse laterRecalled(DateTime at, {required bool right}) => copyWith(
    laterRecall: TrialRecall(at: at, right: right),
  );

  /// Whether a review at [at] is the later recall the trial waits for.
  bool isLaterRecallAt(DateTime at) =>
      introduced != null &&
      laterRecall == null &&
      firstRecall != null &&
      at.difference(introduced!).inDays >= laterRecallDays;

  /// How many days of stability a recall now would give: the stability
  /// grown by a factor that is larger the easier the verse, larger again
  /// when the verse was recalled late, with the chance of recall low
  /// (the harder retrieval is the better one), smaller when the answer
  /// came slowly, and scaled by how well this reader keeps things.
  double _waitAfterSuccess({
    required double retrievability,
    required bool slow,
    required double personal,
  }) {
    final current = stability ?? _ladderStability;
    var growth = 2.2 * (1.3 - difficulty) * personal;
    if (retrievability < 0.7) growth *= 1.2;
    if (slow) growth *= 0.7;
    if (growth < 1.1) growth = 1.1;
    final grown = stability == null ? current : current * growth;
    return grown.clamp(0.5, maxStability);
  }

  /// The stability the old ladder gave a verse on its rung: what a verse
  /// from before carries over, and what a first recall is worth.
  double get _ladderStability => rung <= 0
      ? 1
      : intervals[(rung - 1).clamp(0, intervals.length - 1)].toDouble();

  /// The verse after a practice. Recalled, it climbs a rung, grows more
  /// stable and is due when its chance of recall will have fallen to the
  /// target; missed, it drops to the bottom, loses most of its stability,
  /// is marked harder and is due today. [seconds] and [words] say how
  /// long the answer took, and [personal] how well this reader keeps
  /// verses, 1 being the common run.
  MemoryVerse reviewed({
    required bool remembered,
    required DateTime today,
    double? seconds,
    int? words,
    double personal = 1,
  }) {
    final day = LocalDate.only(today);
    if (!remembered) {
      return copyWith(
        rung: 0,
        due: day,
        stability: stability == null
            ? null
            : (stability! * 0.25).clamp(0.5, 1e9),
        difficulty: (difficulty + 0.15).clamp(0.05, 0.9),
      );
    }
    final slow =
        seconds != null &&
        words != null &&
        words > 0 &&
        seconds / words > slowSecondsPerWord;
    final grown = _waitAfterSuccess(
      retrievability: retrievability(today),
      slow: slow,
      personal: personal,
    );
    final wait = grown.round().clamp(1, 1 << 20);
    return copyWith(
      rung: rung + 1,
      due: day.add(Duration(days: wait)),
      recalled: recalled + 1,
      stability: grown,
      difficulty: (difficulty - 0.02).clamp(0.05, 0.9),
    );
  }

  MemoryVerse withHook(String hook) => copyWith(hook: hook.trim());

  MemoryVerse copyWith({
    DateTime? due,
    int? rung,
    int? recalled,
    DateTime? updated,
    DateTime? introduced,
    DateTime? recallAt,
    TrialRecall? firstRecall,
    TrialRecall? laterRecall,
    int? confidentMisses,
    double? stability,
    double? difficulty,
    String? hook,
  }) => MemoryVerse(
    reference: reference,
    added: added,
    due: due ?? this.due,
    updated: updated ?? DateTime.now(),
    rung: rung ?? this.rung,
    recalled: recalled ?? this.recalled,
    arm: arm,
    introduced: introduced ?? this.introduced,
    recallAt: recallAt ?? this.recallAt,
    firstRecall: firstRecall ?? this.firstRecall,
    laterRecall: laterRecall ?? this.laterRecall,
    confidentMisses: confidentMisses ?? this.confidentMisses,
    stability: stability ?? this.stability,
    difficulty: difficulty ?? this.difficulty,
    hook: hook ?? this.hook,
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
    if (arm != null) 'arm': arm!.name,
    if (introduced != null) 'introduced': introduced!.millisecondsSinceEpoch,
    if (recallAt != null) 'recallAt': recallAt!.millisecondsSinceEpoch,
    if (firstRecall != null) 'first': firstRecall!.toJson(),
    if (laterRecall != null) 'later': laterRecall!.toJson(),
    if (confidentMisses > 0) 'sureMisses': confidentMisses,
    if (stability != null) 's': stability,
    if (difficulty != defaultDifficulty) 'd': difficulty,
    if (hook.isNotEmpty) 'hook': hook,
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
    final arm = json['arm'];
    final introduced = json['introduced'];
    final recallAt = json['recallAt'];
    final sureMisses = json['sureMisses'];
    final stability = json['s'];
    final difficulty = json['d'];
    final hook = json['hook'];
    return MemoryVerse(
      reference: Reference(book, chapter, verse),
      added: added,
      due: due,
      updated: DateTime.fromMillisecondsSinceEpoch(
        json['t'] is int ? json['t']! as int : 0,
      ),
      rung: rung is int && rung > 0 ? rung : 0,
      recalled: recalled is int && recalled > 0 ? recalled : 0,
      arm: arm is String
          ? TrialArm.values.cast<TrialArm?>().firstWhere(
              (a) => a!.name == arm,
              orElse: () => null,
            )
          : null,
      introduced: introduced is int
          ? DateTime.fromMillisecondsSinceEpoch(introduced)
          : null,
      recallAt: recallAt is int
          ? DateTime.fromMillisecondsSinceEpoch(recallAt)
          : null,
      firstRecall: TrialRecall.fromJson(json['first']),
      laterRecall: TrialRecall.fromJson(json['later']),
      confidentMisses: sureMisses is int && sureMisses > 0 ? sureMisses : 0,
      stability: stability is num && stability > 0
          ? stability.toDouble()
          : null,
      difficulty: difficulty is num
          ? difficulty.toDouble().clamp(0.05, 0.9)
          : defaultDifficulty,
      hook: hook is String ? hook : '',
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
