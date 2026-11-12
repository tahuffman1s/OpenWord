import { describe, expect, it } from 'vitest';
import { ReferenceMatcher } from '../src/data/referenceSearch';
import { Reference } from '../src/model/bible';
import { sampleBible } from './fixtures';

describe('ReferenceMatcher', () => {
  const matcher = new ReferenceMatcher(sampleBible().books);

  const refs = (text: string): Reference[] => matcher.findAll(text).map((match) => match.reference);

  it('finds a citation inside a footnote', () => {
    expect(refs('Cited in Genesis 1:3 and elsewhere')).toEqual([new Reference('GEN', 1, 3)]);
  });

  it('finds several in one line, as a parallel-passage note has', () => {
    expect(refs('(Genesis 1:1–5; Psalms 1:2; Matthew 1)')).toEqual([
      new Reference('GEN', 1, 1),
      new Reference('PSA', 1, 2),
      new Reference('MAT', 1),
    ]);
  });

  it('reports where each one sits so it can be tapped', () => {
    const found = matcher.findAll('see Genesis 2:1 now');
    expect(found).toHaveLength(1);
    expect(found[0].start).toBe(4);
    expect(found[0].end).toBe(15);
  });

  it('accepts abbreviations and a full stop between numbers', () => {
    expect(refs('Gen 1:1')).toEqual([new Reference('GEN', 1, 1)]);
    expect(refs('Gen. 1.2')).toEqual([new Reference('GEN', 1, 2)]);
    expect(refs('PSA 1')).toEqual([new Reference('PSA', 1)]);
  });

  it('accepts the aliases people type, where the book is loaded', () => {
    expect(refs('see Ps 1:2 and Mt 1')).toEqual([new Reference('PSA', 1, 2), new Reference('MAT', 1)]);
    // John is not in the fixture, so its alias is not a citation here.
    expect(refs('Jn 3:16')).toEqual([]);
  });

  it('leaves ordinary prose alone', () => {
    expect(refs('He went up onto the mountain and sat down.')).toEqual([]);
    // A book name with no number is not a citation.
    expect(refs('The book of Genesis tells of creation.')).toEqual([]);
    // Nor is a number with no book.
    expect(refs('about 300 years')).toEqual([]);
  });

  it('does not match a book name inside a longer word', () => {
    expect(refs('Genesisx 1:1')).toEqual([]);
    expect(refs('regenesis 2')).toEqual([]);
  });

  it('ignores chapters and verses the book does not have', () => {
    // Genesis has two chapters in the fixture.
    expect(refs('Genesis 40:2')).toEqual([]);
    // An over-long verse is clamped rather than dropped.
    expect(refs('Genesis 1:99')).toEqual([new Reference('GEN', 1, 5)]);
  });
});
