import type { Bible } from './bible';
import { ByteReader, ByteWriter } from './byteIo';

/**
 * Which books of a translation each of its words occurs in.
 *
 * It is a filter and never an answer. The words are indexed, the query may
 * be any substring, and what finally decides a hit is the same pattern
 * match as before; all this does is rule out books that cannot possibly
 * contain the query.
 *
 * A stale index would quietly lose results, so it records the checksum of
 * the text it was built from and is ignored unless the two agree.
 */
export class SearchIndex {
  static readonly version = 1;

  /**
   * A word shorter than this prunes nothing — "of" is in every book — so
   * the query has to offer at least one run this long for the index to be
   * consulted.
   */
  static readonly minimumToken = 3;

  /**
   * Letters and marks. Deliberately the same rule for building the index
   * and for reading a query.
   */
  static readonly token = /[\p{L}\p{M}]+/gu;

  private constructor(
    /** The CRC-32 of the TEXT chunk this was built from. */
    readonly textCrc: number,
    readonly bookCount: number,
    /** Every word, in order, joined by newlines. */
    private readonly blob: string,
    /** Where each word starts in `blob`. */
    private readonly starts: number[],
    private readonly books: number[][],
  ) {}

  get wordCount(): number {
    return this.starts.length;
  }

  /**
   * The books a query could possibly match, or null where the index
   * cannot say and every book must be read.
   */
  booksFor(query: string): Set<number> | null {
    const tokens: string[] = [];
    for (const match of query.toLowerCase().matchAll(SearchIndex.token)) {
      if (match[0].length >= SearchIndex.minimumToken) tokens.push(match[0]);
    }
    if (tokens.length === 0) return null;

    let narrowed: Set<number> | null = null;
    for (const token of tokens) {
      const forToken = new Set<number>();
      let at = this.blob.indexOf(token);
      while (at >= 0) {
        for (const b of this.books[this.wordAt(at)]) forToken.add(b);
        at = this.blob.indexOf(token, at + 1);
      }
      narrowed = narrowed === null ? forToken : intersection(narrowed, forToken);
      if (narrowed.size === 0) return new Set();
    }
    return narrowed;
  }

  /** Which word covers this offset in `blob`: the last one starting at or before it. */
  private wordAt(offset: number): number {
    let low = 0;
    let high = this.starts.length - 1;
    while (low < high) {
      const middle = (low + high + 1) >> 1;
      if (this.starts[middle] <= offset) low = middle;
      else high = middle - 1;
    }
    return low;
  }

  // ---------------------------------------------------------------- writing

  static build(bible: Bible, textCrc: number): Uint8Array {
    const inBooks = new Map<string, Set<number>>();
    for (let b = 0; b < bible.books.length; b++) {
      const book = bible.books[b];
      for (const chapter of book.chapters) {
        for (const block of chapter.blocks) {
          for (const segment of block.segments) {
            for (const match of segment.text.toLowerCase().matchAll(SearchIndex.token)) {
              let set = inBooks.get(match[0]);
              if (!set) inBooks.set(match[0], (set = new Set()));
              set.add(b);
            }
          }
        }
      }
    }
    // Sorted by UTF-16 code units, whatever the locale, so the same
    // Bible always writes the same bytes.
    const words = [...inBooks.keys()].sort(compareCodeUnits);
    const out = new ByteWriter().byte(SearchIndex.version).uint32(textCrc).varint(bible.books.length).varint(words.length);
    for (const word of words) {
      const books = [...inBooks.get(word)!].sort((a, b) => a - b);
      out.string(word).varint(books.length);
      let previous = 0;
      for (const book of books) {
        out.varint(book - previous);
        previous = book;
      }
    }
    return out.takeCopy();
  }

  // ---------------------------------------------------------------- reading

  /**
   * Reads an index, or answers null where it cannot be read or was built
   * from different text. Never throws.
   */
  static parse(bytes: Uint8Array, textCrc: number): SearchIndex | null {
    try {
      const input = new ByteReader(bytes);
      if (input.byte() !== SearchIndex.version) return null;
      const crc = input.uint32();
      if (crc !== textCrc) return null;
      const bookCount = input.varint();
      const wordCount = input.varint();
      const parts: string[] = [];
      const starts = new Array<number>(wordCount).fill(0);
      const books = new Array<number[]>(wordCount);
      let at = 0;
      for (let i = 0; i < wordCount; i++) {
        const word = input.string();
        if (i > 0) {
          parts.push('\n');
          at += 1;
        }
        starts[i] = at;
        parts.push(word);
        at += word.length;
        const count = input.varint();
        const forWord = new Array<number>(count);
        let previous = 0;
        for (let j = 0; j < count; j++) {
          previous += input.varint();
          forWord[j] = previous;
        }
        books[i] = forWord;
      }
      return new SearchIndex(crc, bookCount, parts.join(''), starts, books);
    } catch {
      return null;
    }
  }
}

function intersection(a: Set<number>, b: Set<number>): Set<number> {
  const out = new Set<number>();
  for (const v of a) if (b.has(v)) out.add(v);
  return out;
}

/** Orders two strings by UTF-16 code unit, whatever the locale. */
export function compareCodeUnits(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
