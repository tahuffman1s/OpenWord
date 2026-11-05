import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { BibFile, BibFormatException } from '../src/model/bibFile';
import { Versification, type Bible } from '../src/model/bible';

const load = (name: string) => new Uint8Array(readFileSync(new URL(`../../test/corpus/${name}`, import.meta.url)));

function expectTheSample(bible: Bible) {
  expect(bible.books.map((b) => b.code)).toEqual(['GEN', 'JHN']);
  expect(bible.bookByCode('GEN')!.chapterCount).toBe(2);
  expect(bible.verseCount).toBe(5);
  expect(bible.bookByCode('GEN')!.chapter(1)!.verseText(3)).toBe('A line, indented.');
  expect(bible.bookByCode('JHN')!.chapter(1)!.verseText(1)).toBe('In the beginning was the Word.');
  expect(bible.bookByCode('GEN')!.chapter(1)!.notes).toEqual(['A footnote.']);
}

describe('files a reader must accept', () => {
  for (const name of ['valid-v2.bib', 'valid-v2-stored.bib', 'valid-v1.bib', 'ancillary-unknown.bib']) {
    it(`${name} holds the sample`, () => expectTheSample(BibFile.decode(load(name))));
  }

  it('every version of the sample holds the very same Scripture', () => {
    const v2 = BibFile.decode(load('valid-v2.bib'));
    for (const name of ['valid-v2-stored.bib', 'valid-v1.bib']) {
      const other = BibFile.decode(load(name));
      for (const book of v2.books) {
        const mirror = other.bookByCode(book.code)!;
        for (let c = 1; c <= book.chapterCount; c++) {
          for (let v = 1; v <= book.verseCountAt(c); v++) {
            expect(mirror.chapter(c)!.verseText(v)).toBe(book.chapter(c)!.verseText(v));
          }
        }
      }
    }
  });

  it('the metadata survives in version 2 and is absent in version 1', () => {
    const v2 = BibFile.readInfo(load('valid-v2.bib'));
    expect(v2.language).toBe('en');
    expect(v2.script).toBe('Latn');
    expect(v2.versification).toBe(Versification.english);
    expect(v2.attribution).toBe('Nobody in particular.');
    const v1 = BibFile.readInfo(load('valid-v1.bib'));
    expect(v1.id).toBe('xx-corpus');
    expect(v1.versification).toBe(Versification.unknown);
    expect(v1.attribution).toBe('');
  });

  it('an unknown ancillary chunk is kept, not merely tolerated', () => {
    const bytes = load('ancillary-unknown.bib');
    expect(BibFile.tags(bytes)).toContain('zzzz');
    expect(BibFile.chunk(bytes, 'zzzz')).not.toBeNull();
  });

  it('a damaged chunk is refused only when asked to verify', () => {
    expectTheSample(BibFile.decode(load('damaged-crc.bib')));
    expect(() => BibFile.decode(load('damaged-crc.bib'), true)).toThrow(/damaged/);
  });

  it('round-trips through encode', () => {
    const bible = BibFile.decode(load('valid-v2.bib'));
    const again = BibFile.decode(BibFile.encode(bible), true);
    expectTheSample(again);
    expect(again.translation.attribution).toBe('Nobody in particular.');
    expect(again.searchIndex).not.toBeNull();
    expect(again.searchIndex!.booksFor('Word')!.has(1)).toBe(true);
  });
});

describe('files a reader must refuse', () => {
  const cases: Record<string, string | null> = {
    'critical-unknown.bib': 'ZZZZ',
    'future-version.bib': 'version',
    'truncated.bib': null,
    'header-only.bib': null,
    'not-a-bib.bib': 'not a .bib',
  };
  for (const [name, needle] of Object.entries(cases)) {
    it(`${name} is refused`, () => {
      let caught: unknown;
      try {
        BibFile.decode(load(name));
      } catch (e) {
        caught = e;
      }
      expect(caught).toBeInstanceOf(BibFormatException);
      if (needle) expect((caught as Error).message).toContain(needle);
    });
  }
});
