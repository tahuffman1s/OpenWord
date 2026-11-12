import { LocalDate } from './localDate';

/** What learning earns, in points. */
export const Xp = {
  /**
   * A verse on the ladder answered right: more the higher it stands,
   * since a verse recalled after a month is worth more than one copied.
   */
  memoryRight(rung: number): number {
    return 10 + 2 * rung;
  },

  /** A question in a round answered right. */
  quizRight: 5,

  /** A round with every answer right. */
  perfectRound: 20,

  /** The bonus for the nth right answer in a row, where there is one. */
  comboBonus(inARow: number): number {
    switch (inARow) {
      case 3:
        return 5;
      case 5:
        return 10;
      case 10:
        return 20;
      default:
        return inARow > 10 && inARow % 10 === 0 ? 20 : 0;
    }
  },
} as const;

/**
 * How sure a reader was before answering from memory.
 *
 * Asked so that the misses made with confidence can be told apart: they
 * are the ones most readily corrected once shown, and the ones most
 * likely to come back if they are not.
 */
export enum Confidence {
  sure = 'sure',
  fairly = 'fairly',
  guessing = 'guessing',
}

export const confidenceValues: readonly Confidence[] = [Confidence.sure, Confidence.fairly, Confidence.guessing];

export const confidenceLabel: Record<Confidence, string> = {
  [Confidence.sure]: 'Sure',
  [Confidence.fairly]: 'Fairly sure',
  [Confidence.guessing]: 'Guessing',
};

/**
 * How much a day asks for. Like a language app's, the choice is the
 * reader's and the smallest is meant to be kept.
 */
export class DailyGoal {
  static readonly gentle = new DailyGoal('gentle', 20, 'Gentle', 'A verse or two');
  static readonly steady = new DailyGoal('steady', 40, 'Steady', 'A short session');
  static readonly keen = new DailyGoal('keen', 60, 'Keen', 'A proper sit-down');
  static readonly intense = new DailyGoal('intense', 100, 'Intense', 'Make a dent');

  static readonly values: readonly DailyGoal[] = [DailyGoal.gentle, DailyGoal.steady, DailyGoal.keen, DailyGoal.intense];

  private constructor(
    readonly name: string,
    readonly xp: number,
    readonly label: string,
    readonly description: string,
  ) {}

  static forXp(xp: number): DailyGoal {
    return DailyGoal.values.find((g) => g.xp === xp) ?? DailyGoal.steady;
  }
}

/** A tally of answers from memory at one level of confidence: asked and right. */
export type ConfidenceTally = readonly [asked: number, right: number];

export interface LearnProgressInit {
  xp?: number;
  daily?: ReadonlyMap<number, number>;
  right?: number;
  wrong?: number;
  perfectRounds?: number;
  scribed?: number;
  heard?: number;
  goal?: DailyGoal;
  badges?: ReadonlyMap<string, Date>;
  confidence?: ReadonlyMap<Confidence, ConfidenceTally>;
  confidentMisses?: number;
  recallFactor?: number;
}

/**
 * Points earned, by day and in all, the level they add up to, the day's
 * goal, and the badges won.
 *
 * Levels come thick and fast at first and slowly later: level n is
 * reached at 25·n·(n−1) points, so the second takes 50, the fifth 500
 * and the tenth 2,250.
 */
export class LearnProgress {
  static readonly none = new LearnProgress();

  /** How many days of points are kept. */
  static readonly daysKept = 60;

  readonly xp: number;

  /**
   * Points per local day, the day as `LocalDate.only` gives it — keyed by
   * that date's `getTime()`, since a `Map` cannot key on a `Date` by value.
   */
  readonly daily: ReadonlyMap<number, number>;

  /** Answers right and wrong, ever. */
  readonly right: number;
  readonly wrong: number;

  /** Rounds with every answer right. */
  readonly perfectRounds: number;

  /** Verses written out right. */
  readonly scribed: number;

  /** Verses heard and put together right. */
  readonly heard: number;

  readonly goal: DailyGoal;

  /** Badges won, by id, with the day each was won. */
  readonly badges: ReadonlyMap<string, Date>;

  /** Answers from memory by how sure the reader was: asked and right. */
  readonly confidence: ReadonlyMap<Confidence, ConfidenceTally>;

  /** Misses made while sure. */
  readonly confidentMisses: number;

  /**
   * How well this reader keeps verses against the common run: 1 is the
   * schedule as set, more stretches every wait, less shortens it. Learnt
   * from recalls that came when the chance had fallen low, and misses
   * that came when it was still high.
   */
  readonly recallFactor: number;

  constructor(init: LearnProgressInit = {}) {
    this.xp = init.xp ?? 0;
    this.daily = init.daily ?? new Map();
    this.right = init.right ?? 0;
    this.wrong = init.wrong ?? 0;
    this.perfectRounds = init.perfectRounds ?? 0;
    this.scribed = init.scribed ?? 0;
    this.heard = init.heard ?? 0;
    this.goal = init.goal ?? DailyGoal.steady;
    this.badges = init.badges ?? new Map();
    this.confidence = init.confidence ?? new Map();
    this.confidentMisses = init.confidentMisses ?? 0;
    this.recallFactor = init.recallFactor ?? 1;
  }

  /**
   * How often the reader was right when they said `level`, or null
   * before anything was asked at that level.
   */
  calibration(level: Confidence): number | null {
    const tally = this.confidence.get(level);
    if (tally === undefined || tally[0] === 0) return null;
    return tally[1] / tally[0];
  }

  get level(): number {
    return LearnProgress.levelFor(this.xp);
  }

  /**
   * What the recall factor says of this reader, in a sentence: how long
   * they keep a verse against the common run, and what was done about it.
   */
  get keeping(): string {
    return this.recallFactor < 0.9
      ? 'Verses slip from you a little sooner than from most, so your ' +
          'gaps between recalls have been shortened to match.'
      : this.recallFactor > 1.1
        ? 'You keep a verse longer than most, so your gaps between recalls ' + 'have been stretched to match.'
        : 'You keep a verse about as long as most people; your gaps between ' +
          'recalls are set to match, and move as you go.';
  }

  /** Points at which `level` began and the next begins. */
  get levelFloor(): number {
    return LearnProgress.xpForLevel(this.level);
  }
  get nextLevelAt(): number {
    return LearnProgress.xpForLevel(this.level + 1);
  }

  /** How far through the level, 0 to 1. */
  get levelFraction(): number {
    return (this.xp - this.levelFloor) / Math.min(Math.max(this.nextLevelAt - this.levelFloor, 1), 1 << 30);
  }

  static xpForLevel(level: number): number {
    return 25 * level * (level - 1);
  }

  static levelFor(xp: number): number {
    return Math.min(Math.max(Math.floor((1 + Math.sqrt(1 + (4 * xp) / 25)) / 2), 1), 1 << 20);
  }

  xpOn(day: Date): number {
    return this.daily.get(LocalDate.only(day).getTime()) ?? 0;
  }

  goalMetOn(day: Date): boolean {
    return this.xpOn(day) >= this.goal.xp;
  }

  /** Days running, ending today or yesterday, on which the goal was met. */
  goalDaysRunningOn(today: Date): number {
    let day = LocalDate.only(today);
    if (!this.goalMetOn(day)) day = LocalDate.addDays(day, -1);
    let run = 0;
    while (this.goalMetOn(day)) {
      run++;
      day = LocalDate.addDays(day, -1);
    }
    return run;
  }

  /** Points for each of the `days` days ending today, oldest first. */
  lastDays(today: Date, days: number): number[] {
    const end = LocalDate.only(today);
    const out: number[] = [];
    for (let i = days - 1; i >= 0; i--) {
      out.push(this.daily.get(LocalDate.addDays(end, -i).getTime()) ?? 0);
    }
    return out;
  }

  /** With `points` earned on `today`. */
  earned(
    points: number,
    today: Date,
    options: {
      right?: boolean | null;
      perfectRound?: boolean;
      scribed?: boolean;
      heard?: boolean;
      confidence?: Confidence | null;
    } = {},
  ): LearnProgress {
    const { right = null, perfectRound = false, scribed = false, heard = false, confidence = null } = options;
    const day = LocalDate.only(today);
    const cutoff = LocalDate.addDays(day, -LearnProgress.daysKept).getTime();
    const next = new Map<number, number>();
    for (const [key, value] of this.daily) {
      if (!(key < cutoff)) next.set(key, value);
    }
    next.set(day.getTime(), (next.get(day.getTime()) ?? 0) + points);
    let tallies: Map<Confidence, ConfidenceTally> | undefined;
    if (confidence !== null && right !== null) {
      tallies = new Map(this.confidence);
      const have = this.confidence.get(confidence);
      tallies.set(confidence, [(have?.[0] ?? 0) + 1, (have?.[1] ?? 0) + (right ? 1 : 0)]);
    }
    return this.copyWith({
      xp: this.xp + points,
      daily: next,
      right: right === true ? this.right + 1 : undefined,
      wrong: right === false ? this.wrong + 1 : undefined,
      perfectRounds: perfectRound ? this.perfectRounds + 1 : undefined,
      scribed: scribed ? this.scribed + 1 : undefined,
      heard: heard ? this.heard + 1 : undefined,
      confidence: tallies,
      confidentMisses: confidence === Confidence.sure && right === false ? this.confidentMisses + 1 : undefined,
    });
  }

  awarded(badge: string, today: Date): LearnProgress {
    const badges = new Map(this.badges);
    badges.set(badge, LocalDate.only(today));
    return this.copyWith({ badges });
  }

  copyWith(changes: LearnProgressInit): LearnProgress {
    return new LearnProgress({
      xp: changes.xp ?? this.xp,
      daily: changes.daily ?? this.daily,
      right: changes.right ?? this.right,
      wrong: changes.wrong ?? this.wrong,
      perfectRounds: changes.perfectRounds ?? this.perfectRounds,
      scribed: changes.scribed ?? this.scribed,
      heard: changes.heard ?? this.heard,
      goal: changes.goal ?? this.goal,
      badges: changes.badges ?? this.badges,
      confidence: changes.confidence ?? this.confidence,
      confidentMisses: changes.confidentMisses ?? this.confidentMisses,
      recallFactor: changes.recallFactor ?? this.recallFactor,
    });
  }

  toJson(): Record<string, unknown> {
    const daily: Record<string, number> = {};
    for (const [key, value] of this.daily) daily[LocalDate.format(new Date(key))] = value;
    const badges: Record<string, string> = {};
    for (const [id, day] of this.badges) badges[id] = LocalDate.format(day);
    const conf: Record<string, number[]> = {};
    for (const [level, tally] of this.confidence) conf[level] = [tally[0], tally[1]];
    return {
      xp: this.xp,
      daily,
      right: this.right,
      wrong: this.wrong,
      perfect: this.perfectRounds,
      scribed: this.scribed,
      heard: this.heard,
      goal: this.goal.xp,
      badges,
      ...(this.confidence.size > 0 ? { conf } : {}),
      ...(this.confidentMisses > 0 ? { sureMisses: this.confidentMisses } : {}),
      ...(this.recallFactor !== 1 ? { keep: this.recallFactor } : {}),
    };
  }

  static fromJson(json: Record<string, unknown>): LearnProgress | null {
    const xp = json['xp'];
    if (!Number.isInteger(xp) || (xp as number) < 0) return null;
    const count = (key: string): number => {
      const value = json[key];
      return Number.isInteger(value) && (value as number) > 0 ? (value as number) : 0;
    };

    const rawDaily = json['daily'];
    const rawBadges = json['badges'];
    const rawConf = json['conf'];
    const goal = json['goal'];
    const daily = new Map<number, number>();
    if (isRecord(rawDaily)) {
      for (const [key, points] of Object.entries(rawDaily)) {
        const day = LocalDate.parse(key);
        if (day === null) continue;
        if (Number.isInteger(points) && (points as number) > 0) daily.set(day.getTime(), points as number);
      }
    }
    const badges = new Map<string, Date>();
    if (isRecord(rawBadges)) {
      for (const [id, raw] of Object.entries(rawBadges)) {
        const day = LocalDate.parse(raw);
        if (day !== null) badges.set(id, day);
      }
    }
    const confidence = new Map<Confidence, ConfidenceTally>();
    if (isRecord(rawConf)) {
      for (const level of confidenceValues) {
        const tally = rawConf[level];
        if (Array.isArray(tally) && tally.length === 2 && Number.isInteger(tally[0]) && Number.isInteger(tally[1])) {
          confidence.set(level, [tally[0] as number, tally[1] as number]);
        }
      }
    }
    const keep = json['keep'];
    return new LearnProgress({
      xp: xp as number,
      daily,
      right: count('right'),
      wrong: count('wrong'),
      perfectRounds: count('perfect'),
      scribed: count('scribed'),
      heard: count('heard'),
      goal: Number.isInteger(goal) ? DailyGoal.forXp(goal as number) : DailyGoal.steady,
      badges,
      confidence,
      confidentMisses: count('sureMisses'),
      recallFactor: typeof keep === 'number' ? Math.min(Math.max(keep, 0.7), 1.4) : 1,
    });
  }

  /** Whether `other` holds the same values as this. */
  equals(other: LearnProgress | null | undefined): boolean {
    return (
      other != null &&
      other.xp === this.xp &&
      mapEquals(other.daily, this.daily, (a, b) => a === b) &&
      other.right === this.right &&
      other.wrong === this.wrong &&
      other.perfectRounds === this.perfectRounds &&
      other.scribed === this.scribed &&
      other.heard === this.heard &&
      other.goal === this.goal &&
      mapEquals(other.badges, this.badges, (a, b) => a.getTime() === b.getTime()) &&
      mapEquals(other.confidence, this.confidence, (a, b) => a[0] === b[0] && a[1] === b[1]) &&
      other.confidentMisses === this.confidentMisses &&
      other.recallFactor === this.recallFactor
    );
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function mapEquals<K, V>(a: ReadonlyMap<K, V>, b: ReadonlyMap<K, V>, same: (x: V, y: V) => boolean): boolean {
  if (a.size !== b.size) return false;
  for (const [key, value] of a) {
    if (!b.has(key) || !same(b.get(key)!, value)) return false;
  }
  return true;
}
