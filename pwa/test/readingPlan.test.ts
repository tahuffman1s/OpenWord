import { beforeEach, describe, expect, it } from 'vitest';
import { ReadingStore } from '../src/data/marks';
import { PlanProgress } from '../src/data/planProgress';
import { Prefs } from '../src/infra/prefs';
import { Reference } from '../src/model/bible';
import { chaptersOf, PlanDay, ReadingPlan, ReadingPlans, weave } from '../src/model/readingPlan';
import { englishVerseCounts } from '../src/model/versificationTable';

const versesOf = (chapter: Reference): number =>
  Number.parseInt(englishVerseCounts[chapter.bookCode]!.split(' ')[chapter.chapter - 1], 10);

describe('splitting a book into days', () => {
  it('keeps order, splits nothing and leaves no day empty', () => {
    const weights = [5, 1, 1, 30, 2, 2, 2, 9, 1];
    const days = ReadingPlan.split(weights, 4);
    expect(days.flat()).toEqual(weights.map((_, i) => i));
    expect(days.every((d) => d.length > 0)).toBe(true);
  });

  it('one item a day when there are as many items as days', () => {
    const days = ReadingPlan.split(new Array<number>(31).fill(1), 31);
    expect(days.map((d) => d.length).every((n) => n === 1)).toBe(true);
  });

  it('a very long item does not starve the days after it', () => {
    const days = ReadingPlan.split([1, 1, 176, 1, 1], 5);
    expect(days.map((d) => d.length).every((n) => n === 1)).toBe(true);
  });
});

describe('the plans', () => {
  for (const plan of ReadingPlans.all) {
    it(`${plan.name}: every day has something and nothing repeats`, () => {
      expect(plan.days.length).toBeGreaterThan(0);
      expect(plan.days.every((day) => day.chapters.length > 0)).toBe(true);
      const seen = new Set<string>();
      for (const day of plan.days) {
        for (const chapter of day.chapters) {
          // Appears twice otherwise.
          expect(seen.has(chapter.encode())).toBe(false);
          seen.add(chapter.encode());
        }
      }
      // Slots are numbered straight through, day after day.
      let slot = 0;
      for (const day of plan.days) {
        expect(day.firstSlot).toBe(slot);
        slot += day.slotCount;
      }
      expect(plan.slotCount).toBe(slot);
    });
  }

  it('there are six of them, one recommended', () => {
    expect(ReadingPlans.all.map((p) => p.id)).toEqual([
      'gospels-30',
      'bible-year',
      'ot-nt-year',
      'nt-90',
      'psalms-30',
      'proverbs-31',
    ]);
    expect(ReadingPlans.all.filter((p) => p.recommended).map((p) => p.id)).toEqual(['gospels-30']);
    expect(ReadingPlans.byId('nt-90')).toBe(ReadingPlans.newTestament90);
    expect(ReadingPlans.byId('nope')).toBeNull();
  });

  it('the Bible in a year is the whole Protestant canon, in order', () => {
    const plan = ReadingPlans.bibleInAYear;
    expect(plan.length).toBe(365);
    const chapters = plan.days.flatMap((d) => [...d.chapters]);
    expect(chapters).toHaveLength(1189);
    expect(chapters[0].equals(new Reference('GEN', 1))).toBe(true);
    expect(chapters[chapters.length - 1].equals(new Reference('REV', 22))).toBe(true);
  });

  it('the days are even in reading, not in chapters', () => {
    const plan = ReadingPlans.bibleInAYear;
    const verses = plan.days.map((d) => d.verses).sort((a, b) => a - b);
    const median = verses[Math.trunc(verses.length / 2)];
    // 31,102 verses over 365 days is about 85 a day.
    expect(median).toBeGreaterThanOrEqual(75);
    expect(median).toBeLessThanOrEqual(95);
    // Nothing is a whole week's reading in one sitting.
    expect(verses[verses.length - 1]).toBeLessThan(260);
  });

  it('that plan has two readings every day, and the whole Bible', () => {
    const plan = ReadingPlans.bothTestaments;
    for (const day of plan.days) {
      const codes = new Set(day.chapters.map((c) => c.bookCode));
      const old = [...codes].filter((c) => isOld(c) && c !== 'PSA');
      const other = [...codes].filter((c) => !isOld(c) || c === 'PSA');
      expect(old.length, `day ${day.number}`).toBeGreaterThan(0);
      expect(other.length, `day ${day.number}`).toBeGreaterThan(0);
    }
    expect(plan.slotCount).toBe(1189);
  });

  it('weaving spreads the shorter run through the longer', () => {
    const nt = chaptersOf(['MAT']);
    const psalms = chaptersOf(['PSA']).slice(0, 7);
    const woven = weave(nt, psalms);
    expect(woven).toHaveLength(nt.length + psalms.length);
    const at: number[] = [];
    for (let i = 0; i < woven.length; i++) {
      if (woven[i].bookCode === 'PSA') at.push(i);
    }
    // A psalm about every fifth reading, not seven together at one end.
    for (let k = 1; k < at.length; k++) {
      expect(at[k] - at[k - 1]).toBeGreaterThanOrEqual(4);
      expect(at[k] - at[k - 1]).toBeLessThanOrEqual(6);
    }
  });

  it('Proverbs is one chapter a day; Psalm 119 has a day to itself', () => {
    expect(ReadingPlans.proverbsMonth.days.map((d) => d.label)).toEqual(
      Array.from({ length: 31 }, (_, i) => `Proverbs ${i + 1}`),
    );
    const psalm119 = ReadingPlans.psalms30.days.find((d) => d.chapters.some((c) => c.equals(new Reference('PSA', 119))))!;
    expect(psalm119.chapters.map((c) => c.encode())).toEqual(['PSA/119/']);
    expect(psalm119.label).toBe('Psalm 119');
  });

  it('a day reads as passages', () => {
    const day = new PlanDay({
      number: 1,
      chapters: [new Reference('GEN', 49), new Reference('GEN', 50), new Reference('EXO', 1), new Reference('JUD', 1)],
      firstSlot: 0,
      verses: 0,
    });
    expect(day.label).toBe('Genesis 49–50; Exodus 1; Jude');
  });

  it('says how long a day takes', () => {
    expect(ReadingPlans.proverbsMonth.minutesPerDay).toBe(4);
    expect(ReadingPlans.bibleInAYear.minutesPerDay).toBe(10);
  });

  it("a plan's days never depend on which translation is open", () => {
    // Built from the English verse table, so building twice is the same.
    expect(ReadingPlans.bibleInAYear.days[100].label).toBe(ReadingPlans.bibleInAYear.days[100].label);
    for (const day of ReadingPlans.gospels.days) {
      expect(day.verses).toBe(day.chapters.map(versesOf).reduce((a, b) => a + b, 0));
    }
  });
});

describe('progress', () => {
  let now: Date;
  let store: ReadingStore;
  let prefs: Prefs;

  beforeEach(async () => {
    prefs = Prefs.memory();
    now = new Date(2026, 2, 1, 9);
    store = await ReadingStore.load({ prefs, clock: () => now });
  });

  const plan = ReadingPlans.proverbsMonth;
  const addDays = (date: Date, n: number) => new Date(date.getTime() + n * 86_400_000);

  it('today is the first day with anything left, whatever the date', () => {
    store.startPlan(plan);
    expect(store.progressFor(plan.id)!.currentDay!.number).toBe(1);
    now = addDays(now, 10);
    // Ten days away and nothing read: still day 1, not a pile of ten.
    expect(store.progressFor(plan.id)!.currentDay!.number).toBe(1);
    store.setPlanDay(plan.id, plan.days[0], true);
    expect(store.progressFor(plan.id)!.currentDay!.number).toBe(2);
  });

  it('one day behind is not worth saying; two is', () => {
    store.startPlan(plan);
    now = addDays(now, 1);
    expect(store.progressFor(plan.id)!.behindOn(now)).toBe(1);
    now = addDays(now, 1);
    expect(store.progressFor(plan.id)!.behindOn(now)).toBe(2);
    expect(PlanProgress.behindThreshold).toBe(2);
  });

  it('picking up from today moves the pace and marks nothing read', () => {
    store.startPlan(plan);
    store.setPlanDay(plan.id, plan.days[0], true);
    now = addDays(now, 7);
    expect(store.progressFor(plan.id)!.behindOn(now)).toBe(6);
    store.pickUpPlanToday(plan.id);
    const progress = store.progressFor(plan.id)!;
    expect(progress.behindOn(now)).toBe(0);
    expect(progress.currentDay!.number).toBe(2);
    expect(progress.slotsDone).toBe(1);
    expect(progress.scheduledDayOn(now)).toBe(2);
  });

  it('reading ahead is allowed and is not called ahead', () => {
    store.startPlan(plan);
    for (const day of plan.days.slice(0, 5)) {
      store.setPlanDay(plan.id, day, true);
    }
    expect(store.progressFor(plan.id)!.behindOn(now)).toBe(0);
    expect(store.hasPlanReadingDue).toBe(false);
  });

  it("a reading is due until today's is read", () => {
    store.startPlan(plan);
    expect(store.hasPlanReadingDue).toBe(true);
    store.setPlanSlot(plan.id, 0, true);
    expect(store.hasPlanReadingDue).toBe(false);
  });

  it('a finished plan knows it is finished', () => {
    store.startPlan(plan);
    for (const day of plan.days) {
      store.setPlanDay(plan.id, day, true);
    }
    const progress = store.progressFor(plan.id)!;
    expect(progress.isComplete).toBe(true);
    expect(progress.currentDay).toBeNull();
    expect(progress.fraction).toBe(1);
  });

  it('survives a restart', async () => {
    store.startPlan(ReadingPlans.gospels);
    store.setPlanSlot(ReadingPlans.gospels.id, 2, true);
    const again = await ReadingStore.load({ prefs, clock: () => now });
    const progress = again.progressFor(ReadingPlans.gospels.id)!;
    expect(progress.done).toEqual(new Set([2]));
    expect(progress.startedOn).toEqual(new Date(Date.UTC(2026, 2, 1)));
  });

  it('goes into the backup and comes back out of it', async () => {
    store.startPlan(plan);
    store.setPlanSlot(plan.id, 0, true);
    const backup = store.export();
    expect((JSON.parse(backup) as { plans: unknown[] }).plans).toHaveLength(1);

    const fresh = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => now });
    expect(fresh.hasBackupContent).toBe(false);
    const result = fresh.import(backup);
    expect(result.ok).toBe(true);
    expect(fresh.progressFor(plan.id)!.done).toEqual(new Set([0]));
  });

  it('a date across a change of clocks is still one day', () => {
    store.startPlan(plan);
    // Europe's clocks go forward on the last Sunday of March.
    now = new Date(2026, 2, 30, 0, 30);
    expect(store.progressFor(plan.id)!.scheduledDayOn(now)).toBe(30);
  });

  it('a plan is stopped, restored, and started over', () => {
    store.startPlan(plan);
    store.setPlanSlot(plan.id, 0, true);
    const progress = store.progressFor(plan.id)!;
    store.stopPlan(plan.id);
    expect(store.plans).toEqual([]);
    store.restorePlan(progress);
    expect(store.progressFor(plan.id)!.done).toEqual(new Set([0]));
    store.startPlan(plan);
    expect(store.progressFor(plan.id)!.done.size).toBe(0);
    expect(store.progressFor(plan.id)!.chapterAt(3).equals(new Reference('PRO', 4))).toBe(true);
  });
});

function isOld(code: string): boolean {
  const newTestament = new Set([
    'MAT', 'MRK', 'LUK', 'JHN', 'ACT', 'ROM', '1CO', '2CO', 'GAL', 'EPH',
    'PHP', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS',
    '1PE', '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV',
  ]);
  return !newTestament.has(code);
}
