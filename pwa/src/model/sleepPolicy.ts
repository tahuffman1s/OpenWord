import { TrialArm, type MemoryVerse } from './memoryVerse';
import { nextBool, type RandomSource } from './random';

/**
 * How the app times a new verse's first learning against a night's
 * sleep, and whether it measures the difference.
 */
export enum SleepMode {
  /**
   * Each new verse is allotted at random to a night or a day: learnt in
   * the evening with its first recall the next morning, or learnt by
   * day with its first recall a few hours on. Over time the app can say
   * which worked better for this reader.
   */
  trial = 'trial',

  /** Every new verse is learnt in the evening and recalled next morning. */
  nights = 'nights',

  /** New verses are learnt whenever, as before. */
  off = 'off',
}

export const sleepModes: readonly SleepMode[] = [SleepMode.trial, SleepMode.nights, SleepMode.off];

export const sleepModeLabel: Record<SleepMode, string> = {
  [SleepMode.trial]: 'Measure it',
  [SleepMode.nights]: 'Nights only',
  [SleepMode.off]: 'Off',
};

export const sleepModeDescription: Record<SleepMode, string> = {
  [SleepMode.trial]:
    'New verses take turns: some learnt at night, some by day, and the app reports which you recall better.',
  [SleepMode.nights]: 'Every new verse is learnt in the evening and asked for next morning.',
  [SleepMode.off]: 'New verses are learnt whenever you practise, with no timing.',
};

export interface SleepPolicyInit {
  mode?: SleepMode;
  eveningStart?: number;
  morningEnd?: number;
}

/** When evening begins and morning ends, and the `SleepMode`. */
export class SleepPolicy {
  static readonly standard = new SleepPolicy();

  readonly mode: SleepMode;

  /**
   * The hour, 0 to 23, from which it is evening: new night verses are
   * offered from here.
   */
  readonly eveningStart: number;

  /**
   * The hour before which it is morning: first recalls of night verses
   * are expected before it, though they are offered until done.
   */
  readonly morningEnd: number;

  /** Hours a day verse waits between its learning and its first recall. */
  static readonly dayGapHours = 4;

  /** The hour a night verse's first recall is offered from. */
  static readonly wakeHour = 5;

  constructor(init: SleepPolicyInit = {}) {
    this.mode = init.mode ?? SleepMode.trial;
    this.eveningStart = init.eveningStart ?? 19;
    this.morningEnd = init.morningEnd ?? 11;
  }

  isEvening(at: Date): boolean {
    return at.getHours() >= this.eveningStart;
  }

  isMorning(at: Date): boolean {
    return at.getHours() < this.morningEnd;
  }

  /** Whether a day verse learnt now would have its recall before evening. */
  roomForDayVerse(at: Date): boolean {
    return at.getHours() + SleepPolicy.dayGapHours < this.eveningStart;
  }

  /**
   * The arm a verse added now goes to: random in a trial, a night when
   * nights only, and none at all when off.
   */
  armForNew(random: RandomSource): TrialArm | null {
    switch (this.mode) {
      case SleepMode.trial:
        return nextBool(random) ? TrialArm.night : TrialArm.day;
      case SleepMode.nights:
        return TrialArm.night;
      case SleepMode.off:
        return null;
    }
  }

  /** Whether a verse still waiting to be learnt is offered at `at`. */
  offersLearning(arm: TrialArm | null, at: Date): boolean {
    switch (arm) {
      case null:
        return true;
      case TrialArm.night:
        return this.mode === SleepMode.off || this.isEvening(at);
      case TrialArm.day:
        return this.mode === SleepMode.off || this.roomForDayVerse(at);
    }
  }

  /** When a verse learnt at `at` has its first recall offered from. */
  recallAfter(at: Date, arm: TrialArm | null): Date {
    switch (arm) {
      case TrialArm.night:
        return new Date(at.getFullYear(), at.getMonth(), at.getDate() + 1, SleepPolicy.wakeHour);
      case TrialArm.day:
        return new Date(at.getTime() + SleepPolicy.dayGapHours * 3_600_000);
      // As before this: the next day, whenever.
      case null:
        return new Date(at.getFullYear(), at.getMonth(), at.getDate() + 1);
    }
  }

  copyWith(changes: SleepPolicyInit): SleepPolicy {
    return new SleepPolicy({
      mode: changes.mode ?? this.mode,
      eveningStart: changes.eveningStart ?? this.eveningStart,
      morningEnd: changes.morningEnd ?? this.morningEnd,
    });
  }

  toJson(): Record<string, unknown> {
    return {
      mode: this.mode,
      evening: this.eveningStart,
      morning: this.morningEnd,
    };
  }

  static fromJson(json: Record<string, unknown>): SleepPolicy {
    const mode = json['mode'];
    const evening = json['evening'];
    const morning = json['morning'];
    return new SleepPolicy({
      mode: sleepModes.find((m) => m === mode) ?? SleepMode.trial,
      eveningStart: Number.isInteger(evening) ? Math.min(Math.max(evening as number, 12), 23) : 19,
      morningEnd: Number.isInteger(morning) ? Math.min(Math.max(morning as number, 6), 14) : 11,
    });
  }

  /** Whether `other` holds the same values as this. */
  equals(other: SleepPolicy | null | undefined): boolean {
    return (
      other != null &&
      other.mode === this.mode &&
      other.eveningStart === this.eveningStart &&
      other.morningEnd === this.morningEnd
    );
  }
}

export interface SleepTrialReportInit {
  sleptAsked: number;
  sleptRight: number;
  awakeAsked: number;
  awakeRight: number;
  sleptLaterAsked: number;
  sleptLaterRight: number;
  awakeLaterAsked: number;
  awakeLaterRight: number;
}

/**
 * What the trial has found so far: first recalls after sleep against
 * first recalls the same day, as they happened rather than as they were
 * allotted, since a verse put off until tomorrow was slept on whatever
 * the plan was.
 */
export class SleepTrialReport {
  /** Verses in each group before the report says anything. */
  static readonly minimum = 5;

  readonly sleptAsked: number;
  readonly sleptRight: number;
  readonly awakeAsked: number;
  readonly awakeRight: number;
  readonly sleptLaterAsked: number;
  readonly sleptLaterRight: number;
  readonly awakeLaterAsked: number;
  readonly awakeLaterRight: number;

  constructor(init: SleepTrialReportInit) {
    this.sleptAsked = init.sleptAsked;
    this.sleptRight = init.sleptRight;
    this.awakeAsked = init.awakeAsked;
    this.awakeRight = init.awakeRight;
    this.sleptLaterAsked = init.sleptLaterAsked;
    this.sleptLaterRight = init.sleptLaterRight;
    this.awakeLaterAsked = init.awakeLaterAsked;
    this.awakeLaterRight = init.awakeLaterRight;
  }

  get hasEnough(): boolean {
    return this.sleptAsked >= SleepTrialReport.minimum && this.awakeAsked >= SleepTrialReport.minimum;
  }

  get sleptRate(): number {
    return this.sleptAsked === 0 ? 0 : this.sleptRight / this.sleptAsked;
  }
  get awakeRate(): number {
    return this.awakeAsked === 0 ? 0 : this.awakeRight / this.awakeAsked;
  }

  get hasLater(): boolean {
    return this.sleptLaterAsked >= SleepTrialReport.minimum && this.awakeLaterAsked >= SleepTrialReport.minimum;
  }
  get sleptLaterRate(): number {
    return this.sleptLaterAsked === 0 ? 0 : this.sleptLaterRight / this.sleptLaterAsked;
  }
  get awakeLaterRate(): number {
    return this.awakeLaterAsked === 0 ? 0 : this.awakeLaterRight / this.awakeLaterAsked;
  }

  static of(verses: Iterable<MemoryVerse>): SleepTrialReport {
    let sa = 0,
      sr = 0,
      aa = 0,
      ar = 0,
      sla = 0,
      slr = 0,
      ala = 0,
      alr = 0;
    for (const verse of verses) {
      const first = verse.firstRecall;
      if (first === null || first.slept === null) continue;
      if (first.slept) {
        sa++;
        if (first.right) sr++;
      } else {
        aa++;
        if (first.right) ar++;
      }
      const later = verse.laterRecall;
      if (later === null) continue;
      if (first.slept) {
        sla++;
        if (later.right) slr++;
      } else {
        ala++;
        if (later.right) alr++;
      }
    }
    return new SleepTrialReport({
      sleptAsked: sa,
      sleptRight: sr,
      awakeAsked: aa,
      awakeRight: ar,
      sleptLaterAsked: sla,
      sleptLaterRight: slr,
      awakeLaterAsked: ala,
      awakeLaterRight: alr,
    });
  }
}
