import { describe, expect, it } from 'vitest';
import { Reference } from '../src/model/bible';
import { VerseSelection } from '../src/model/verseSelection';
import { sampleBible } from './modelFixture';

describe('citing a selection', () => {
  it('runs collapse and gaps are kept', () => {
    expect(VerseSelection.ranges([16])).toBe('16');
    expect(VerseSelection.ranges([18, 16, 17])).toBe('16–18');
    expect(VerseSelection.ranges([16, 17, 18, 20])).toBe('16–18, 20');
    expect(VerseSelection.ranges([1, 3, 5, 6])).toBe('1, 3, 5–6');
  });

  it('names the book and chapter', () => {
    expect(VerseSelection.citation(new Reference('JHN', 3), [16, 17])).toBe('John 3:16–17');
  });

  it('quotes the words, with an ellipsis for what is skipped', () => {
    const chapter = sampleBible().bookByCode('GEN')!.chapter(1)!;
    expect(VerseSelection.text(chapter, [3, 5])).toBe(`${chapter.verseText(3)} … ${chapter.verseText(5)}`);
    expect(VerseSelection.text(chapter, [4, 3])).toBe(`${chapter.verseText(3)} ${chapter.verseText(4)}`);
    const quotation = VerseSelection.quotation({
      chapter,
      reference: new Reference('GEN', 1),
      verses: [3, 4],
      translation: 'TST',
    });
    expect(quotation.endsWith('\n\n— Genesis 1:3–4 (TST)')).toBe(true);
    expect(quotation).toContain('Let there be light');
  });
});
