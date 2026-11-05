import { readFileSync } from 'node:fs';
import { beforeAll, describe, expect, it } from 'vitest';
import { Translations } from '../src/data/translations';
import { BibFile } from '../src/model/bibFile';
import { Reference, type Bible, type Book } from '../src/model/bible';
import { BookSection } from '../src/model/bookMeta';
import { QuizKind, QuizMaker, quizBooks, type QuizQuestion } from '../src/model/quiz';
import { seededRandom } from '../src/model/random';
import { sampleBible } from './modelFixture';

describe('the quiz', () => {
  // The whole World English Bible: a question set drawn from three
  // fixture verses would prove little.
  let web: Bible;
  let canon: Book[];
  beforeAll(() => {
    const path = new URL(`../../${Translations.assetFor(Translations.fallback.id)}`, import.meta.url);
    web = BibFile.decode(new Uint8Array(readFileSync(path)));
    canon = quizBooks(web, false);
  });

  function checkShape(questions: QuizQuestion[], kind: QuizKind): void {
    expect(questions).toHaveLength(10);
    const references = new Set<string>();
    for (const question of questions) {
      if (kind !== QuizKind.mixed) expect(question.kind).toBe(kind);
      expect(question.options).toHaveLength(QuizMaker.optionCount);
      expect(new Set(question.options).size).toBe(QuizMaker.optionCount);
      expect(question.answer).toBeGreaterThanOrEqual(0);
      expect(question.answer).toBeLessThanOrEqual(3);
      expect(question.stem.length).toBeGreaterThan(0);
      expect(references.has(question.reference.key)).toBe(false);
      references.add(question.reference.key);
      const book = web.bookByCode(question.reference.bookCode)!;
      expect(book.section).not.toBe(BookSection.deuterocanon);
      const chapter = book.chapter(question.reference.chapter)!;
      if (question.reference.verse !== null) {
        expect(chapter.verseText(question.reference.verse).length).toBeGreaterThan(0);
      }
    }
  }

  it('which book: the verse is from the book, the options its neighbours', () => {
    const questions = new QuizMaker(web, { books: canon, random: seededRandom(1) }).make(QuizKind.whichBook);
    checkShape(questions, QuizKind.whichBook);
    for (const question of questions) {
      const book = web.bookByCode(question.reference.bookCode)!;
      expect(question.correct).toBe(book.name);
      expect(question.prompt).toBe(book.chapter(question.reference.chapter)!.verseText(question.reference.verse!));
      expect(question.prompt.length).toBeGreaterThanOrEqual(30);
      for (const option of question.options) {
        const other = canon.find((b) => b.name === option)!;
        expect(other.section).toBe(book.section);
      }
    }
  });

  it('finish the verse: the halves make the verse again', () => {
    const questions = new QuizMaker(web, { books: canon, random: seededRandom(2) }).make(QuizKind.finishVerse);
    checkShape(questions, QuizKind.finishVerse);
    for (const question of questions) {
      expect(question.prompt.endsWith(' …')).toBe(true);
      const head = question.prompt.substring(0, question.prompt.length - 2);
      const whole = web
        .bookByCode(question.reference.bookCode)!
        .chapter(question.reference.chapter)!
        .verseText(question.reference.verse!);
      expect(`${head} ${question.correct}`).toBe(whole);
      expect(whole.length).toBeGreaterThanOrEqual(80);
    }
  });

  it('a verse is cut at the clause break nearest its middle', () => {
    const text =
      'For God so loved the world, that he gave his only born Son, ' +
      'that whoever believes in him should not perish, but have eternal life.';
    const at = QuizMaker.splitPoint(text);
    expect(text.substring(0, at).trimEnd().endsWith('only born Son,')).toBe(true);
    // No clause break in the middle: the space nearest the middle.
    const plain = 'one two three four five six seven eight nine ten';
    const plainAt = QuizMaker.splitPoint(plain);
    expect(plain.substring(0, plainAt).trimEnd()).toBe('one two three four five');
  });

  it('books in order: the answer is the neighbour asked for', () => {
    const questions = new QuizMaker(web, { books: canon, random: seededRandom(3) }).make(QuizKind.bookOrder);
    checkShape(questions, QuizKind.bookOrder);
    const names = canon.map((b) => b.name);
    for (const question of questions) {
      expect(question.prompt).toBe('');
      const match = /^Which book comes (after|before) (.+)\?$/.exec(question.stem)!;
      const asked = names.indexOf(match[2]);
      const expected = names[match[1] === 'after' ? asked + 1 : asked - 1];
      expect(question.correct).toBe(expected);
      expect(question.reference.bookCode).toBe(canon[names.indexOf(expected)].code);
      expect(question.reference.verse).toBeNull();
    }
  });

  it('a bit of everything has all three kinds', () => {
    const questions = new QuizMaker(web, { books: canon, random: seededRandom(4) }).make(QuizKind.mixed);
    checkShape(questions, QuizKind.mixed);
    expect(new Set(questions.map((q) => q.kind))).toEqual(new Set([QuizKind.whichBook, QuizKind.finishVerse, QuizKind.bookOrder]));
  });

  it('the same seed draws the same round; another draws another', () => {
    const draw = (seed: number) =>
      new QuizMaker(web, { books: canon, random: seededRandom(seed) }).make(QuizKind.whichBook).map((q) => q.reference.encode());
    expect(draw(7)).toEqual(draw(7));
    expect(draw(7)).not.toEqual(draw(8));
  });

  it('the deuterocanon is asked about only when shown', () => {
    const shown = quizBooks(web, true);
    expect(shown.length).toBeGreaterThan(canon.length);
    expect(canon.some((b) => b.section === BookSection.deuterocanon)).toBe(false);
  });

  it('a small translation gets what questions it can', () => {
    const small = sampleBible();
    const maker = new QuizMaker(small, { random: seededRandom(5) });
    // Three books: whichever is asked about, one is the answer and the
    // other the only wrong choice.
    const order = maker.make(QuizKind.bookOrder);
    expect(order.length).toBeGreaterThan(0);
    for (const question of order) {
      expect(question.options).toHaveLength(2);
      expect(question.options).toContain(question.correct);
    }
    // Verses long enough to place, and no round asks one twice.
    const which = maker.make(QuizKind.whichBook);
    expect(which.length).toBeGreaterThan(0);
    expect(which.length).toBeLessThanOrEqual(8);
    expect(new Set(which.map((q) => q.reference.key)).size).toBe(which.length);
    // No verse long enough to finish: none at all, and no error.
    expect(maker.make(QuizKind.finishVerse)).toEqual([]);
  });
});
