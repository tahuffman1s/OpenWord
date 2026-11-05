import { LocalDate } from './localDate';

export interface StreakInit {
  count: number;
  best: number;
  last?: Date | null;
  freezes?: number;
}

/**
 * Days in a row with some learning done: a verse answered in practice,
 * or a round of questions finished.
 *
 * A day is a local calendar day. Practising twice in a day is one day;
 * a day missed ends the run, and the next practice starts a new one.
 * The best run is kept so that a broken streak is not nothing.
 *
 * A streak freeze forgives one missed day. One is earned for every seven
 * days kept up, at most `maxFreezes` held, and one is spent, unasked,
 * the first time a day is missed with one in hand.
 */
export class Streak {
  static readonly none = new Streak({ count: 0, best: 0 });

  static readonly maxFreezes = 2;

  /** Days kept up per freeze earned. */
  static readonly daysPerFreeze = 7;

  /** Days in the run that `last` ended. */
  readonly count: number;

  /** The longest run ever. */
  readonly best: number;

  /** The last day with learning done, as `LocalDate.only` gives it. */
  readonly last: Date | null;

  /** Missed days the run can survive. */
  readonly freezes: number;

  constructor(init: StreakInit) {
    this.count = init.count;
    this.best = init.best;
    this.last = init.last ?? null;
    this.freezes = init.freezes ?? 0;
  }

  practisedOn(today: Date): boolean {
    return this.last !== null && this.last.getTime() === LocalDate.only(today).getTime();
  }

  private gapTo(today: Date): number {
    const last = this.last;
    if (last === null) return -1;
    return LocalDate.daysBetween(LocalDate.only(today), last);
  }

  /**
   * Whether a freeze is what holds the run on `today`: yesterday was
   * missed, and one is in hand.
   */
  frozenOn(today: Date): boolean {
    return this.gapTo(today) === 2 && this.freezes > 0;
  }

  /**
   * The run as it stands on `today`: `count` while it is unbroken —
   * practised today, or yesterday with today still to come, or the day
   * before with a freeze to cover yesterday — and nothing once broken.
   */
  currentOn(today: Date): number {
    const gap = this.gapTo(today);
    if (gap < 0) return 0;
    return gap <= 1 || this.frozenOn(today) ? this.count : 0;
  }

  /** Whether the run is at risk: it stands, but today has not been done. */
  needsPractiseOn(today: Date): boolean {
    return this.currentOn(today) > 0 && !this.practisedOn(today);
  }

  /**
   * The streak after learning on `today`: a day longer, a freeze spent
   * where one was needed, and a freeze earned at every seventh day.
   */
  extendedOn(today: Date): Streak {
    if (this.practisedOn(today)) return this;
    const spent = this.frozenOn(today);
    const count = this.currentOn(today) + 1;
    let freezes = spent ? this.freezes - 1 : this.freezes;
    if (count % Streak.daysPerFreeze === 0 && freezes < Streak.maxFreezes) freezes++;
    return new Streak({
      count,
      best: count > this.best ? count : this.best,
      last: LocalDate.only(today),
      freezes,
    });
  }

  toJson(): Record<string, unknown> {
    return {
      count: this.count,
      best: this.best,
      ...(this.last !== null ? { last: LocalDate.format(this.last) } : {}),
      ...(this.freezes > 0 ? { freezes: this.freezes } : {}),
    };
  }

  static fromJson(json: Record<string, unknown>): Streak | null {
    const count = json['count'];
    const best = json['best'];
    const freezes = json['freezes'];
    if (!Number.isInteger(count) || (count as number) < 0) return null;
    return new Streak({
      count: count as number,
      best: Number.isInteger(best) && (best as number) >= (count as number) ? (best as number) : (count as number),
      last: LocalDate.parse(json['last']),
      freezes: Number.isInteger(freezes) ? Math.min(Math.max(freezes as number, 0), Streak.maxFreezes) : 0,
    });
  }

  /** Dart's `operator ==`. */
  equals(other: Streak | null | undefined): boolean {
    return (
      other != null &&
      other.count === this.count &&
      other.best === this.best &&
      LocalDate.same(other.last, this.last) &&
      other.freezes === this.freezes
    );
  }
}
