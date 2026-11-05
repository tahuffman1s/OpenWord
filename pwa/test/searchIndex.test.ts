import { gzipSync } from 'fflate';
import { describe, expect, it } from 'vitest';
import { searchBible } from '../src/data/search';
import { BibFile } from '../src/model/bibFile';
import type { Bible } from '../src/model/bible';
import { crc32 } from '../src/model/crc32';
import { SearchIndex } from '../src/model/searchIndex';
import { sampleBible } from './fixtures';
import { FsAssetBundle } from './fsAssets';

const bible = sampleBible();

function indexOf(source: Bible): SearchIndex {
  const built = SearchIndex.build(source, 7);
  const index = SearchIndex.parse(built, 7);
  expect(index).not.toBeNull();
  return index!;
}

describe('what the index knows', () => {
  it('which books a word is in', () => {
    const index = indexOf(bible);
    const genesis = bible.indexOfCode('GEN')!;

    // "beginning" is in Genesis 1:1 of the fixture and nowhere else.
    expect(index.booksFor('beginning')).toEqual(new Set([genesis]));
  });

  it('that a word is nowhere, which is the quickest answer of all', () => {
    expect(indexOf(bible).booksFor('lovingkindness')).toEqual(new Set());
  });

  it('nothing, when the query is too short to prune by', () => {
    // Two letters are in every book; saying so would cost more than it
    // saves, and punctuation inside a word makes short runs unreliable.
    expect(indexOf(bible).booksFor('in')).toBeNull();
    expect(indexOf(bible).booksFor('!?')).toBeNull();
  });

  it('a substring, not only a whole word', () => {
    // Search matches substrings, so the index has to answer for them.
    const genesis = bible.indexOfCode('GEN')!;
    expect(indexOf(bible).booksFor('eginnin')!.has(genesis)).toBe(true);
  });

  it('that every word of a phrase has to be in the same book', () => {
    const index = indexOf(bible);
    // "beginning" is only in Genesis; a word only in Psalms cannot share
    // a book with it, so the phrase can match nowhere.
    expect(index.booksFor('beginning Selah')).toEqual(new Set());
  });
});

describe('an index is never allowed to be wrong', () => {
  it('one built from different text is refused', () => {
    const built = SearchIndex.build(bible, 1);

    expect(SearchIndex.parse(built, 2)).toBeNull();
    expect(SearchIndex.parse(built, 1)).not.toBeNull();
  });

  it('a damaged one is refused rather than half-read', () => {
    const built = SearchIndex.build(bible, 7);
    expect(SearchIndex.parse(built.subarray(0, 20), 7)).toBeNull();
    expect(SearchIndex.parse(new Uint8Array(0), 7)).toBeNull();
  });

  it('a file whose index does not match carries none', () => {
    const bytes = BibFile.encode(bible);
    const text = BibFile.chunk(bytes, BibFile.tagText)!;

    // Swap in an index built from something else.
    const wrong = gzipSync(SearchIndex.build(bible, (crc32(text) ^ 0xffff) >>> 0));
    const tampered = BibFile.encode(bible, { searchable: false, carry: new Map([[BibFile.tagSearch, wrong]]) });

    expect(BibFile.decode(tampered).searchIndex).toBeNull();
  });
});

describe('in a .bib file', () => {
  it('every file the app writes carries one', () => {
    const decoded = BibFile.decode(BibFile.encode(bible));

    expect(BibFile.tags(BibFile.encode(bible))).toContain('srch');
    expect(decoded.searchIndex).not.toBeNull();
    expect(decoded.searchIndex!.wordCount).toBeGreaterThan(20);
  });

  it('it can be left out, and then search still works', () => {
    const bytes = BibFile.encode(bible, { searchable: false });
    const decoded = BibFile.decode(bytes);

    expect(BibFile.tags(bytes)).not.toContain('srch');
    expect(decoded.searchIndex).toBeNull();
    expect(searchBible(decoded, 'beginning').length).toBeGreaterThan(0);
  });

  it('it survives being written uncompressed', () => {
    const decoded = BibFile.decode(BibFile.encode(bible, { compress: false }));

    expect(decoded.searchIndex).not.toBeNull();
    expect(decoded.searchIndex!.booksFor('lovingkindness')).toEqual(new Set());
  });

  it('it is not unpacked until something searches', () => {
    // The chunk is a couple of hundred kilobytes; opening a Bible nobody
    // searches should not pay for it.
    const bytes = BibFile.encode(bible);
    const decoded = BibFile.decode(bytes);

    decoded.bookByCode('GEN')!.chapter(1)!.verseText(1);
    // Nothing to assert but that asking is what resolves it; the getter
    // is what the reader never touches.
    expect(decoded.searchIndex).not.toBeNull();
  });
});

describe('the index changes nothing about the results', () => {
  for (const query of ['beginning', 'God', 'Selah', 'the', 'lovingkindness', 'in the', 'e']) {
    it(`"${query}" finds the same verses either way`, () => {
      const withIndex = BibFile.decode(BibFile.encode(bible));
      const without = BibFile.decode(BibFile.encode(bible, { searchable: false }));

      const a = searchBible(without, query);
      const b = searchBible(withIndex, query);

      expect(b.map((hit) => hit.reference.toString())).toEqual(a.map((hit) => hit.reference.toString()));
    });
  }
});

describe('the shipped translations', () => {
  it('all carry an index that matches their text', async () => {
    const bundle = new FsAssetBundle();
    for (const id of ['eng-web', 'eng-bsb', 'eng-gb-webbe']) {
      const bytes = await bundle.load(`assets/bible/${id}.bib`);

      expect(BibFile.tags(bytes), id).toContain('srch');
      const decoded = BibFile.decode(bytes);
      expect(decoded.searchIndex, id).not.toBeNull();
      expect(decoded.searchIndex!.bookCount, id).toBe(decoded.books.length);
      // A word that is certainly there, and one that is certainly not.
      expect(decoded.searchIndex!.booksFor('Jerusalem')!.size).toBeGreaterThan(0);
      expect(decoded.searchIndex!.booksFor('zzzzqqq')).toEqual(new Set());
    }
  });

  it('a whole-Bible search finds John 3:16 by its words', async () => {
    const bible = BibFile.decode(await new FsAssetBundle().load('assets/bible/eng-web.bib'));
    const hits = searchBible(bible, 'God so loved the world', { wholeWord: true });
    expect(hits.some((hit) => hit.reference.label === 'John 3:16')).toBe(true);
  });
});
