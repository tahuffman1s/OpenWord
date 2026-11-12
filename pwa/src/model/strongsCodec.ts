import { gunzipSync, gzipSync } from 'fflate';
import { ByteReader, ByteWriter, FormatException } from './byteIo';

/** One word of the original text, as it stands in a particular verse. */
export class OriginalWord {
  /** The Hebrew or Greek, pointed and accented as the source has it. */
  readonly text: string;

  /**
   * The Strong's number, or null for a word the source leaves untagged —
   * a few particles and prefixes.
   */
  readonly strongs: StrongsNumber | null;

  /**
   * The parsing, spelled out: "Noun common feminine singular absolute".
   * Empty where the source gives none.
   */
  readonly morphology: string;

  constructor(init: { text: string; strongs: StrongsNumber | null; morphology: string }) {
    this.text = init.text;
    this.strongs = init.strongs;
    this.morphology = init.morphology;
  }
}

/** A Strong's number, which is a language and a number: H7225 is not G7225. */
export class StrongsNumber {
  constructor(
    /** 'H' for the Hebrew Bible, 'G' for the Greek New Testament. */
    readonly language: string,
    readonly number: number,
  ) {}

  get isHebrew(): boolean {
    return this.language === 'H';
  }

  /** How the number is written, and typed into the search field. */
  get label(): string {
    return `${this.language}${this.number}`;
  }

  /** The key it is stored under; Hebrew and Greek share one space. */
  get key(): number {
    return this.isHebrew ? this.number : 1000000 + this.number;
  }

  static fromKey(key: number): StrongsNumber {
    return key >= 1000000 ? new StrongsNumber('G', key - 1000000) : new StrongsNumber('H', key);
  }

  /** Reads "H7225", "g2316", "H 7225". Null where the text is not one. */
  static parse(text: string): StrongsNumber | null {
    const match = /^\s*([hHgG])\s*0*(\d{1,4})\s*$/.exec(text);
    if (match === null) return null;
    const number = Number.parseInt(match[2], 10);
    if (number < 1) return null;
    return new StrongsNumber(match[1].toUpperCase(), number);
  }

  compareTo(other: StrongsNumber): number {
    return this.key - other.key;
  }

  /** Dart's `operator ==`: two numbers are the same when their keys are. */
  equals(other: StrongsNumber | null | undefined): boolean {
    return other != null && other.key === this.key;
  }

  toString(): string {
    return this.label;
  }
}

/** A Strong's dictionary entry. */
export class StrongsEntry {
  readonly number: StrongsNumber;

  /** The headword, in Hebrew or Greek. */
  readonly lemma: string;
  readonly transliteration: string;
  readonly pronunciation: string;

  /** Where the word comes from, in Strong's own words. */
  readonly derivation: string;

  /** Strong's definition. */
  readonly definition: string;

  /**
   * The words the King James translators used for it — which is also how a
   * tapped English word is matched to its Strong's number.
   */
  readonly kjvUsage: string;

  constructor(init: {
    number: StrongsNumber;
    lemma: string;
    transliteration: string;
    pronunciation: string;
    derivation: string;
    definition: string;
    kjvUsage: string;
  }) {
    this.number = init.number;
    this.lemma = init.lemma;
    this.transliteration = init.transliteration;
    this.pronunciation = init.pronunciation;
    this.derivation = init.derivation;
    this.definition = init.definition;
    this.kjvUsage = init.kjvUsage;
  }

  /**
   * The first few words the King James translators used, for a line under
   * the original.
   *
   * Strong's gives no single gloss, and picking one would be inventing it:
   * the usage list for H430 opens with "angels", which is not what אֱלֹהִים
   * means. So this shows what the list actually is, and the entry shows it
   * in full.
   */
  get renderedAs(): string {
    const words = this.renderings.slice(0, 3);
    return words.join(', ');
  }

  /**
   * The English words this number is rendered by, for matching a tapped
   * word against the verse.
   * The editorial marks come out first and the list is split second.
   * Strong's writes "God (gods) (-dess, -ly)", and splitting on the comma
   * inside those brackets yields "god -dess", which matches nothing.
   */
  get renderings(): string[] {
    const stripped = this.kjvUsage.replace(/\([^)]*\)/g, ' ').replace(/\[[^\]]*\]/g, ' ');
    const words = new Set<string>();
    for (const part of stripped.split(/[,;.]/)) {
      const cleaned = StrongsEntry.clean(part);
      if (cleaned.length > 0) words.add(cleaned);
    }
    return [...words];
  }

  /**
   * Strong's usage lists carry editorial marks — "[idiom]", "(-ness)",
   * "[phrase]", and a bare "X" for "not rendered literally" — which are
   * not words anyone reads or taps.
   */
  private static clean(part: string): string {
    return part
      .replace(/\[[^\]]*\]/g, ' ')
      .replace(/\([^)]*\)/g, ' ')
      .replace(/[^A-Za-z \-]/g, ' ')
      .replace(/(^| )[A-Za-z]( |$)/g, ' ')
      .replace(/(^|\s)-+|-+(\s|$)/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .toLowerCase();
  }
}

/**
 * The binary the original-language layer ships in.
 *
 * Four hundred and fifty thousand words is too many to hold as objects —
 * it would cost more memory than the Scripture itself. So the file is
 * gunzipped once into a byte array that stays put, and a verse's words are
 * decoded from it only when that verse is looked at. The indexes that make
 * that possible are small: a verse key and an offset, both varints, delta
 * coded.
 *
 *     'OWS' version=1
 *     u32 ×4  where the lexicon, its index, the concordance and its index
 *             begin
 *     morphology table: varint count, then each spelled-out parsing
 *     verse index: varint count, then per verse a key delta and an offset
 *     verse data:  per verse, varint wordCount, then per word
 *                  varint strongs key + 1 (0 where untagged),
 *                  varint morphology index + 1 (0 where none),
 *                  the word itself, length-prefixed
 *     lexicon index / data: the same shape, keyed by Strong's number
 *     concordance index / data: per number, the verses it occurs in, as
 *                  deltas — this is what "N occurrences" counts
 */
export const StrongsCodec = {
  magic: [0x4f, 0x57, 0x53] as const, // 'OWS'
  version: 1,

  /**
   * The `.bib` chunk a translation's own Hebrew and Greek travel in.
   * Ancillary, so a file gains them without becoming unreadable to
   * anything written before them.
   */
  chunkTag: 'strg',

  verseKey(book: number, chapter: number, verse: number): number {
    return (book * 1000 + chapter) * 1000 + verse;
  },

  /**
   * Reads a layer as it is stored — gzipped — or raw. Free of the DOM, so
   * the tools and a worker can both read one.
   *
   * Either is accepted because the asset on disk is gzipped and a chunk
   * inside a `.bib` may or may not be, depending on what wrote it; the
   * magic says which without having to be told.
   */
  unpack(bytes: Uint8Array): StrongsReader {
    return StrongsReader.parse(StrongsCodec.inflate(bytes));
  },

  /** Gzipped or not, as its first two bytes say. */
  inflate(bytes: Uint8Array): Uint8Array {
    const gzipped = bytes.length > 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
    if (!gzipped) return bytes;
    return gunzipSync(bytes);
  },

  /** Packs a layer the way the asset and the chunk both store it. */
  deflate(raw: Uint8Array): Uint8Array {
    return gzipSync(raw);
  },
};

/** Reads the asset without unpacking all of it. */
export class StrongsReader {
  private constructor(
    private readonly bytes: Uint8Array,
    private readonly morphology: readonly string[],
    /** Verse key → where that verse's words begin. */
    private readonly verses: Map<number, number>,
    /** Strong's key → where that entry begins. */
    private readonly lexicon: Map<number, number>,
    /** Strong's key → where its list of occurrences begins. */
    private readonly concordance: Map<number, number>,
  ) {}

  get verseCount(): number {
    return this.verses.size;
  }

  get entryCount(): number {
    return this.lexicon.size;
  }

  hasVerse(key: number): boolean {
    return this.verses.has(key);
  }

  /**
   * Every verse this layer has words for, in no particular order. What a
   * rewrite iterates over.
   */
  get verseKeys(): Iterable<number> {
    return this.verses.keys();
  }

  /** Every Strong's number this layer has a dictionary entry for. */
  get entryNumbers(): Iterable<StrongsNumber> {
    const keys = this.lexicon.keys();
    return {
      *[Symbol.iterator]() {
        for (const key of keys) yield StrongsNumber.fromKey(key);
      },
    };
  }

  /** The words of one verse, decoded now. */
  wordsAt(key: number): OriginalWord[] {
    const offset = this.verses.get(key);
    if (offset === undefined) return [];
    const input = new ByteReader(this.bytes, offset);
    const count = input.varint();
    const words: OriginalWord[] = new Array(count);
    for (let i = 0; i < count; i++) {
      const strongs = input.varint();
      const morph = input.varint();
      words[i] = new OriginalWord({
        text: input.string(),
        strongs: strongs === 0 ? null : StrongsNumber.fromKey(strongs - 1),
        morphology: morph === 0 ? '' : this.morphology[morph - 1],
      });
    }
    return words;
  }

  entryFor(number: StrongsNumber): StrongsEntry | null {
    const offset = this.lexicon.get(number.key);
    if (offset === undefined) return null;
    const input = new ByteReader(this.bytes, offset);
    return new StrongsEntry({
      number,
      lemma: input.string(),
      transliteration: input.string(),
      pronunciation: input.string(),
      derivation: input.string(),
      definition: input.string(),
      kjvUsage: input.string(),
    });
  }

  /** How many verses a number occurs in. */
  occurrenceCount(number: StrongsNumber): number {
    const offset = this.concordance.get(number.key);
    if (offset === undefined) return 0;
    return new ByteReader(this.bytes, offset).varint();
  }

  /** Every verse a number occurs in, in canonical order. */
  occurrences(number: StrongsNumber): number[] {
    const offset = this.concordance.get(number.key);
    if (offset === undefined) return [];
    const input = new ByteReader(this.bytes, offset);
    const count = input.varint();
    const keys: number[] = [];
    let key = 0;
    for (let i = 0; i < count; i++) {
      key += input.varint();
      keys.push(key);
    }
    return keys;
  }

  static parse(bytes: Uint8Array): StrongsReader {
    const input = new ByteReader(bytes, 0);
    for (const byte of StrongsCodec.magic) {
      if (input.byte() !== byte) {
        throw new FormatException('not the original-language asset');
      }
    }
    const found = input.byte();
    if (found !== StrongsCodec.version) {
      throw new FormatException(`the original-language asset is version ${found}, not ${StrongsCodec.version}`);
    }

    // Every index holds offsets from the start of its own data, so the
    // sections can be laid out without predicting their own sizes.
    const verseDataAt = input.uint32();
    const lexiconIndexAt = input.uint32();
    const lexiconDataAt = input.uint32();
    const concordanceIndexAt = input.uint32();
    const concordanceDataAt = input.uint32();

    const morphologyCount = input.varint();
    const morphology = new Array<string>(morphologyCount);
    for (let i = 0; i < morphologyCount; i++) morphology[i] = input.string();
    const verses = StrongsReader.index(input, verseDataAt);
    const lexicon = StrongsReader.index(new ByteReader(bytes, lexiconIndexAt), lexiconDataAt);
    const concordance = StrongsReader.index(new ByteReader(bytes, concordanceIndexAt), concordanceDataAt);

    return new StrongsReader(bytes, morphology, verses, lexicon, concordance);
  }

  /**
   * A run of key/offset pairs, both delta coded, offsets measured from
   * `base` — the start of the data the index points into.
   */
  private static index(input: ByteReader, base: number): Map<number, number> {
    const count = input.varint();
    const out = new Map<number, number>();
    let key = 0;
    let offset = 0;
    for (let i = 0; i < count; i++) {
      key += input.varint();
      offset += input.varint();
      out.set(key, base + offset);
    }
    return out;
  }
}

/** Builds the asset. Only the tool uses this; the app only reads. */
export class StrongsWriter {
  private readonly morphology = new Map<string, number>();
  private readonly verses = new Map<number, OriginalWord[]>();
  private readonly entries = new Map<number, StrongsEntry>();

  addVerse(key: number, words: OriginalWord[]): void {
    if (words.length === 0) return;
    this.verses.set(key, words);
    for (const word of words) {
      if (word.morphology.length > 0 && !this.morphology.has(word.morphology)) {
        this.morphology.set(word.morphology, this.morphology.size);
      }
    }
  }

  addEntry(entry: StrongsEntry): void {
    this.entries.set(entry.number.key, entry);
  }

  get verseCount(): number {
    return this.verses.size;
  }

  get entryCount(): number {
    return this.entries.size;
  }

  build(): Uint8Array {
    // Which verses each number turns up in, gathered as the words are
    // written rather than in a second pass over the whole Bible.
    const occurrences = new Map<number, number[]>();

    const verseKeys = [...this.verses.keys()].sort((a, b) => a - b);
    const verseData = new ByteWriter();
    const verseOffsets = new Map<number, number>();
    for (const key of verseKeys) {
      verseOffsets.set(key, verseData.length);
      const words = this.verses.get(key)!;
      verseData.varint(words.length);
      for (const word of words) {
        const strongs = word.strongs;
        verseData
          .varint(strongs === null ? 0 : strongs.key + 1)
          .varint(word.morphology.length === 0 ? 0 : this.morphology.get(word.morphology)! + 1)
          .string(word.text);
        if (strongs !== null) {
          let list = occurrences.get(strongs.key);
          if (!list) occurrences.set(strongs.key, (list = []));
          if (list.length === 0 || list[list.length - 1] !== key) list.push(key);
        }
      }
    }

    const entryKeys = [...this.entries.keys()].sort((a, b) => a - b);
    const lexiconData = new ByteWriter();
    const lexiconOffsets = new Map<number, number>();
    for (const key of entryKeys) {
      lexiconOffsets.set(key, lexiconData.length);
      const entry = this.entries.get(key)!;
      lexiconData
        .string(entry.lemma)
        .string(entry.transliteration)
        .string(entry.pronunciation)
        .string(entry.derivation)
        .string(entry.definition)
        .string(entry.kjvUsage);
    }

    const occurrenceKeys = [...occurrences.keys()].sort((a, b) => a - b);
    const concordanceData = new ByteWriter();
    const concordanceOffsets = new Map<number, number>();
    for (const key of occurrenceKeys) {
      concordanceOffsets.set(key, concordanceData.length);
      const verses = occurrences.get(key)!;
      concordanceData.varint(verses.length);
      let previous = 0;
      for (const verse of verses) {
        concordanceData.varint(verse - previous);
        previous = verse;
      }
    }

    const tables = new ByteWriter().varint(this.morphology.size);
    for (const code of this.morphology.keys()) {
      tables.string(code);
    }
    StrongsWriter.writeIndex(tables, verseKeys, verseOffsets);

    const lexiconIndex = new ByteWriter();
    StrongsWriter.writeIndex(lexiconIndex, entryKeys, lexiconOffsets);

    const concordanceIndex = new ByteWriter();
    StrongsWriter.writeIndex(concordanceIndex, occurrenceKeys, concordanceOffsets);

    // The header is fixed width, so where each section lands is simple
    // addition rather than a prediction that can be wrong.
    const headerLength = 3 + 1 + 4 * 5;
    const tableBytes = tables.take();
    const verseBytes = verseData.take();
    const lexiconIndexBytes = lexiconIndex.take();
    const lexiconBytes = lexiconData.take();
    const concordanceIndexBytes = concordanceIndex.take();
    const concordanceBytes = concordanceData.take();

    const verseDataAt = headerLength + tableBytes.length;
    const lexiconIndexAt = verseDataAt + verseBytes.length;
    const lexiconDataAt = lexiconIndexAt + lexiconIndexBytes.length;
    const concordanceIndexAt = lexiconDataAt + lexiconBytes.length;
    const concordanceDataAt = concordanceIndexAt + concordanceIndexBytes.length;

    const out = new ByteWriter()
      .bytes(StrongsCodec.magic)
      .byte(StrongsCodec.version)
      .uint32(verseDataAt)
      .uint32(lexiconIndexAt)
      .uint32(lexiconDataAt)
      .uint32(concordanceIndexAt)
      .uint32(concordanceDataAt)
      .bytes(tableBytes)
      .bytes(verseBytes)
      .bytes(lexiconIndexBytes)
      .bytes(lexiconBytes)
      .bytes(concordanceIndexBytes)
      .bytes(concordanceBytes);
    return out.takeCopy();
  }

  /**
   * Keys and offsets, both delta coded; the offsets are measured from the
   * start of the data the index points into.
   */
  private static writeIndex(out: ByteWriter, keys: readonly number[], offsets: Map<number, number>): void {
    out.varint(keys.length);
    let key = 0;
    let offset = 0;
    for (const k of keys) {
      out.varint(k - key);
      key = k;
      const at = offsets.get(k)!;
      out.varint(at - offset);
      offset = at;
    }
  }
}

/**
 * Rewrites an original-language layer for just the verses a Bible has.
 *
 * The bundled layer covers the whole Protestant canon. Writing all of it
 * into a New Testament, or into a Bible missing a book, is waste: the
 * verses that are not there are dead weight, and so is every dictionary
 * entry and every concordance line that only those verses reached.
 *
 * Free of the DOM and taking nothing but what it is given, so a tool, a
 * worker and a test can all call it.
 */
export function trimOriginalsTo(source: StrongsReader, wanted: ReadonlySet<number>): Uint8Array {
  const writer = new StrongsWriter();

  // The dictionary is the larger half of the layer, so only the entries
  // the kept words actually reach are carried over. The concordance is
  // rebuilt from the verses as they are added, so it needs no filtering:
  // it can only ever name a verse that went in.
  const reached = new Set<number>();
  for (const key of source.verseKeys) {
    if (!wanted.has(key)) continue;
    const words = source.wordsAt(key);
    if (words.length === 0) continue;
    writer.addVerse(key, words);
    for (const word of words) {
      const number = word.strongs;
      if (number !== null) reached.add(number.key);
    }
  }

  for (const number of source.entryNumbers) {
    if (!reached.has(number.key)) continue;
    const entry = source.entryFor(number);
    if (entry !== null) writer.addEntry(entry);
  }

  return writer.build();
}
