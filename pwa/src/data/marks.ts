import { ChangeNotifier } from '../infra/changeNotifier';
import { Prefs } from '../infra/prefs';
import { Achievement } from '../model/achievements';
import { Reference } from '../model/bible';
import { BookMeta } from '../model/bookMeta';
import { confidenceValues, type Confidence, type ConfidenceTally, type DailyGoal, LearnProgress } from '../model/learnProgress';
import { MemoryStage, MemoryVerse } from '../model/memoryVerse';
import type { RandomSource } from '../model/random';
import type { PlanDay, ReadingPlan } from '../model/readingPlan';
import { SleepPolicy, SleepTrialReport } from '../model/sleepPolicy';
import { Streak } from '../model/streak';
import { PlanProgress } from './planProgress';

export interface MarkInit {
  reference: Reference;
  updated: Date;
  bookmarked?: boolean;
  colorIndex?: number | null;
  note?: string;
}

/**
 * Everything a reader has attached to one verse: a bookmark, a highlight
 * colour, a note, or any combination.
 */
export class Mark {
  readonly reference: Reference;
  readonly updated: Date;
  readonly bookmarked: boolean;

  /** Index into the reader's highlight palette, or null for no highlight. */
  readonly colorIndex: number | null;

  readonly note: string;

  constructor(init: MarkInit) {
    this.reference = init.reference;
    this.updated = init.updated;
    this.bookmarked = init.bookmarked ?? false;
    this.colorIndex = init.colorIndex ?? null;
    this.note = init.note ?? '';
  }

  get isEmpty(): boolean {
    return !this.bookmarked && this.colorIndex === null && this.note.length === 0;
  }
  get hasNote(): boolean {
    return this.note.length > 0;
  }
  get highlighted(): boolean {
    return this.colorIndex !== null;
  }

  get key(): string {
    return Mark.keyFor(this.reference);
  }

  static keyFor(reference: Reference): string {
    return `${reference.bookCode}/${reference.chapter}/${reference.verse ?? 0}`;
  }

  copyWith(changes: {
    bookmarked?: boolean;
    colorIndex?: number | null;
    clearColor?: boolean;
    note?: string;
    updated?: Date;
  }): Mark {
    return new Mark({
      reference: this.reference,
      updated: changes.updated ?? new Date(),
      bookmarked: changes.bookmarked ?? this.bookmarked,
      colorIndex: changes.clearColor ? null : (changes.colorIndex ?? this.colorIndex),
      note: changes.note ?? this.note,
    });
  }

  toJson(): Record<string, unknown> {
    return {
      b: this.reference.bookCode,
      c: this.reference.chapter,
      v: this.reference.verse ?? 0,
      t: this.updated.getTime(),
      ...(this.bookmarked ? { m: true } : {}),
      ...(this.colorIndex !== null ? { k: this.colorIndex } : {}),
      ...(this.note.length > 0 ? { n: this.note } : {}),
    };
  }

  static fromJson(json: Record<string, unknown>): Mark | null {
    const book = json['b'];
    const chapter = json['c'];
    if (typeof book !== 'string' || !Number.isInteger(chapter)) return null;
    if (BookMeta.lookup(book) === undefined) return null;
    const verse = json['v'];
    const color = json['k'];
    const t = json['t'];
    const note = json['n'];
    const mark = new Mark({
      reference: new Reference(book, chapter as number, Number.isInteger(verse) && (verse as number) > 0 ? (verse as number) : null),
      updated: new Date(Number.isInteger(t) ? (t as number) : 0),
      bookmarked: json['m'] === true,
      colorIndex: Number.isInteger(color) ? (color as number) : null,
      note: typeof note === 'string' ? note : '',
    });
    return mark.isEmpty ? null : mark;
  }
}

/** What an import did, so the user can be told. */
export class ImportResult {
  constructor(
    readonly added: number,
    readonly updated: number,
  ) {}

  static failed(): ImportResult {
    return new ImportResult(-1, -1);
  }

  get ok(): boolean {
    return this.added >= 0;
  }
  get total(): number {
    return this.added + this.updated;
  }
}

const kMarks = 'marks';
const kLegacyBookmarks = 'bookmarks';
const kPosition = 'lastPosition';
const kListening = 'listeningPlace';
const kHistory = 'history';
const kPlans = 'plans';
const kMemory = 'memory';
const kStreak = 'streak';
const kProgress = 'progress';
const kSleep = 'sleep';
const historyLimit = 20;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** Dart's `DateTime.toIso8601String()` for a local time: no zone suffix. */
function localIso8601(at: Date): string {
  const pad = (n: number, width = 2) => String(n).padStart(width, '0');
  return (
    `${pad(at.getFullYear(), 4)}-${pad(at.getMonth() + 1)}-${pad(at.getDate())}` +
    `T${pad(at.getHours())}:${pad(at.getMinutes())}:${pad(at.getSeconds())}.${pad(at.getMilliseconds(), 3)}`
  );
}

export interface ReadingStoreOptions {
  prefs?: Prefs;
  clock?: () => Date;
  random?: RandomSource;
}

/** Marks, reading position and history, persisted with `Prefs`. */
export class ReadingStore extends ChangeNotifier {
  /** Number of colours in the highlight palette. */
  static readonly paletteSize = 5;

  private readonly prefs: Prefs;
  private readonly marks = new Map<string, Mark>();
  private _history: Reference[] = [];

  /** Reading plans in progress, in the order they were started. */
  private readonly _plans = new Map<string, PlanProgress>();

  /** Verses being learnt by heart, in the order they were added. */
  private readonly memory = new Map<string, MemoryVerse>();

  private _streak: Streak = Streak.none;
  private _progress: LearnProgress = LearnProgress.none;

  /** What "today" is. A test sets it; the app reads the clock. */
  private readonly clock: () => Date;

  /** Allots new verses to a night or a day; a test fixes it. */
  private readonly random: RandomSource;

  private sleep: SleepPolicy = SleepPolicy.standard;

  private constructor(prefs: Prefs, clock: () => Date, random: RandomSource) {
    super();
    this.prefs = prefs;
    this.clock = clock;
    this.random = random;
    this.load();
  }

  static async load(options: ReadingStoreOptions = {}): Promise<ReadingStore> {
    return new ReadingStore(options.prefs ?? Prefs.open(), options.clock ?? (() => new Date()), options.random ?? Math.random);
  }

  get today(): Date {
    return this.clock();
  }

  private load(): void {
    const raw = this.prefs.getString(kMarks);
    if (raw !== null) {
      ReadingStore.decodeInto(raw, this.marks);
    } else {
      this.migrateLegacyBookmarks();
    }
    this._history = [];
    for (const entry of this.prefs.getStringList(kHistory) ?? []) {
      const reference = Reference.decode(entry);
      if (reference !== null) this._history.push(reference);
    }
    const plans = this.prefs.getString(kPlans);
    if (plans !== null) ReadingStore.decodePlansInto(plans, this._plans);
    const memory = this.prefs.getString(kMemory);
    if (memory !== null) ReadingStore.decodeMemoryInto(memory, this.memory);
    this._streak = ReadingStore.decodeStreak(this.prefs.getString(kStreak)) ?? Streak.none;
    this._progress = ReadingStore.decodeProgress(this.prefs.getString(kProgress)) ?? LearnProgress.none;
    const sleep = this.prefs.getString(kSleep);
    if (sleep !== null) {
      const decoded: unknown = JSON.parse(sleep);
      if (isRecord(decoded)) {
        this.sleep = SleepPolicy.fromJson(decoded);
      }
    }
  }

  private static decodeProgress(raw: unknown): LearnProgress | null {
    const decoded: unknown = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!isRecord(decoded)) return null;
    return LearnProgress.fromJson(decoded);
  }

  private static decodeStreak(raw: unknown): Streak | null {
    const decoded: unknown = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!isRecord(decoded)) return null;
    return Streak.fromJson(decoded);
  }

  private static decodeMemoryInto(raw: unknown, into: Map<string, MemoryVerse>): number {
    const decoded: unknown = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!Array.isArray(decoded)) return 0;
    let count = 0;
    for (const entry of decoded) {
      if (!isRecord(entry)) continue;
      const verse = MemoryVerse.fromJson(entry);
      if (verse === null) continue;
      into.set(verse.key, verse);
      count++;
    }
    return count;
  }

  private static decodePlansInto(raw: unknown, into: Map<string, PlanProgress>): number {
    const decoded: unknown = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!Array.isArray(decoded)) return 0;
    let count = 0;
    for (const entry of decoded) {
      if (!isRecord(entry)) continue;
      const progress = PlanProgress.fromJson(entry);
      if (progress === null) continue;
      into.set(progress.plan.id, progress);
      count++;
    }
    return count;
  }

  /** Version 1.0 stored plain bookmarks under another key. */
  private migrateLegacyBookmarks(): void {
    const legacy = this.prefs.getString(kLegacyBookmarks);
    if (legacy === null) return;
    const decoded: unknown = JSON.parse(legacy);
    if (!Array.isArray(decoded)) return;
    for (const entry of decoded) {
      if (!isRecord(entry)) continue;
      const mark = Mark.fromJson({ ...entry, m: true, k: null });
      if (mark !== null) this.marks.set(mark.key, mark);
    }
    if (this.marks.size > 0) this.persist();
  }

  private static decodeInto(raw: string, into: Map<string, Mark>): number {
    const decoded: unknown = JSON.parse(raw);
    let entries: unknown[];
    if (Array.isArray(decoded)) {
      entries = decoded;
    } else if (isRecord(decoded)) {
      // Dart's `decoded['marks'] as List?` throws on anything else.
      const marks = decoded['marks'];
      if (marks == null) entries = [];
      else if (Array.isArray(marks)) entries = marks;
      else throw new TypeError('marks is not a list');
    } else {
      entries = [];
    }
    let count = 0;
    for (const entry of entries) {
      if (!isRecord(entry)) continue;
      const mark = Mark.fromJson(entry);
      if (mark === null) continue;
      into.set(mark.key, mark);
      count++;
    }
    return count;
  }

  // --- reading ---------------------------------------------------------

  markFor(reference: Reference): Mark | null {
    return this.marks.get(Mark.keyFor(reference)) ?? null;
  }

  isBookmarked(reference: Reference): boolean {
    return this.markFor(reference)?.bookmarked ?? false;
  }

  /** Every mark, most recently touched first. */
  get all(): readonly Mark[] {
    return [...this.marks.values()].sort((a, b) => b.updated.getTime() - a.updated.getTime());
  }

  get bookmarks(): readonly Mark[] {
    return this.all.filter((mark) => mark.bookmarked);
  }

  get highlights(): readonly Mark[] {
    return this.all.filter((mark) => mark.highlighted);
  }

  get notes(): readonly Mark[] {
    return this.all.filter((mark) => mark.hasNote);
  }

  get history(): readonly Reference[] {
    return [...this._history];
  }

  /** Highlight colour index per verse for one chapter. */
  highlightsIn(bookCode: string, chapter: number): Map<number, number> {
    const out = new Map<number, number>();
    for (const mark of this.marks.values()) {
      if (
        mark.reference.bookCode === bookCode &&
        mark.reference.chapter === chapter &&
        mark.reference.verse !== null &&
        mark.colorIndex !== null
      ) {
        out.set(mark.reference.verse, mark.colorIndex);
      }
    }
    return out;
  }

  /**
   * Verses in one chapter carrying a bookmark or a note, for the gutter and
   * the pickers.
   */
  flaggedVersesIn(bookCode: string, chapter: number): Set<number> {
    const out = new Set<number>();
    for (const mark of this.marks.values()) {
      if (
        mark.reference.bookCode === bookCode &&
        mark.reference.chapter === chapter &&
        mark.reference.verse !== null &&
        (mark.bookmarked || mark.hasNote)
      ) {
        out.add(mark.reference.verse);
      }
    }
    return out;
  }

  /** Chapters of a book that carry any mark. */
  markedChaptersIn(bookCode: string): Set<number> {
    const out = new Set<number>();
    for (const mark of this.marks.values()) {
      if (mark.reference.bookCode === bookCode) out.add(mark.reference.chapter);
    }
    return out;
  }

  get markedBookCodes(): Set<string> {
    return new Set([...this.marks.values()].map((mark) => mark.reference.bookCode));
  }

  // --- writing ---------------------------------------------------------

  /**
   * Adds a bookmark, or removes it if the verse already has one. Returns
   * true when a bookmark was added.
   */
  toggleBookmark(reference: Reference): boolean {
    const existing = this.markFor(reference);
    const next = (existing ?? this.blank(reference)).copyWith({
      bookmarked: !(existing?.bookmarked ?? false),
      updated: this.nextTimestamp(),
    });
    this.write(next);
    return next.bookmarked;
  }

  /** Sets or clears the highlight colour on a verse. */
  setHighlight(reference: Reference, colorIndex: number | null): void {
    const existing = this.markFor(reference) ?? this.blank(reference);
    this.write(
      existing.copyWith({
        colorIndex,
        clearColor: colorIndex === null,
        updated: this.nextTimestamp(),
      }),
    );
  }

  setNote(reference: Reference, note: string): void {
    const existing = this.markFor(reference) ?? this.blank(reference);
    this.write(existing.copyWith({ note: note.trim(), updated: this.nextTimestamp() }));
  }

  remove(reference: Reference): void {
    if (this.marks.delete(Mark.keyFor(reference))) this.persist();
  }

  /** Removes every mark and every verse being learnt. */
  clearAll(): void {
    if (this.memory.size > 0) {
      this.memory.clear();
      this.persistMemory();
    }
    if (this.marks.size === 0) return;
    this.marks.clear();
    this.persist();
  }

  private blank(reference: Reference): Mark {
    return new Mark({ reference, updated: new Date() });
  }

  private write(mark: Mark): void {
    if (mark.isEmpty) {
      this.marks.delete(mark.key);
    } else {
      this.marks.set(mark.key, mark);
    }
    this.persist();
  }

  /**
   * Marks are ordered by when they were touched, so two saved inside the
   * same millisecond — which the web's clock resolution makes easy — would
   * otherwise sort arbitrarily.
   */
  private nextTimestamp(): Date {
    const now = new Date();
    let latest = 0;
    for (const mark of this.marks.values()) {
      const stamp = mark.updated.getTime();
      if (stamp > latest) latest = stamp;
    }
    if (now.getTime() > latest) return now;
    return new Date(latest + 1);
  }

  private persist(): void {
    this.prefs.setString(kMarks, JSON.stringify([...this.marks.values()].map((mark) => mark.toJson())));
    this.notifyListeners();
  }

  // --- reading plans ---------------------------------------------------

  /**
   * Plans in progress, finished ones included until the reader removes
   * them, in the order they were started.
   */
  get plans(): readonly PlanProgress[] {
    return [...this._plans.values()];
  }

  progressFor(planId: string): PlanProgress | null {
    return this._plans.get(planId) ?? null;
  }

  /**
   * Starts a plan with day 1 today. Starting one already under way starts
   * it over.
   */
  startPlan(plan: ReadingPlan): void {
    this._plans.delete(plan.id);
    this._plans.set(
      plan.id,
      new PlanProgress({
        plan,
        startedOn: PlanProgress.dateOnly(this.today),
        done: new Set(),
        updated: new Date(),
      }),
    );
    this.persistPlans();
  }

  stopPlan(planId: string): void {
    if (this._plans.delete(planId)) this.persistPlans();
  }

  /** Puts back a plan just removed, ticks and all: what Undo does. */
  restorePlan(progress: PlanProgress): void {
    this._plans.set(progress.plan.id, progress);
    this.persistPlans();
  }

  /** Marks one chapter of a plan read or unread. */
  setPlanSlot(planId: string, slot: number, read: boolean): void {
    const progress = this._plans.get(planId);
    if (progress === undefined || slot < 0 || slot >= progress.plan.slotCount) {
      return;
    }
    if (progress.isRead(slot) === read) return;
    const done = new Set(progress.done);
    if (read) done.add(slot);
    else done.delete(slot);
    this._plans.set(planId, progress.copyWith({ done }));
    this.persistPlans();
  }

  /** Marks every chapter of a day read or unread. */
  setPlanDay(planId: string, day: PlanDay, read: boolean): void {
    const progress = this._plans.get(planId);
    if (progress === undefined) return;
    const done = new Set(progress.done);
    for (const slot of day.slots) {
      if (read) done.add(slot);
      else done.delete(slot);
    }
    this._plans.set(planId, progress.copyWith({ done }));
    this.persistPlans();
  }

  /**
   * Moves a plan's pace so its current day is today, the way a reader who
   * has been away would want. Nothing is marked read that was not.
   */
  pickUpPlanToday(planId: string): void {
    const progress = this._plans.get(planId);
    if (progress === undefined) return;
    this._plans.set(planId, progress.pickedUpOn(this.today));
    this.persistPlans();
  }

  /** Whether any plan has a reading due today that is not yet read. */
  get hasPlanReadingDue(): boolean {
    const today = this.today;
    for (const progress of this._plans.values()) {
      if (progress.hasReadingDueOn(today)) return true;
    }
    return false;
  }

  private persistPlans(): void {
    this.prefs.setString(kPlans, JSON.stringify([...this._plans.values()].map((progress) => progress.toJson())));
    this.notifyListeners();
  }

  // --- memory verses ---------------------------------------------------

  /** Verses being learnt, in the order they were added. */
  get memoryVerses(): readonly MemoryVerse[] {
    return [...this.memory.values()];
  }

  memoryFor(reference: Reference): MemoryVerse | null {
    return reference.verse === null ? null : (this.memory.get(reference.encode()) ?? null);
  }

  isMemorising(reference: Reference): boolean {
    return this.memoryFor(reference) !== null;
  }

  /**
   * Whether `verse` is offered for practice at `now`: a first recall
   * once its time has come, a verse on the ladder on its day, and a
   * verse still to be learnt when the sleep policy says so.
   */
  isOffered(verse: MemoryVerse, now: Date): boolean {
    switch (verse.stage) {
      case MemoryStage.introduced:
        return verse.recallOfferedAt(now);
      case MemoryStage.onLadder:
        return verse.isDueOn(now);
      case MemoryStage.waiting:
        return verse.isDueOn(now) && this.sleep.offersLearning(verse.arm, now);
    }
  }

  /**
   * Verses offered for practice now: first recalls first, then the
   * ladder's due verses, the likeliest to be recalled first so that a
   * session opens on a success, then the new ones.
   */
  get memoryDue(): readonly MemoryVerse[] {
    const now = this.today;
    const rank = (v: MemoryVerse): number =>
      v.stage === MemoryStage.introduced ? 0 : v.stage === MemoryStage.onLadder ? 1 : 2;
    const due = [...this.memory.values()].filter((verse) => this.isOffered(verse, now));
    due.sort((a, b) => {
      const byRank = rank(a) - rank(b);
      if (byRank !== 0) return byRank;
      if (a.stage === MemoryStage.onLadder) {
        const byChance = b.retrievability(now) - a.retrievability(now);
        if (byChance !== 0) return byChance;
      }
      return a.due.getTime() - b.due.getTime();
    });
    return due;
  }

  /**
   * Verses still to be learnt that the sleep policy holds back for now:
   * a night verse by day, a day verse too late in the day.
   */
  get memoryHeldBack(): readonly MemoryVerse[] {
    const now = this.today;
    return [...this.memory.values()].filter(
      (verse) => verse.stage === MemoryStage.waiting && verse.isDueOn(now) && !this.sleep.offersLearning(verse.arm, now),
    );
  }

  /**
   * Whether any verse is waiting to be practised now: what the library
   * button carries a dot for.
   */
  get hasMemoryDue(): boolean {
    const now = this.today;
    for (const verse of this.memory.values()) {
      if (this.isOffered(verse, now)) return true;
    }
    return false;
  }

  /** How the app times a new verse against sleep. */
  get sleepPolicy(): SleepPolicy {
    return this.sleep;
  }

  setSleepPolicy(policy: SleepPolicy): void {
    if (policy.equals(this.sleep)) return;
    this.sleep = policy;
    this.prefs.setString(kSleep, JSON.stringify(policy.toJson()));
    this.notifyListeners();
  }

  /** What the trial has found about this reader so far. */
  get sleepTrialReport(): SleepTrialReport {
    return SleepTrialReport.of(this.memory.values());
  }

  /**
   * Starts learning a verse, or stops if it is being learnt already.
   * Returns true when the verse was added.
   */
  toggleMemorise(reference: Reference): boolean {
    if (reference.verse === null) return false;
    const key = reference.encode();
    if (this.memory.delete(key)) {
      this.persistMemory();
      return false;
    }
    this.memory.set(key, MemoryVerse.start(reference, this.today, this.sleep.armForNew(this.random)));
    this.persistMemory();
    return true;
  }

  /**
   * Records a practice. A verse learnt for the first time is set its
   * first recall by the sleep policy; a first recall is recorded for
   * the trial, with whether the reader `slept` since; and from then on
   * the verse grows more stable when recalled and falls back when not.
   * `seconds` is how long the answer took, over `words` of verse. A
   * review six days or more after learning is kept as the later recall.
   * A miss made while `sure` is counted. Each recall also teaches the
   * store how well this reader keeps verses, which stretches or
   * shortens every wait a little.
   */
  reviewMemory(
    reference: Reference,
    options: { remembered: boolean; slept?: boolean | null; sure?: boolean; seconds?: number | null; words?: number | null },
  ): void {
    const { remembered, slept = null, sure = false, seconds = null, words = null } = options;
    const verse = this.memoryFor(reference);
    if (verse === null) return;
    const now = this.today;
    const personal = this._progress.recallFactor;
    let next: MemoryVerse;
    switch (verse.stage) {
      case MemoryStage.waiting:
        // A verse with no timing — added before this, or with it off —
        // climbs the ladder as it always did, with no trial to record.
        next =
          verse.arm === null || !remembered
            ? verse.reviewed({ remembered, today: now, seconds, words, personal })
            : verse.introducedAt(now, this.sleep.recallAfter(now, verse.arm));
        break;
      case MemoryStage.introduced:
        next = verse.firstRecalled(now, remembered, slept);
        break;
      case MemoryStage.onLadder:
        next = verse.reviewed({ remembered, today: now, seconds, words, personal });
        break;
    }
    // What the answer said about this reader: a recall when the chance
    // had fallen low says they keep verses better than the schedule
    // thought; a miss when it was still high says the reverse.
    if (verse.stage === MemoryStage.onLadder && verse.stability !== null) {
      const chance = verse.retrievability(now);
      if (remembered && chance < 0.75) {
        this._progress = this._progress.copyWith({
          recallFactor: Math.min(Math.max(personal + 0.03, 0.7), 1.4),
        });
        this.persistProgress();
      } else if (!remembered && chance > 0.9) {
        this._progress = this._progress.copyWith({
          recallFactor: Math.min(Math.max(personal - 0.03, 0.7), 1.4),
        });
        this.persistProgress();
      }
    }
    if (next.isLaterRecallAt(now) && verse.stage === MemoryStage.onLadder) {
      next = next.laterRecalled(now, remembered);
    }
    if (sure && !remembered) {
      next = next.copyWith({ confidentMisses: next.confidentMisses + 1 });
    }
    this.memory.set(verse.key, next);
    this.persistMemory();
  }

  /** Keeps the reader's own word for a verse. */
  setMemoryHook(reference: Reference, hook: string): void {
    const verse = this.memoryFor(reference);
    if (verse === null || verse.hook === hook.trim()) return;
    this.memory.set(verse.key, verse.withHook(hook));
    this.persistMemory();
  }

  removeMemory(reference: Reference): void {
    if (this.memory.delete(reference.encode())) this.persistMemory();
  }

  /**
   * Puts back a verse just removed, its place on the ladder and all:
   * what Undo does.
   */
  restoreMemory(verse: MemoryVerse): void {
    this.memory.set(verse.key, verse);
    this.persistMemory();
  }

  // --- streak ----------------------------------------------------------

  /** Days in a row with learning done. */
  get streak(): Streak {
    return this._streak;
  }

  /**
   * Counts today as a day with learning done: a verse answered, or a
   * round finished. Once a day is enough; calling it again does nothing.
   */
  recordPractice(): void {
    const next = this._streak.extendedOn(this.today);
    if (next.equals(this._streak)) return;
    this._streak = next;
    this.prefs.setString(kStreak, JSON.stringify(next.toJson()));
    this.notifyListeners();
  }

  // --- points and badges -----------------------------------------------

  /** Points earned, the level, the day's goal and the badges won. */
  get progress(): LearnProgress {
    return this._progress;
  }

  /** Verses on the ladder that have been recalled after a month away. */
  get versesLearnt(): number {
    let count = 0;
    for (const verse of this.memory.values()) if (verse.isLearnt) count++;
    return count;
  }

  /**
   * Records what an answer or a round earned: the points go on today's
   * count, today counts towards the streak, and any badge whose
   * condition now holds is won. Returns the badges newly won.
   */
  recordLearning(options: {
    xp: number;
    right?: boolean | null;
    perfectRound?: boolean;
    scribed?: boolean;
    heard?: boolean;
    confidence?: Confidence | null;
  }): Achievement[] {
    const { xp, right = null, perfectRound = false, scribed = false, heard = false, confidence = null } = options;
    const now = this.today;
    this._progress = this._progress.earned(xp, now, { right, perfectRound, scribed, heard, confidence });
    this.recordPractice();
    const won: Achievement[] = [];
    for (const achievement of Achievement.values) {
      if (this._progress.badges.has(achievement.id)) continue;
      const earned = achievement.earnedBy({
        progress: this._progress,
        streak: this._streak.currentOn(now),
        versesOnLadder: this.memory.size,
        versesLearnt: this.versesLearnt,
        today: now,
      });
      if (!earned) continue;
      this._progress = this._progress.awarded(achievement.id, now);
      won.push(achievement);
    }
    this.persistProgress();
    return won;
  }

  setDailyGoal(goal: DailyGoal): void {
    if (goal === this._progress.goal) return;
    this._progress = this._progress.copyWith({ goal });
    this.persistProgress();
  }

  private persistProgress(): void {
    this.prefs.setString(kProgress, JSON.stringify(this._progress.toJson()));
    this.notifyListeners();
  }

  /**
   * Two copies of the progress put together: each day's points the
   * higher of the two, the totals likewise, and every badge either has,
   * from the earlier day it was won.
   */
  private static mergeProgress(mine: LearnProgress, theirs: LearnProgress): LearnProgress {
    const most = (a: number, b: number): number => (a > b ? a : b);
    const daily = new Map(mine.daily);
    for (const [day, points] of theirs.daily) {
      daily.set(day, most(daily.get(day) ?? 0, points));
    }
    const badges = new Map(mine.badges);
    for (const [id, day] of theirs.badges) {
      const have = badges.get(id);
      if (have === undefined || day.getTime() < have.getTime()) {
        badges.set(id, day);
      }
    }
    const confidence = new Map<Confidence, ConfidenceTally>();
    for (const level of confidenceValues) {
      const a = mine.confidence.get(level);
      const b = theirs.confidence.get(level);
      if (a === undefined && b === undefined) continue;
      confidence.set(level, [most(a?.[0] ?? 0, b?.[0] ?? 0), most(a?.[1] ?? 0, b?.[1] ?? 0)]);
    }
    return new LearnProgress({
      xp: most(mine.xp, theirs.xp),
      daily,
      right: most(mine.right, theirs.right),
      wrong: most(mine.wrong, theirs.wrong),
      perfectRounds: most(mine.perfectRounds, theirs.perfectRounds),
      scribed: most(mine.scribed, theirs.scribed),
      heard: most(mine.heard, theirs.heard),
      goal: mine.goal,
      badges,
      confidence,
      confidentMisses: most(mine.confidentMisses, theirs.confidentMisses),
      recallFactor: mine.recallFactor,
    });
  }

  private persistMemory(): void {
    this.prefs.setString(kMemory, JSON.stringify([...this.memory.values()].map((verse) => verse.toJson())));
    this.notifyListeners();
  }

  // --- position --------------------------------------------------------

  /** Where the reader was last looking, used to resume on launch. */
  get lastPosition(): Reference | null {
    return Reference.decode(this.prefs.getString(kPosition));
  }

  async savePosition(reference: Reference): Promise<void> {
    const previous = this.lastPosition;
    this.prefs.setString(kPosition, reference.encode());
    if (previous === null || previous.bookCode !== reference.bookCode || previous.chapter !== reference.chapter) {
      this.pushHistory(reference.withVerse(null));
    }
  }

  /**
   * Where listening aloud last got to, as `ListeningPlace.encode` puts
   * it, so that it can be taken up after the app has been closed.
   */
  get listeningPlace(): string | null {
    return this.prefs.getString(kListening);
  }

  set listeningPlace(value: string | null) {
    if (value === null) {
      this.prefs.remove(kListening);
    } else {
      this.prefs.setString(kListening, value);
    }
  }

  private pushHistory(reference: Reference): void {
    this._history = this._history.filter(
      (entry) => !(entry.bookCode === reference.bookCode && entry.chapter === reference.chapter),
    );
    this._history.unshift(reference);
    if (this._history.length > historyLimit) {
      this._history = this._history.slice(0, historyLimit);
    }
    this.prefs.setStringList(
      kHistory,
      this._history.map((entry) => entry.encode()),
    );
    this.notifyListeners();
  }

  clearHistory(): void {
    this._history = [];
    this.prefs.setStringList(kHistory, []);
    this.notifyListeners();
  }

  // --- backup ----------------------------------------------------------

  /**
   * Everything the reader has added, as JSON they can keep anywhere. The
   * shape is the Flutter app's, key for key, so a backup moves either way.
   */
  export(): string {
    return JSON.stringify(
      {
        app: 'openword',
        version: 1,
        exported: localIso8601(new Date()),
        position: this.lastPosition?.encode() ?? null,
        marks: [...this.marks.values()].map((mark) => mark.toJson()),
        ...(this._plans.size > 0 ? { plans: [...this._plans.values()].map((progress) => progress.toJson()) } : {}),
        ...(this.memory.size > 0 ? { memory: [...this.memory.values()].map((verse) => verse.toJson()) } : {}),
        ...(this._streak.last !== null ? { streak: this._streak.toJson() } : {}),
        ...(this._progress.xp > 0 ? { progress: this._progress.toJson() } : {}),
        sleep: this.sleep.toJson(),
      },
      null,
      2,
    );
  }

  /** Whether there is anything a backup would hold. */
  get hasBackupContent(): boolean {
    return (
      this.marks.size > 0 ||
      this._plans.size > 0 ||
      this.memory.size > 0 ||
      this._streak.last !== null ||
      this._progress.xp > 0
    );
  }

  /**
   * Merges exported JSON back in, keeping whichever copy of a verse was
   * touched more recently. Existing marks are never dropped.
   *
   * A reading plan is merged the same way: the copy touched more recently
   * wins, since a plan's ticks only make sense together. So is a verse
   * being learnt, with its place on the ladder. Of two streaks the one
   * practised more recently is kept, and the better best of the two.
   */
  import(raw: string): ImportResult {
    const incoming = new Map<string, Mark>();
    const incomingPlans = new Map<string, PlanProgress>();
    const incomingMemory = new Map<string, MemoryVerse>();
    let incomingStreak: Streak | null = null;
    let incomingProgress: LearnProgress | null = null;
    try {
      const marks = ReadingStore.decodeInto(raw, incoming);
      const decoded: unknown = JSON.parse(raw);
      const plans = isRecord(decoded) ? ReadingStore.decodePlansInto(decoded['plans'], incomingPlans) : 0;
      const memory = isRecord(decoded) ? ReadingStore.decodeMemoryInto(decoded['memory'], incomingMemory) : 0;
      if (isRecord(decoded)) {
        incomingStreak = ReadingStore.decodeStreak(decoded['streak']);
        incomingProgress = ReadingStore.decodeProgress(decoded['progress']);
      }
      if (marks === 0 && plans === 0 && memory === 0 && incomingStreak === null && incomingProgress === null) {
        return ImportResult.failed();
      }
    } catch {
      return ImportResult.failed();
    }
    let added = 0;
    let updated = 0;
    if (incomingProgress !== null) {
      const merged = ReadingStore.mergeProgress(this._progress, incomingProgress);
      if (!merged.equals(this._progress)) {
        this._progress = merged;
        this.prefs.setString(kProgress, JSON.stringify(merged.toJson()));
        updated++;
        this.notifyListeners();
      }
    }
    if (incomingStreak !== null && incomingStreak.last !== null) {
      const theirs = incomingStreak;
      const mine = this._streak;
      const newer = mine.last === null || theirs.last!.getTime() > mine.last.getTime() ? theirs : mine;
      const merged = new Streak({
        count: newer.count,
        best: theirs.best > mine.best ? theirs.best : mine.best,
        last: newer.last,
        freezes: newer.freezes,
      });
      if (!merged.equals(mine)) {
        this._streak = merged;
        this.prefs.setString(kStreak, JSON.stringify(merged.toJson()));
        updated++;
        this.notifyListeners();
      }
    }
    let memoryChanged = false;
    for (const verse of incomingMemory.values()) {
      const existing = this.memory.get(verse.key);
      if (existing === undefined) {
        this.memory.set(verse.key, verse);
        added++;
        memoryChanged = true;
      } else if (verse.updated.getTime() > existing.updated.getTime()) {
        this.memory.set(verse.key, verse);
        updated++;
        memoryChanged = true;
      }
    }
    if (memoryChanged) this.persistMemory();
    let plansChanged = false;
    for (const progress of incomingPlans.values()) {
      const existing = this._plans.get(progress.plan.id);
      if (existing === undefined) {
        this._plans.set(progress.plan.id, progress);
        added++;
        plansChanged = true;
      } else if (progress.updated.getTime() > existing.updated.getTime()) {
        this._plans.set(progress.plan.id, progress);
        updated++;
        plansChanged = true;
      }
    }
    if (plansChanged) this.persistPlans();
    for (const mark of incoming.values()) {
      const existing = this.marks.get(mark.key);
      if (existing === undefined) {
        this.marks.set(mark.key, mark);
        added++;
      } else if (mark.updated.getTime() > existing.updated.getTime()) {
        this.marks.set(mark.key, mark);
        updated++;
      }
    }
    if (added + updated > 0) this.persist();
    return new ImportResult(added, updated);
  }
}
