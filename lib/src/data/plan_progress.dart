import 'package:flutter/foundation.dart';

import '../model/bible.dart';
import '../model/reading_plan.dart';

/// How far a reader is through one plan.
///
/// There is no streak and no count of days missed. "Today" is simply the
/// first day with anything left to read, so a day not read is waiting
/// tomorrow rather than added to a pile. The date a plan was started is
/// kept only to say, gently and only when it is worth saying, that the
/// reader has fallen behind the pace they set — and to let them pick up
/// from today without pretending they read what they did not.
@immutable
class PlanProgress {
  const PlanProgress({
    required this.plan,
    required this.startedOn,
    required this.done,
    required this.updated,
  });

  final ReadingPlan plan;

  /// The local date day 1 was, or would have been, read on.
  final DateTime startedOn;

  /// Slots read. A slot is one chapter on one day of the plan.
  final Set<int> done;
  final DateTime updated;

  /// A single day off makes no measurable difference to a habit, so being
  /// one day behind is not mentioned. Two is when it is.
  static const int behindThreshold = 2;

  int get slotsDone => done.length;

  bool get isComplete => slotsDone >= plan.slotCount;

  double get fraction => plan.slotCount == 0 ? 0 : slotsDone / plan.slotCount;

  bool isRead(int slot) => done.contains(slot);

  bool isDayRead(PlanDay day) => day.slots.every(done.contains);

  int readInDay(PlanDay day) => day.slots.where(done.contains).length;

  int get daysRead => plan.days.where(isDayRead).length;

  /// The first day with anything unread, or null when the plan is done.
  PlanDay? get currentDay {
    for (final day in plan.days) {
      if (!isDayRead(day)) return day;
    }
    return null;
  }

  /// The first unread chapter of the current day: where "Continue" goes.
  int? get nextSlot {
    final day = currentDay;
    if (day == null) return null;
    for (final slot in day.slots) {
      if (!done.contains(slot)) return slot;
    }
    return null;
  }

  Reference chapterAt(int slot) {
    final day = plan.dayOfSlot(slot);
    return day.chapters[slot - day.firstSlot];
  }

  /// The day number the pace set at the start would have the reader on.
  int scheduledDayOn(DateTime today) {
    final elapsed = dateOnly(today).difference(startedOn).inDays;
    return (elapsed + 1).clamp(1, plan.length);
  }

  /// Days behind that pace, never negative: reading ahead is not "ahead"
  /// of anything worth announcing.
  int behindOn(DateTime today) {
    final current = currentDay;
    if (current == null) return 0;
    final behind = scheduledDayOn(today) - current.number;
    return behind > 0 ? behind : 0;
  }

  /// Whether today's reading is still to do — what the reader's plan
  /// button carries a dot for.
  bool hasReadingDueOn(DateTime today) {
    final current = currentDay;
    return current != null && current.number <= scheduledDayOn(today);
  }

  /// Moves the pace so that the current day is today. Marks nothing read.
  PlanProgress pickedUpOn(DateTime today) {
    final current = currentDay;
    if (current == null) return this;
    return copyWith(
      startedOn: dateOnly(today).subtract(Duration(days: current.number - 1)),
    );
  }

  PlanProgress copyWith({
    DateTime? startedOn,
    Set<int>? done,
    DateTime? updated,
  }) => PlanProgress(
    plan: plan,
    startedOn: startedOn ?? this.startedOn,
    done: done ?? this.done,
    updated: updated ?? DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': plan.id,
    'start': _formatDate(startedOn),
    't': updated.millisecondsSinceEpoch,
    'done': (done.toList()..sort()),
  };

  static PlanProgress? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String) return null;
    final plan = ReadingPlans.byId(id);
    if (plan == null) return null;
    final start = _parseDate(json['start']);
    if (start == null) return null;
    final rawDone = json['done'];
    return PlanProgress(
      plan: plan,
      startedOn: start,
      done: {
        if (rawDone is List)
          for (final slot in rawDone)
            if (slot is int && slot >= 0 && slot < plan.slotCount) slot,
      },
      updated: DateTime.fromMillisecondsSinceEpoch(
        json['t'] is int ? json['t']! as int : 0,
      ),
    );
  }

  /// Midnight UTC of the local calendar date, so that the days between
  /// two dates are never 23 or 25 hours across a change of clocks.
  static DateTime dateOnly(DateTime moment) =>
      DateTime.utc(moment.year, moment.month, moment.day);

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.contains(null)) return null;
    return DateTime.utc(numbers[0]!, numbers[1]!, numbers[2]!);
  }
}
