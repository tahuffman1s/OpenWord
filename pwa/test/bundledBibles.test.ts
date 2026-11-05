import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { BibFile } from '../src/model/bibFile';
import { crc32 } from '../src/model/crc32';
import { sha256Hex } from '../src/model/sha256';

const load = (name: string) => new Uint8Array(readFileSync(new URL(`../../assets/bible/${name}`, import.meta.url)));

describe('the bundled Scripture', () => {
  it('sha256 and crc32 agree with known vectors', () => {
    expect(sha256Hex(new TextEncoder().encode('abc'))).toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(sha256Hex(new Uint8Array(0))).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(crc32(new TextEncoder().encode('123456789'))).toBe(0xcbf43926);
  });

  for (const [file, id, verseOfJohn316] of [
    ['eng-web.bib', 'eng-web', 'For God so loved the world'],
    ['eng-bsb.bib', 'eng-bsb', 'For God so loved the world'],
    ['eng-gb-webbe.bib', 'eng-gb-webbe', 'For God so loved the world'],
  ] as const) {
    it(`${file} opens, verifies and reads John 3:16 without unpacking Genesis`, () => {
      const bytes = load(file);
      const info = BibFile.readInfo(bytes.subarray(0, BibFile.maxHeaderLength));
      expect(info.id).toBe(id);
      const bible = BibFile.decode(bytes, true);
      expect(bible.translation.id).toBe(id);
      expect(bible.books.length).toBeGreaterThanOrEqual(66);
      const john = bible.bookByCode('JHN')!;
      expect(john.chapterCount).toBe(21);
      expect(john.verseCountAt(3)).toBe(36);
      expect(john.chapter(3)!.verseText(16)).toContain(verseOfJohn316);
      expect(bible.bookByCode('GEN')!.isLoaded).toBe(false);
      const index = bible.searchIndex;
      expect(index).not.toBeNull();
      const books = index!.booksFor('Nicodemus');
      expect(books).not.toBeNull();
      expect(books!.has(bible.indexOfCode('JHN')!)).toBe(true);
      // The content hash in the metadata is of the TEXT chunk.
      const text = BibFile.chunk(bytes, 'TEXT')!;
      const meta = JSON.parse(new TextDecoder().decode(BibFile.chunk(bytes, 'META')!));
      expect(meta.contentHash).toBe(`sha256:${sha256Hex(text)}`);
    });
  }
});
