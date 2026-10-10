import 'dart:math';

import 'package:flutter/foundation.dart';

import 'memory_verse.dart';

/// How the app times a new verse's first learning against a night's
/// sleep, and whether it measures the difference.
enum SleepMode {
  /// Each new verse is allotted at random to a night or a day: learnt in
  /// the evening with its first recall the next morning, or learnt by
  /// day with its first recall a few hours on. Over time the app can say
  /// which worked better for this reader.
  trial(
    'Measure it',
    'New verses take turns: some learnt at night, some by day, and the app reports which you recall better.',
  ),

  /// Every new verse is learnt in the evening and recalled next morning.
  nights(
    'Nights only',
    'Every new verse is learnt in the evening and asked for next morning.',
  ),

  /// New verses are learnt whenever, as before.
  off('Off', 'New verses are learnt whenever you practise, with no timing.');

  const SleepMode(this.label, this.description);

  final String label;
  final String description;
}

/// When evening begins and morning ends, and the [SleepMode].
@immutable
class SleepPolicy {
  const SleepPolicy({
    this.mode = SleepMode.trial,
    this.eveningStart = 19,
    this.morningEnd = 11,
  });

  static const SleepPolicy standard = SleepPolicy();

  final SleepMode mode;

  /// The hour, 0 to 23, from which it is evening: new night verses are
  /// offered from here.
  final int eveningStart;

  /// The hour before which it is morning: first recalls of night verses
  /// are expected before it, though they are offered until done.
  final int morningEnd;

  /// Hours a day verse waits between its learning and its first recall.
  static const int dayGapHours = 4;

  /// The hour a night verse's first recall is offered from.
  static const int wakeHour = 5;

  bool isEvening(DateTime at) => at.hour >= eveningStart;

  bool isMorning(DateTime at) => at.hour < morningEnd;

  /// Whether a day verse learnt now would have its recall before evening.
  bool roomForDayVerse(DateTime at) => at.hour + dayGapHours < eveningStart;

  /// The arm a verse added now goes to: random in a trial, a night when
  /// nights only, and none at all when off.
  TrialArm? armForNew(Random random) => switch (mode) {
    SleepMode.trial => random.nextBool() ? TrialArm.night : TrialArm.day,
    SleepMode.nights => TrialArm.night,
    SleepMode.off => null,
  };

  /// Whether a verse still waiting to be learnt is offered at [at].
  bool offersLearning(TrialArm? arm, DateTime at) => switch (arm) {
    null => true,
    TrialArm.night => mode == SleepMode.off || isEvening(at),
    TrialArm.day => mode == SleepMode.off || roomForDayVerse(at),
  };

  /// When a verse learnt at [at] has its first recall offered from.
  DateTime recallAfter(DateTime at, TrialArm? arm) => switch (arm) {
    TrialArm.night => DateTime(at.year, at.month, at.day + 1, wakeHour),
    TrialArm.day => at.add(const Duration(hours: dayGapHours)),
    // As before this: the next day, whenever.
    null => DateTime(at.year, at.month, at.day + 1),
  };

  SleepPolicy copyWith({SleepMode? mode, int? eveningStart, int? morningEnd}) =>
      SleepPolicy(
        mode: mode ?? this.mode,
        eveningStart: eveningStart ?? this.eveningStart,
        morningEnd: morningEnd ?? this.morningEnd,
      );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'evening': eveningStart,
    'morning': morningEnd,
  };

  static SleepPolicy fromJson(Map<String, Object?> json) {
    final mode = json['mode'];
    final evening = json['evening'];
    final morning = json['morning'];
    return SleepPolicy(
      mode: SleepMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => SleepMode.trial,
      ),
      eveningStart: evening is int ? evening.clamp(12, 23) : 19,
      morningEnd: morning is int ? morning.clamp(6, 14) : 11,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SleepPolicy &&
      other.mode == mode &&
      other.eveningStart == eveningStart &&
      other.morningEnd == morningEnd;

  @override
  int get hashCode => Object.hash(mode, eveningStart, morningEnd);
}

/// What the trial has found so far: first recalls after sleep against
/// first recalls the same day, as they happened rather than as they were
/// allotted, since a verse put off until tomorrow was slept on whatever
/// the plan was.
@immutable
class SleepTrialReport {
  const SleepTrialReport({
    required this.sleptAsked,
    required this.sleptRight,
    required this.awakeAsked,
    required this.awakeRight,
    required this.sleptLaterAsked,
    required this.sleptLaterRight,
    required this.awakeLaterAsked,
    required this.awakeLaterRight,
  });

  /// Verses in each group before the report says anything.
  static const int minimum = 5;

  final int sleptAsked;
  final int sleptRight;
  final int awakeAsked;
  final int awakeRight;
  final int sleptLaterAsked;
  final int sleptLaterRight;
  final int awakeLaterAsked;
  final int awakeLaterRight;

  bool get hasEnough => sleptAsked >= minimum && awakeAsked >= minimum;

  double get sleptRate => sleptAsked == 0 ? 0 : sleptRight / sleptAsked;
  double get awakeRate => awakeAsked == 0 ? 0 : awakeRight / awakeAsked;

  bool get hasLater => sleptLaterAsked >= minimum && awakeLaterAsked >= minimum;
  double get sleptLaterRate =>
      sleptLaterAsked == 0 ? 0 : sleptLaterRight / sleptLaterAsked;
  double get awakeLaterRate =>
      awakeLaterAsked == 0 ? 0 : awakeLaterRight / awakeLaterAsked;

  static SleepTrialReport of(Iterable<MemoryVerse> verses) {
    var sa = 0, sr = 0, aa = 0, ar = 0, sla = 0, slr = 0, ala = 0, alr = 0;
    for (final verse in verses) {
      final first = verse.firstRecall;
      if (first == null || first.slept == null) continue;
      if (first.slept!) {
        sa++;
        if (first.right) sr++;
      } else {
        aa++;
        if (first.right) ar++;
      }
      final later = verse.laterRecall;
      if (later == null) continue;
      if (first.slept!) {
        sla++;
        if (later.right) slr++;
      } else {
        ala++;
        if (later.right) alr++;
      }
    }
    return SleepTrialReport(
      sleptAsked: sa,
      sleptRight: sr,
      awakeAsked: aa,
      awakeRight: ar,
      sleptLaterAsked: sla,
      sleptLaterRight: slr,
      awakeLaterAsked: ala,
      awakeLaterRight: alr,
    );
  }
}
