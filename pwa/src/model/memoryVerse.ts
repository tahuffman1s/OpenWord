import { Reference } from './bible';
import { BookMeta } from './bookMeta';
import { LocalDate } from './localDate';

/**
 * Which timing a new verse was allotted: learnt in the evening with its
 * first recall next morning, or learnt by day with its recall a few
 * hours on.
 */
export enum TrialArm {
  night = 'night',
  day = 'day',
}

/** Where a verse is on its way onto the ladder. */
export enum MemoryStage {
  /** Added, not yet learnt. */
  waiting = 'waiting',

  /** Learnt once, its first recall still to come. */
  introduced = 'introduced',

  /** First recall done: on the ladder proper. */
  onLadder = 'onLadder',
}

/**
 * One recall that the trial records: when, whether it was right, and
 * whether the reader had slept since the verse was learnt.
 */
export class TrialRecall {
  readonly at: Date;
  readonly right: boolean;

  /**
   * Whether a night's sleep came between the learning and this recall,
   * as the reader said; null where the question was not asked.
   */
  readonly slept: boolean | null;

  constructor(init: { at: Date; right: boolean; slept?: boolean | null }) {
    this.at = init.at;
    this.right = init.right;
    this.slept = init.slept ?? null;
  }

  toJson(): Record<string, unknown> {
    return {
      at: this.at.getTime(),
      right: this.right,
      ...(this.slept !== null ? { slept: this.slept } : {}),
    };
  }

  static fromJson(raw: unknown): TrialRecall | null {
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return null;
    const json = raw as Record<string, unknown>;
    const at = json['at'];
    const right = json['right'];
    if (!Number.isInteger(at) || typeof right !== 'boolean') return null;
    const slept = json['slept'];
    return new TrialRecall({
      at: new Date(at as number),
      right,
      slept: typeof slept === 'boolean' ? slept : null,
    });
  }
}

export interface MemoryVerseInit {
  reference: Reference;
  added: Date;
  due: Date;
  updated: Date;
  rung?: number;
  recalled?: number;
  arm?: TrialArm | null;
  introduced?: Date | null;
  recallAt?: Date | null;
  firstRecall?: TrialRecall | null;
  laterRecall?: TrialRecall | null;
  confidentMisses?: number;
  stability?: number | null;
  difficulty?: number;
  hook?: string;
}

/**
 * One verse a reader is learning by heart, and when it is next due.
 *
 * Each verse carries a memory of its own: how stable it is, in days
 * until the chance of recalling it falls to nine in ten, and how hard
 * it has proved. A recall makes it more stable, by more the easier the
 * verse and the longer it was left; a miss sets it back and marks it
 * harder. The due date is where the chance of recall is about to drop
 * below the target. The rungs remain as the count of recalls in a row,
 * for what the exercises and the words on screen go by: a new verse
 * climbs much as it always did, a day, then three, a week, a fortnight,
 * a month, two, four, but a verse that is easy, or a reader who keeps
 * things well, moves faster, and the reverse slower. The only question
 * ever asked is whether the reader had it or not, and how long that
 * took.
 */
export class MemoryVerse {
  /** Days after learning at which a recall counts as the later one. */
  static readonly laterRecallDays = 6;

  /** How hard a verse is taken to be until it shows otherwise, 0 to 1. */
  static readonly defaultDifficulty = 0.3;

  /** The chance of recall a verse is let fall to before it is due. */
  static readonly targetRecall = 0.9;

  /** Stability at which a verse counts as learnt: a month. */
  static readonly learntStability = 30;

  /**
   * The longest a verse is left between recalls, in days: a year, so a
   * verse well known is still met now and then.
   */
  static readonly maxStability = 365;

  /**
   * Seconds a word may take in a right answer before it counts as slow,
   * which says the memory is weaker than a right answer alone suggests.
   */
  static readonly slowSecondsPerWord = 2.5;

  /** Days to wait after a successful recall on each rung, bottom first. */
  static readonly intervals: readonly number[] = [1, 3, 7, 14, 30, 60, 120];

  /**
   * The rung at which a verse is counted as learnt: it has been recalled
   * after a month away, which is as good a test as an app can set.
   */
  static readonly learntRung = 5;

  readonly reference: Reference;

  /** The local date the verse was added, as `LocalDate.only` gives it. */
  readonly added: Date;

  /** The local date it is next due, the same way. */
  readonly due: Date;

  readonly updated: Date;

  /** How many rungs up the ladder the verse is, from 0. */
  readonly rung: number;

  /** Times it has been recalled, ever. */
  readonly recalled: number;

  /** The timing this verse was allotted when added, or null for none. */
  readonly arm: TrialArm | null;

  /** When it was first learnt: the moment its first exercise was done. */
  readonly introduced: Date | null;

  /** From when its first recall is offered. */
  readonly recallAt: Date | null;

  /**
   * Its first recall, once made, and its first recall six days or more
   * after learning, once made.
   */
  readonly firstRecall: TrialRecall | null;
  readonly laterRecall: TrialRecall | null;

  /** Times it was missed while the reader was sure of it. */
  readonly confidentMisses: number;

  /**
   * Days until the chance of recalling the verse falls to nine in ten,
   * or null for a verse that has not yet been recalled and so is due
   * by the day it was last set.
   */
  readonly stability: number | null;

  /** How hard the verse has proved, 0 easy to 1 hard. */
  readonly difficulty: number;

  /**
   * The reader's own word for what the verse is about, their hook for
   * it; empty until given.
   */
  readonly hook: string;

  constructor(init: MemoryVerseInit) {
    this.reference = init.reference;
    this.added = init.added;
    this.due = init.due;
    this.updated = init.updated;
    this.rung = init.rung ?? 0;
    this.recalled = init.recalled ?? 0;
    this.arm = init.arm ?? null;
    this.introduced = init.introduced ?? null;
    this.recallAt = init.recallAt ?? null;
    this.firstRecall = init.firstRecall ?? null;
    this.laterRecall = init.laterRecall ?? null;
    this.confidentMisses = init.confidentMisses ?? 0;
    this.stability = init.stability ?? null;
    this.difficulty = init.difficulty ?? MemoryVerse.defaultDifficulty;
    this.hook = init.hook ?? '';
  }

  /**
   * The chance of recalling the verse at `now`, from its stability and
   * how long since it was last recalled: nine in ten at one stability's
   * worth of days, and falling slowly after.
   */
  retrievability(now: Date): number {
    const s = this.stability;
    if (s === null) return 1;
    // Dart's `difference().inSeconds` truncates to whole seconds.
    const since = Math.trunc((now.getTime() - this.lastRecall.getTime()) / 1000) / 86400;
    if (since <= 0) return 1;
    return 1 / (1 + since / (9 * s));
  }

  /**
   * The day the verse was last recalled: `due` less the wait that the
   * stability set.
   */
  private get lastRecall(): Date {
    return this.stability === null
      ? this.due
      : LocalDate.addDays(this.due, -Math.min(Math.max(Math.round(this.stability), 1), 1 << 20));
  }

  get key(): string {
    return this.reference.encode();
  }

  get stage(): MemoryStage {
    return this.firstRecall !== null || this.recalled > 0
      ? MemoryStage.onLadder
      : this.introduced !== null
        ? MemoryStage.introduced
        : MemoryStage.waiting;
  }

  /** Whether the next practice is the first recall after learning. */
  get awaitsFirstRecall(): boolean {
    return this.stage === MemoryStage.introduced;
  }

  get isLearnt(): boolean {
    return this.rung >= MemoryVerse.learntRung || (this.stability ?? 0) >= MemoryVerse.learntStability;
  }

  /**
   * Days the verse waits after its next recall, as it stands: what the
   * screen says comes next.
   */
  get nextWaitDays(): number {
    return Math.min(Math.max(Math.round(this.waitAfterSuccess(1, false, 1)), 1), 1 << 20);
  }

  isDueOn(today: Date): boolean {
    return !(this.due.getTime() > LocalDate.only(today).getTime());
  }

  /** Whether the first recall is offered at `now`: from `recallAt` on. */
  recallOfferedAt(now: Date): boolean {
    return this.awaitsFirstRecall && this.recallAt !== null && !(now.getTime() < this.recallAt.getTime());
  }

  /** Days until the verse is due, negative when it is overdue. */
  daysUntilDueOn(today: Date): number {
    return LocalDate.daysBetween(this.due, LocalDate.only(today));
  }

  /** A new verse, due today, allotted to `arm`. */
  static start(reference: Reference, today: Date, arm: TrialArm | null = null): MemoryVerse {
    const day = LocalDate.only(today);
    return new MemoryVerse({
      reference,
      added: day,
      due: day,
      updated: new Date(),
      arm,
    });
  }

  /**
   * The verse once first learnt at `at`: a rung up, its first recall
   * offered from `recallAt`.
   */
  introducedAt(at: Date, recallAt: Date): MemoryVerse {
    return this.copyWith({
      rung: 1,
      due: LocalDate.only(recallAt),
      introduced: at,
      recallAt,
    });
  }

  /** The verse after its first recall at `at`, and after a later one. */
  firstRecalled(at: Date, right: boolean, slept: boolean | null = null): MemoryVerse {
    return this.reviewed({ remembered: right, today: at }).copyWith({
      firstRecall: new TrialRecall({ at, right, slept }),
    });
  }

  laterRecalled(at: Date, right: boolean): MemoryVerse {
    return this.copyWith({
      laterRecall: new TrialRecall({ at, right }),
    });
  }

  /** Whether a review at `at` is the later recall the trial waits for. */
  isLaterRecallAt(at: Date): boolean {
    return (
      this.introduced !== null &&
      this.laterRecall === null &&
      this.firstRecall !== null &&
      LocalDate.daysBetween(at, this.introduced) >= MemoryVerse.laterRecallDays
    );
  }

  /**
   * How many days of stability a recall now would give: the stability
   * grown by a factor that is larger the easier the verse, larger again
   * when the verse was recalled late, with the chance of recall low
   * (the harder retrieval is the better one), smaller when the answer
   * came slowly, and scaled by how well this reader keeps things.
   */
  private waitAfterSuccess(retrievability: number, slow: boolean, personal: number): number {
    const current = this.stability ?? this.ladderStability;
    let growth = 2.2 * (1.3 - this.difficulty) * personal;
    if (retrievability < 0.7) growth *= 1.2;
    if (slow) growth *= 0.7;
    if (growth < 1.1) growth = 1.1;
    const grown = this.stability === null ? current : current * growth;
    return Math.min(Math.max(grown, 0.5), MemoryVerse.maxStability);
  }

  /**
   * The stability the old ladder gave a verse on its rung: what a verse
   * from before carries over, and what a first recall is worth.
   */
  private get ladderStability(): number {
    const intervals = MemoryVerse.intervals;
    return this.rung <= 0 ? 1 : intervals[Math.min(Math.max(this.rung - 1, 0), intervals.length - 1)];
  }

  /**
   * The verse after a practice. Recalled, it climbs a rung, grows more
   * stable and is due when its chance of recall will have fallen to the
   * target; missed, it drops to the bottom, loses most of its stability,
   * is marked harder and is due today. `seconds` and `words` say how
   * long the answer took, and `personal` how well this reader keeps
   * verses, 1 being the common run.
   */
  reviewed(options: {
    remembered: boolean;
    today: Date;
    seconds?: number | null;
    words?: number | null;
    personal?: number;
  }): MemoryVerse {
    const { remembered, today, seconds = null, words = null, personal = 1 } = options;
    const day = LocalDate.only(today);
    if (!remembered) {
      return this.copyWith({
        rung: 0,
        due: day,
        stability: this.stability === null ? null : Math.min(Math.max(this.stability * 0.25, 0.5), 1e9),
        difficulty: Math.min(Math.max(this.difficulty + 0.15, 0.05), 0.9),
      });
    }
    const slow = seconds !== null && words !== null && words > 0 && seconds / words > MemoryVerse.slowSecondsPerWord;
    const grown = this.waitAfterSuccess(this.retrievability(today), slow, personal);
    const wait = Math.min(Math.max(Math.round(grown), 1), 1 << 20);
    return this.copyWith({
      rung: this.rung + 1,
      due: LocalDate.addDays(day, wait),
      recalled: this.recalled + 1,
      stability: grown,
      difficulty: Math.min(Math.max(this.difficulty - 0.02, 0.05), 0.9),
    });
  }

  withHook(hook: string): MemoryVerse {
    return this.copyWith({ hook: hook.trim() });
  }

  copyWith(changes: {
    due?: Date;
    rung?: number;
    recalled?: number;
    updated?: Date;
    introduced?: Date | null;
    recallAt?: Date | null;
    firstRecall?: TrialRecall | null;
    laterRecall?: TrialRecall | null;
    confidentMisses?: number;
    stability?: number | null;
    difficulty?: number;
    hook?: string;
  }): MemoryVerse {
    return new MemoryVerse({
      reference: this.reference,
      added: this.added,
      due: changes.due ?? this.due,
      updated: changes.updated ?? new Date(),
      rung: changes.rung ?? this.rung,
      recalled: changes.recalled ?? this.recalled,
      arm: this.arm,
      introduced: changes.introduced ?? this.introduced,
      recallAt: changes.recallAt ?? this.recallAt,
      firstRecall: changes.firstRecall ?? this.firstRecall,
      laterRecall: changes.laterRecall ?? this.laterRecall,
      confidentMisses: changes.confidentMisses ?? this.confidentMisses,
      stability: changes.stability ?? this.stability,
      difficulty: changes.difficulty ?? this.difficulty,
      hook: changes.hook ?? this.hook,
    });
  }

  toJson(): Record<string, unknown> {
    return {
      b: this.reference.bookCode,
      c: this.reference.chapter,
      v: this.reference.verse,
      added: LocalDate.format(this.added),
      due: LocalDate.format(this.due),
      t: this.updated.getTime(),
      ...(this.rung > 0 ? { rung: this.rung } : {}),
      ...(this.recalled > 0 ? { recalled: this.recalled } : {}),
      ...(this.arm !== null ? { arm: this.arm } : {}),
      ...(this.introduced !== null ? { introduced: this.introduced.getTime() } : {}),
      ...(this.recallAt !== null ? { recallAt: this.recallAt.getTime() } : {}),
      ...(this.firstRecall !== null ? { first: this.firstRecall.toJson() } : {}),
      ...(this.laterRecall !== null ? { later: this.laterRecall.toJson() } : {}),
      ...(this.confidentMisses > 0 ? { sureMisses: this.confidentMisses } : {}),
      ...(this.stability !== null ? { s: this.stability } : {}),
      ...(this.difficulty !== MemoryVerse.defaultDifficulty ? { d: this.difficulty } : {}),
      ...(this.hook.length > 0 ? { hook: this.hook } : {}),
    };
  }

  static fromJson(json: Record<string, unknown>): MemoryVerse | null {
    const book = json['b'];
    const chapter = json['c'];
    const verse = json['v'];
    if (typeof book !== 'string' || !Number.isInteger(chapter) || !Number.isInteger(verse)) return null;
    if (BookMeta.lookup(book) === undefined || (chapter as number) < 1 || (verse as number) < 1) {
      return null;
    }
    const added = LocalDate.parse(json['added']);
    const due = LocalDate.parse(json['due']);
    if (added === null || due === null) return null;
    const rung = json['rung'];
    const recalled = json['recalled'];
    const arm = json['arm'];
    const introduced = json['introduced'];
    const recallAt = json['recallAt'];
    const sureMisses = json['sureMisses'];
    const stability = json['s'];
    const difficulty = json['d'];
    const hook = json['hook'];
    const t = json['t'];
    return new MemoryVerse({
      reference: new Reference(book, chapter as number, verse as number),
      added,
      due,
      updated: new Date(Number.isInteger(t) ? (t as number) : 0),
      rung: Number.isInteger(rung) && (rung as number) > 0 ? (rung as number) : 0,
      recalled: Number.isInteger(recalled) && (recalled as number) > 0 ? (recalled as number) : 0,
      arm: typeof arm === 'string' ? ((Object.values(TrialArm) as string[]).includes(arm) ? (arm as TrialArm) : null) : null,
      introduced: Number.isInteger(introduced) ? new Date(introduced as number) : null,
      recallAt: Number.isInteger(recallAt) ? new Date(recallAt as number) : null,
      firstRecall: TrialRecall.fromJson(json['first']),
      laterRecall: TrialRecall.fromJson(json['later']),
      confidentMisses: Number.isInteger(sureMisses) && (sureMisses as number) > 0 ? (sureMisses as number) : 0,
      stability: typeof stability === 'number' && stability > 0 ? stability : null,
      difficulty: typeof difficulty === 'number' ? Math.min(Math.max(difficulty, 0.05), 0.9) : MemoryVerse.defaultDifficulty,
      hook: typeof hook === 'string' ? hook : '',
    });
  }
}

/** How much of a verse a practice shows before the reader says it. */
export class MemoryPrompt {
  /** The whole verse: reading it over. */
  static readonly read = new MemoryPrompt('read', 'Read');

  /**
   * The first letter of every word, the rest blanked: enough of a hint
   * to keep a half-known verse moving.
   */
  static readonly firstLetters = new MemoryPrompt('firstLetters', 'First letters');

  /** The reference alone. */
  static readonly fromMemory = new MemoryPrompt('fromMemory', 'From memory');

  static readonly values: readonly MemoryPrompt[] = [MemoryPrompt.read, MemoryPrompt.firstLetters, MemoryPrompt.fromMemory];

  private constructor(
    readonly name: string,
    readonly label: string,
  ) {}

  /**
   * The prompt a verse on `rung` is ready for: read it over while it is
   * new, then the first letters, then nothing at all.
   */
  static forRung(rung: number): MemoryPrompt {
    return rung === 0 ? MemoryPrompt.read : rung < 3 ? MemoryPrompt.firstLetters : MemoryPrompt.fromMemory;
  }

  /** `text` as this prompt shows it. */
  apply(text: string): string {
    switch (this) {
      case MemoryPrompt.read:
        return text;
      case MemoryPrompt.firstLetters:
        return MemoryPrompt.hint(text);
      default:
        return '';
    }
  }

  /**
   * Every word cut to its first letter, the rest of its letters each
   * shown as a blank, with the punctuation and spacing left where they
   * were: "For God so loved the world," becomes "F__ G__ s_ l____ t__
   * w____,".
   */
  static hint(text: string): string {
    let out = '';
    let inWord = false;
    for (const char of text) {
      if (MemoryPrompt.isLetter(char)) {
        out += inWord ? '_' : char;
        inWord = true;
      } else {
        // An apostrophe inside a word — don't, Lord's — is part of it: the
        // letters after it stay blank rather than starting a new word.
        if (!(inWord && MemoryPrompt.isWordJoiner(char))) inWord = false;
        out += char;
      }
    }
    return out;
  }

  private static readonly letter = /[\p{L}\p{M}\p{N}]/u;

  private static isLetter(char: string): boolean {
    return MemoryPrompt.letter.test(char);
  }

  private static isWordJoiner(char: string): boolean {
    return char === '’' || char === "'" || char === '‘';
  }
}
