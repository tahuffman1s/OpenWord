import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/local_date.dart';
import 'package:openword/src/model/memory_verse.dart';
import 'package:openword/src/model/sleep_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      // These are about the ladder, not the timing of new verses.
      'sleep': '{"mode":"off"}',
    }),
  );

  const john = Reference('JHN', 3, 16);
  const psalm = Reference('PSA', 23, 1);
  final monday = DateTime(2026, 9, 28, 9, 30);

  group('the ladder', () {
    test('a new verse is due the day it is added', () {
      final verse = MemoryVerse.start(john, monday);
      expect(verse.rung, 0);
      expect(verse.recalled, 0);
      expect(verse.isDueOn(monday), isTrue);
      expect(verse.isLearnt, isFalse);
      expect(verse.daysUntilDueOn(monday), 0);
    });

    test('each recall climbs a rung and waits longer', () {
      var verse = MemoryVerse.start(john, monday);
      var day = monday;
      final waits = <int>[];
      for (var i = 0; i < MemoryVerse.intervals.length + 2; i++) {
        verse = verse.reviewed(remembered: true, today: day);
        waits.add(verse.daysUntilDueOn(day));
        expect(verse.isDueOn(day), isFalse);
        expect(verse.rung, i + 1);
        expect(verse.recalled, i + 1);
        day = LocalDate.only(day).add(Duration(days: waits.last));
        expect(verse.isDueOn(day), isTrue);
      }
      // A day, then a little over double each time, to the year that is
      // the most a verse is left; the old 120-day ceiling is gone.
      expect(waits, [1, 2, 5, 12, 28, 69, 170, 365, 365]);
      expect(verse.isLearnt, isTrue);
      expect(verse.stability, MemoryVerse.maxStability);
    });

    test('the chance of recall falls with the days', () {
      final verse = MemoryVerse.start(john, monday)
          .reviewed(remembered: true, today: monday)
          .reviewed(
            remembered: true,
            today: monday.add(const Duration(days: 1)),
          );
      final recalled = monday.add(const Duration(days: 1));
      expect(verse.retrievability(recalled), greaterThan(0.95));
      // Nine in ten when it comes due; lower the longer it is left.
      final due = recalled.add(Duration(days: verse.nextWaitDays));
      expect(verse.retrievability(verse.due), closeTo(0.9, 0.02));
      expect(
        verse.retrievability(due.add(const Duration(days: 30))),
        lessThan(0.5),
      );
    });

    test('a miss costs most of the stability and marks the verse harder', () {
      var verse = MemoryVerse.start(john, monday);
      for (var i = 0; i < 5; i++) {
        verse = verse.reviewed(remembered: true, today: monday);
      }
      final before = verse.stability!;
      final missed = verse.reviewed(remembered: false, today: monday);
      expect(missed.stability, before * 0.25);
      expect(missed.difficulty, greaterThan(verse.difficulty));
      // Harder: the next wait grows by less than it would have.
      final retry = missed.reviewed(remembered: true, today: monday);
      expect(retry.nextWaitDays, lessThan(verse.nextWaitDays));
    });

    test('a slow answer, a late one, and the reader all set the wait', () {
      final verse = MemoryVerse.start(john, monday)
          .reviewed(remembered: true, today: monday)
          .reviewed(remembered: true, today: monday);
      final quick = verse.reviewed(remembered: true, today: monday);
      final slow = verse.reviewed(
        remembered: true,
        today: monday,
        seconds: 60,
        words: 8,
      );
      expect(slow.stability, lessThan(quick.stability!));
      // Recalled a month late, when the chance had fallen: worth more.
      final late = verse.reviewed(
        remembered: true,
        today: monday.add(const Duration(days: 30)),
      );
      expect(late.stability, greaterThan(quick.stability!));
      // A reader who keeps verses well waits longer; one who does not, less.
      final keeper = verse.reviewed(
        remembered: true,
        today: monday,
        personal: 1.3,
      );
      final forgetter = verse.reviewed(
        remembered: true,
        today: monday,
        personal: 0.8,
      );
      expect(keeper.stability, greaterThan(quick.stability!));
      expect(forgetter.stability, lessThan(quick.stability!));
    });

    test('a verse from the old ladder carries its rung over', () {
      final old = MemoryVerse.fromJson({
        'b': 'JHN',
        'c': 3,
        'v': 16,
        'added': '2026-09-01',
        'due': '2026-09-28',
        'rung': 4,
        'recalled': 4,
      })!;
      expect(old.stability, isNull);
      // Rung 4 waited 14 days; the next recall starts from there.
      expect(old.nextWaitDays, 14);
      final next = old.reviewed(remembered: true, today: monday);
      expect(next.stability, 14);
      expect(next.daysUntilDueOn(monday), 14);
    });

    test('the hook rides through JSON', () {
      final verse = MemoryVerse.start(john, monday).withHook('  love ');
      expect(verse.hook, 'love');
      final copy = MemoryVerse.fromJson(
        jsonDecode(jsonEncode(verse.toJson())) as Map<String, Object?>,
      )!;
      expect(copy.hook, 'love');
      expect(copy.difficulty, MemoryVerse.defaultDifficulty);
      expect(MemoryVerse.start(john, monday).toJson(), isNot(contains('hook')));
    });

    test('a lapse drops to the bottom and is due again today', () {
      var verse = MemoryVerse.start(john, monday);
      final later = monday.add(const Duration(days: 40));
      for (var i = 0; i < 4; i++) {
        verse = verse.reviewed(remembered: true, today: later);
      }
      expect(verse.rung, 4);
      verse = verse.reviewed(remembered: false, today: later);
      expect(verse.rung, 0);
      expect(verse.isDueOn(later), isTrue);
      // What was recalled stays counted; only the place is lost.
      expect(verse.recalled, 4);
    });

    test('is due the moment the day arrives, whatever the hour', () {
      final verse = MemoryVerse.start(
        john,
        monday,
      ).reviewed(remembered: true, today: monday);
      expect(verse.isDueOn(DateTime(2026, 9, 28, 23, 59)), isFalse);
      expect(verse.isDueOn(DateTime(2026, 9, 29, 0, 0)), isTrue);
    });

    test('round-trips through JSON', () {
      final verse = MemoryVerse.start(
        john,
        monday,
      ).reviewed(remembered: true, today: monday);
      final copy = MemoryVerse.fromJson(
        jsonDecode(jsonEncode(verse.toJson())) as Map<String, Object?>,
      )!;
      expect(copy.reference, john);
      expect(copy.added, verse.added);
      expect(copy.due, verse.due);
      expect(copy.rung, 1);
      expect(copy.recalled, 1);
      expect(
        copy.updated.millisecondsSinceEpoch,
        verse.updated.millisecondsSinceEpoch,
      );
    });

    test('refuses what is not a verse', () {
      expect(MemoryVerse.fromJson({'b': 'JHN', 'c': 3}), isNull);
      expect(
        MemoryVerse.fromJson({
          'b': 'NOPE',
          'c': 1,
          'v': 1,
          'added': '2026-01-01',
          'due': '2026-01-01',
        }),
        isNull,
      );
      expect(
        MemoryVerse.fromJson({'b': 'JHN', 'c': 3, 'v': 16, 'added': 'x'}),
        isNull,
      );
    });
  });

  group('the prompts', () {
    test('first letters keep the shape of the verse', () {
      expect(
        MemoryPrompt.hint('For God so loved the world, that he gave'),
        'F__ G__ s_ l____ t__ w____, t___ h_ g___',
      );
    });

    test('punctuation, quotes and numbers keep their places', () {
      expect(
        MemoryPrompt.hint('He said, "Follow me."'),
        'H_ s___, "F_____ m_."',
      );
      expect(MemoryPrompt.hint('12 men'), '1_ m__');
    });

    test('an apostrophe stays, and does not start a new word', () {
      expect(MemoryPrompt.hint("don’t the Lord's"), "d__’_ t__ L___'_");
    });

    test('accented letters are letters', () {
      expect(MemoryPrompt.hint('Élan café'), 'É___ c___');
    });

    test('each prompt shows its share', () {
      const text = 'God said, "Let there be light."';
      expect(MemoryPrompt.read.apply(text), text);
      expect(MemoryPrompt.firstLetters.apply(text), MemoryPrompt.hint(text));
      expect(MemoryPrompt.fromMemory.apply(text), '');
    });

    test('a verse is read while new, hinted while young, then bare', () {
      expect(MemoryPrompt.forRung(0), MemoryPrompt.read);
      expect(MemoryPrompt.forRung(1), MemoryPrompt.firstLetters);
      expect(MemoryPrompt.forRung(2), MemoryPrompt.firstLetters);
      expect(MemoryPrompt.forRung(3), MemoryPrompt.fromMemory);
      expect(MemoryPrompt.forRung(9), MemoryPrompt.fromMemory);
    });
  });

  group('the store', () {
    test('memorising toggles on and off and is due at once', () async {
      final store = await ReadingStore.load(clock: () => monday);
      expect(store.isMemorising(john), isFalse);
      expect(store.hasMemoryDue, isFalse);

      expect(store.toggleMemorise(john), isTrue);
      expect(store.isMemorising(john), isTrue);
      expect(store.memoryVerses.single.reference, john);
      expect(store.memoryDue.single.reference, john);
      expect(store.hasMemoryDue, isTrue);

      expect(store.toggleMemorise(john), isFalse);
      expect(store.memoryVerses, isEmpty);
      expect(store.hasMemoryDue, isFalse);
    });

    test('a verse added with the timing off is learnt whenever', () async {
      final store = await ReadingStore.load(clock: () => monday);
      expect(store.sleepPolicy.mode, SleepMode.off);
      store.toggleMemorise(john);
      expect(store.memoryFor(john)!.arm, isNull);
      expect(store.memoryDue.single.reference, john);
    });

    test('a whole chapter cannot be memorised', () async {
      final store = await ReadingStore.load(clock: () => monday);
      expect(store.toggleMemorise(const Reference('JHN', 3)), isFalse);
      expect(store.memoryVerses, isEmpty);
    });

    test('a review moves the verse and the dot goes out', () async {
      var today = monday;
      final store = await ReadingStore.load(clock: () => today);
      store.toggleMemorise(john);
      store.reviewMemory(john, remembered: true);
      expect(store.memoryFor(john)!.rung, 1);
      expect(store.hasMemoryDue, isFalse);
      expect(store.memoryDue, isEmpty);

      today = monday.add(const Duration(days: 1));
      expect(store.hasMemoryDue, isTrue);
      store.reviewMemory(john, remembered: false);
      expect(store.memoryFor(john)!.rung, 0);
      expect(store.hasMemoryDue, isTrue);

      // A verse never added is not reviewed into being.
      store.reviewMemory(psalm, remembered: true);
      expect(store.memoryFor(psalm), isNull);
    });

    test('due verses come longest waiting first', () async {
      var today = monday;
      final store = await ReadingStore.load(clock: () => today);
      store.toggleMemorise(john);
      store.reviewMemory(john, remembered: true);
      today = monday.add(const Duration(days: 1));
      store.reviewMemory(john, remembered: true); // due in 3 days
      store.toggleMemorise(psalm); // due today
      today = monday.add(const Duration(days: 4));
      // The ladder's due verses come before the ones still to be learnt.
      expect(store.memoryDue.map((v) => v.reference), [john, psalm]);
    });

    test('due verses come easiest first, so the session warms up', () async {
      var today = monday;
      final store = await ReadingStore.load(clock: () => today);
      store.toggleMemorise(john);
      store.toggleMemorise(psalm);
      for (var i = 0; i < 3; i++) {
        store.reviewMemory(john, remembered: true);
        store.reviewMemory(psalm, remembered: true);
      }
      // Both due in five days; the psalm is left a fortnight longer, so its
      // chance of recall is the lower, and it is asked second.
      today = monday.add(const Duration(days: 5));
      store.reviewMemory(john, remembered: true);
      today = monday.add(const Duration(days: 40));
      expect(store.memoryDue.map((v) => v.reference), [john, psalm]);
      expect(
        store.memoryFor(john)!.retrievability(today),
        greaterThan(store.memoryFor(psalm)!.retrievability(today)),
      );
    });

    test(
      'a recall against the odds says the reader keeps verses well',
      () async {
        var today = monday;
        final store = await ReadingStore.load(clock: () => today);
        store.toggleMemorise(john);
        store.reviewMemory(john, remembered: true);
        store.reviewMemory(john, remembered: true);
        expect(store.progress.recallFactor, 1);
        // Recalled long after it was due: the gaps are stretched a little.
        today = monday.add(const Duration(days: 60));
        store.reviewMemory(john, remembered: true);
        expect(store.progress.recallFactor, closeTo(1.03, 1e-9));
        // Missed the day after a recall: pulled back in.
        today = today.add(const Duration(days: 1));
        store.reviewMemory(john, remembered: false);
        expect(store.progress.recallFactor, closeTo(1.0, 1e-9));
        expect(
          (await ReadingStore.load(clock: () => today)).progress.recallFactor,
          closeTo(1.0, 1e-9),
        );
      },
    );

    test('a hook is kept with the verse', () async {
      final store = await ReadingStore.load(clock: () => monday);
      store.toggleMemorise(john);
      store.setMemoryHook(john, ' love ');
      expect(store.memoryFor(john)!.hook, 'love');
      expect((await ReadingStore.load()).memoryFor(john)!.hook, 'love');
      store.setMemoryHook(psalm, 'rest');
      expect(store.memoryFor(psalm), isNull);
    });

    test('survives a restart, and remove and restore', () async {
      final store = await ReadingStore.load(clock: () => monday);
      store.toggleMemorise(john);
      store.reviewMemory(john, remembered: true);

      final again = await ReadingStore.load(clock: () => monday);
      final verse = again.memoryFor(john)!;
      expect(verse.rung, 1);

      again.removeMemory(john);
      expect(again.memoryVerses, isEmpty);
      again.restoreMemory(verse);
      expect(again.memoryFor(john)!.rung, 1);
    });

    test('goes into a backup and merges back by recency', () async {
      final store = await ReadingStore.load(clock: () => monday);
      store.toggleMemorise(john);
      expect(store.hasBackupContent, isTrue);
      final backup = store.export();
      expect(backup, contains('"memory"'));

      SharedPreferences.setMockInitialValues({});
      final fresh = await ReadingStore.load(clock: () => monday);
      final result = fresh.import(backup);
      expect(result.ok, isTrue);
      expect(result.added, 1);
      expect(fresh.memoryFor(john)!.due, store.memoryFor(john)!.due);

      // The copy with the later touch wins.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      fresh.reviewMemory(john, remembered: true);
      expect(store.import(fresh.export()).updated, 1);
      expect(store.memoryFor(john)!.rung, 1);
      expect(fresh.import(backup).total, 0);
    });

    test('remove everything takes the memory verses with it', () async {
      final store = await ReadingStore.load(clock: () => monday);
      store.toggleMemorise(john);
      store.clearAll();
      expect(store.memoryVerses, isEmpty);
      expect((await ReadingStore.load()).memoryVerses, isEmpty);
    });
  });
}
