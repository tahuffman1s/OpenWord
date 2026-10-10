import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/learn_progress.dart';
import 'package:openword/src/model/memory_verse.dart';
import 'package:openword/src/model/quiz.dart';
import 'package:openword/src/model/sleep_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const john = Reference('JHN', 3, 16);
  const psalm = Reference('PSA', 23, 1);
  final morning = DateTime(2026, 9, 28, 8, 30);
  final noon = DateTime(2026, 9, 28, 12, 0);
  final evening = DateTime(2026, 9, 28, 20, 0);
  final nextMorning = DateTime(2026, 9, 29, 7, 0);

  group('the policy', () {
    const policy = SleepPolicy();

    test('knows evening from morning', () {
      expect(policy.isEvening(evening), isTrue);
      expect(policy.isEvening(noon), isFalse);
      expect(policy.isMorning(morning), isTrue);
      expect(policy.isMorning(noon), isFalse);
      expect(policy.roomForDayVerse(noon), isTrue);
      expect(policy.roomForDayVerse(DateTime(2026, 9, 28, 16)), isFalse);
    });

    test('offers a night verse in the evening and a day verse by day', () {
      expect(policy.offersLearning(TrialArm.night, evening), isTrue);
      expect(policy.offersLearning(TrialArm.night, noon), isFalse);
      expect(policy.offersLearning(TrialArm.day, noon), isTrue);
      expect(policy.offersLearning(TrialArm.day, evening), isFalse);
      expect(policy.offersLearning(null, evening), isTrue);
      const off = SleepPolicy(mode: SleepMode.off);
      expect(off.offersLearning(TrialArm.night, noon), isTrue);
    });

    test('sets the first recall next morning, or hours on', () {
      expect(
        policy.recallAfter(evening, TrialArm.night),
        DateTime(2026, 9, 29, SleepPolicy.wakeHour),
      );
      expect(policy.recallAfter(noon, TrialArm.day), DateTime(2026, 9, 28, 16));
      expect(policy.recallAfter(noon, null), DateTime(2026, 9, 29));
    });

    test('allots by mode', () {
      final random = Random(1);
      expect(policy.armForNew(random), isNotNull);
      expect(
        const SleepPolicy(mode: SleepMode.nights).armForNew(random),
        TrialArm.night,
      );
      expect(const SleepPolicy(mode: SleepMode.off).armForNew(random), isNull);
    });

    test('round-trips through JSON, within bounds', () {
      const chosen = SleepPolicy(
        mode: SleepMode.nights,
        eveningStart: 21,
        morningEnd: 9,
      );
      expect(SleepPolicy.fromJson(chosen.toJson()), chosen);
      expect(
        SleepPolicy.fromJson({'mode': 'x', 'evening': 3}).mode,
        SleepMode.trial,
      );
      expect(SleepPolicy.fromJson({'evening': 3}).eveningStart, 12);
    });
  });

  group('a verse through the trial', () {
    test('waits, is learnt, is recalled, and then is on the ladder', () async {
      var now = evening;
      final store = await ReadingStore.load(
        clock: () => now,
        random: Random(3),
      );
      store.setSleepPolicy(const SleepPolicy(mode: SleepMode.nights));
      store.toggleMemorise(john);
      var verse = store.memoryFor(john)!;
      expect(verse.arm, TrialArm.night);
      expect(verse.stage, MemoryStage.waiting);
      expect(store.memoryDue.single.reference, john);

      // Learnt tonight: a rung up, first recall from five tomorrow.
      store.reviewMemory(john, remembered: true);
      verse = store.memoryFor(john)!;
      expect(verse.stage, MemoryStage.introduced);
      expect(verse.rung, 1);
      expect(verse.introduced, evening);
      expect(verse.recallAt, DateTime(2026, 9, 29, SleepPolicy.wakeHour));
      expect(store.memoryDue, isEmpty, reason: 'not before morning');
      expect(store.hasMemoryDue, isFalse);

      now = nextMorning;
      expect(store.memoryDue.single.awaitsFirstRecall, isTrue);
      store.reviewMemory(john, remembered: true, slept: true);
      verse = store.memoryFor(john)!;
      expect(verse.stage, MemoryStage.onLadder);
      expect(verse.rung, 2);
      expect(verse.firstRecall!.right, isTrue);
      expect(verse.firstRecall!.slept, isTrue);
      expect(verse.laterRecall, isNull);

      // A week on: the later recall, kept once.
      now = nextMorning.add(const Duration(days: 7));
      store.reviewMemory(john, remembered: false);
      verse = store.memoryFor(john)!;
      expect(verse.laterRecall!.right, isFalse);
      expect(verse.rung, 0);
      store.reviewMemory(john, remembered: true);
      expect(store.memoryFor(john)!.laterRecall!.right, isFalse);
    });

    test(
      'a day verse is held back in the evening and offered by day',
      () async {
        var now = evening;
        final store = await ReadingStore.load(
          clock: () => now,
          random: Random(3),
        );
        store.setSleepPolicy(const SleepPolicy(mode: SleepMode.trial));
        // Draw until a day verse: the allotment is random.
        Reference? dayVerse;
        for (var v = 1; v <= 20 && dayVerse == null; v++) {
          final reference = Reference('JHN', 3, v);
          store.toggleMemorise(reference);
          if (store.memoryFor(reference)!.arm == TrialArm.day) {
            dayVerse = reference;
          }
        }
        expect(dayVerse, isNotNull);
        expect(
          store.memoryHeldBack.map((v) => v.reference),
          contains(dayVerse),
        );
        expect(
          store.memoryDue.map((v) => v.reference),
          isNot(contains(dayVerse)),
        );
        now = noon;
        expect(store.memoryDue.map((v) => v.reference), contains(dayVerse));
        store.reviewMemory(dayVerse!, remembered: true);
        final verse = store.memoryFor(dayVerse)!;
        expect(verse.recallAt, DateTime(2026, 9, 28, 16));
        now = DateTime(2026, 9, 28, 15);
        expect(
          store.memoryDue.map((v) => v.reference),
          isNot(contains(dayVerse)),
        );
        now = DateTime(2026, 9, 28, 16, 5);
        expect(store.memoryDue.first.reference, dayVerse);
      },
    );

    test('a miss while learning keeps the verse waiting', () async {
      final store = await ReadingStore.load(clock: () => evening);
      store.setSleepPolicy(const SleepPolicy(mode: SleepMode.nights));
      store.toggleMemorise(john);
      store.reviewMemory(john, remembered: false, sure: true);
      final verse = store.memoryFor(john)!;
      expect(verse.stage, MemoryStage.waiting);
      expect(verse.introduced, isNull);
      expect(verse.confidentMisses, 1);
    });

    test('with the timing off, a verse climbs as it always did', () async {
      final store = await ReadingStore.load(clock: () => evening);
      store.setSleepPolicy(const SleepPolicy(mode: SleepMode.off));
      store.toggleMemorise(john);
      store.reviewMemory(john, remembered: true);
      final verse = store.memoryFor(john)!;
      expect(verse.stage, MemoryStage.onLadder);
      expect(verse.rung, 1);
      expect(verse.introduced, isNull);
      expect(verse.awaitsFirstRecall, isFalse);
    });

    test('verses from before carry on as they were', () async {
      SharedPreferences.setMockInitialValues({
        'memory':
            '[{"b":"JHN","c":3,"v":16,"added":"2026-09-20","due":"2026-09-28",'
            '"t":1,"rung":2,"recalled":2}]',
      });
      final store = await ReadingStore.load(clock: () => noon);
      final verse = store.memoryFor(john)!;
      expect(verse.arm, isNull);
      expect(verse.stage, MemoryStage.onLadder);
      expect(store.memoryDue.single.reference, john);
      store.reviewMemory(john, remembered: true);
      expect(store.memoryFor(john)!.rung, 3);
      expect(store.memoryFor(john)!.firstRecall, isNull);
    });

    test('the policy is kept, and goes into a backup', () async {
      final store = await ReadingStore.load(clock: () => noon);
      store.setSleepPolicy(const SleepPolicy(mode: SleepMode.nights));
      expect((await ReadingStore.load()).sleepPolicy.mode, SleepMode.nights);
      expect(store.export(), contains('"sleep"'));
    });

    test('a verse round-trips with its trial record', () async {
      var now = evening;
      final store = await ReadingStore.load(clock: () => now);
      store.setSleepPolicy(const SleepPolicy(mode: SleepMode.nights));
      store.toggleMemorise(psalm);
      store.reviewMemory(psalm, remembered: true);
      now = nextMorning;
      store.reviewMemory(psalm, remembered: false, slept: true);
      final again = await ReadingStore.load(clock: () => now);
      final verse = again.memoryFor(psalm)!;
      expect(verse.arm, TrialArm.night);
      expect(verse.introduced, evening);
      expect(verse.firstRecall!.right, isFalse);
      expect(verse.firstRecall!.slept, isTrue);
      expect(verse.firstRecall!.at, nextMorning);
    });
  });

  group('the report', () {
    MemoryVerse recalled(
      int n, {
      required bool slept,
      required bool right,
      bool? later,
    }) {
      final verse = MemoryVerse.start(Reference('JHN', 3, n), morning)
          .introducedAt(morning, morning)
          .firstRecalled(morning, right: right, slept: slept);
      return later == null ? verse : verse.laterRecalled(morning, right: later);
    }

    test('says nothing until five of each', () {
      final report = SleepTrialReport.of([
        for (var i = 1; i <= 4; i++) recalled(i, slept: true, right: true),
        for (var i = 5; i <= 9; i++) recalled(i, slept: false, right: true),
      ]);
      expect(report.hasEnough, isFalse);
      expect(report.sleptAsked, 4);
      expect(report.awakeAsked, 5);
    });

    test('counts as it happened, not as allotted', () {
      final report = SleepTrialReport.of([
        for (var i = 1; i <= 5; i++) recalled(i, slept: true, right: i != 5),
        for (var i = 6; i <= 10; i++)
          recalled(
            i,
            slept: false,
            right: i.isEven,
            later: i == 6 ? true : null,
          ),
        // Not asked: left out.
        MemoryVerse.start(const Reference('JHN', 3, 11), morning),
      ]);
      expect(report.hasEnough, isTrue);
      expect(report.sleptRate, 0.8);
      expect(report.awakeRate, 0.6);
      expect(report.hasLater, isFalse);
      expect(report.awakeLaterAsked, 1);
    });
  });

  group('confidence', () {
    test('is tallied by level and sure misses counted', () {
      var progress = LearnProgress.none
          .earned(10, morning, right: true, confidence: Confidence.sure)
          .earned(0, morning, right: false, confidence: Confidence.sure)
          .earned(10, morning, right: true, confidence: Confidence.guessing)
          .earned(10, morning, right: true);
      expect(progress.calibration(Confidence.sure), 0.5);
      expect(progress.calibration(Confidence.guessing), 1.0);
      expect(progress.calibration(Confidence.fairly), isNull);
      expect(progress.confidentMisses, 1);
      final copy = LearnProgress.fromJson(progress.toJson())!;
      expect(copy, progress);
      progress = LearnProgress.fromJson({
        'xp': 1,
        'conf': {
          'sure': [1],
        },
      })!;
      expect(progress.confidence, isEmpty);
    });

    test('goes through the store', () async {
      final store = await ReadingStore.load(clock: () => noon);
      store.recordLearning(xp: 0, right: false, confidence: Confidence.sure);
      expect(store.progress.confidentMisses, 1);
      expect(store.progress.calibration(Confidence.sure), 0);
    });
  });

  test('a chapter has its own questions to guess at', () {
    final bible = parseFixture();
    final maker = QuizMaker(bible, random: Random(1));
    // The fixture's verses are too short to finish.
    expect(maker.makeForChapter(const Reference('GEN', 1)), isEmpty);
    expect(maker.makeForChapter(const Reference('REV', 1)), isEmpty);
  });
}
