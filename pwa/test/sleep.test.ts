import { beforeEach, describe, expect, it } from 'vitest';
import { ReadingStore } from '../src/data/marks';
import { Prefs } from '../src/infra/prefs';
import { Reference } from '../src/model/bible';
import { Confidence, LearnProgress } from '../src/model/learnProgress';
import { MemoryStage, MemoryVerse, TrialArm } from '../src/model/memoryVerse';
import { QuizMaker } from '../src/model/quiz';
import { seededRandom } from '../src/model/random';
import { SleepMode, SleepPolicy, SleepTrialReport } from '../src/model/sleepPolicy';
import { sampleBible } from './modelFixture';

const john = new Reference('JHN', 3, 16);
const psalm = new Reference('PSA', 23, 1);
const morning = new Date(2026, 8, 28, 8, 30);
const noon = new Date(2026, 8, 28, 12, 0);
const evening = new Date(2026, 8, 28, 20, 0);
const nextMorning = new Date(2026, 8, 29, 7, 0);

const references = (verses: readonly MemoryVerse[]) => verses.map((v) => v.reference.encode());

describe('the policy', () => {
  const policy = new SleepPolicy();

  it('knows evening from morning', () => {
    expect(policy.isEvening(evening)).toBe(true);
    expect(policy.isEvening(noon)).toBe(false);
    expect(policy.isMorning(morning)).toBe(true);
    expect(policy.isMorning(noon)).toBe(false);
    expect(policy.roomForDayVerse(noon)).toBe(true);
    expect(policy.roomForDayVerse(new Date(2026, 8, 28, 16))).toBe(false);
  });

  it('offers a night verse in the evening and a day verse by day', () => {
    expect(policy.offersLearning(TrialArm.night, evening)).toBe(true);
    expect(policy.offersLearning(TrialArm.night, noon)).toBe(false);
    expect(policy.offersLearning(TrialArm.day, noon)).toBe(true);
    expect(policy.offersLearning(TrialArm.day, evening)).toBe(false);
    expect(policy.offersLearning(null, evening)).toBe(true);
    const off = new SleepPolicy({ mode: SleepMode.off });
    expect(off.offersLearning(TrialArm.night, noon)).toBe(true);
  });

  it('sets the first recall next morning, or hours on', () => {
    expect(policy.recallAfter(evening, TrialArm.night)).toEqual(new Date(2026, 8, 29, SleepPolicy.wakeHour));
    expect(policy.recallAfter(noon, TrialArm.day)).toEqual(new Date(2026, 8, 28, 16));
    expect(policy.recallAfter(noon, null)).toEqual(new Date(2026, 8, 29));
  });

  it('allots by mode', () => {
    const random = seededRandom(1);
    expect(policy.armForNew(random)).not.toBeNull();
    expect(new SleepPolicy({ mode: SleepMode.nights }).armForNew(random)).toBe(TrialArm.night);
    expect(new SleepPolicy({ mode: SleepMode.off }).armForNew(random)).toBeNull();
  });

  it('round-trips through JSON, within bounds', () => {
    const chosen = new SleepPolicy({ mode: SleepMode.nights, eveningStart: 21, morningEnd: 9 });
    expect(SleepPolicy.fromJson(chosen.toJson()).equals(chosen)).toBe(true);
    expect(SleepPolicy.fromJson({ mode: 'x', evening: 3 }).mode).toBe(SleepMode.trial);
    expect(SleepPolicy.fromJson({ evening: 3 }).eveningStart).toBe(12);
  });
});

describe('a verse through the trial', () => {
  let prefs: Prefs;
  beforeEach(() => {
    prefs = Prefs.memory();
  });

  it('waits, is learnt, is recalled, and then is on the ladder', async () => {
    let now = evening;
    const store = await ReadingStore.load({ prefs, clock: () => now, random: seededRandom(3) });
    store.setSleepPolicy(new SleepPolicy({ mode: SleepMode.nights }));
    store.toggleMemorise(john);
    let verse = store.memoryFor(john)!;
    expect(verse.arm).toBe(TrialArm.night);
    expect(verse.stage).toBe(MemoryStage.waiting);
    expect(references(store.memoryDue)).toEqual([john.encode()]);

    // Learnt tonight: a rung up, first recall from five tomorrow.
    store.reviewMemory(john, { remembered: true });
    verse = store.memoryFor(john)!;
    expect(verse.stage).toBe(MemoryStage.introduced);
    expect(verse.rung).toBe(1);
    expect(verse.introduced).toEqual(evening);
    expect(verse.recallAt).toEqual(new Date(2026, 8, 29, SleepPolicy.wakeHour));
    // Not before morning.
    expect(store.memoryDue).toEqual([]);
    expect(store.hasMemoryDue).toBe(false);

    now = nextMorning;
    expect(store.memoryDue).toHaveLength(1);
    expect(store.memoryDue[0].awaitsFirstRecall).toBe(true);
    store.reviewMemory(john, { remembered: true, slept: true });
    verse = store.memoryFor(john)!;
    expect(verse.stage).toBe(MemoryStage.onLadder);
    expect(verse.rung).toBe(2);
    expect(verse.firstRecall!.right).toBe(true);
    expect(verse.firstRecall!.slept).toBe(true);
    expect(verse.laterRecall).toBeNull();

    // A week on: the later recall, kept once.
    now = new Date(nextMorning.getTime() + 7 * 86_400_000);
    store.reviewMemory(john, { remembered: false });
    verse = store.memoryFor(john)!;
    expect(verse.laterRecall!.right).toBe(false);
    expect(verse.rung).toBe(0);
    store.reviewMemory(john, { remembered: true });
    expect(store.memoryFor(john)!.laterRecall!.right).toBe(false);
  });

  it('a day verse is held back in the evening and offered by day', async () => {
    let now = evening;
    const store = await ReadingStore.load({ prefs, clock: () => now, random: seededRandom(3) });
    store.setSleepPolicy(new SleepPolicy({ mode: SleepMode.trial }));
    // Draw until a day verse: the allotment is random.
    let dayVerse: Reference | null = null;
    for (let v = 1; v <= 20 && dayVerse === null; v++) {
      const reference = new Reference('JHN', 3, v);
      store.toggleMemorise(reference);
      if (store.memoryFor(reference)!.arm === TrialArm.day) {
        dayVerse = reference;
      }
    }
    expect(dayVerse).not.toBeNull();
    expect(references(store.memoryHeldBack)).toContain(dayVerse!.encode());
    expect(references(store.memoryDue)).not.toContain(dayVerse!.encode());
    now = noon;
    expect(references(store.memoryDue)).toContain(dayVerse!.encode());
    store.reviewMemory(dayVerse!, { remembered: true });
    const verse = store.memoryFor(dayVerse!)!;
    expect(verse.recallAt).toEqual(new Date(2026, 8, 28, 16));
    now = new Date(2026, 8, 28, 15);
    expect(references(store.memoryDue)).not.toContain(dayVerse!.encode());
    now = new Date(2026, 8, 28, 16, 5);
    expect(store.memoryDue[0].reference.equals(dayVerse)).toBe(true);
  });

  it('a miss while learning keeps the verse waiting', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => evening });
    store.setSleepPolicy(new SleepPolicy({ mode: SleepMode.nights }));
    store.toggleMemorise(john);
    store.reviewMemory(john, { remembered: false, sure: true });
    const verse = store.memoryFor(john)!;
    expect(verse.stage).toBe(MemoryStage.waiting);
    expect(verse.introduced).toBeNull();
    expect(verse.confidentMisses).toBe(1);
  });

  it('with the timing off, a verse climbs as it always did', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => evening });
    store.setSleepPolicy(new SleepPolicy({ mode: SleepMode.off }));
    store.toggleMemorise(john);
    store.reviewMemory(john, { remembered: true });
    const verse = store.memoryFor(john)!;
    expect(verse.stage).toBe(MemoryStage.onLadder);
    expect(verse.rung).toBe(1);
    expect(verse.introduced).toBeNull();
    expect(verse.awaitsFirstRecall).toBe(false);
  });

  it('verses from before carry on as they were', async () => {
    prefs.setString(
      'memory',
      '[{"b":"JHN","c":3,"v":16,"added":"2026-09-20","due":"2026-09-28","t":1,"rung":2,"recalled":2}]',
    );
    const store = await ReadingStore.load({ prefs, clock: () => noon });
    const verse = store.memoryFor(john)!;
    expect(verse.arm).toBeNull();
    expect(verse.stage).toBe(MemoryStage.onLadder);
    expect(references(store.memoryDue)).toEqual([john.encode()]);
    store.reviewMemory(john, { remembered: true });
    expect(store.memoryFor(john)!.rung).toBe(3);
    expect(store.memoryFor(john)!.firstRecall).toBeNull();
  });

  it('the policy is kept, and goes into a backup', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => noon });
    store.setSleepPolicy(new SleepPolicy({ mode: SleepMode.nights }));
    expect((await ReadingStore.load({ prefs })).sleepPolicy.mode).toBe(SleepMode.nights);
    expect(store.export()).toContain('"sleep"');
  });

  it('a verse round-trips with its trial record', async () => {
    let now = evening;
    const store = await ReadingStore.load({ prefs, clock: () => now });
    store.setSleepPolicy(new SleepPolicy({ mode: SleepMode.nights }));
    store.toggleMemorise(psalm);
    store.reviewMemory(psalm, { remembered: true });
    now = nextMorning;
    store.reviewMemory(psalm, { remembered: false, slept: true });
    const again = await ReadingStore.load({ prefs, clock: () => now });
    const verse = again.memoryFor(psalm)!;
    expect(verse.arm).toBe(TrialArm.night);
    expect(verse.introduced).toEqual(evening);
    expect(verse.firstRecall!.right).toBe(false);
    expect(verse.firstRecall!.slept).toBe(true);
    expect(verse.firstRecall!.at).toEqual(nextMorning);
  });
});

describe('the report', () => {
  const recalled = (n: number, slept: boolean, right: boolean, later: boolean | null = null): MemoryVerse => {
    const verse = MemoryVerse.start(new Reference('JHN', 3, n), morning)
      .introducedAt(morning, morning)
      .firstRecalled(morning, right, slept);
    return later === null ? verse : verse.laterRecalled(morning, later);
  };

  it('says nothing until five of each', () => {
    const verses: MemoryVerse[] = [];
    for (let i = 1; i <= 4; i++) verses.push(recalled(i, true, true));
    for (let i = 5; i <= 9; i++) verses.push(recalled(i, false, true));
    const report = SleepTrialReport.of(verses);
    expect(report.hasEnough).toBe(false);
    expect(report.sleptAsked).toBe(4);
    expect(report.awakeAsked).toBe(5);
  });

  it('counts as it happened, not as allotted', () => {
    const verses: MemoryVerse[] = [];
    for (let i = 1; i <= 5; i++) verses.push(recalled(i, true, i !== 5));
    for (let i = 6; i <= 10; i++) verses.push(recalled(i, false, i % 2 === 0, i === 6 ? true : null));
    // Not asked: left out.
    verses.push(MemoryVerse.start(new Reference('JHN', 3, 11), morning));
    const report = SleepTrialReport.of(verses);
    expect(report.hasEnough).toBe(true);
    expect(report.sleptRate).toBe(0.8);
    expect(report.awakeRate).toBe(0.6);
    expect(report.hasLater).toBe(false);
    expect(report.awakeLaterAsked).toBe(1);
  });
});

describe('confidence', () => {
  it('is tallied by level and sure misses counted', () => {
    let progress = LearnProgress.none.earned(10, morning, { right: true, confidence: Confidence.sure })
      .earned(0, morning, { right: false, confidence: Confidence.sure })
      .earned(10, morning, { right: true, confidence: Confidence.guessing })
      .earned(10, morning, { right: true });
    expect(progress.calibration(Confidence.sure)).toBe(0.5);
    expect(progress.calibration(Confidence.guessing)).toBe(1.0);
    expect(progress.calibration(Confidence.fairly)).toBeNull();
    expect(progress.confidentMisses).toBe(1);
    const copy = LearnProgress.fromJson(progress.toJson())!;
    expect(copy.equals(progress)).toBe(true);
    progress = LearnProgress.fromJson({ xp: 1, conf: { sure: [1] } })!;
    expect(progress.confidence.size).toBe(0);
  });

  it('goes through the store', async () => {
    const store = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => noon });
    store.recordLearning({ xp: 0, right: false, confidence: Confidence.sure });
    expect(store.progress.confidentMisses).toBe(1);
    expect(store.progress.calibration(Confidence.sure)).toBe(0);
  });
});

it('a chapter has its own questions to guess at', () => {
  const bible = sampleBible();
  const maker = new QuizMaker(bible, { random: seededRandom(1) });
  // The fixture's verses are too short to finish.
  expect(maker.makeForChapter(new Reference('GEN', 1))).toEqual([]);
  expect(maker.makeForChapter(new Reference('REV', 1))).toEqual([]);
});
