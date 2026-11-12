import { Reference } from './bible';
import { BookMeta, BookSection } from './bookMeta';
import { englishVerseCounts } from './versificationTable';

/** A run of chapters of one book read together: "Genesis 1–3". */
export class Passage {
  constructor(
    readonly bookCode: string,
    readonly firstChapter: number,
    readonly lastChapter: number,
  ) {}

  get chapterCount(): number {
    return this.lastChapter - this.firstChapter + 1;
  }

  /** How a single chapter is named in a plan. */
  static labelFor(chapter: Reference): string {
    return new Passage(chapter.bookCode, chapter.chapter, chapter.chapter).label;
  }

  get chapters(): Reference[] {
    const out: Reference[] = [];
    for (let c = this.firstChapter; c <= this.lastChapter; c++) {
      out.push(new Reference(this.bookCode, c));
    }
    return out;
  }

  get label(): string {
    const name = BookMeta.lookup(this.bookCode)?.name ?? this.bookCode;
    // A book of one chapter is named, not numbered: "Jude", not "Jude 1".
    if (chapterCountOf(this.bookCode) === 1) return name;
    if (this.firstChapter === this.lastChapter) {
      // One psalm is a psalm.
      return this.bookCode === 'PSA' ? `Psalm ${this.firstChapter}` : `${name} ${this.firstChapter}`;
    }
    return `${name} ${this.firstChapter}–${this.lastChapter}`;
  }

  /** Dart's `operator ==`. */
  equals(other: Passage | null | undefined): boolean {
    return (
      other != null &&
      other.bookCode === this.bookCode &&
      other.firstChapter === this.firstChapter &&
      other.lastChapter === this.lastChapter
    );
  }

  toString(): string {
    return this.label;
  }
}

export interface PlanDayInit {
  number: number;
  chapters: readonly Reference[];
  firstSlot: number;
  verses: number;
}

/**
 * One day of a plan: the chapters to read, in order.
 *
 * Each chapter is a slot. A plan can read the same chapter twice — a
 * psalm on two different days — so progress is kept per slot rather than
 * per chapter.
 */
export class PlanDay {
  /** 1-based. */
  readonly number: number;
  readonly chapters: readonly Reference[];

  /** The slot of this day's first chapter; the rest follow in order. */
  readonly firstSlot: number;

  /**
   * How many verses the day holds, which is what a reading time is
   * estimated from.
   */
  readonly verses: number;

  constructor(init: PlanDayInit) {
    this.number = init.number;
    this.chapters = init.chapters;
    this.firstSlot = init.firstSlot;
    this.verses = init.verses;
  }

  get slotCount(): number {
    return this.chapters.length;
  }

  get slots(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.chapters.length; i++) {
      out.push(this.firstSlot + i);
    }
    return out;
  }

  /** The day's chapters gathered into passages: "Genesis 50; Exodus 1–2". */
  get passages(): Passage[] {
    const result: Passage[] = [];
    for (const chapter of this.chapters) {
      const last = result.length === 0 ? null : result[result.length - 1];
      if (last !== null && last.bookCode === chapter.bookCode && last.lastChapter + 1 === chapter.chapter) {
        result[result.length - 1] = new Passage(last.bookCode, last.firstChapter, chapter.chapter);
      } else {
        result.push(new Passage(chapter.bookCode, chapter.chapter, chapter.chapter));
      }
    }
    return result;
  }

  get label(): string {
    return this.passages.map((p) => p.label).join('; ');
  }
}

export interface ReadingPlanEvenInit {
  id: string;
  name: string;
  summary: string;
  description: string;
  days: number;
  tracks: readonly (readonly Reference[])[];
  recommended?: boolean;
}

/**
 * A reading plan: which chapters to read on which day.
 *
 * Days are numbered, not dated. A plan starts whenever the reader starts
 * it, and a day not read is still there tomorrow — the reason most people
 * give a yearly plan up is that the readings they missed pile up behind
 * them, and a plan here does not pile anything up.
 */
export class ReadingPlan {
  /**
   * Stable: progress is saved against it. A plan that changed shape would
   * have to take a new id rather than move a reader's ticks onto other
   * chapters.
   */
  readonly id: string;
  readonly name: string;

  /** One line, for the list. */
  readonly summary: string;

  /** A paragraph, for the plan's own page. */
  readonly description: string;
  readonly days: readonly PlanDay[];

  /** Offered first to someone who has never followed a plan. */
  readonly recommended: boolean;

  private constructor(init: {
    id: string;
    name: string;
    summary: string;
    description: string;
    days: readonly PlanDay[];
    recommended?: boolean;
  }) {
    this.id = init.id;
    this.name = init.name;
    this.summary = init.summary;
    this.description = init.description;
    this.days = init.days;
    this.recommended = init.recommended ?? false;
  }

  get length(): number {
    return this.days.length;
  }

  get slotCount(): number {
    if (this.days.length === 0) return 0;
    const last = this.days[this.days.length - 1];
    return last.firstSlot + last.slotCount;
  }

  /** The day a slot belongs to. */
  dayOfSlot(slot: number): PlanDay {
    let low = 0;
    let high = this.days.length - 1;
    while (low < high) {
      const mid = (low + high + 1) >> 1;
      if (this.days[mid].firstSlot <= slot) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return this.days[low];
  }

  /**
   * Minutes a typical day takes to read silently: an English verse is
   * about 25 words, and adults read about 230 words a minute. Rounded to
   * something a person would say.
   */
  get minutesPerDay(): number {
    if (this.days.length === 0) return 0;
    const verses = this.days.reduce((sum, day) => sum + day.verses, 0);
    const minutes = ((verses / this.days.length) * 25) / 230;
    if (minutes < 5) return Math.min(Math.max(Math.ceil(minutes), 1), 5);
    return Math.round(minutes / 5) * 5;
  }

  /**
   * Builds a plan from one or more tracks, each read through at an even
   * pace over `days`.
   *
   * The pace is even in verses rather than chapters, because chapters are
   * nothing like the same length: Psalm 117 has two verses and Psalm 119
   * a hundred and seventy-six. No chapter is split, and no day is empty.
   */
  static even(init: ReadingPlanEvenInit): ReadingPlan {
    const days = init.days;
    const perDay: Reference[][] = Array.from({ length: days }, () => []);
    const versesPerDay: number[] = new Array<number>(days).fill(0);
    for (const chapters of init.tracks) {
      const split = ReadingPlan.split(
        chapters.map((c) => versesIn(c)),
        days,
      );
      for (let d = 0; d < days; d++) {
        for (const i of split[d]) {
          perDay[d].push(chapters[i]);
          versesPerDay[d] += versesIn(chapters[i]);
        }
      }
    }
    let slot = 0;
    const built: PlanDay[] = [];
    for (let d = 0; d < days; d++) {
      built.push(
        new PlanDay({
          number: d + 1,
          chapters: [...perDay[d]],
          firstSlot: slot,
          verses: versesPerDay[d],
        }),
      );
      slot += perDay[d].length;
    }
    return new ReadingPlan({
      id: init.id,
      name: init.name,
      summary: init.summary,
      description: init.description,
      days: built,
      recommended: init.recommended,
    });
  }

  /**
   * Splits weighted items, in order, into `days` runs that are as even as
   * they can be without splitting an item or leaving a day empty.
   *
   * Each day takes items until the running total reaches that day's share
   * of the whole — an item goes to the day its middle falls in — while
   * always leaving at least one item for every day still to come. With
   * fewer items than days the last days are empty; no plan here asks for
   * that.
   */
  static split(weights: readonly number[], days: number): number[][] {
    const result: number[][] = Array.from({ length: Math.max(days, 0) }, () => []);
    if (weights.length === 0 || days <= 0) return result;
    const total = weights.reduce((a, b) => a + b, 0);
    let next = 0;
    let running = 0;
    for (let d = 0; d < days; d++) {
      const target = (total * (d + 1)) / days;
      const daysAfter = days - d - 1;
      while (next < weights.length) {
        const left = weights.length - next;
        const mustTake = result[d].length === 0;
        const mustLeave = left <= daysAfter;
        if (!mustTake && mustLeave) break;
        if (!mustTake && d < days - 1 && running + weights[next] / 2 > target) {
          break;
        }
        result[d].push(next);
        running += weights[next];
        next++;
      }
    }
    return result;
  }
}

/** Every chapter of these books, in order. */
export function chaptersOf(codes: readonly string[]): Reference[] {
  const out: Reference[] = [];
  for (const code of codes) {
    for (let c = 1; c <= chapterCountOf(code); c++) out.push(new Reference(code, c));
  }
  return out;
}

/**
 * Two runs of chapters woven into one, each spread evenly through the
 * other: the New Testament with a psalm every so often.
 */
export function weave(a: readonly Reference[], b: readonly Reference[]): Reference[] {
  const result: Reference[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length) {
    // Whichever run is further behind its share goes next.
    const aDue = i < a.length && (j >= b.length || i / a.length <= j / b.length);
    result.push(aDue ? a[i++] : b[j++]);
  }
  return result;
}

function section(section: BookSection, except: ReadonlySet<string> = new Set()): Reference[] {
  return chaptersOf(booksIn(section).filter((code) => !except.has(code)));
}

function booksIn(section: BookSection): string[] {
  return BookMeta.all.filter((book) => book.section === section && book.code in englishVerseCounts).map((b) => b.code);
}

/**
 * The plans OpenWord offers.
 *
 * Built from the English verse counts rather than from whichever
 * translation is open, so a plan's days are the same in every translation
 * and a reader can change translation half way through without their
 * place moving.
 *
 * Each plan is built the first time it is asked for, as Dart's lazy
 * statics are.
 */
export const ReadingPlans = {
  _all: null as ReadingPlan[] | null,
  _gospels: null as ReadingPlan | null,
  _bibleInAYear: null as ReadingPlan | null,
  _bothTestaments: null as ReadingPlan | null,
  _newTestament90: null as ReadingPlan | null,
  _psalms30: null as ReadingPlan | null,
  _proverbsMonth: null as ReadingPlan | null,

  get all(): readonly ReadingPlan[] {
    return (ReadingPlans._all ??= [
      ReadingPlans.gospels,
      ReadingPlans.bibleInAYear,
      ReadingPlans.bothTestaments,
      ReadingPlans.newTestament90,
      ReadingPlans.psalms30,
      ReadingPlans.proverbsMonth,
    ]);
  },

  byId(id: string): ReadingPlan | null {
    for (const plan of ReadingPlans.all) {
      if (plan.id === id) return plan;
    }
    return null;
  },

  get gospels(): ReadingPlan {
    return (ReadingPlans._gospels ??= ReadingPlan.even({
      id: 'gospels-30',
      name: 'The Gospels in 30 days',
      summary: 'The life of Jesus, told four times',
      description:
        'Matthew, Mark, Luke and John, about three chapters a day. The ' +
        'place most people start: short, all story, and it is the centre ' +
        'of the rest.',
      days: 30,
      tracks: [chaptersOf(['MAT', 'MRK', 'LUK', 'JHN'])],
      recommended: true,
    }));
  },

  get bibleInAYear(): ReadingPlan {
    return (ReadingPlans._bibleInAYear ??= ReadingPlan.even({
      id: 'bible-year',
      name: 'The Bible in a year',
      summary: 'Genesis to Revelation, straight through',
      description:
        'Every book in the order the Bible prints them, a little over ' +
        'three chapters a day. Days are even in length rather than in ' +
        'chapters, so a day of short chapters has more of them.',
      days: 365,
      tracks: [[...section(BookSection.oldTestament), ...section(BookSection.newTestament)]],
    }));
  },

  get bothTestaments(): ReadingPlan {
    return (ReadingPlans._bothTestaments ??= ReadingPlan.even({
      id: 'ot-nt-year',
      name: 'Old and New Testament together',
      summary: 'The whole Bible in a year, from both ends at once',
      description:
        'Two readings a day: one from the Old Testament, and one from the ' +
        'New Testament or the Psalms, so Leviticus is never all there is. ' +
        'The Psalms are read alongside the New Testament, the way the old ' +
        "M'Cheyne plan reads them, rather than all at once in the middle.",
      days: 365,
      tracks: [
        section(BookSection.oldTestament, new Set(['PSA'])),
        weave(section(BookSection.newTestament), chaptersOf(['PSA'])),
      ],
    }));
  },

  get newTestament90(): ReadingPlan {
    return (ReadingPlans._newTestament90 ??= ReadingPlan.even({
      id: 'nt-90',
      name: 'The New Testament in 90 days',
      summary: 'Matthew to Revelation in three months',
      description:
        'The whole New Testament in order, about three chapters a day: the ' +
        'Gospels, the early church, the letters and Revelation.',
      days: 90,
      tracks: [section(BookSection.newTestament)],
    }));
  },

  get psalms30(): ReadingPlan {
    return (ReadingPlans._psalms30 ??= ReadingPlan.even({
      id: 'psalms-30',
      name: 'The Psalms in a month',
      summary: 'All 150 psalms in 30 days',
      description:
        'The prayer book of the Bible, about five psalms a day. Psalm 119, ' +
        'the longest chapter in the Bible, has a day to itself.',
      days: 30,
      tracks: [chaptersOf(['PSA'])],
    }));
  },

  get proverbsMonth(): ReadingPlan {
    return (ReadingPlans._proverbsMonth ??= ReadingPlan.even({
      id: 'proverbs-31',
      name: 'Proverbs in a month',
      summary: 'One chapter a day, 31 days',
      description:
        'Proverbs has 31 chapters and a month has up to 31 days, so many ' +
        'people read the chapter that matches the date. Five minutes a day.',
      days: 31,
      tracks: [chaptersOf(['PRO'])],
    }));
  },
};

const parsedCounts = new Map<string, number[]>();

function countsOf(code: string): number[] {
  let counts = parsedCounts.get(code);
  if (counts === undefined) {
    counts = (englishVerseCounts[code] ?? '')
      .split(' ')
      .filter((part) => part.length > 0)
      .map((part) => Number.parseInt(part, 10));
    parsedCounts.set(code, counts);
  }
  return counts;
}

function chapterCountOf(code: string): number {
  return countsOf(code).length;
}

function versesIn(chapter: Reference): number {
  const counts = countsOf(chapter.bookCode);
  const index = chapter.chapter - 1;
  return index >= 0 && index < counts.length ? counts[index] : 0;
}
