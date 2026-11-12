import { Bible, Block, BlockAlign, blockAlignFromIndex, BlockStyle, blockStyleCount, Book, Chapter, TranslationInfo, type VerseSegment } from './bible';
import { BookMeta } from './bookMeta';
import { ByteReader, ByteWriter, FormatException } from './byteIo';

/**
 * A compact binary encoding for a whole `Bible`.
 *
 * Layout, all integers LEB128 varints unless stated:
 *
 *     'OWB' u8:version
 *     str:id str:name str:abbreviation str:license str:sourceUrl
 *     n:books
 *       str:code n:chapters
 *         n:number n:blocks
 *           u8:style u8:indent u8:flags n:segments
 *             (flags bit 0: the first line is indented)
 *             n:verse u8:startsVerse str:text
 *           n:notes str:note...
 */
const magic = [0x4f, 0x57, 0x42]; // 'OWB'
const indentsFirstLine = 0x01;
const continues = 0x02;

export const BibleCodec = {
  version: 2,

  encode(bible: Bible): Uint8Array {
    const out = new ByteWriter()
      .bytes(magic)
      .byte(BibleCodec.version)
      .string(bible.translation.id)
      .string(bible.translation.name)
      .string(bible.translation.abbreviation)
      .string(bible.translation.license)
      .string(bible.translation.sourceUrl)
      .varint(bible.books.length);
    for (const book of bible.books) {
      out.string(book.code);
      // This writes the single-stream format, which predates the extra
      // block attributes; a reader of it would not know to skip them.
      BibleCodec.writeChapters(out, book.chapters, false);
    }
    return out.take();
  },

  /**
   * One book's chapters, and nothing else. This is what a `.bib` v2 file
   * compresses one at a time.
   */
  writeChapters(out: ByteWriter, chapters: readonly Chapter[], rich = true): void {
    out.varint(chapters.length);
    for (const chapter of chapters) {
      out.varint(chapter.number).varint(chapter.blocks.length);
      for (const block of chapter.blocks) {
        out
          .byte(block.style)
          .byte(clamp(block.indent, 0, 255))
          .byte((block.indentFirstLine ? indentsFirstLine : 0) | (block.continuesParagraph ? continues : 0));
        if (rich) out.byte(clamp(block.level, 0, 255)).byte(block.align);
        out.varint(block.segments.length);
        for (const segment of block.segments) {
          out.varint(segment.verse).byte(segment.startsVerse ? 1 : 0).string(segment.text);
        }
      }
      out.varint(chapter.notes.length);
      for (const note of chapter.notes) out.string(note);
      if (!rich) continue;
      out.string(chapter.label);
      out.varint(chapter.labels.size);
      for (const [verse, label] of chapter.labels) out.varint(verse).string(label);
      const omitted = [...chapter.omitted].sort((a, b) => a - b);
      out.varint(omitted.length);
      let previous = 0;
      for (const verse of omitted) {
        out.varint(verse - previous);
        previous = verse;
      }
    }
  },

  /** The inverse of `writeChapters`. */
  readChapters(input: ByteReader, rich = true): Chapter[] {
    const chapterCount = input.varint();
    const chapters: Chapter[] = [];
    for (let c = 0; c < chapterCount; c++) {
      const number = input.varint();
      const blockCount = input.varint();
      const blocks: Block[] = [];
      for (let i = 0; i < blockCount; i++) {
        const styleIndex = input.byte();
        const indent = input.byte();
        const flags = input.byte();
        const level = rich ? input.byte() : 0;
        const align = rich ? blockAlignFromIndex(input.byte()) : BlockAlign.start;
        const segmentCount = input.varint();
        const segments: VerseSegment[] = [];
        for (let s = 0; s < segmentCount; s++) {
          const verse = input.varint();
          const startsVerse = input.byte() === 1;
          const text = input.string();
          segments.push({ verse, startsVerse, text });
        }
        blocks.push(
          new Block({
            // A style added after this reader was written is read as a
            // paragraph rather than refused.
            style: styleIndex < blockStyleCount ? (styleIndex as BlockStyle) : BlockStyle.paragraph,
            indent,
            indentFirstLine: (flags & indentsFirstLine) !== 0,
            continuesParagraph: (flags & continues) !== 0,
            level,
            align,
            segments,
          }),
        );
      }
      const noteCount = input.varint();
      const notes: string[] = [];
      for (let n = 0; n < noteCount; n++) notes.push(input.string());

      let chapterLabel = '';
      let labels: Map<number, string> | undefined;
      let omitted: Set<number> | undefined;
      if (rich) {
        chapterLabel = input.string();
        const labelCount = input.varint();
        if (labelCount > 0) {
          labels = new Map();
          for (let l = 0; l < labelCount; l++) {
            const verse = input.varint();
            labels.set(verse, input.string());
          }
        }
        const omittedCount = input.varint();
        if (omittedCount > 0) {
          omitted = new Set();
          let previous = 0;
          for (let o = 0; o < omittedCount; o++) {
            previous += input.varint();
            omitted.add(previous);
          }
        }
      }
      chapters.push(new Chapter({ number, blocks, notes, labels, omitted, label: chapterLabel }));
    }
    return chapters;
  },

  /** One book's chapters, packed on their own. */
  encodeChapters(chapters: readonly Chapter[], rich = true): Uint8Array {
    const out = new ByteWriter();
    BibleCodec.writeChapters(out, chapters, rich);
    return out.takeCopy();
  },

  /** Unpacks what `encodeChapters` wrote. */
  decodeChapters(data: Uint8Array, rich = true): Chapter[] {
    return BibleCodec.readChapters(new ByteReader(data), rich);
  },

  /** Decodes `data`. Throws `FormatException` if it is not this format. */
  decode(data: Uint8Array): Bible {
    const input = new ByteReader(data);
    for (const expected of magic) {
      if (input.byte() !== expected) throw new FormatException('Not an OpenWord Bible file');
    }
    const fileVersion = input.byte();
    if (fileVersion !== BibleCodec.version) throw new FormatException(`Unsupported Bible format version ${fileVersion}`);
    const translation = new TranslationInfo({
      id: input.string(),
      name: input.string(),
      abbreviation: input.string(),
      license: input.string(),
      sourceUrl: input.string(),
    });
    const bookCount = input.varint();
    const books: Book[] = [];
    for (let b = 0; b < bookCount; b++) {
      const code = input.string();
      const chapters = BibleCodec.readChapters(input, false);
      const meta = BookMeta.lookup(code);
      if (meta) books.push(Book.of(meta, chapters));
    }
    if (books.length === 0) throw new FormatException('Bible file has no books');
    return new Bible({ translation, books });
  },
};

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}
