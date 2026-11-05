import { Block, BlockStyle, Book, Chapter, Markup } from './bible';

/** What came of taking an edition's furniture out of its Scripture. */
export class BoilerplateSweep {
  constructor(
    readonly books: readonly Book[],
    /**
     * The lines that were taken out, each once, longest first. Worth
     * showing: a reader told what was dropped can say whether it should
     * have been.
     */
    readonly removed: readonly string[],
  ) {}

  get isEmpty(): boolean {
    return this.removed.length === 0;
  }
}

/** Styles that say a block is part of the text whatever it repeats. */
const neverFurniture: ReadonlySet<BlockStyle> = new Set([
  BlockStyle.heading,
  BlockStyle.descriptiveTitle,
  BlockStyle.acrostic,
  BlockStyle.speaker,
  BlockStyle.reference,
]);

/**
 * How many separate books a line must turn up in before it is furniture.
 *
 * Two would not be enough. A pair of books can share a line honestly —
 * the same doxology, the same closing — and three is the point at which
 * coincidence stops being the likely explanation.
 */
export const boilerplateBooks = 3;

/**
 * Takes an edition's furniture out of a Bible: the navigation, the
 * running headers and the footers it prints around every book.
 *
 * Every rule that reads the markup can be defeated by an edition that
 * marks its furniture up some other way — as links, as plain paragraphs,
 * as a table, as whatever the publisher's template happened to emit. This
 * one does not read the markup at all. It reads the text, and asks a
 * question about the book as a whole that no single paragraph can answer:
 * does this line belong to no verse, and does it turn up word for word in
 * three or more separate books?
 *
 * Nothing in Scripture answers yes. Text that belongs to a verse is never
 * considered, so a doxology or an "Amen." inside a verse is safe. What
 * repeats outside a verse repeats inside one book — a psalm's
 * superscription is in Psalms and nowhere else, and one book is not three.
 * What repeats across books is what the edition printed around the text
 * rather than in it.
 */
export function stripBoilerplate(books: readonly Book[]): BoilerplateSweep {
  // Which books each candidate line appears in.
  const seenIn = new Map<string, Set<string>>();
  for (const book of books) {
    for (const chapter of book.chapters) {
      for (const line of candidatesIn(chapter)) {
        let codes = seenIn.get(line);
        if (codes === undefined) seenIn.set(line, (codes = new Set()));
        codes.add(book.code);
      }
    }
  }

  const furniture = new Set<string>();
  for (const [line, codes] of seenIn) {
    if (codes.size >= boilerplateBooks) furniture.add(line);
  }
  if (furniture.size === 0) {
    return new BoilerplateSweep(books, []);
  }

  const swept: Book[] = [];
  for (const book of books) {
    const chapters: Chapter[] = [];
    for (const chapter of book.chapters) {
      const drop = furnitureIn(chapter, furniture);
      chapters.push(
        drop.size === 0
          ? chapter
          : new Chapter({
              number: chapter.number,
              blocks: chapter.blocks.filter((_, i) => !drop.has(i)),
              notes: [...chapter.notes],
              labels: chapter.labels,
              omitted: chapter.omitted,
              label: chapter.label,
            }),
      );
    }
    swept.push(Book.of(book.meta, chapters));
  }

  const removed = [...furniture].sort((a, b) => b.length - a.length);
  return new BoilerplateSweep(swept, removed);
}

/**
 * The lines of a chapter that could be furniture: those lying outside
 * its Scripture altogether, before the first verse of it or after the
 * last.
 *
 * Position matters as much as repetition. The Gospels quote the Psalms
 * and each other, so a line can repeat across books and be Scripture in
 * every one of them — "The stone that the builders rejected" stands in
 * five. What it does not do is stand outside the verses: a quotation is
 * in the middle of a chapter, and an edition's furniture is at its edges.
 * Without this the rule took that verse out of all five books.
 * Which blocks of a chapter are furniture, by position.
 */
function furnitureIn(chapter: Chapter, furniture: ReadonlySet<string>): Set<number> {
  const out = new Set<number>();
  for (const at of candidatePositions(chapter)) {
    const line = lineOf(chapter.blocks[at]);
    if (line !== null && furniture.has(line)) out.add(at);
  }
  return out;
}

function* candidatesIn(chapter: Chapter): Generator<string> {
  for (const at of candidatePositions(chapter)) {
    const line = lineOf(chapter.blocks[at]);
    if (line !== null) yield line;
  }
}

/** The positions a chapter's furniture could be in. */
function* candidatePositions(chapter: Chapter): Generator<number> {
  let first = -1;
  let last = -1;
  for (let i = 0; i < chapter.blocks.length; i++) {
    if (chapter.blocks[i].segments.some((segment) => segment.startsVerse)) {
      if (first < 0) first = i;
      last = i;
    }
  }
  // A chapter with no numbered verse at all is not Scripture to begin
  // with, and is left to the rules that decide that.
  if (first < 0) return;
  for (let i = 0; i < chapter.blocks.length; i++) {
    if (i > first && i < last) continue;
    yield i;
  }
}

/**
 * A block's text, where the block belongs to no verse — and null where it
 * belongs to one, which puts it beyond this rule's reach entirely.
 *
 * A blank is not a line: an edition that spaces its furniture out would
 * otherwise have every stanza break in the Bible counted together.
 */
function lineOf(block: Block): string | null {
  if (block.style === BlockStyle.blank) return null;
  // A section heading is never furniture, however often it repeats. The
  // Gospels tell the same events and an edition heads them the same way:
  // "Jesus Foretells His Death" stands over Matthew, Mark and Luke alike,
  // and sweeping it would take a heading out of three Gospels at once.
  // This rule cost the ESV fifty-eight of them before the test caught it.
  if (neverFurniture.has(block.style)) return null;
  if (block.segments.some((segment) => segment.startsVerse)) return null;
  const text = block.segments
    .map((segment) => Markup.strip(segment.text))
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
  return text.length === 0 ? null : text;
}
