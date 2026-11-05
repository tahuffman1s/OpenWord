import { beforeEach, describe, expect, it } from 'vitest';
import { ReadingStore } from '../src/data/marks';
import { Prefs } from '../src/infra/prefs';
import { Reference } from '../src/model/bible';
import { LocalDate } from '../src/model/localDate';
import { MemoryPrompt, MemoryVerse } from '../src/model/memoryVerse';
import { SleepMode } from '../src/model/sleepPolicy';

const john = new Reference('JHN', 3, 16);
const psalm = new Reference('PSA', 23, 1);
const monday = new Date(2026, 8, 28, 9, 30);
const addDays = (date: Date, n: number) => new Date(date.getTime() + n * 86_400_000);

describe('the ladder', () => {
  it('a new verse is due the day it is added', () => {
    const verse = MemoryVerse.start(john, monday);
    expect(verse.rung).toBe(0);
    expect(verse.recalled).toBe(0);
    expect(verse.isDueOn(monday)).toBe(true);
    expect(verse.isLearnt).toBe(false);
    expect(verse.daysUntilDueOn(monday)).toBe(0);
  });

  it('each recall climbs a rung and waits longer', () => {
    let verse = MemoryVerse.start(john, monday);
    let day = monday;
    const waits: number[] = [];
    for (let i = 0; i < MemoryVerse.intervals.length + 2; i++) {
      verse = verse.reviewed({ remembered: true, today: day });
      waits.push(verse.daysUntilDueOn(day));
      expect(verse.isDueOn(day)).toBe(false);
      expect(verse.rung).toBe(i + 1);
      expect(verse.recalled).toBe(i + 1);
      day = LocalDate.addDays(LocalDate.only(day), waits[waits.length - 1]);
      expect(verse.isDueOn(day)).toBe(true);
    }
    // A day, then a little over double each time, to the year that is
    // the most a verse is left; the old 120-day ceiling is gone.
    expect(waits).toEqual([1, 2, 5, 12, 28, 69, 170, 365, 365]);
    expect(verse.isLearnt).toBe(true);
    expect(verse.stability).toBe(MemoryVerse.maxStability);
  });

  it('the chance of recall falls with the days', () => {
    const verse = MemoryVerse.start(john, monday)
      .reviewed({ remembered: true, today: monday })
      .reviewed({ remembered: true, today: addDays(monday, 1) });
    const recalled = addDays(monday, 1);
    expect(verse.retrievability(recalled)).toBeGreaterThan(0.95);
    // Nine in ten when it comes due; lower the longer it is left.
    const due = addDays(recalled, verse.nextWaitDays);
    expect(Math.abs(verse.retrievability(verse.due) - 0.9)).toBeLessThanOrEqual(0.02);
    expect(verse.retrievability(addDays(due, 30))).toBeLessThan(0.5);
  });

  it('a miss costs most of the stability and marks the verse harder', () => {
    let verse = MemoryVerse.start(john, monday);
    for (let i = 0; i < 5; i++) {
      verse = verse.reviewed({ remembered: true, today: monday });
    }
    const before = verse.stability!;
    const missed = verse.reviewed({ remembered: false, today: monday });
    expect(missed.stability).toBe(before * 0.25);
    expect(missed.difficulty).toBeGreaterThan(verse.difficulty);
    // Harder: the next wait grows by less than it would have.
    const retry = missed.reviewed({ remembered: true, today: monday });
    expect(retry.nextWaitDays).toBeLessThan(verse.nextWaitDays);
  });

  it('a slow answer, a late one, and the reader all set the wait', () => {
    const verse = MemoryVerse.start(john, monday)
      .reviewed({ remembered: true, today: monday })
      .reviewed({ remembered: true, today: monday });
    const quick = verse.reviewed({ remembered: true, today: monday });
    const slow = verse.reviewed({ remembered: true, today: monday, seconds: 60, words: 8 });
    expect(slow.stability).toBeLessThan(quick.stability!);
    // Recalled a month late, when the chance had fallen: worth more.
    const late = verse.reviewed({ remembered: true, today: addDays(monday, 30) });
    expect(late.stability).toBeGreaterThan(quick.stability!);
    // A reader who keeps verses well waits longer; one who does not, less.
    const keeper = verse.reviewed({ remembered: true, today: monday, personal: 1.3 });
    const forgetter = verse.reviewed({ remembered: true, today: monday, personal: 0.8 });
    expect(keeper.stability).toBeGreaterThan(quick.stability!);
    expect(forgetter.stability).toBeLessThan(quick.stability!);
  });

  it('a verse from the old ladder carries its rung over', () => {
    const old = MemoryVerse.fromJson({
      b: 'JHN',
      c: 3,
      v: 16,
      added: '2026-09-01',
      due: '2026-09-28',
      rung: 4,
      recalled: 4,
    })!;
    expect(old.stability).toBeNull();
    // Rung 4 waited 14 days; the next recall starts from there.
    expect(old.nextWaitDays).toBe(14);
    const next = old.reviewed({ remembered: true, today: monday });
    expect(next.stability).toBe(14);
    expect(next.daysUntilDueOn(monday)).toBe(14);
  });

  it('the hook rides through JSON', () => {
    const verse = MemoryVerse.start(john, monday).withHook('  love ');
    expect(verse.hook).toBe('love');
    const copy = MemoryVerse.fromJson(JSON.parse(JSON.stringify(verse.toJson())) as Record<string, unknown>)!;
    expect(copy.hook).toBe('love');
    expect(copy.difficulty).toBe(MemoryVerse.defaultDifficulty);
    expect(MemoryVerse.start(john, monday).toJson()).not.toHaveProperty('hook');
  });

  it('a lapse drops to the bottom and is due again today', () => {
    let verse = MemoryVerse.start(john, monday);
    const later = addDays(monday, 40);
    for (let i = 0; i < 4; i++) {
      verse = verse.reviewed({ remembered: true, today: later });
    }
    expect(verse.rung).toBe(4);
    verse = verse.reviewed({ remembered: false, today: later });
    expect(verse.rung).toBe(0);
    expect(verse.isDueOn(later)).toBe(true);
    // What was recalled stays counted; only the place is lost.
    expect(verse.recalled).toBe(4);
  });

  it('is due the moment the day arrives, whatever the hour', () => {
    const verse = MemoryVerse.start(john, monday).reviewed({ remembered: true, today: monday });
    expect(verse.isDueOn(new Date(2026, 8, 28, 23, 59))).toBe(false);
    expect(verse.isDueOn(new Date(2026, 8, 29, 0, 0))).toBe(true);
  });

  it('round-trips through JSON', () => {
    const verse = MemoryVerse.start(john, monday).reviewed({ remembered: true, today: monday });
    const copy = MemoryVerse.fromJson(JSON.parse(JSON.stringify(verse.toJson())) as Record<string, unknown>)!;
    expect(copy.reference.equals(john)).toBe(true);
    expect(copy.added).toEqual(verse.added);
    expect(copy.due).toEqual(verse.due);
    expect(copy.rung).toBe(1);
    expect(copy.recalled).toBe(1);
    expect(copy.updated.getTime()).toBe(verse.updated.getTime());
  });

  it('refuses what is not a verse', () => {
    expect(MemoryVerse.fromJson({ b: 'JHN', c: 3 })).toBeNull();
    expect(MemoryVerse.fromJson({ b: 'NOPE', c: 1, v: 1, added: '2026-01-01', due: '2026-01-01' })).toBeNull();
    expect(MemoryVerse.fromJson({ b: 'JHN', c: 3, v: 16, added: 'x' })).toBeNull();
  });
});

describe('the prompts', () => {
  it('first letters keep the shape of the verse', () => {
    expect(MemoryPrompt.hint('For God so loved the world, that he gave')).toBe('F__ G__ s_ l____ t__ w____, t___ h_ g___');
  });

  it('punctuation, quotes and numbers keep their places', () => {
    expect(MemoryPrompt.hint('He said, "Follow me."')).toBe('H_ s___, "F_____ m_."');
    expect(MemoryPrompt.hint('12 men')).toBe('1_ m__');
  });

  it('an apostrophe stays, and does not start a new word', () => {
    expect(MemoryPrompt.hint("don’t the Lord's")).toBe("d__’_ t__ L___'_");
  });

  it('accented letters are letters', () => {
    expect(MemoryPrompt.hint('Élan café')).toBe('É___ c___');
  });

  it('each prompt shows its share', () => {
    const text = 'God said, "Let there be light."';
    expect(MemoryPrompt.read.apply(text)).toBe(text);
    expect(MemoryPrompt.firstLetters.apply(text)).toBe(MemoryPrompt.hint(text));
    expect(MemoryPrompt.fromMemory.apply(text)).toBe('');
  });

  it('a verse is read while new, hinted while young, then bare', () => {
    expect(MemoryPrompt.forRung(0)).toBe(MemoryPrompt.read);
    expect(MemoryPrompt.forRung(1)).toBe(MemoryPrompt.firstLetters);
    expect(MemoryPrompt.forRung(2)).toBe(MemoryPrompt.firstLetters);
    expect(MemoryPrompt.forRung(3)).toBe(MemoryPrompt.fromMemory);
    expect(MemoryPrompt.forRung(9)).toBe(MemoryPrompt.fromMemory);
  });
});

describe('the store', () => {
  let prefs: Prefs;
  beforeEach(() => {
    prefs = Prefs.memory();
    // These are about the ladder, not the timing of new verses.
    prefs.setString('sleep', '{"mode":"off"}');
  });

  const references = (verses: readonly MemoryVerse[]) => verses.map((v) => v.reference.encode());

  it('memorising toggles on and off and is due at once', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    expect(store.isMemorising(john)).toBe(false);
    expect(store.hasMemoryDue).toBe(false);

    expect(store.toggleMemorise(john)).toBe(true);
    expect(store.isMemorising(john)).toBe(true);
    expect(references(store.memoryVerses)).toEqual([john.encode()]);
    expect(references(store.memoryDue)).toEqual([john.encode()]);
    expect(store.hasMemoryDue).toBe(true);

    expect(store.toggleMemorise(john)).toBe(false);
    expect(store.memoryVerses).toEqual([]);
    expect(store.hasMemoryDue).toBe(false);
  });

  it('a verse added with the timing off is learnt whenever', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    expect(store.sleepPolicy.mode).toBe(SleepMode.off);
    store.toggleMemorise(john);
    expect(store.memoryFor(john)!.arm).toBeNull();
    expect(references(store.memoryDue)).toEqual([john.encode()]);
  });

  it('a whole chapter cannot be memorised', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    expect(store.toggleMemorise(new Reference('JHN', 3))).toBe(false);
    expect(store.memoryVerses).toEqual([]);
  });

  it('a review moves the verse and the dot goes out', async () => {
    let today = monday;
    const store = await ReadingStore.load({ prefs, clock: () => today });
    store.toggleMemorise(john);
    store.reviewMemory(john, { remembered: true });
    expect(store.memoryFor(john)!.rung).toBe(1);
    expect(store.hasMemoryDue).toBe(false);
    expect(store.memoryDue).toEqual([]);

    today = addDays(monday, 1);
    expect(store.hasMemoryDue).toBe(true);
    store.reviewMemory(john, { remembered: false });
    expect(store.memoryFor(john)!.rung).toBe(0);
    expect(store.hasMemoryDue).toBe(true);

    // A verse never added is not reviewed into being.
    store.reviewMemory(psalm, { remembered: true });
    expect(store.memoryFor(psalm)).toBeNull();
  });

  it('due verses come longest waiting first', async () => {
    let today = monday;
    const store = await ReadingStore.load({ prefs, clock: () => today });
    store.toggleMemorise(john);
    store.reviewMemory(john, { remembered: true });
    today = addDays(monday, 1);
    store.reviewMemory(john, { remembered: true }); // due in 3 days
    store.toggleMemorise(psalm); // due today
    today = addDays(monday, 4);
    // The ladder's due verses come before the ones still to be learnt.
    expect(references(store.memoryDue)).toEqual([john.encode(), psalm.encode()]);
  });

  it('due verses come easiest first, so the session warms up', async () => {
    let today = monday;
    const store = await ReadingStore.load({ prefs, clock: () => today });
    store.toggleMemorise(john);
    store.toggleMemorise(psalm);
    for (let i = 0; i < 3; i++) {
      store.reviewMemory(john, { remembered: true });
      store.reviewMemory(psalm, { remembered: true });
    }
    // Both due in five days; the psalm is left a fortnight longer, so its
    // chance of recall is the lower, and it is asked second.
    today = addDays(monday, 5);
    store.reviewMemory(john, { remembered: true });
    today = addDays(monday, 40);
    expect(references(store.memoryDue)).toEqual([john.encode(), psalm.encode()]);
    expect(store.memoryFor(john)!.retrievability(today)).toBeGreaterThan(store.memoryFor(psalm)!.retrievability(today));
  });

  it('a recall against the odds says the reader keeps verses well', async () => {
    let today = monday;
    const store = await ReadingStore.load({ prefs, clock: () => today });
    store.toggleMemorise(john);
    store.reviewMemory(john, { remembered: true });
    store.reviewMemory(john, { remembered: true });
    expect(store.progress.recallFactor).toBe(1);
    // Recalled long after it was due: the gaps are stretched a little.
    today = addDays(monday, 60);
    store.reviewMemory(john, { remembered: true });
    expect(store.progress.recallFactor).toBeCloseTo(1.03, 9);
    // Missed the day after a recall: pulled back in.
    today = addDays(today, 1);
    store.reviewMemory(john, { remembered: false });
    expect(store.progress.recallFactor).toBeCloseTo(1.0, 9);
    expect((await ReadingStore.load({ prefs, clock: () => today })).progress.recallFactor).toBeCloseTo(1.0, 9);
  });

  it('a hook is kept with the verse', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    store.toggleMemorise(john);
    store.setMemoryHook(john, ' love ');
    expect(store.memoryFor(john)!.hook).toBe('love');
    expect((await ReadingStore.load({ prefs })).memoryFor(john)!.hook).toBe('love');
    store.setMemoryHook(psalm, 'rest');
    expect(store.memoryFor(psalm)).toBeNull();
  });

  it('survives a restart, and remove and restore', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    store.toggleMemorise(john);
    store.reviewMemory(john, { remembered: true });

    const again = await ReadingStore.load({ prefs, clock: () => monday });
    const verse = again.memoryFor(john)!;
    expect(verse.rung).toBe(1);

    again.removeMemory(john);
    expect(again.memoryVerses).toEqual([]);
    again.restoreMemory(verse);
    expect(again.memoryFor(john)!.rung).toBe(1);
  });

  it('goes into a backup and merges back by recency', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    store.toggleMemorise(john);
    expect(store.hasBackupContent).toBe(true);
    const backup = store.export();
    expect(backup).toContain('"memory"');

    const fresh = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => monday });
    const result = fresh.import(backup);
    expect(result.ok).toBe(true);
    expect(result.added).toBe(1);
    expect(fresh.memoryFor(john)!.due).toEqual(store.memoryFor(john)!.due);

    // The copy with the later touch wins.
    await new Promise((resolve) => setTimeout(resolve, 2));
    fresh.reviewMemory(john, { remembered: true });
    expect(store.import(fresh.export()).updated).toBe(1);
    expect(store.memoryFor(john)!.rung).toBe(1);
    expect(fresh.import(backup).total).toBe(0);
  });

  it('remove everything takes the memory verses with it', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    store.toggleMemorise(john);
    store.clearAll();
    expect(store.memoryVerses).toEqual([]);
    expect((await ReadingStore.load({ prefs })).memoryVerses).toEqual([]);
  });
});
