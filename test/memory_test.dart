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
      // 1, 3, 7, 14, 30, 60, 120 — and then 120 again, and again: the top
      // rung keeps its wait rather than running off the ladder.
      expect(waits, [...MemoryVerse.intervals, 120, 120]);
      expect(verse.isLearnt, isTrue);
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
