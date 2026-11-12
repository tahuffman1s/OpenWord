import { strToU8 } from 'fflate';
import { describe, expect, it } from 'vitest';
import { tidyBib } from '../src/data/importTidy';
import { BibFile } from '../src/model/bibFile';
import { Bible, Block, BlockStyle, Book, Chapter, type VerseSegment } from '../src/model/bible';
import { BookMeta } from '../src/model/bookMeta';
import { sampleBible, testTranslation } from './fixtures';

const seg = (verse: number, startsVerse: boolean, text: string): VerseSegment => ({ verse, startsVerse, text });

/**
 * A Bible an edition has printed its furniture into: three books, each
 * ending with the same line belonging to no verse.
 */
function furnished(): Bible {
  const book = (code: string, verse: string): Book =>
    Book.of(BookMeta.lookup(code)!, [
      new Chapter({
        number: 1,
        blocks: [
          new Block({ style: BlockStyle.paragraph, segments: [seg(1, true, verse)] }),
          new Block({ style: BlockStyle.paragraph, segments: [seg(1, false, 'Test Standard Version · Home')] }),
        ],
        notes: [],
      }),
    ]);
  return new Bible({
    translation: testTranslation,
    books: [book('GEN', 'In the beginning.'), book('EXO', 'These are the names.'), book('LEV', 'The LORD called.')],
    extras: new Map([['zzzz', new Uint8Array([1, 2, 3])]]),
  });
}

describe('sweeping an import already on the shelf', () => {
  it('finds the furniture and offers a file without it', () => {
    const result = tidyBib(BibFile.encode(furnished()));

    expect(result.failure).toBeNull();
    expect(result.foundSomething).toBe(true);
    expect(result.removed).toEqual(['Test Standard Version · Home']);

    const swept = BibFile.decode(result.bytes!, true);
    for (const book of swept.books) {
      const lines = book.chapter(1)!.blocks.flatMap((block) => block.segments.map((segment) => segment.text));
      expect(lines, book.code).not.toContain('Test Standard Version · Home');
      expect(book.chapter(1)!.verseText(1).length).toBeGreaterThan(0);
    }
  });

  it('keeps whatever chunks the file carried', () => {
    const result = tidyBib(BibFile.encode(furnished()));
    expect(BibFile.tags(result.bytes!)).toContain('zzzz');
    expect([...BibFile.decode(result.bytes!).extras.get('zzzz')!]).toEqual([1, 2, 3]);
  });

  it('has nothing to say about a clean file', () => {
    const result = tidyBib(BibFile.encode(sampleBible()));

    expect(result.failure).toBeNull();
    expect(result.bytes).toBeNull();
    expect(result.removed).toEqual([]);
    expect(result.foundSomething).toBe(false);
  });

  it('refuses what is not a .bib with a reason', () => {
    const result = tidyBib(strToU8('not scripture'));

    expect(result.failure).not.toBeNull();
    expect(result.foundSomething).toBe(false);
  });

  it('refuses a damaged .bib rather than rewriting it', () => {
    const bytes = BibFile.encode(furnished());
    bytes[bytes.length - 30] ^= 0x01;

    const result = tidyBib(bytes);

    expect(result.failure).not.toBeNull();
    expect(result.bytes).toBeNull();
  });
});
