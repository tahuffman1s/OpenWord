import 'package:flutter/foundation.dart';

import 'local_date.dart';

/// Days in a row with some learning done: a verse answered in practice,
/// or a round of questions finished.
///
/// A day is a local calendar day. Practising twice in a day is one day;
/// a day missed ends the run, and the next practice starts a new one.
/// The best run is kept so that a broken streak is not nothing.
///
/// A streak freeze forgives one missed day. One is earned for every seven
/// days kept up, at most [maxFreezes] held, and one is spent, unasked,
/// the first time a day is missed with one in hand.
@immutable
class Streak {
  const Streak({
    required this.count,
    required this.best,
    this.last,
    this.freezes = 0,
  });

  static const Streak none = Streak(count: 0, best: 0);

  static const int maxFreezes = 2;

  /// Days kept up per freeze earned.
  static const int daysPerFreeze = 7;

  /// Days in the run that [last] ended.
  final int count;

  /// The longest run ever.
  final int best;

  /// The last day with learning done, as [LocalDate.only] gives it.
  final DateTime? last;

  /// Missed days the run can survive.
  final int freezes;

  bool practisedOn(DateTime today) => last == LocalDate.only(today);

  int _gapTo(DateTime today) {
    final last = this.last;
    if (last == null) return -1;
    return LocalDate.only(today).difference(last).inDays;
  }

  /// Whether a freeze is what holds the run on [today]: yesterday was
  /// missed, and one is in hand.
  bool frozenOn(DateTime today) => _gapTo(today) == 2 && freezes > 0;

  /// The run as it stands on [today]: [count] while it is unbroken —
  /// practised today, or yesterday with today still to come, or the day
  /// before with a freeze to cover yesterday — and nothing once broken.
  int currentOn(DateTime today) {
    final gap = _gapTo(today);
    if (gap < 0) return 0;
    return gap <= 1 || frozenOn(today) ? count : 0;
  }

  /// Whether the run is at risk: it stands, but today has not been done.
  bool needsPractiseOn(DateTime today) =>
      currentOn(today) > 0 && !practisedOn(today);

  /// The streak after learning on [today]: a day longer, a freeze spent
  /// where one was needed, and a freeze earned at every seventh day.
  Streak extendedOn(DateTime today) {
    if (practisedOn(today)) return this;
    final spent = frozenOn(today);
    final count = currentOn(today) + 1;
    var freezes = spent ? this.freezes - 1 : this.freezes;
    if (count % daysPerFreeze == 0 && freezes < maxFreezes) freezes++;
    return Streak(
      count: count,
      best: count > best ? count : best,
      last: LocalDate.only(today),
      freezes: freezes,
    );
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'best': best,
    if (last != null) 'last': LocalDate.format(last!),
    if (freezes > 0) 'freezes': freezes,
  };

  static Streak? fromJson(Map<String, Object?> json) {
    final count = json['count'];
    final best = json['best'];
    final freezes = json['freezes'];
    if (count is! int || count < 0) return null;
    return Streak(
      count: count,
      best: best is int && best >= count ? best : count,
      last: LocalDate.parse(json['last']),
      freezes: freezes is int ? freezes.clamp(0, maxFreezes) : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Streak &&
      other.count == count &&
      other.best == best &&
      other.last == last &&
      other.freezes == freezes;

  @override
  int get hashCode => Object.hash(count, best, last, freezes);
}
