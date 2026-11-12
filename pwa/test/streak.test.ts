import { beforeEach, describe, expect, it } from 'vitest';
import { ReadingStore } from '../src/data/marks';
import { Prefs } from '../src/infra/prefs';
import { Reference } from '../src/model/bible';
import { LocalDate } from '../src/model/localDate';
import { Streak } from '../src/model/streak';

const monday = new Date(2026, 8, 28, 9, 30);
const days = (n: number) => new Date(monday.getTime() + n * 86_400_000);

describe('a streak', () => {
  it('grows a day at a time and once a day', () => {
    let streak = Streak.none;
    expect(streak.currentOn(monday)).toBe(0);
    streak = streak.extendedOn(monday);
    expect(streak.count).toBe(1);
    expect(streak.practisedOn(monday)).toBe(true);
    expect(streak.extendedOn(new Date(monday.getTime() + 5 * 3_600_000))).toBe(streak);
    streak = streak.extendedOn(days(1));
    expect(streak.count).toBe(2);
    expect(streak.best).toBe(2);
    expect(streak.last).toEqual(LocalDate.only(days(1)));
  });

  it('stands through the next day and breaks after', () => {
    const streak = Streak.none.extendedOn(monday).extendedOn(days(1));
    expect(streak.currentOn(days(1))).toBe(2);
    expect(streak.currentOn(days(2))).toBe(2);
    expect(streak.needsPractiseOn(days(2))).toBe(true);
    expect(streak.needsPractiseOn(days(1))).toBe(false);
    expect(streak.currentOn(days(3))).toBe(0);
    expect(streak.needsPractiseOn(days(3))).toBe(false);
    // A new run starts at one; the best is kept.
    const again = streak.extendedOn(days(3));
    expect(again.count).toBe(1);
    expect(again.best).toBe(2);
  });

  it('a clock set back does not count the run', () => {
    const streak = Streak.none.extendedOn(days(2));
    expect(streak.currentOn(monday)).toBe(0);
  });

  it('round-trips through JSON, and refuses nonsense', () => {
    const streak = Streak.none.extendedOn(monday).extendedOn(days(1));
    expect(Streak.fromJson(streak.toJson())!.equals(streak)).toBe(true);
    expect(Streak.fromJson({ count: -1 })).toBeNull();
    expect(Streak.fromJson({ count: 'x' })).toBeNull();
    // A best below the count is the count.
    expect(Streak.fromJson({ count: 3, best: 1 })!.best).toBe(3);
  });
});

describe('in the store', () => {
  const john = new Reference('JHN', 3, 16);
  let prefs: Prefs;

  beforeEach(() => {
    prefs = Prefs.memory();
    prefs.setString('sleep', '{"mode":"off"}');
  });

  it('practice is recorded, kept, and shown on the next day', async () => {
    let today = monday;
    const store = await ReadingStore.load({ prefs, clock: () => today });
    expect(store.streak.currentOn(today)).toBe(0);
    store.recordPractice();
    store.recordPractice();
    expect(store.streak.count).toBe(1);
    expect(store.streak.practisedOn(today)).toBe(true);

    today = days(1);
    const again = await ReadingStore.load({ prefs, clock: () => today });
    expect(again.streak.currentOn(today)).toBe(1);
    expect(again.streak.needsPractiseOn(today)).toBe(true);
    again.recordPractice();
    expect(again.streak.count).toBe(2);
  });

  it('goes into a backup and the better one is kept', async () => {
    let today = monday;
    const store = await ReadingStore.load({ prefs, clock: () => today });
    store.toggleMemorise(john);
    store.recordPractice();
    today = days(1);
    store.recordPractice();
    const backup = store.export();
    expect(backup).toContain('"streak"');

    const fresh = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => today });
    expect(fresh.import(backup).ok).toBe(true);
    expect(fresh.streak.equals(store.streak)).toBe(true);

    // The device practised on more recently sets the run; the best of
    // the two stays the best.
    today = days(5);
    const other = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => today });
    other.recordPractice();
    const merged = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => today });
    merged.import(backup);
    expect(merged.streak.best).toBe(2);
    merged.import(other.export());
    expect(merged.streak.count).toBe(1);
    expect(merged.streak.best).toBe(2);
    expect(merged.streak.last).toEqual(LocalDate.only(today));
    // The older backup brought back changes nothing.
    expect(merged.import(backup).total).toBe(0);
  });

  it('a backup holding only a streak still imports', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    store.recordPractice();
    expect(store.hasBackupContent).toBe(true);
    const fresh = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => monday });
    expect(fresh.import(store.export()).ok).toBe(true);
    expect(fresh.streak.count).toBe(1);
  });
});
