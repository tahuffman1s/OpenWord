import type { Reference } from '../model/bible';
import { LocalDate } from '../model/localDate';
import { ReadingPlans, type PlanDay, type ReadingPlan } from '../model/readingPlan';

export interface PlanProgressInit {
  plan: ReadingPlan;
  startedOn: Date;
  done: ReadonlySet<number>;
  updated: Date;
}

/**
 * How far a reader is through one plan.
 *
 * There is no streak and no count of days missed. "Today" is simply the
 * first day with anything left to read, so a day not read is waiting
 * tomorrow rather than added to a pile. The date a plan was started is
 * kept only to say, gently and only when it is worth saying, that the
 * reader has fallen behind the pace they set — and to let them pick up
 * from today without pretending they read what they did not.
 */
export class PlanProgress {
  readonly plan: ReadingPlan;

  /** The local date day 1 was, or would have been, read on. */
  readonly startedOn: Date;

  /** Slots read. A slot is one chapter on one day of the plan. */
  readonly done: ReadonlySet<number>;
  readonly updated: Date;

  constructor(init: PlanProgressInit) {
    this.plan = init.plan;
    this.startedOn = init.startedOn;
    this.done = init.done;
    this.updated = init.updated;
  }

  /**
   * A single day off makes no measurable difference to a habit, so being
   * one day behind is not mentioned. Two is when it is.
   */
  static readonly behindThreshold = 2;

  get slotsDone(): number {
    return this.done.size;
  }

  get isComplete(): boolean {
    return this.slotsDone >= this.plan.slotCount;
  }

  get fraction(): number {
    return this.plan.slotCount === 0 ? 0 : this.slotsDone / this.plan.slotCount;
  }

  isRead(slot: number): boolean {
    return this.done.has(slot);
  }

  isDayRead(day: PlanDay): boolean {
    return day.slots.every((slot) => this.done.has(slot));
  }

  readInDay(day: PlanDay): number {
    return day.slots.filter((slot) => this.done.has(slot)).length;
  }

  get daysRead(): number {
    return this.plan.days.filter((day) => this.isDayRead(day)).length;
  }

  /** The first day with anything unread, or null when the plan is done. */
  get currentDay(): PlanDay | null {
    for (const day of this.plan.days) {
      if (!this.isDayRead(day)) return day;
    }
    return null;
  }

  /** The first unread chapter of the current day: where "Continue" goes. */
  get nextSlot(): number | null {
    const day = this.currentDay;
    if (day === null) return null;
    for (const slot of day.slots) {
      if (!this.done.has(slot)) return slot;
    }
    return null;
  }

  chapterAt(slot: number): Reference {
    const day = this.plan.dayOfSlot(slot);
    return day.chapters[slot - day.firstSlot];
  }

  /** The day number the pace set at the start would have the reader on. */
  scheduledDayOn(today: Date): number {
    const elapsed = LocalDate.daysBetween(PlanProgress.dateOnly(today), this.startedOn);
    return Math.min(Math.max(elapsed + 1, 1), this.plan.length);
  }

  /**
   * Days behind that pace, never negative: reading ahead is not "ahead"
   * of anything worth announcing.
   */
  behindOn(today: Date): number {
    const current = this.currentDay;
    if (current === null) return 0;
    const behind = this.scheduledDayOn(today) - current.number;
    return behind > 0 ? behind : 0;
  }

  /**
   * Whether today's reading is still to do — what the reader's plan
   * button carries a dot for.
   */
  hasReadingDueOn(today: Date): boolean {
    const current = this.currentDay;
    return current !== null && current.number <= this.scheduledDayOn(today);
  }

  /** Moves the pace so that the current day is today. Marks nothing read. */
  pickedUpOn(today: Date): PlanProgress {
    const current = this.currentDay;
    if (current === null) return this;
    return this.copyWith({
      startedOn: LocalDate.addDays(PlanProgress.dateOnly(today), -(current.number - 1)),
    });
  }

  copyWith(changes: { startedOn?: Date; done?: ReadonlySet<number>; updated?: Date }): PlanProgress {
    return new PlanProgress({
      plan: this.plan,
      startedOn: changes.startedOn ?? this.startedOn,
      done: changes.done ?? this.done,
      updated: changes.updated ?? new Date(),
    });
  }

  toJson(): Record<string, unknown> {
    return {
      id: this.plan.id,
      start: LocalDate.format(this.startedOn),
      t: this.updated.getTime(),
      done: [...this.done].sort((a, b) => a - b),
    };
  }

  static fromJson(json: Record<string, unknown>): PlanProgress | null {
    const id = json['id'];
    if (typeof id !== 'string') return null;
    const plan = ReadingPlans.byId(id);
    if (plan === null) return null;
    const start = LocalDate.parse(json['start']);
    if (start === null) return null;
    const rawDone = json['done'];
    const done = new Set<number>();
    if (Array.isArray(rawDone)) {
      for (const slot of rawDone) {
        if (Number.isInteger(slot) && (slot as number) >= 0 && (slot as number) < plan.slotCount) done.add(slot as number);
      }
    }
    const t = json['t'];
    return new PlanProgress({
      plan,
      startedOn: start,
      done,
      updated: new Date(Number.isInteger(t) ? (t as number) : 0),
    });
  }

  /**
   * Midnight UTC of the local calendar date, so that the days between
   * two dates are never 23 or 25 hours across a change of clocks.
   */
  static dateOnly(moment: Date): Date {
    return LocalDate.only(moment);
  }
}
