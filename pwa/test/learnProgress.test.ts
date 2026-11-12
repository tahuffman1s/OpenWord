import { beforeEach, describe, expect, it } from 'vitest';
import { ReadingStore } from '../src/data/marks';
import { Prefs } from '../src/infra/prefs';
import { Achievement } from '../src/model/achievements';
import { Reference } from '../src/model/bible';
import { DailyGoal, LearnProgress, Xp } from '../src/model/learnProgress';
import { LocalDate } from '../src/model/localDate';
import { Streak } from '../src/model/streak';

const monday = new Date(2026, 8, 28, 9, 30);
const days = (n: number) => new Date(monday.getTime() + n * 86_400_000);

const withFreezes = (streak: Streak, freezes: number) =>
  new Streak({ count: streak.count, best: streak.best, last: streak.last, freezes });

describe('points', () => {
  it('a verse is worth more the higher it stands', () => {
    expect(Xp.memoryRight(0)).toBe(10);
    expect(Xp.memoryRight(3)).toBe(16);
    expect(Xp.quizRight).toBe(5);
    expect(Xp.perfectRound).toBe(20);
  });

  it('a run of right answers earns a bonus at three, five and ten', () => {
    const bonuses: number[] = [];
    for (let n = 1; n <= 11; n++) bonuses.push(Xp.comboBonus(n));
    expect(bonuses).toEqual([0, 0, 5, 0, 10, 0, 0, 0, 0, 20, 0]);
    expect(Xp.comboBonus(20)).toBe(20);
  });
});

describe('levels', () => {
  it('come quickly at first and slowly later', () => {
    expect(LearnProgress.levelFor(0)).toBe(1);
    expect(LearnProgress.levelFor(49)).toBe(1);
    expect(LearnProgress.levelFor(50)).toBe(2);
    expect(LearnProgress.levelFor(150)).toBe(3);
    expect(LearnProgress.levelFor(499)).toBe(4);
    expect(LearnProgress.levelFor(500)).toBe(5);
    expect(LearnProgress.levelFor(2250)).toBe(10);
    for (let level = 1; level < 30; level++) {
      expect(LearnProgress.levelFor(LearnProgress.xpForLevel(level))).toBe(level);
      expect(LearnProgress.levelFor(LearnProgress.xpForLevel(level + 1) - 1)).toBe(level);
    }
  });

  it('the bar shows how far through the level', () => {
    const progress = new LearnProgress({ xp: 100 });
    expect(progress.level).toBe(2);
    expect(progress.levelFloor).toBe(50);
    expect(progress.nextLevelAt).toBe(150);
    expect(progress.levelFraction).toBe(0.5);
  });
});

describe('days and goals', () => {
  it('points land on the day and the goal is met at the mark', () => {
    let progress = LearnProgress.none.earned(15, monday, { right: true });
    expect(progress.xpOn(monday)).toBe(15);
    expect(progress.right).toBe(1);
    expect(progress.goalMetOn(monday)).toBe(false);
    progress = progress.earned(25, new Date(monday.getTime() + 8 * 3_600_000));
    expect(progress.xpOn(monday)).toBe(40);
    expect(progress.goalMetOn(monday)).toBe(true);
    expect(progress.xpOn(days(1))).toBe(0);
    expect(progress.lastDays(days(1), 3)).toEqual([0, 40, 0]);
  });

  it('a run of goal days counts back from today or yesterday', () => {
    let progress = LearnProgress.none;
    for (let i = 0; i < 3; i++) {
      progress = progress.earned(40, days(i));
    }
    expect(progress.goalDaysRunningOn(days(2))).toBe(3);
    // Today not yet done: the run still stands from yesterday.
    expect(progress.goalDaysRunningOn(days(3))).toBe(3);
    // A day missed: the run is over.
    expect(progress.goalDaysRunningOn(days(4))).toBe(0);
    // A smaller goal makes more days count.
    expect(progress.earned(20, days(3)).copyWith({ goal: DailyGoal.gentle }).goalDaysRunningOn(days(3))).toBe(4);
  });

  it('old days fall away', () => {
    let progress = LearnProgress.none.earned(10, monday);
    progress = progress.earned(10, days(LearnProgress.daysKept + 1));
    expect(progress.daily.size).toBe(1);
    // The total keeps them.
    expect(progress.xp).toBe(20);
  });

  it('a goal is found from its points', () => {
    expect(DailyGoal.forXp(100)).toBe(DailyGoal.intense);
    expect(DailyGoal.forXp(7)).toBe(DailyGoal.steady);
  });
});

it('says how the reader keeps verses, from the recall factor', () => {
  expect(new LearnProgress().keeping).toContain('about as long as most');
  expect(new LearnProgress({ recallFactor: 1.2 }).keeping).toContain('longer than most');
  expect(new LearnProgress({ recallFactor: 0.8 }).keeping).toContain('sooner than from most');
  const copy = LearnProgress.fromJson(new LearnProgress({ recallFactor: 1.2 }).toJson());
  expect(copy!.recallFactor).toBe(1.2);
});

it('round-trips through JSON', () => {
  const progress = LearnProgress.none.earned(16, monday, { right: true, scribed: true })
    .earned(0, days(1), { right: false })
    .earned(20, days(1), { perfectRound: true, heard: true })
    .copyWith({ goal: DailyGoal.keen })
    .awarded('first_step', monday);
  const copy = LearnProgress.fromJson(JSON.parse(JSON.stringify(progress.toJson())) as Record<string, unknown>);
  expect(copy!.equals(progress)).toBe(true);
  expect(copy!.badges.get('first_step')).toEqual(LocalDate.only(monday));
  expect(LearnProgress.fromJson({ xp: -1 })).toBeNull();
  expect(LearnProgress.fromJson({ xp: 'x' })).toBeNull();
});

describe('badges', () => {
  const withXp = (xp: number) => new LearnProgress({ xp });
  const earned = (
    badge: Achievement,
    options: { progress?: LearnProgress; streak?: number; onLadder?: number; learnt?: number } = {},
  ) =>
    badge.earnedBy({
      progress: options.progress ?? LearnProgress.none,
      streak: options.streak ?? 0,
      versesOnLadder: options.onLadder ?? 0,
      versesLearnt: options.learnt ?? 0,
      today: monday,
    });

  it('each knows its own condition', () => {
    expect(earned(Achievement.firstStep)).toBe(false);
    expect(earned(Achievement.firstStep, { progress: withXp(1) })).toBe(true);
    expect(earned(Achievement.weekOfFire, { streak: 6 })).toBe(false);
    expect(earned(Achievement.weekOfFire, { streak: 7 })).toBe(true);
    expect(earned(Achievement.monthOfFire, { streak: 30 })).toBe(true);
    expect(earned(Achievement.gathering, { onLadder: 10 })).toBe(true);
    expect(earned(Achievement.byHeart, { learnt: 1 })).toBe(true);
    expect(earned(Achievement.fiveByHeart, { learnt: 4 })).toBe(false);
    expect(earned(Achievement.perfectRound, { progress: new LearnProgress({ perfectRounds: 1 }) })).toBe(true);
    expect(earned(Achievement.scribe, { progress: new LearnProgress({ scribed: 1 }) })).toBe(true);
    expect(earned(Achievement.goodEar, { progress: new LearnProgress({ heard: 1 }) })).toBe(true);
    expect(earned(Achievement.hundred, { progress: new LearnProgress({ right: 100 }) })).toBe(true);
    expect(earned(Achievement.levelFive, { progress: withXp(500) })).toBe(true);
    expect(earned(Achievement.levelFive, { progress: withXp(499) })).toBe(false);
  });

  it('ids are unique and look themselves up', () => {
    const ids = new Set(Achievement.values.map((a) => a.id));
    expect(ids.size).toBe(Achievement.values.length);
    expect(Achievement.values).toHaveLength(12);
    for (const badge of Achievement.values) {
      expect(Achievement.byId(badge.id)).toBe(badge);
    }
    expect(Achievement.byId('nope')).toBeNull();
  });
});

describe('streak freezes', () => {
  it('one is earned every seventh day, two at most', () => {
    let streak = Streak.none;
    for (let i = 0; i < 6; i++) {
      streak = streak.extendedOn(days(i));
    }
    expect(streak.freezes).toBe(0);
    streak = streak.extendedOn(days(6));
    expect(streak.count).toBe(7);
    expect(streak.freezes).toBe(1);
    for (let i = 7; i < 21; i++) {
      streak = streak.extendedOn(days(i));
    }
    expect(streak.count).toBe(21);
    expect(streak.freezes).toBe(Streak.maxFreezes);
  });

  it('a freeze holds the run across one missed day, and is spent', () => {
    let streak = Streak.none;
    for (let i = 0; i < 7; i++) {
      streak = streak.extendedOn(days(i));
    }
    // Day 7 missed; on day 8 the run still stands.
    expect(streak.frozenOn(days(8))).toBe(true);
    expect(streak.currentOn(days(8))).toBe(7);
    expect(streak.needsPractiseOn(days(8))).toBe(true);
    streak = streak.extendedOn(days(8));
    expect(streak.count).toBe(8);
    expect(streak.freezes).toBe(0);
    // Without one, the next missed day ends it.
    expect(streak.currentOn(days(10))).toBe(0);
    // Two missed days are too many for one freeze.
    const again = withFreezes(Streak.none.extendedOn(monday), 1);
    expect(again.currentOn(days(3))).toBe(0);
  });

  it('is kept in JSON', () => {
    const streak = withFreezes(Streak.none.extendedOn(monday), 2);
    expect(Streak.fromJson(streak.toJson())!.equals(streak)).toBe(true);
    expect(Streak.fromJson({ count: 1, freezes: 9 })!.freezes).toBe(2);
  });
});

describe('in the store', () => {
  const john = new Reference('JHN', 3, 16);
  let prefs: Prefs;

  beforeEach(() => {
    prefs = Prefs.memory();
    prefs.setString('sleep', '{"mode":"off"}');
  });

  it('an answer earns points, a day, and the first badge', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    const won = store.recordLearning({ xp: 10, right: true });
    expect(won).toEqual([Achievement.firstStep]);
    expect(store.progress.xp).toBe(10);
    expect(store.progress.right).toBe(1);
    expect([...store.progress.badges.keys()]).toEqual(['first_step']);
    expect(store.streak.count).toBe(1);
    // Won once: not again.
    expect(store.recordLearning({ xp: 10, right: true })).toEqual([]);
    const again = await ReadingStore.load({ prefs, clock: () => monday });
    expect(again.progress.xp).toBe(20);
    expect([...again.progress.badges.keys()]).toEqual(['first_step']);
  });

  it('the goal is a choice and is kept', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    store.setDailyGoal(DailyGoal.intense);
    expect((await ReadingStore.load({ prefs })).progress.goal).toBe(DailyGoal.intense);
  });

  it('a verse known after a month wins By heart', async () => {
    const today = monday;
    const store = await ReadingStore.load({ prefs, clock: () => today });
    store.toggleMemorise(john);
    for (let i = 0; i < 5; i++) {
      store.reviewMemory(john, { remembered: true });
    }
    expect(store.versesLearnt).toBe(1);
    const won = store.recordLearning({ xp: 20, right: true });
    expect(won).toEqual(expect.arrayContaining([Achievement.firstStep, Achievement.byHeart]));
  });

  it('goes into a backup, and two copies add up to the better one', async () => {
    const store = await ReadingStore.load({ prefs, clock: () => monday });
    store.recordLearning({ xp: 30, right: true });
    store.setDailyGoal(DailyGoal.keen);
    const backup = store.export();
    expect(backup).toContain('"progress"');

    const other = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => days(1) });
    other.recordLearning({ xp: 50, right: true });
    other.recordLearning({ xp: 0, right: false });
    expect(other.import(backup).ok).toBe(true);
    const merged = other.progress;
    // The higher total.
    expect(merged.xp).toBe(50);
    expect(merged.xpOn(monday)).toBe(30);
    expect(merged.xpOn(days(1))).toBe(50);
    expect(merged.right).toBe(1);
    expect(merged.wrong).toBe(1);
    // The goal stays mine.
    expect(merged.goal).toBe(DailyGoal.steady);
    expect(merged.badges.get('first_step')).toEqual(LocalDate.only(monday));
    // The same backup again changes nothing.
    expect(other.import(backup).total).toBe(0);
  });
});
