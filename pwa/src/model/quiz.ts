import { Reference, type Bible, type Book } from './bible';
import { BookSection } from './bookMeta';
import { nextBool, nextInt, shuffle, type RandomSource } from './random';

/** The kinds of question a round can ask. */
export class QuizKind {
  static readonly whichBook = new QuizKind('whichBook', 'Which book?', 'A verse; say which book it is from.');
  static readonly finishVerse = new QuizKind('finishVerse', 'Finish the verse', 'The first half of a verse; pick how it goes on.');
  static readonly bookOrder = new QuizKind('bookOrder', 'Books in order', 'Which book comes before or after another.');
  static readonly mixed = new QuizKind('mixed', 'A bit of everything', 'All three kinds, shuffled together.');

  static readonly values: readonly QuizKind[] = [QuizKind.whichBook, QuizKind.finishVerse, QuizKind.bookOrder, QuizKind.mixed];

  private constructor(
    readonly name: string,
    readonly label: string,
    readonly description: string,
  ) {}

  /** The kinds a round of this kind draws on. */
  get parts(): QuizKind[] {
    return this === QuizKind.mixed ? [QuizKind.whichBook, QuizKind.finishVerse, QuizKind.bookOrder] : [this];
  }
}

export interface QuizQuestionInit {
  kind: QuizKind;
  stem: string;
  prompt: string;
  options: readonly string[];
  answer: number;
  reference: Reference;
}

/**
 * One question: what is shown, the choices, which is right, and where
 * the answer is to be read.
 */
export class QuizQuestion {
  readonly kind: QuizKind;

  /** The question in words: "Which book is this from?" */
  readonly stem: string;

  /**
   * Scripture shown under the stem, or empty when the stem is the whole
   * question.
   */
  readonly prompt: string;

  readonly options: readonly string[];

  /** Index into `options` of the right one. */
  readonly answer: number;

  /**
   * Where the answer is found: the verse, or the first chapter of the
   * book.
   */
  readonly reference: Reference;

  constructor(init: QuizQuestionInit) {
    this.kind = init.kind;
    this.stem = init.stem;
    this.prompt = init.prompt;
    this.options = init.options;
    this.answer = init.answer;
    this.reference = init.reference;
  }

  get correct(): string {
    return this.options[this.answer];
  }
}

interface VerseDraw {
  reference: Reference;
  text: string;
}

/**
 * Makes questions from a translation. Nothing is stored: a round is
 * drawn afresh each time, at random, so no two rounds are alike.
 */
export class QuizMaker {
  readonly bible: Bible;

  /**
   * The books questions are drawn from, in canonical order — the reader's
   * choice of whether the deuterocanon is among them.
   */
  readonly books: readonly Book[];

  private readonly random: RandomSource;

  constructor(bible: Bible, options: { books?: readonly Book[]; random?: RandomSource } = {}) {
    this.bible = bible;
    this.books = options.books ?? bible.books;
    this.random = options.random ?? Math.random;
  }

  /** A verse shorter than this says too little to place. */
  static readonly minWhichBookLength = 30;

  /** A verse shorter than this has no second half worth guessing. */
  static readonly minFinishLength = 80;

  static readonly optionCount = 4;

  /**
   * `count` questions of `kind`, or as many as the text allows: a small
   * translation cannot ask ten different questions about three verses.
   */
  make(kind: QuizKind, count = 10): QuizQuestion[] {
    const parts = shuffle([...kind.parts], this.random);
    const questions: QuizQuestion[] = [];
    const used = new Set<string>();
    let misses = 0;
    while (questions.length < count && misses < count * 4) {
      const part = parts[(questions.length + misses) % parts.length];
      const question =
        part === QuizKind.whichBook
          ? this.whichBook()
          : part === QuizKind.finishVerse
            ? this.finishVerse()
            : part === QuizKind.bookOrder
              ? this.bookOrder()
              : null;
      if (question === null || used.has(question.reference.key)) {
        misses++;
        continue;
      }
      used.add(question.reference.key);
      questions.push(question);
    }
    return questions;
  }

  /**
   * Questions about one chapter, for guessing at before it is read and
   * answering again after: its verses finished, as many as it has long
   * enough, up to `count`. The wrong endings come from the whole
   * translation, so a reader who has not read the chapter has only
   * sense to go on.
   */
  makeForChapter(chapter: Reference, count = 2): QuizQuestion[] {
    const book = this.bible.bookByCode(chapter.bookCode);
    const text = book?.chapter(chapter.chapter);
    if (book === undefined || text === undefined) return [];
    const candidates: VerseDraw[] = [];
    for (let verse = 1; verse <= text.verseCount; verse++) {
      if (text.isOmitted(verse)) continue;
      const t = text.verseText(verse);
      if (t.length >= QuizMaker.minFinishLength) {
        candidates.push({ reference: new Reference(book.code, text.number, verse), text: t });
      }
    }
    shuffle(candidates, this.random);
    const questions: QuizQuestion[] = [];
    for (const verse of candidates.slice(0, count)) {
      const question = this.finishVerseFor(verse);
      if (question !== null) questions.push(question);
    }
    return questions;
  }

  // --- which book? -----------------------------------------------------

  private whichBook(): QuizQuestion | null {
    const verse = this.randomVerse(QuizMaker.minWhichBookLength);
    if (verse === null) return null;
    const book = this.bible.bookByCode(verse.reference.bookCode)!;
    const others = this.books.filter((b) => b.code !== book.code && b.section === book.section);
    if (others.length === 0) {
      others.push(...this.books.filter((b) => b.code !== book.code));
    }
    if (others.length === 0) return null;
    const options = this.withDistractors(
      book.name,
      shuffle(others, this.random).map((b) => b.name),
    );
    return new QuizQuestion({
      kind: QuizKind.whichBook,
      stem: 'Which book is this from?',
      prompt: verse.text,
      options: options.items,
      answer: options.answer,
      reference: verse.reference,
    });
  }

  // --- finish the verse ------------------------------------------------

  private finishVerse(): QuizQuestion | null {
    const verse = this.randomVerse(QuizMaker.minFinishLength);
    if (verse === null) return null;
    return this.finishVerseFor(verse);
  }

  private finishVerseFor(verse: VerseDraw): QuizQuestion | null {
    const split = QuizMaker.splitPoint(verse.text);
    const ending = verse.text.substring(split).trim();
    const endings: string[] = [];
    let tries = 0;
    while (endings.length < QuizMaker.optionCount - 1 && tries++ < 12) {
      const other = this.randomVerse(QuizMaker.minFinishLength);
      if (other === null || other.reference.equals(verse.reference)) continue;
      const candidate = other.text.substring(QuizMaker.splitPoint(other.text)).trim();
      if (candidate === ending || endings.includes(candidate)) continue;
      endings.push(candidate);
    }
    if (endings.length === 0) return null;
    const options = this.withDistractors(ending, endings);
    return new QuizQuestion({
      kind: QuizKind.finishVerse,
      stem: 'How does it go on?',
      prompt: `${verse.text.substring(0, split).trimEnd()} …`,
      options: options.items,
      answer: options.answer,
      reference: verse.reference,
    });
  }

  /**
   * Where to cut a verse in two: at the clause break nearest its middle,
   * or at the space nearest its middle where it has no clause breaks in
   * the middle three fifths.
   */
  static splitPoint(text: string): number {
    const middle = Math.trunc(text.length / 2);
    let best: number | null = null;
    for (const match of text.matchAll(QuizMaker.clauseBreak)) {
      const at = match.index + match[0].length;
      if (at < text.length * 0.2 || at > text.length * 0.8) continue;
      if (best === null || Math.abs(at - middle) < Math.abs(best - middle)) {
        best = at;
      }
    }
    if (best !== null) return best;
    for (let i = text.indexOf(' '); i >= 0; i = text.indexOf(' ', i + 1)) {
      const at = i + 1;
      if (best === null || Math.abs(at - middle) < Math.abs(best - middle)) {
        best = at;
      }
    }
    return best ?? middle;
  }

  private static readonly clauseBreak = /[,;:.!?]["”’]? /g;

  // --- books in order --------------------------------------------------

  private bookOrder(): QuizQuestion | null {
    const books = this.books;
    if (books.length < 2) return null;
    const after = nextBool(this.random);
    // The book asked about has a neighbour on the side asked.
    const index = after ? nextInt(this.random, books.length - 1) : 1 + nextInt(this.random, books.length - 1);
    const book = books[index];
    const answer = books[after ? index + 1 : index - 1];
    const near: Book[] = [];
    for (let d = 1; near.length < QuizMaker.optionCount * 2 && d < books.length; d++) {
      for (const i of [index - d, index + d]) {
        if (i < 0 || i >= books.length) continue;
        const other = books[i];
        if (other === book || other === answer) continue;
        near.push(other);
      }
    }
    const options = this.withDistractors(
      answer.name,
      shuffle(near, this.random).map((b) => b.name),
    );
    return new QuizQuestion({
      kind: QuizKind.bookOrder,
      stem: after ? `Which book comes after ${book.name}?` : `Which book comes before ${book.name}?`,
      prompt: '',
      options: options.items,
      answer: options.answer,
      reference: new Reference(answer.code, answer.outline[0].number),
    });
  }

  // --- helpers ---------------------------------------------------------

  /** The right answer among up to three wrong ones, in random order. */
  private withDistractors(correct: string, distractors: Iterable<string>): { items: string[]; answer: number } {
    const items = [correct, ...[...distractors].slice(0, QuizMaker.optionCount - 1)];
    shuffle(items, this.random);
    return { items, answer: items.indexOf(correct) };
  }

  private chapterPool: { book: Book; position: number }[] | null = null;

  /**
   * A verse of at least `minLength` characters, chosen so that every
   * chapter is as likely as any other, from a translation that has one.
   */
  private randomVerse(minLength: number): VerseDraw | null {
    if (this.chapterPool === null) {
      this.chapterPool = [];
      for (const book of this.books) {
        for (let position = 1; position <= book.chapterCount; position++) {
          this.chapterPool.push({ book, position });
        }
      }
    }
    const pool = this.chapterPool;
    if (pool.length === 0) return null;
    for (let attempt = 0; attempt < 24; attempt++) {
      const pick = pool[nextInt(this.random, pool.length)];
      const chapter = pick.book.chapter(pick.position);
      if (chapter === undefined || chapter.verseCount === 0) continue;
      const verse = 1 + nextInt(this.random, chapter.verseCount);
      if (chapter.isOmitted(verse)) continue;
      const text = chapter.verseText(verse);
      if (text.length < minLength) continue;
      return {
        reference: new Reference(pick.book.code, chapter.number, verse),
        text,
      };
    }
    return null;
  }
}

/**
 * The books a quiz may draw on: the canon, and the deuterocanon only when
 * the reader has it shown.
 */
export function quizBooks(bible: Bible, deuterocanon: boolean): Book[] {
  return bible.books.filter((book) => deuterocanon || book.section !== BookSection.deuterocanon);
}
