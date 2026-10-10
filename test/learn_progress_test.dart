import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/model/achievements.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/learn_progress.dart';
import 'package:openword/src/model/local_date.dart';
import 'package:openword/src/model/streak.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'sleep': '{"mode":"off"}'}),
  );

  final monday = DateTime(2026, 9, 28, 9, 30);
  DateTime days(int n) => monday.add(Duration(days: n));

  group('points', () {
    test('a verse is worth more the higher it stands', () {
      expect(Xp.memoryRight(0), 10);
      expect(Xp.memoryRight(3), 16);
      expect(Xp.quizRight, 5);
      expect(Xp.perfectRound, 20);
    });

    test('a run of right answers earns a bonus at three, five and ten', () {
      expect(
        [for (var n = 1; n <= 11; n++) Xp.comboBonus(n)],
        [
          0, 0, 5, 0, 10, 0, 0, 0, 0, 20, 0, //
        ],
      );
      expect(Xp.comboBonus(20), 20);
    });
  });

  group('levels', () {
    test('come quickly at first and slowly later', () {
      expect(LearnProgress.levelFor(0), 1);
      expect(LearnProgress.levelFor(49), 1);
      expect(LearnProgress.levelFor(50), 2);
      expect(LearnProgress.levelFor(150), 3);
      expect(LearnProgress.levelFor(499), 4);
      expect(LearnProgress.levelFor(500), 5);
      expect(LearnProgress.levelFor(2250), 10);
      for (var level = 1; level < 30; level++) {
        expect(LearnProgress.levelFor(LearnProgress.xpForLevel(level)), level);
        expect(
          LearnProgress.levelFor(LearnProgress.xpForLevel(level + 1) - 1),
          level,
        );
      }
    });

    test('the bar shows how far through the level', () {
      const progress = LearnProgress(xp: 100);
      expect(progress.level, 2);
      expect(progress.levelFloor, 50);
      expect(progress.nextLevelAt, 150);
      expect(progress.levelFraction, 0.5);
    });
  });

  group('days and goals', () {
    test('points land on the day and the goal is met at the mark', () {
      var progress = LearnProgress.none.earned(15, monday, right: true);
      expect(progress.xpOn(monday), 15);
      expect(progress.right, 1);
      expect(progress.goalMetOn(monday), isFalse);
      progress = progress.earned(25, monday.add(const Duration(hours: 8)));
      expect(progress.xpOn(monday), 40);
      expect(progress.goalMetOn(monday), isTrue);
      expect(progress.xpOn(days(1)), 0);
      expect(progress.lastDays(days(1), 3), [0, 40, 0]);
    });

    test('a run of goal days counts back from today or yesterday', () {
      var progress = LearnProgress.none;
      for (var i = 0; i < 3; i++) {
        progress = progress.earned(40, days(i));
      }
      expect(progress.goalDaysRunningOn(days(2)), 3);
      // Today not yet done: the run still stands from yesterday.
      expect(progress.goalDaysRunningOn(days(3)), 3);
      // A day missed: the run is over.
      expect(progress.goalDaysRunningOn(days(4)), 0);
      // A smaller goal makes more days count.
      expect(
        progress
            .earned(20, days(3))
            .copyWith(goal: DailyGoal.gentle)
            .goalDaysRunningOn(days(3)),
        4,
      );
    });

    test('old days fall away', () {
      var progress = LearnProgress.none.earned(10, monday);
      progress = progress.earned(10, days(LearnProgress.daysKept + 1));
      expect(progress.daily.length, 1);
      expect(progress.xp, 20, reason: 'the total keeps them');
    });

    test('a goal is found from its points', () {
      expect(DailyGoal.forXp(100), DailyGoal.intense);
      expect(DailyGoal.forXp(7), DailyGoal.steady);
    });
  });

  test('round-trips through JSON', () {
    final progress = LearnProgress.none
        .earned(16, monday, right: true, scribed: true)
        .earned(0, days(1), right: false)
        .earned(20, days(1), perfectRound: true, heard: true)
        .copyWith(goal: DailyGoal.keen)
        .awarded('first_step', monday);
    final copy = LearnProgress.fromJson(
      jsonDecode(jsonEncode(progress.toJson())) as Map<String, Object?>,
    );
    expect(copy, progress);
    expect(copy!.badges['first_step'], LocalDate.only(monday));
    expect(LearnProgress.fromJson({'xp': -1}), isNull);
    expect(LearnProgress.fromJson({'xp': 'x'}), isNull);
  });

  group('badges', () {
    LearnProgress withXp(int xp) => LearnProgress(xp: xp);
    bool earned(
      Achievement badge, {
      LearnProgress progress = LearnProgress.none,
      int streak = 0,
      int onLadder = 0,
      int learnt = 0,
    }) => badge.earnedBy(
      progress: progress,
      streak: streak,
      versesOnLadder: onLadder,
      versesLearnt: learnt,
      today: monday,
    );

    test('each knows its own condition', () {
      expect(earned(Achievement.firstStep), isFalse);
      expect(earned(Achievement.firstStep, progress: withXp(1)), isTrue);
      expect(earned(Achievement.weekOfFire, streak: 6), isFalse);
      expect(earned(Achievement.weekOfFire, streak: 7), isTrue);
      expect(earned(Achievement.monthOfFire, streak: 30), isTrue);
      expect(earned(Achievement.gathering, onLadder: 10), isTrue);
      expect(earned(Achievement.byHeart, learnt: 1), isTrue);
      expect(earned(Achievement.fiveByHeart, learnt: 4), isFalse);
      expect(
        earned(
          Achievement.perfectRound,
          progress: const LearnProgress(perfectRounds: 1),
        ),
        isTrue,
      );
      expect(
        earned(Achievement.scribe, progress: const LearnProgress(scribed: 1)),
        isTrue,
      );
      expect(
        earned(Achievement.goodEar, progress: const LearnProgress(heard: 1)),
        isTrue,
      );
      expect(
        earned(Achievement.hundred, progress: const LearnProgress(right: 100)),
        isTrue,
      );
      expect(earned(Achievement.levelFive, progress: withXp(500)), isTrue);
      expect(earned(Achievement.levelFive, progress: withXp(499)), isFalse);
    });

    test('ids are unique and look themselves up', () {
      final ids = Achievement.values.map((a) => a.id).toSet();
      expect(ids.length, Achievement.values.length);
      for (final badge in Achievement.values) {
        expect(Achievement.byId(badge.id), badge);
      }
      expect(Achievement.byId('nope'), isNull);
    });
  });

  group('streak freezes', () {
    test('one is earned every seventh day, two at most', () {
      var streak = Streak.none;
      for (var i = 0; i < 6; i++) {
        streak = streak.extendedOn(days(i));
      }
      expect(streak.freezes, 0);
      streak = streak.extendedOn(days(6));
      expect(streak.count, 7);
      expect(streak.freezes, 1);
      for (var i = 7; i < 21; i++) {
        streak = streak.extendedOn(days(i));
      }
      expect(streak.count, 21);
      expect(streak.freezes, Streak.maxFreezes);
    });

    test('a freeze holds the run across one missed day, and is spent', () {
      var streak = Streak.none;
      for (var i = 0; i < 7; i++) {
        streak = streak.extendedOn(days(i));
      }
      // Day 7 missed; on day 8 the run still stands.
      expect(streak.frozenOn(days(8)), isTrue);
      expect(streak.currentOn(days(8)), 7);
      expect(streak.needsPractiseOn(days(8)), isTrue);
      streak = streak.extendedOn(days(8));
      expect(streak.count, 8);
      expect(streak.freezes, 0);
      // Without one, the next missed day ends it.
      expect(streak.currentOn(days(10)), 0);
      // Two missed days are too many for one freeze.
      final again = Streak.none.extendedOn(monday).copyWithFreezes(1);
      expect(again.currentOn(days(3)), 0);
    });

    test('is kept in JSON', () {
      final streak = Streak.none.extendedOn(monday).copyWithFreezes(2);
      expect(Streak.fromJson(streak.toJson()), streak);
      expect(Streak.fromJson({'count': 1, 'freezes': 9})!.freezes, 2);
    });
  });

  group('in the store', () {
    const john = Reference('JHN', 3, 16);

    test('an answer earns points, a day, and the first badge', () async {
      final store = await ReadingStore.load(clock: () => monday);
      final won = store.recordLearning(xp: 10, right: true);
      expect(won, [Achievement.firstStep]);
      expect(store.progress.xp, 10);
      expect(store.progress.right, 1);
      expect(store.progress.badges.keys, ['first_step']);
      expect(store.streak.count, 1);
      // Won once: not again.
      expect(store.recordLearning(xp: 10, right: true), isEmpty);
      final again = await ReadingStore.load(clock: () => monday);
      expect(again.progress.xp, 20);
      expect(again.progress.badges.keys, ['first_step']);
    });

    test('the goal is a choice and is kept', () async {
      final store = await ReadingStore.load(clock: () => monday);
      store.setDailyGoal(DailyGoal.intense);
      expect((await ReadingStore.load()).progress.goal, DailyGoal.intense);
    });

    test('a verse known after a month wins By heart', () async {
      var today = monday;
      final store = await ReadingStore.load(clock: () => today);
      store.toggleMemorise(john);
      for (var i = 0; i < 5; i++) {
        store.reviewMemory(john, remembered: true);
      }
      expect(store.versesLearnt, 1);
      final won = store.recordLearning(xp: 20, right: true);
      expect(won, containsAll([Achievement.firstStep, Achievement.byHeart]));
    });

    test(
      'goes into a backup, and two copies add up to the better one',
      () async {
        final store = await ReadingStore.load(clock: () => monday);
        store.recordLearning(xp: 30, right: true);
        store.setDailyGoal(DailyGoal.keen);
        final backup = store.export();
        expect(backup, contains('"progress"'));

        SharedPreferences.setMockInitialValues({});
        final other = await ReadingStore.load(clock: () => days(1));
        other.recordLearning(xp: 50, right: true);
        other.recordLearning(xp: 0, right: false);
        expect(other.import(backup).ok, isTrue);
        final merged = other.progress;
        expect(merged.xp, 50, reason: 'the higher total');
        expect(merged.xpOn(monday), 30);
        expect(merged.xpOn(days(1)), 50);
        expect(merged.right, 1);
        expect(merged.wrong, 1);
        expect(merged.goal, DailyGoal.steady, reason: 'the goal stays mine');
        expect(merged.badges['first_step'], LocalDate.only(monday));
        // The same backup again changes nothing.
        expect(other.import(backup).total, 0);
      },
    );
  });
}

extension on Streak {
  Streak copyWithFreezes(int freezes) =>
      Streak(count: count, best: best, last: last, freezes: freezes);
}
