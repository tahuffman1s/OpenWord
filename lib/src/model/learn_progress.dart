import 'dart:math';

import 'package:flutter/foundation.dart';

import 'local_date.dart';

/// What learning earns, in points.
abstract final class Xp {
  /// A verse on the ladder answered right: more the higher it stands,
  /// since a verse recalled after a month is worth more than one copied.
  static int memoryRight(int rung) => 10 + 2 * rung;

  /// A question in a round answered right.
  static const int quizRight = 5;

  /// A round with every answer right.
  static const int perfectRound = 20;

  /// The bonus for the nth right answer in a row, where there is one.
  static int comboBonus(int inARow) => switch (inARow) {
    3 => 5,
    5 => 10,
    10 => 20,
    _ => inARow > 10 && inARow % 10 == 0 ? 20 : 0,
  };
}

/// How sure a reader was before answering from memory.
///
/// Asked so that the misses made with confidence can be told apart: they
/// are the ones most readily corrected once shown, and the ones most
/// likely to come back if they are not.
enum Confidence {
  sure('Sure'),
  fairly('Fairly sure'),
  guessing('Guessing');

  const Confidence(this.label);

  final String label;
}

/// How much a day asks for. Like a language app's, the choice is the
/// reader's and the smallest is meant to be kept.
enum DailyGoal {
  gentle(20, 'Gentle', 'A verse or two'),
  steady(40, 'Steady', 'A short session'),
  keen(60, 'Keen', 'A proper sit-down'),
  intense(100, 'Intense', 'Make a dent');

  const DailyGoal(this.xp, this.label, this.description);

  final int xp;
  final String label;
  final String description;

  static DailyGoal forXp(int xp) =>
      values.firstWhere((g) => g.xp == xp, orElse: () => steady);
}

/// Points earned, by day and in all, the level they add up to, the day's
/// goal, and the badges won.
///
/// Levels come thick and fast at first and slowly later: level n is
/// reached at 25·n·(n−1) points, so the second takes 50, the fifth 500
/// and the tenth 2,250.
@immutable
class LearnProgress {
  const LearnProgress({
    this.xp = 0,
    this.daily = const {},
    this.right = 0,
    this.wrong = 0,
    this.perfectRounds = 0,
    this.scribed = 0,
    this.heard = 0,
    this.goal = DailyGoal.steady,
    this.badges = const {},
    this.confidence = const {},
    this.confidentMisses = 0,
  });

  static const LearnProgress none = LearnProgress();

  /// How many days of points are kept.
  static const int daysKept = 60;

  final int xp;

  /// Points per local day, the day as [LocalDate.only] gives it.
  final Map<DateTime, int> daily;

  /// Answers right and wrong, ever.
  final int right;
  final int wrong;

  /// Rounds with every answer right.
  final int perfectRounds;

  /// Verses written out right.
  final int scribed;

  /// Verses heard and put together right.
  final int heard;

  final DailyGoal goal;

  /// Badges won, by id, with the day each was won.
  final Map<String, DateTime> badges;

  /// Answers from memory by how sure the reader was: asked and right.
  final Map<Confidence, (int asked, int right)> confidence;

  /// Misses made while sure.
  final int confidentMisses;

  /// How often the reader was right when they said [level], or null
  /// before anything was asked at that level.
  double? calibration(Confidence level) {
    final tally = confidence[level];
    if (tally == null || tally.$1 == 0) return null;
    return tally.$2 / tally.$1;
  }

  int get level => levelFor(xp);

  /// Points at which [level] began and the next begins.
  int get levelFloor => xpForLevel(level);
  int get nextLevelAt => xpForLevel(level + 1);

  /// How far through the level, 0 to 1.
  double get levelFraction =>
      (xp - levelFloor) / (nextLevelAt - levelFloor).clamp(1, 1 << 30);

  static int xpForLevel(int level) => 25 * level * (level - 1);

  static int levelFor(int xp) =>
      ((1 + sqrt(1 + 4 * xp / 25)) / 2).floor().clamp(1, 1 << 20);

  int xpOn(DateTime day) => daily[LocalDate.only(day)] ?? 0;

  bool goalMetOn(DateTime day) => xpOn(day) >= goal.xp;

  /// Days running, ending today or yesterday, on which the goal was met.
  int goalDaysRunningOn(DateTime today) {
    var day = LocalDate.only(today);
    if (!goalMetOn(day)) day = day.subtract(const Duration(days: 1));
    var run = 0;
    while (goalMetOn(day)) {
      run++;
      day = day.subtract(const Duration(days: 1));
    }
    return run;
  }

  /// Points for each of the [days] days ending today, oldest first.
  List<int> lastDays(DateTime today, int days) {
    final end = LocalDate.only(today);
    return [
      for (var i = days - 1; i >= 0; i--)
        daily[end.subtract(Duration(days: i))] ?? 0,
    ];
  }

  /// With [points] earned on [today].
  LearnProgress earned(
    int points,
    DateTime today, {
    bool? right,
    bool perfectRound = false,
    bool scribed = false,
    bool heard = false,
    Confidence? confidence,
  }) {
    final day = LocalDate.only(today);
    final cutoff = day.subtract(const Duration(days: daysKept));
    final next = {
      for (final entry in daily.entries)
        if (!entry.key.isBefore(cutoff)) entry.key: entry.value,
    };
    next[day] = (next[day] ?? 0) + points;
    return copyWith(
      xp: xp + points,
      daily: next,
      right: right == true ? this.right + 1 : null,
      wrong: right == false ? wrong + 1 : null,
      perfectRounds: perfectRound ? perfectRounds + 1 : null,
      scribed: scribed ? this.scribed + 1 : null,
      heard: heard ? this.heard + 1 : null,
      confidence: confidence == null || right == null
          ? null
          : {
              ...this.confidence,
              confidence: (
                (this.confidence[confidence]?.$1 ?? 0) + 1,
                (this.confidence[confidence]?.$2 ?? 0) + (right ? 1 : 0),
              ),
            },
      confidentMisses: confidence == Confidence.sure && right == false
          ? confidentMisses + 1
          : null,
    );
  }

  LearnProgress awarded(String badge, DateTime today) =>
      copyWith(badges: {...badges, badge: LocalDate.only(today)});

  LearnProgress copyWith({
    int? xp,
    Map<DateTime, int>? daily,
    int? right,
    int? wrong,
    int? perfectRounds,
    int? scribed,
    int? heard,
    DailyGoal? goal,
    Map<String, DateTime>? badges,
    Map<Confidence, (int, int)>? confidence,
    int? confidentMisses,
  }) => LearnProgress(
    xp: xp ?? this.xp,
    daily: daily ?? this.daily,
    right: right ?? this.right,
    wrong: wrong ?? this.wrong,
    perfectRounds: perfectRounds ?? this.perfectRounds,
    scribed: scribed ?? this.scribed,
    heard: heard ?? this.heard,
    goal: goal ?? this.goal,
    badges: badges ?? this.badges,
    confidence: confidence ?? this.confidence,
    confidentMisses: confidentMisses ?? this.confidentMisses,
  );

  Map<String, Object?> toJson() => {
    'xp': xp,
    'daily': {
      for (final entry in daily.entries)
        LocalDate.format(entry.key): entry.value,
    },
    'right': right,
    'wrong': wrong,
    'perfect': perfectRounds,
    'scribed': scribed,
    'heard': heard,
    'goal': goal.xp,
    'badges': {
      for (final entry in badges.entries)
        entry.key: LocalDate.format(entry.value),
    },
    if (confidence.isNotEmpty)
      'conf': {
        for (final entry in confidence.entries)
          entry.key.name: [entry.value.$1, entry.value.$2],
      },
    if (confidentMisses > 0) 'sureMisses': confidentMisses,
  };

  static LearnProgress? fromJson(Map<String, Object?> json) {
    final xp = json['xp'];
    if (xp is! int || xp < 0) return null;
    int count(String key) {
      final value = json[key];
      return value is int && value > 0 ? value : 0;
    }

    final rawDaily = json['daily'];
    final rawBadges = json['badges'];
    final rawConf = json['conf'];
    final goal = json['goal'];
    return LearnProgress(
      xp: xp,
      daily: {
        if (rawDaily is Map)
          for (final entry in rawDaily.entries)
            if (LocalDate.parse(entry.key) case final day?)
              if (entry.value case final int points when points > 0)
                day: points,
      },
      right: count('right'),
      wrong: count('wrong'),
      perfectRounds: count('perfect'),
      scribed: count('scribed'),
      heard: count('heard'),
      goal: goal is int ? DailyGoal.forXp(goal) : DailyGoal.steady,
      badges: {
        if (rawBadges is Map)
          for (final entry in rawBadges.entries)
            if (entry.key case final String id)
              if (LocalDate.parse(entry.value) case final day?) id: day,
      },
      confidence: {
        if (rawConf is Map)
          for (final level in Confidence.values)
            if (rawConf[level.name] case final List tally)
              if (tally.length == 2 && tally[0] is int && tally[1] is int)
                level: (tally[0] as int, tally[1] as int),
      },
      confidentMisses: count('sureMisses'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LearnProgress &&
      other.xp == xp &&
      mapEquals(other.daily, daily) &&
      other.right == right &&
      other.wrong == wrong &&
      other.perfectRounds == perfectRounds &&
      other.scribed == scribed &&
      other.heard == heard &&
      other.goal == goal &&
      mapEquals(other.badges, badges) &&
      mapEquals(other.confidence, confidence) &&
      other.confidentMisses == confidentMisses;

  @override
  int get hashCode => Object.hash(xp, right, wrong, goal, badges.length);
}
