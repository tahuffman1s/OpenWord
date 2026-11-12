import { describe, expect, it } from 'vitest';
import { ReferenceSearch } from '../src/data/referenceSearch';
import { Reference } from '../src/model/bible';
import { sampleBible } from './fixtures';

describe('ReferenceSearch', () => {
  const bible = sampleBible();
  const books = bible.books;

  const parse = (input: string): Reference | null => ReferenceSearch.parse(input, books);

  it('parses book, chapter and verse', () => {
    expect(parse('Genesis 1:2')).toEqual(new Reference('GEN', 1, 2));
    expect(parse('genesis 2')).toEqual(new Reference('GEN', 2));
    expect(parse('Genesis')).toEqual(new Reference('GEN', 1));
  });

  it('accepts the spellings people actually type', () => {
    expect(parse('gen 1:1')).toEqual(new Reference('GEN', 1, 1));
    expect(parse('GEN1:1')).toEqual(new Reference('GEN', 1, 1));
    expect(parse('gen.1.1')).toEqual(new Reference('GEN', 1, 1));
    expect(parse('gen 1 1')).toEqual(new Reference('GEN', 1, 1));
    expect(parse('  Gen  1 : 1 ')).toEqual(new Reference('GEN', 1, 1));
    expect(parse('psalm 1')).toEqual(new Reference('PSA', 1));
    expect(parse('ps 1:2')).toEqual(new Reference('PSA', 1, 2));
    expect(parse('mat 1')).toEqual(new Reference('MAT', 1));
  });

  it('clamps out-of-range chapters and verses', () => {
    expect(parse('Genesis 99')).toEqual(new Reference('GEN', 2));
    expect(parse('Genesis 1:99')).toEqual(new Reference('GEN', 1, 5));
    expect(parse('Genesis 0')).toEqual(new Reference('GEN', 1));
  });

  it('refuses an ambiguous name', () => {
    // Both Genesis and Psalms are loaded, so a bare letter means nothing.
    expect(parse('a')).toBeNull();
    expect(parse('nonsense 3')).toBeNull();
    expect(parse('')).toBeNull();
    expect(parse('12')).toBeNull();
  });

  it('normalises numbered and roman-numeral book names', () => {
    expect(ReferenceSearch.normalise('1 John')).toBe('1john');
    expect(ReferenceSearch.normalise('I John')).toBe('1john');
    expect(ReferenceSearch.normalise('III  john.')).toBe('3john');
    expect(ReferenceSearch.normalise(' Song of Solomon ')).toBe('songofsolomon');
  });

  it('splits a reference into its name and numbers', () => {
    expect(ReferenceSearch.split('jn 3:16').name.trim()).toBe('jn');
    expect(ReferenceSearch.split('jn 3:16').chapter).toBe(3);
    expect(ReferenceSearch.split('jn 3:16').verse).toBe(16);
    expect(ReferenceSearch.split('genesis').name).toBe('genesis');
    expect(ReferenceSearch.split('genesis').chapter).toBeNull();
    // A bare number is a book name as far as splitting goes, so "1 John"
    // never loses its numeral.
    expect(ReferenceSearch.split('1').name).toBe('1');
  });

  it('ranks book matches, exact first', () => {
    const matches = ReferenceSearch.matchBooks('ge', books);
    expect(matches[0].code).toBe('GEN');

    expect(ReferenceSearch.matchBooks('psalms', books)[0].code).toBe('PSA');
    expect(ReferenceSearch.matchBooks('', books)).toHaveLength(books.length);
    expect(ReferenceSearch.matchBooks('zzz', books)).toEqual([]);
  });

  it('matches on abbreviation and code', () => {
    expect(ReferenceSearch.matchBooks('psa', books)[0].code).toBe('PSA');
    expect(ReferenceSearch.matchBooks('mat', books)[0].code).toBe('MAT');
  });
});
