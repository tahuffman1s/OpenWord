import { Book, parseIntStrict, Reference } from '../model/bible';

/** What `ReferenceSearch.split` makes of a query: the name and the numbers after it. */
export interface SplitReference {
  name: string;
  chapter: number | null;
  verse: number | null;
}

/**
 * Matching book names and parsing references typed by hand.
 *
 * This is what replaced the alphabet rail: one field where `jn 3:16`,
 * `1 co 13`, `psalm 23` or just `mat` all get you where you are going.
 */
export class ReferenceSearch {
  private constructor() {}

  /** Trailing `12`, `12:3`, `12.3` or `12 3`. */
  private static readonly trailingNumbers = /\s*(\d{1,3})\s*(?:[:.,v]\s*|\s+)?(\d{1,3})?\s*$/;

  private static readonly romanPrefix = /^(i{1,3})\s+/;
  private static readonly notAlphanumeric = /[^a-z0-9]/g;

  /** Spellings people type that are not the book's name or abbreviation. */
  static readonly aliases: Readonly<Record<string, string>> = {
    psalm: 'PSA',
    psalms: 'PSA',
    ps: 'PSA',
    song: 'SNG',
    songofsongs: 'SNG',
    songs: 'SNG',
    canticles: 'SNG',
    sos: 'SNG',
    ecc: 'ECC',
    qoheleth: 'ECC',
    phlm: 'PHM',
    philem: 'PHM',
    phil: 'PHP',
    philip: 'PHP',
    jas: 'JAS',
    jam: 'JAS',
    rev: 'REV',
    apocalypse: 'REV',
    act: 'ACT',
    mk: 'MRK',
    mt: 'MAT',
    lk: 'LUK',
    jn: 'JHN',
    '1jn': '1JN',
    '2jn': '2JN',
    '3jn': '3JN',
    jhn: 'JHN',
    jdg: 'JDG',
    judg: 'JDG',
    deut: 'DEU',
    josh: 'JOS',
    isa: 'ISA',
    jer: 'JER',
    ezek: 'EZK',
    eze: 'EZK',
    hab: 'HAB',
    zech: 'ZEC',
    zeph: 'ZEP',
    matt: 'MAT',
    rom: 'ROM',
    cor: '1CO',
    gal: 'GAL',
    eph: 'EPH',
    col: 'COL',
    thess: '1TH',
    tim: '1TI',
    heb: 'HEB',
    pet: '1PE',
  };

  /**
   * Reduces a name to comparable form: `1 John` and `1john.` both become
   * `1john`, and `I John` is normalised to `1john` as well.
   */
  static normalise(value: string): string {
    let text = value.toLowerCase().trim();
    const roman = ReferenceSearch.romanPrefix.exec(text);
    if (roman !== null) {
      text = `${roman[1].length}${text.substring(roman[0].length - 1)}`;
    }
    return text.replace(ReferenceSearch.notAlphanumeric, '');
  }

  /** Splits `jn 3:16` into its book name and the numbers after it. */
  static split(input: string): SplitReference {
    const text = input.trim();
    const numbers = ReferenceSearch.trailingNumbers.exec(text);
    // Guard against eating the whole input, as in "1" or "2 3".
    if (numbers === null || numbers.index === 0) {
      return { name: text, chapter: null, verse: null };
    }
    return {
      name: text.substring(0, numbers.index),
      chapter: parseIntStrict(numbers[1]),
      verse: numbers[2] === undefined ? null : parseIntStrict(numbers[2]),
    };
  }

  /** Books matching `query`, best first. An empty query matches everything. */
  static matchBooks(query: string, books: readonly Book[]): Book[] {
    const needle = ReferenceSearch.normalise(query);
    if (needle.length === 0) return [...books];

    const exact: Book[] = [];
    const prefix: Book[] = [];
    const abbreviation: Book[] = [];
    const contains: Book[] = [];

    const aliasCode = ReferenceSearch.aliases[needle];
    for (const book of books) {
      const name = ReferenceSearch.normalise(book.name);
      const code = ReferenceSearch.normalise(book.code);
      const abbrev = ReferenceSearch.normalise(book.abbrev);
      if (name === needle || code === needle || abbrev === needle || book.code === aliasCode) {
        exact.push(book);
      } else if (name.startsWith(needle)) {
        prefix.push(book);
      } else if (abbrev.startsWith(needle) || code.startsWith(needle)) {
        abbreviation.push(book);
      } else if (name.includes(needle)) {
        contains.push(book);
      }
    }
    return [...exact, ...prefix, ...abbreviation, ...contains];
  }

  /**
   * Parses something like `jn 3:16` into a reference, clamped to what the
   * book actually has. Returns null when no single book is meant.
   */
  static parse(input: string, books: readonly Book[]): Reference | null {
    if (input.trim().length === 0) return null;
    const { name, chapter, verse } = ReferenceSearch.split(input);
    const text = name;

    const candidates = ReferenceSearch.matchBooks(text, books);
    if (candidates.length === 0) return null;
    // An ambiguous name is only usable when the matches agree on a book.
    const book = candidates[0];
    if (
      candidates.length > 1 &&
      ReferenceSearch.normalise(book.name) !== ReferenceSearch.normalise(text) &&
      ReferenceSearch.normalise(book.abbrev) !== ReferenceSearch.normalise(text) &&
      ReferenceSearch.aliases[ReferenceSearch.normalise(text)] !== book.code
    ) {
      return null;
    }

    const targetChapter = clamp(chapter ?? 1, 1, book.chapterCount);
    const verseCount = book.verseCountAt(targetChapter);
    const targetVerse = verse === null ? null : clamp(verse, 1, verseCount === 0 ? 1 : verseCount);
    return new Reference(book.code, targetChapter, targetVerse);
  }
}

/** `value`, kept between `low` and `high`. */
function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

/** One reference found inside a piece of prose. */
export class ReferenceMatch {
  readonly start: number;
  readonly end: number;
  readonly reference: Reference;

  constructor(init: { start: number; end: number; reference: Reference }) {
    this.start = init.start;
    this.end = init.end;
    this.reference = init.reference;
  }
}

/** Escapes `text` to match literally in a RegExp. */
function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Finds citations such as `Exodus 30:12` or `2 Kings 23:21` inside footnotes
 * and parallel-passage lines, so they can be tapped.
 *
 * Built from the books actually loaded, and matched longest name first, so
 * `2 John 1` is never read as `John 1`. Only a real book name followed by a
 * number matches, which keeps ordinary prose from lighting up.
 */
export class ReferenceMatcher {
  private readonly codes = new Map<string, string>();
  private readonly books = new Map<string, Book>();
  private readonly pattern: RegExp;

  constructor(books: readonly Book[]) {
    const names: string[] = [];
    for (const book of books) {
      for (const form of new Set([book.name, book.abbrev, book.code])) {
        this.codes.set(form.toLowerCase(), book.code);
        names.push(form);
      }
      this.books.set(book.code, book);
    }
    for (const [alias, code] of Object.entries(ReferenceSearch.aliases)) {
      if (!this.books.has(code)) continue;
      this.codes.set(alias, code);
      names.push(alias);
    }
    names.sort((a, b) => b.length - a.length);
    this.pattern = new RegExp(
      `(?<![A-Za-z])(${names.map(escapeRegExp).join('|')})` + String.raw`\.?\s*(\d{1,3})(?:\s*[:.]\s*(\d{1,3}))?`,
      'gi',
    );
  }

  findAll(text: string): ReferenceMatch[] {
    const found: ReferenceMatch[] = [];
    for (const match of text.matchAll(this.pattern)) {
      const code = this.codes.get(match[1].toLowerCase());
      const book = code === undefined ? undefined : this.books.get(code);
      if (book === undefined) continue;
      const chapter = parseIntStrict(match[2]);
      if (chapter === null || chapter < 1 || chapter > book.chapterCount) {
        continue;
      }
      const verse = match[3] === undefined ? null : parseIntStrict(match[3]);
      const verses = book.verseCountAt(chapter);
      found.push(
        new ReferenceMatch({
          start: match.index,
          end: match.index + match[0].length,
          reference: new Reference(book.code, chapter, verse === null ? null : clamp(verse, 1, verses === 0 ? 1 : verses)),
        }),
      );
    }
    return found;
  }
}
