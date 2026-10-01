import 'package:flutter/foundation.dart';

import 'local_date.dart';

/// Days in a row with some learning done: a verse answered in practice,
/// or a round of questions finished.
///
/// A day is a local calendar day. Practising twice in a day is one day;
/// a day missed ends the run, and the next practice starts a new one.
/// The best run is kept so that a broken streak is not nothing.
@immutable
class Streak {
  const Streak({required this.count, required this.best, this.last});

  static const Streak none = Streak(count: 0, best: 0);

  /// Days in the run that [last] ended.
  final int count;

  /// The longest run ever.
  final int best;

  /// The last day with learning done, as [LocalDate.only] gives it.
  final DateTime? last;

  bool practisedOn(DateTime today) => last == LocalDate.only(today);

  /// The run as it stands on [today]: [count] while it is unbroken —
  /// practised today, or yesterday with today still to come — and
  /// nothing once a day has been missed.
  int currentOn(DateTime today) {
    final last = this.last;
    if (last == null) return 0;
    final gap = LocalDate.only(today).difference(last).inDays;
    return gap >= 0 && gap <= 1 ? count : 0;
  }

  /// Whether the run is at risk: it stands, but today has not been done.
  bool needsPractiseOn(DateTime today) =>
      currentOn(today) > 0 && !practisedOn(today);

  /// The streak after learning on [today].
  Streak extendedOn(DateTime today) {
    if (practisedOn(today)) return this;
    final count = currentOn(today) + 1;
    return Streak(
      count: count,
      best: count > best ? count : best,
      last: LocalDate.only(today),
    );
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'best': best,
    if (last != null) 'last': LocalDate.format(last!),
  };

  static Streak? fromJson(Map<String, Object?> json) {
    final count = json['count'];
    final best = json['best'];
    if (count is! int || count < 0) return null;
    return Streak(
      count: count,
      best: best is int && best >= count ? best : count,
      last: LocalDate.parse(json['last']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Streak &&
      other.count == count &&
      other.best == best &&
      other.last == last;

  @override
  int get hashCode => Object.hash(count, best, last);
}
