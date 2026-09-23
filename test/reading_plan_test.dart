import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/data/plan_progress.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/reading_plan.dart';
import 'package:openword/src/model/versification_table.dart';
import 'package:shared_preferences/shared_preferences.dart';

int versesOf(Reference chapter) => int.parse(
  englishVerseCounts[chapter.bookCode]!.split(' ')[chapter.chapter - 1],
);

void main() {
  group('splitting a book into days', () {
    test('keeps order, splits nothing and leaves no day empty', () {
      final weights = [5, 1, 1, 30, 2, 2, 2, 9, 1];
      final days = ReadingPlan.split(weights, 4);
      expect(days.expand((d) => d), List.generate(weights.length, (i) => i));
      expect(days.every((d) => d.isNotEmpty), isTrue);
    });

    test('one item a day when there are as many items as days', () {
      final days = ReadingPlan.split(List.filled(31, 1), 31);
      expect(days.map((d) => d.length), everyElement(1));
    });

    test('a very long item does not starve the days after it', () {
      final days = ReadingPlan.split([1, 1, 176, 1, 1], 5);
      expect(days.map((d) => d.length), everyElement(1));
    });
  });

  group('the plans', () {
    for (final plan in ReadingPlans.all) {
      test('${plan.name}: every day has something and nothing repeats', () {
        expect(plan.days, isNotEmpty);
        expect(plan.days.every((day) => day.chapters.isNotEmpty), isTrue);
        final seen = <String>{};
        for (final day in plan.days) {
          for (final chapter in day.chapters) {
            expect(
              seen.add(chapter.encode()),
              isTrue,
              reason: '$chapter appears twice',
            );
          }
        }
        // Slots are numbered straight through, day after day.
        var slot = 0;
        for (final day in plan.days) {
          expect(day.firstSlot, slot);
          slot += day.slotCount;
        }
        expect(plan.slotCount, slot);
      });
    }

    test('the Bible in a year is the whole Protestant canon, in order', () {
      final plan = ReadingPlans.bibleInAYear;
      expect(plan.length, 365);
      final chapters = plan.days.expand((d) => d.chapters).toList();
      expect(chapters, hasLength(1189));
      expect(chapters.first, const Reference('GEN', 1));
      expect(chapters.last, const Reference('REV', 22));
    });

    test('the days are even in reading, not in chapters', () {
      final plan = ReadingPlans.bibleInAYear;
      final verses = plan.days.map((d) => d.verses).toList()..sort();
      final median = verses[verses.length ~/ 2];
      // 31,102 verses over 365 days is about 85 a day.
      expect(median, inInclusiveRange(75, 95));
      // Nothing is a whole week's reading in one sitting.
      expect(verses.last, lessThan(260));
    });

    test('that plan has two readings every day, and the whole Bible', () {
      final plan = ReadingPlans.bothTestaments;
      for (final day in plan.days) {
        final codes = day.chapters.map((c) => c.bookCode).toSet();
        final old = codes.where((c) => _isOld(c) && c != 'PSA');
        final other = codes.where((c) => !_isOld(c) || c == 'PSA');
        expect(old, isNotEmpty, reason: 'day ${day.number}');
        expect(other, isNotEmpty, reason: 'day ${day.number}');
      }
      expect(plan.slotCount, 1189);
    });

    test('weaving spreads the shorter run through the longer', () {
      final nt = chaptersOf(['MAT']);
      final psalms = chaptersOf(['PSA']).take(7).toList();
      final woven = weave(nt, psalms);
      expect(woven, hasLength(nt.length + psalms.length));
      final at = [
        for (var i = 0; i < woven.length; i++)
          if (woven[i].bookCode == 'PSA') i,
      ];
      // A psalm about every fifth reading, not seven together at one end.
      for (var k = 1; k < at.length; k++) {
        expect(at[k] - at[k - 1], inInclusiveRange(4, 6));
      }
    });

    test('Proverbs is one chapter a day; Psalm 119 has a day to itself', () {
      expect(
        ReadingPlans.proverbsMonth.days.map((d) => d.label),
        List.generate(31, (i) => 'Proverbs ${i + 1}'),
      );
      final psalm119 = ReadingPlans.psalms30.days.firstWhere(
        (d) => d.chapters.contains(const Reference('PSA', 119)),
      );
      expect(psalm119.chapters, [const Reference('PSA', 119)]);
      expect(psalm119.label, 'Psalm 119');
    });

    test('a day reads as passages', () {
      final day = PlanDay(
        number: 1,
        chapters: const [
          Reference('GEN', 49),
          Reference('GEN', 50),
          Reference('EXO', 1),
          Reference('JUD', 1),
        ],
        firstSlot: 0,
        verses: 0,
      );
      expect(day.label, 'Genesis 49–50; Exodus 1; Jude');
    });

    test('says how long a day takes', () {
      expect(ReadingPlans.proverbsMonth.minutesPerDay, 4);
      expect(ReadingPlans.bibleInAYear.minutesPerDay, 10);
    });

    test('a plan\'s days never depend on which translation is open', () {
      // Built from the English verse table, so building twice is the same.
      expect(
        ReadingPlans.bibleInAYear.days[100].label,
        ReadingPlans.bibleInAYear.days[100].label,
      );
      for (final day in ReadingPlans.gospels.days) {
        expect(day.verses, day.chapters.map(versesOf).fold(0, (a, b) => a + b));
      }
    });
  });

  group('progress', () {
    late DateTime now;
    late ReadingStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(const {});
      now = DateTime(2026, 3, 1, 9);
      store = await ReadingStore.load(clock: () => now);
    });

    final plan = ReadingPlans.proverbsMonth;

    test('today is the first day with anything left, whatever the date', () {
      store.startPlan(plan);
      expect(store.progressFor(plan.id)!.currentDay!.number, 1);
      now = now.add(const Duration(days: 10));
      // Ten days away and nothing read: still day 1, not a pile of ten.
      expect(store.progressFor(plan.id)!.currentDay!.number, 1);
      store.setPlanDay(plan.id, plan.days[0], read: true);
      expect(store.progressFor(plan.id)!.currentDay!.number, 2);
    });

    test('one day behind is not worth saying; two is', () {
      store.startPlan(plan);
      now = now.add(const Duration(days: 1));
      expect(store.progressFor(plan.id)!.behindOn(now), 1);
      now = now.add(const Duration(days: 1));
      expect(store.progressFor(plan.id)!.behindOn(now), 2);
      expect(PlanProgress.behindThreshold, 2);
    });

    test('picking up from today moves the pace and marks nothing read', () {
      store.startPlan(plan);
      store.setPlanDay(plan.id, plan.days[0], read: true);
      now = now.add(const Duration(days: 7));
      expect(store.progressFor(plan.id)!.behindOn(now), 6);
      store.pickUpPlanToday(plan.id);
      final progress = store.progressFor(plan.id)!;
      expect(progress.behindOn(now), 0);
      expect(progress.currentDay!.number, 2);
      expect(progress.slotsDone, 1);
      expect(progress.scheduledDayOn(now), 2);
    });

    test('reading ahead is allowed and is not called ahead', () {
      store.startPlan(plan);
      for (final day in plan.days.take(5)) {
        store.setPlanDay(plan.id, day, read: true);
      }
      expect(store.progressFor(plan.id)!.behindOn(now), 0);
      expect(store.hasPlanReadingDue, isFalse);
    });

    test('a reading is due until today\'s is read', () {
      store.startPlan(plan);
      expect(store.hasPlanReadingDue, isTrue);
      store.setPlanSlot(plan.id, 0, read: true);
      expect(store.hasPlanReadingDue, isFalse);
    });

    test('a finished plan knows it is finished', () {
      store.startPlan(plan);
      for (final day in plan.days) {
        store.setPlanDay(plan.id, day, read: true);
      }
      final progress = store.progressFor(plan.id)!;
      expect(progress.isComplete, isTrue);
      expect(progress.currentDay, isNull);
      expect(progress.fraction, 1);
    });

    test('survives a restart', () async {
      store.startPlan(ReadingPlans.gospels);
      store.setPlanSlot(ReadingPlans.gospels.id, 2, read: true);
      final again = await ReadingStore.load(clock: () => now);
      final progress = again.progressFor(ReadingPlans.gospels.id)!;
      expect(progress.done, {2});
      expect(progress.startedOn, DateTime.utc(2026, 3, 1));
    });

    test('goes into the backup and comes back out of it', () async {
      store.startPlan(plan);
      store.setPlanSlot(plan.id, 0, read: true);
      final backup = store.export();
      expect((jsonDecode(backup) as Map)['plans'], hasLength(1));

      SharedPreferences.setMockInitialValues(const {});
      final fresh = await ReadingStore.load(clock: () => now);
      expect(fresh.hasBackupContent, isFalse);
      final result = fresh.import(backup);
      expect(result.ok, isTrue);
      expect(fresh.progressFor(plan.id)!.done, {0});
    });

    test('a date across a change of clocks is still one day', () {
      store.startPlan(plan);
      // Europe's clocks go forward on the last Sunday of March.
      now = DateTime(2026, 3, 30, 0, 30);
      expect(store.progressFor(plan.id)!.scheduledDayOn(now), 30);
    });
  });
}

bool _isOld(String code) {
  const newTestament = {
    'MAT', 'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH', //
    'PHP', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS',
    '1PE', '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
  };
  return !newTestament.contains(code);
}
