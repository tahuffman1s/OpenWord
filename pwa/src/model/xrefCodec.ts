import { gunzipSync } from 'fflate';
import { ByteReader, ByteWriter, FormatException } from './byteIo';

/**
 * One passage a cross-reference points at.
 *
 * A reference is often a run of verses — "Proverbs 8:22-24" — so it carries
 * a first and a last verse rather than one number.
 */
export class XrefRange {
  /** Index into the sixty-six books of the Protestant canon. */
  readonly book: number;
  readonly chapter: number;
  readonly verse: number;
  readonly endVerse: number;

  constructor(init: { book: number; chapter: number; verse: number; endVerse: number }) {
    this.book = init.book;
    this.chapter = init.chapter;
    this.verse = init.verse;
    this.endVerse = init.endVerse;
  }

  get isRange(): boolean {
    return this.endVerse > this.verse;
  }
}

/**
 * The references hanging off one phrase of a verse.
 *
 * The Treasury of Scripture Knowledge anchors its references to the words
 * they belong to, not to the verse as a whole, which is what makes a long
 * list of them readable: each is under the phrase that prompted it.
 */
export class XrefAnchor {
  readonly phrase: string;
  readonly ranges: XrefRange[];

  constructor(init: { phrase: string; ranges: XrefRange[] }) {
    this.phrase = init.phrase;
    this.ranges = init.ranges;
  }
}

/** Every anchor of one verse. */
export class XrefEntry {
  readonly book: number;
  readonly chapter: number;
  readonly verse: number;
  readonly anchors: XrefAnchor[];

  constructor(init: { book: number; chapter: number; verse: number; anchors: XrefAnchor[] }) {
    this.book = init.book;
    this.chapter = init.chapter;
    this.verse = init.verse;
    this.anchors = init.anchors;
  }

  get key(): number {
    return XrefCodec.keyOf(this.book, this.chapter, this.verse);
  }

  get passages(): number {
    let total = 0;
    for (const anchor of this.anchors) {
      total += anchor.ranges.length;
    }
    return total;
  }
}

/**
 * The binary form the cross-references ship in.
 *
 * Three hundred thousand references is too many for JSON — decoding it
 * builds a short-lived object per number. This is the same approach the
 * Scripture itself takes: LEB128 varints, deltas where the numbers climb,
 * and a table of the phrases, which repeat endlessly ("the LORD", "God").
 *
 *     'OWX' version=1
 *     varint phraseCount, then each phrase as length-prefixed UTF-8
 *     varint entryCount
 *     per entry: delta of the verse key, varint anchorCount
 *       per anchor: varint phrase index, varint rangeCount
 *         per range: varint book, chapter, verse, endVerse - verse
 */
export const XrefCodec = {
  magic: [0x4f, 0x57, 0x58] as const, // 'OWX'
  version: 1,

  /**
   * The `.bib` chunk a translation's own cross-references travel in.
   * Ancillary, so a file gains them without becoming unreadable to
   * anything written before them.
   */
  chunkTag: 'xref',

  /**
   * Unpacks a set as it is stored — gzipped — or throws. Free of the DOM,
   * so the tools can read one too.
   */
  unpack(bytes: Uint8Array): XrefEntry[] {
    return XrefCodec.decode(gunzipSync(bytes));
  },

  /** Verses are looked up by one number rather than three. */
  keyOf(book: number, chapter: number, verse: number): number {
    return (book * 1000 + chapter) * 1000 + verse;
  },

  encode(entries: readonly XrefEntry[]): Uint8Array {
    const phrases = new Map<string, number>();
    for (const entry of entries) {
      for (const anchor of entry.anchors) {
        if (!phrases.has(anchor.phrase)) phrases.set(anchor.phrase, phrases.size);
      }
    }

    const out = new ByteWriter().bytes(XrefCodec.magic).byte(XrefCodec.version).varint(phrases.size);
    for (const phrase of phrases.keys()) {
      out.string(phrase);
    }

    out.varint(entries.length);
    let previous = 0;
    for (const entry of entries) {
      out.varint(entry.key - previous);
      previous = entry.key;
      out.varint(entry.anchors.length);
      for (const anchor of entry.anchors) {
        out.varint(phrases.get(anchor.phrase)!);
        out.varint(anchor.ranges.length);
        for (const range of anchor.ranges) {
          out.varint(range.book).varint(range.chapter).varint(range.verse).varint(range.endVerse - range.verse);
        }
      }
    }
    return out.takeCopy();
  },

  decode(bytes: Uint8Array): XrefEntry[] {
    const input = new ByteReader(bytes);
    for (const byte of XrefCodec.magic) {
      if (input.byte() !== byte) {
        throw new FormatException('not a cross-reference asset');
      }
    }
    const found = input.byte();
    if (found !== XrefCodec.version) {
      throw new FormatException(`cross-references are version ${found}, not ${XrefCodec.version}`);
    }

    const phraseCount = input.varint();
    const phrases = new Array<string>(phraseCount);
    for (let i = 0; i < phraseCount; i++) phrases[i] = input.string();
    const entries: XrefEntry[] = [];
    const count = input.varint();
    let key = 0;
    for (let i = 0; i < count; i++) {
      key += input.varint();
      const anchors: XrefAnchor[] = [];
      const anchorCount = input.varint();
      for (let a = 0; a < anchorCount; a++) {
        const phrase = phrases[input.varint()];
        const ranges: XrefRange[] = [];
        const rangeCount = input.varint();
        for (let r = 0; r < rangeCount; r++) {
          const book = input.varint();
          const chapter = input.varint();
          const verse = input.varint();
          ranges.push(new XrefRange({ book, chapter, verse, endVerse: verse + input.varint() }));
        }
        anchors.push(new XrefAnchor({ phrase, ranges }));
      }
      entries.push(
        new XrefEntry({
          book: Math.trunc(key / 1000000),
          chapter: Math.trunc(key / 1000) % 1000,
          verse: key % 1000,
          anchors,
        }),
      );
    }
    return entries;
  },
};
