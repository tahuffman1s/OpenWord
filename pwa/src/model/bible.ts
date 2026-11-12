import { BookMeta, BookSection } from './bookMeta';
import type { SearchIndex } from './searchIndex';

/**
 * Sentinel characters used to carry inline character formatting inside verse
 * text. Control characters are used because they never occur in Scripture
 * text, so no escaping is needed when the text is stored or searched.
 */
export const Markup = {
  /** Words of Jesus (`\wj ... \wj*`). */
  wjStart: '\u0011',
  wjEnd: '\u0012',

  /** Words supplied by the translators (`\add ... \add*`) — rendered italic. */
  addStart: '\u0013',
  addEnd: '\u0014',

  /**
   * A footnote / cross-reference marker, followed by the note index and
   * terminated by `noteEnd`.
   */
  noteStart: '\u0015',
  noteEnd: '\u0016',

  /** `Selah` and similar poetry directions (`\qs ... \qs*`). */
  selahStart: '\u0017',
  selahEnd: '\u0018',

  /**
   * The divine name (`\nd ... \nd*`) — the tetragrammaton, which every
   * printed Bible sets in small capitals so that it reads apart from
   * "Lord" as a title.
   */
  divineStart: '\u0019',
  divineEnd: '\u001a',

  /**
   * Words quoted from elsewhere in Scripture (`\qt ... \qt*`).
   *
   * Not the same thing as `addStart`, though both used to be stored as
   * it: that marks words the translator supplied and this marks words
   * taken from somewhere else, which is nearly the opposite claim.
   */
  quotationStart: '\u001b',
  quotationEnd: '\u001c',

  /** Between the cells of a table row. */
  cell: '\u001d',

  noteMarker: /\u0015(\d+)\u0016/g,

  /**
   * The text with every marker removed — used for search and for copying.
   *
   * A cell boundary becomes a space rather than nothing: it stands
   * between two words, and dropping it outright would run them together
   * and put "Judahseventy" in the search index.
   */
  strip(text: string): string {
    return text
      .replace(/\u0015(\d+)\u0016/g, '')
      .replace(/\u001d/g, ' ')
      .replace(/[\u0011-\u001f]/g, '')
      .replace(/  +/g, ' ');
  },
};

/** How a block of text is laid out on the page. */
export enum BlockStyle {
  /** Prose paragraph; verses flow into each other. */
  paragraph = 0,
  /** A line of poetry. `Block.indent` carries the indent level. */
  poetry = 1,
  /** A psalm's descriptive title (`\d`). */
  descriptiveTitle = 2,
  /** A major section heading such as `BOOK 1` in the Psalms (`\ms`, `\s`). */
  heading = 3,
  /** A blank line used to separate stanzas (`\b`). */
  blank = 4,
  /** A parallel-passage reference printed under a heading (`\r`). */
  reference = 5,
  // Everything below was added after the first version of the format and
  // so must stay at the end: a reader that does not know a style falls
  // back to paragraph by its number.
  /** The letter an acrostic stanza runs on (`\qa`). */
  acrostic = 6,
  /** Who is speaking (`\sp`), as the Song of Songs is set. */
  speaker = 7,
  /** An item of a list (`\li`). `Block.indent` carries the level. */
  listItem = 8,
  /** A row of a table (`\tr`), its cells parted by `Markup.cell`. */
  tableRow = 9,
}

export const blockStyleCount = 10;

export function blockStyleFromKey(key: string): BlockStyle {
  switch (key) {
    case 'q':
      return BlockStyle.poetry;
    case 'd':
      return BlockStyle.descriptiveTitle;
    case 'h':
      return BlockStyle.heading;
    case 'b':
      return BlockStyle.blank;
    case 'r':
      return BlockStyle.reference;
    case 'qa':
      return BlockStyle.acrostic;
    case 'sp':
      return BlockStyle.speaker;
    case 'li':
      return BlockStyle.listItem;
    case 'tr':
      return BlockStyle.tableRow;
    default:
      return BlockStyle.paragraph;
  }
}

/** Whether blocks of this kind carry Scripture rather than apparatus. */
export function isVerseText(style: BlockStyle): boolean {
  return (
    style === BlockStyle.paragraph ||
    style === BlockStyle.poetry ||
    style === BlockStyle.listItem ||
    style === BlockStyle.tableRow
  );
}

export function blockStyleKey(style: BlockStyle): string {
  switch (style) {
    case BlockStyle.poetry:
      return 'q';
    case BlockStyle.descriptiveTitle:
      return 'd';
    case BlockStyle.heading:
      return 'h';
    case BlockStyle.blank:
      return 'b';
    case BlockStyle.reference:
      return 'r';
    case BlockStyle.acrostic:
      return 'qa';
    case BlockStyle.speaker:
      return 'sp';
    case BlockStyle.listItem:
      return 'li';
    case BlockStyle.tableRow:
      return 'tr';
    default:
      return 'p';
  }
}

/**
 * How a block sits across the column.
 *
 * Most of Scripture runs to the margin. A doxology or an acrostic line is
 * sometimes centred, and a colophon — "written from Corinth by Paul" —
 * set to the right.
 */
export enum BlockAlign {
  start = 0,
  center = 1,
  end = 2,
}

export function blockAlignFromIndex(index: number): BlockAlign {
  return index >= 0 && index < 3 ? (index as BlockAlign) : BlockAlign.start;
}

/** A run of text inside a `Block` that belongs to a single verse. */
export interface VerseSegment {
  /** The verse this text belongs to, or 0 for text outside any verse. */
  readonly verse: number;
  /** Whether the verse number should be printed before this run. */
  readonly startsVerse: boolean;
  readonly text: string;
}

export interface BlockInit {
  style: BlockStyle;
  indent?: number;
  indentFirstLine?: boolean;
  segments?: readonly VerseSegment[];
  level?: number;
  align?: BlockAlign;
  continuesParagraph?: boolean;
}

/** A paragraph, poetry line or heading. */
export class Block {
  readonly style: BlockStyle;
  /** Indent level; 1-based for poetry, 0 for flush-left prose. */
  readonly indent: number;
  /**
   * Whether the first line is indented, as `\p` is and `\m` is not. Some
   * translations set every paragraph flush to the margin, and indenting
   * those would misrepresent the text.
   */
  readonly indentFirstLine: boolean;
  readonly segments: readonly VerseSegment[];
  /**
   * For a heading, how major it is: 1 for a division of the book — "BOOK 1"
   * of the Psalms — and 2 or 3 for the section headings under it. 0 where
   * the translation does not say.
   */
  readonly level: number;
  readonly align: BlockAlign;
  /**
   * Set by `\nb`: this paragraph carries on the one before it across a
   * chapter break, and starting it afresh would break a sentence the
   * translation runs on.
   */
  readonly continuesParagraph: boolean;

  constructor(init: BlockInit) {
    this.style = init.style;
    this.indent = init.indent ?? 0;
    this.indentFirstLine = init.indentFirstLine ?? true;
    this.segments = init.segments ?? [];
    this.level = init.level ?? 0;
    this.align = init.align ?? BlockAlign.start;
    this.continuesParagraph = init.continuesParagraph ?? false;
  }

  get isEmpty(): boolean {
    return this.segments.length === 0 || this.segments.every((s) => s.text.trim().length === 0);
  }

  /**
   * The same block with its text belonging to no verse.
   *
   * A heading or a psalm's superscription stands above a chapter's first
   * verse rather than inside a verse of its own.
   */
  withoutVerses(): Block {
    return new Block({
      style: this.style,
      indent: this.indent,
      indentFirstLine: this.indentFirstLine,
      level: this.level,
      align: this.align,
      continuesParagraph: this.continuesParagraph,
      segments: this.segments.map((segment) => ({ verse: 0, startsVerse: false, text: segment.text })),
    });
  }

  /**
   * The cells of a table row, in order. One cell for anything else, which
   * is what a row of one column is.
   */
  get cells(): string[] {
    return this.segments
      .map((segment) => segment.text)
      .join(' ')
      .split(Markup.cell)
      .map((cell) => Markup.strip(cell).trim());
  }
}

export interface ChapterInit {
  number: number;
  blocks: Block[];
  notes: string[];
  labels?: ReadonlyMap<number, string>;
  omitted?: ReadonlySet<number>;
  label?: string;
}

/** One chapter: an ordered list of blocks plus the chapter's footnotes. */
export class Chapter {
  readonly number: number;
  readonly blocks: readonly Block[];
  /**
   * Footnote and cross-reference bodies, addressed by the index carried in a
   * note marker.
   */
  readonly notes: readonly string[];
  /**
   * What a verse is printed as, where that is not simply its number
   * (`\vp`). Keyed by the verse the text is stored under.
   */
  readonly labels: ReadonlyMap<number, string>;
  /** What this chapter is called where the translation says (`\cl`). */
  readonly label: string;
  /**
   * Verses this translation does not have. Not an error and not a gap to
   * be filled.
   */
  readonly omitted: ReadonlySet<number>;
  readonly verseCount: number;

  constructor(init: ChapterInit) {
    this.number = init.number;
    this.blocks = init.blocks;
    this.notes = init.notes;
    this.labels = init.labels ?? new Map();
    this.omitted = init.omitted ?? new Set();
    this.label = init.label ?? '';
    let max = 0;
    for (const block of init.blocks) {
      for (const segment of block.segments) if (segment.verse > max) max = segment.verse;
    }
    this.verseCount = max;
  }

  /** How a verse's number is printed. */
  labelFor(verse: number): string {
    return this.labels.get(verse) ?? `${verse}`;
  }

  /** Whether this translation leaves the verse out on purpose. */
  isOmitted(verse: number): boolean {
    return this.omitted.has(verse);
  }

  /**
   * Plain text of a single verse, with inline markers removed.
   *
   * Headings and psalm titles sit between verses and carry the number of
   * whichever verse precedes them, so they are left out.
   */
  verseText(verse: number): string {
    const parts: string[] = [];
    for (const block of this.blocks) {
      if (!isVerseText(block.style)) continue;
      for (const segment of block.segments) {
        if (segment.verse !== verse) continue;
        const text = Markup.strip(segment.text).trim();
        if (text.length === 0) continue;
        parts.push(text);
      }
    }
    return parts.join(' ').trim();
  }

  /**
   * A single verse with its inline marks kept — the words of Jesus, the
   * translators' additions, the divine name — and only the footnote
   * callers removed: what `verseText` gives, for somewhere that sets the
   * verse as Scripture rather than as a quotation.
   */
  verseMarked(verse: number): string {
    const parts: string[] = [];
    for (const block of this.blocks) {
      if (!isVerseText(block.style)) continue;
      for (const segment of block.segments) {
        if (segment.verse !== verse) continue;
        if (Markup.strip(segment.text).trim().length === 0) continue;
        parts.push(segment.text.replace(Markup.noteMarker, '').replace(/\u001d/g, ' ').trim());
      }
    }
    return parts.join(' ');
  }
}

/**
 * What a book is, before any of it has been read: how many chapters, how
 * many verses each of them has.
 */
export interface ChapterOutline {
  readonly number: number;
  readonly verseCount: number;
}

/**
 * A book of the Bible with its chapters.
 *
 * The chapters may not have been read yet. A book out of a `.bib` file
 * carries its outline and a way to fetch the rest, and unpacks itself the
 * first time anything asks for `chapters`.
 */
export class Book {
  readonly meta: BookMeta;
  /** Every chapter's number and length, always available. */
  readonly outline: readonly ChapterOutline[];
  private _chapters: Chapter[] | null;
  private readonly _load: (() => Chapter[]) | null;

  private constructor(meta: BookMeta, outline: readonly ChapterOutline[], chapters: Chapter[] | null, load: (() => Chapter[]) | null) {
    this.meta = meta;
    this.outline = outline;
    this._chapters = chapters;
    this._load = load;
  }

  /** A book whose chapters are already in hand: an import, a parse, a test. */
  static of(meta: BookMeta, chapters: Chapter[]): Book {
    return new Book(
      meta,
      chapters.map((c) => ({ number: c.number, verseCount: c.verseCount })),
      chapters,
      null,
    );
  }

  /** A book still in the file. `load` is called at most once. */
  static deferred(meta: BookMeta, outline: readonly ChapterOutline[], load: () => Chapter[]): Book {
    return new Book(meta, [...outline], null, load);
  }

  /** The chapters, unpacking them if that has not happened yet. */
  get chapters(): Chapter[] {
    if (this._chapters === null) this._chapters = this._load!();
    return this._chapters;
  }

  /** Whether the text is in memory. */
  get isLoaded(): boolean {
    return this._chapters !== null;
  }

  get code(): string {
    return this.meta.code;
  }
  get name(): string {
    return this.meta.name;
  }
  get abbrev(): string {
    return this.meta.abbrev;
  }
  get section(): BookSection {
    return this.meta.section;
  }

  get chapterCount(): number {
    return this.outline.length;
  }

  /** Every chapter number, in order, without unpacking anything. */
  get chapterNumbers(): number[] {
    return this.outline.map((c) => c.number);
  }

  /**
   * How many verses the nth chapter has, counting from one — a position,
   * not the printed number. Answered from the outline.
   */
  verseCountAt(position: number): number {
    return position < 1 || position > this.outline.length ? 0 : this.outline[position - 1].verseCount;
  }

  /** Every verse in the book, from the outline. */
  get verseCount(): number {
    return this.outline.reduce((sum, c) => sum + c.verseCount, 0);
  }

  /**
   * The nth chapter, counting from one — a position, not a number. A book
   * that begins at chapter 3 answers that chapter to `chapter(1)`.
   */
  chapter(number: number): Chapter | undefined {
    if (number < 1 || number > this.outline.length) return undefined;
    return this.chapters[number - 1];
  }
}

/** Which way the script of a translation runs. */
export enum ReadingDirection {
  ltr = 'ltr',
  rtl = 'rtl',
}

export function readingDirectionFromKey(key: string): ReadingDirection {
  return key.toLowerCase() === 'rtl' ? ReadingDirection.rtl : ReadingDirection.ltr;
}

/** How a translation numbers its verses. */
export const Versification = {
  /** The numbering of the English Protestant Bible. */
  english: 'eng',
  /** Said by a file that does not know. */
  unknown: 'unknown',
  /** Measured against `english` and found not to match it. */
  other: 'other',
  /**
   * Whether verse-anchored data built for `english` — the bundled
   * cross-references, the original-language layer — can be trusted
   * against a translation saying this.
   */
  mayAnchorEnglish(versification: string): boolean {
    return versification !== 'other';
  },
} as const;

export interface TranslationInfoInit {
  id: string;
  name: string;
  abbreviation: string;
  license: string;
  sourceUrl: string;
  language?: string;
  script?: string;
  direction?: ReadingDirection;
  versification?: string;
  attribution?: string;
}

/** Identity and licensing of a translation. */
export class TranslationInfo {
  readonly id: string;
  readonly name: string;
  readonly abbreviation: string;
  readonly license: string;
  readonly sourceUrl: string;
  /** BCP 47, so `en`, `es-419`, `arb`. */
  readonly language: string;
  /** ISO 15924, so `Latn`, `Hebr`, `Arab`. Empty where it is not said. */
  readonly script: string;
  readonly direction: ReadingDirection;
  /** The verse numbering this translation follows; see `Versification`. */
  readonly versification: string;
  /** Wording the licence obliges the app to show. Empty where none. */
  readonly attribution: string;

  constructor(init: TranslationInfoInit) {
    this.id = init.id;
    this.name = init.name;
    this.abbreviation = init.abbreviation;
    this.license = init.license;
    this.sourceUrl = init.sourceUrl;
    this.language = init.language ?? 'en';
    this.script = init.script ?? '';
    this.direction = init.direction ?? ReadingDirection.ltr;
    this.versification = init.versification ?? Versification.unknown;
    this.attribution = init.attribution ?? '';
  }

  copyWith(changes: Partial<TranslationInfoInit>): TranslationInfo {
    return new TranslationInfo({
      id: changes.id ?? this.id,
      name: changes.name ?? this.name,
      abbreviation: changes.abbreviation ?? this.abbreviation,
      license: changes.license ?? this.license,
      sourceUrl: changes.sourceUrl ?? this.sourceUrl,
      language: changes.language ?? this.language,
      script: changes.script ?? this.script,
      direction: changes.direction ?? this.direction,
      versification: changes.versification ?? this.versification,
      attribution: changes.attribution ?? this.attribution,
    });
  }
}

export interface BibleInit {
  translation: TranslationInfo;
  books: Book[];
  searchIndex?: (() => SearchIndex | null) | null;
  extras?: ReadonlyMap<string, Uint8Array>;
}

/** A fully parsed Bible held in memory. */
export class Bible {
  readonly translation: TranslationInfo;
  readonly books: readonly Book[];
  /**
   * The ancillary chunks the file carried and this layer does not itself
   * read — cross-references of its own, and whatever else a `.bib` comes
   * to hold. Kept as bytes, by tag.
   */
  readonly extras: ReadonlyMap<string, Uint8Array>;

  private readonly _searchIndex: (() => SearchIndex | null) | null;
  private _resolved: SearchIndex | null = null;
  private _looked = false;
  private readonly indexByCode = new Map<string, number>();

  constructor(init: BibleInit) {
    this.translation = init.translation;
    this._searchIndex = init.searchIndex ?? null;
    this.extras = init.extras ?? new Map();
    this.books = [...init.books].sort(
      (a, b) => (BookMeta.ordinalByCode.get(a.code) ?? 999) - (BookMeta.ordinalByCode.get(b.code) ?? 999),
    );
    for (let i = 0; i < this.books.length; i++) this.indexByCode.set(this.books[i].code, i);
  }

  /**
   * Which books each word is in, where the file carried it, unpacked the
   * first time anything asks. An optimisation for search and nothing more.
   */
  get searchIndex(): SearchIndex | null {
    if (!this._looked) {
      this._looked = true;
      this._resolved = this._searchIndex?.() ?? null;
    }
    return this._resolved;
  }

  bookByCode(code: string): Book | undefined {
    const index = this.indexByCode.get(code.toUpperCase());
    return index === undefined ? undefined : this.books[index];
  }

  indexOfCode(code: string): number | undefined {
    return this.indexByCode.get(code.toUpperCase());
  }

  /** Every verse in the translation, counted from the books' outlines. */
  get verseCount(): number {
    return this.books.reduce((total, book) => total + book.verseCount, 0);
  }
}

/** A place in the Bible: book code plus chapter, and optionally a verse. */
export class Reference {
  constructor(
    readonly bookCode: string,
    readonly chapter: number,
    readonly verse: number | null = null,
  ) {}

  get bookName(): string {
    return BookMeta.lookup(this.bookCode)?.name ?? this.bookCode;
  }

  get label(): string {
    return this.verse === null ? `${this.bookName} ${this.chapter}` : `${this.bookName} ${this.chapter}:${this.verse}`;
  }

  withVerse(verse: number | null): Reference {
    return new Reference(this.bookCode, this.chapter, verse);
  }

  encode(): string {
    return `${this.bookCode}/${this.chapter}/${this.verse ?? ''}`;
  }

  static decode(raw: string | null | undefined): Reference | null {
    if (raw == null) return null;
    const parts = raw.split('/');
    if (parts.length < 2) return null;
    const chapter = parseIntStrict(parts[1]);
    if (chapter === null) return null;
    const verse = parts.length > 2 ? parseIntStrict(parts[2]) : null;
    return new Reference(parts[0], chapter, verse);
  }

  equals(other: Reference | null | undefined): boolean {
    return (
      other != null && other.bookCode === this.bookCode && other.chapter === this.chapter && other.verse === this.verse
    );
  }

  /** A key for maps and sets, since two instances never compare equal by identity. */
  get key(): string {
    return this.encode();
  }

  toString(): string {
    return this.label;
  }
}

/** A strict integer parse: the whole string, decimal, optional sign, or null. */
export function parseIntStrict(s: string | null | undefined): number | null {
  if (s == null) return null;
  const t = s.trim();
  if (!/^[+-]?\d+$/.test(t)) return null;
  return Number.parseInt(t, 10);
}
