import { Markup } from './bible';

/**
 * One verse set beside itself in other translations: its words as runs
 * that keep their marks, and which of them a second translation words
 * differently.
 */

/** A stretch of a verse that is all set one way. */
export interface MarkedRun {
  readonly text: string;
  /** Words of Jesus. */
  readonly wj: boolean;
  /** Words the translators supplied, or a direction such as Selah. */
  readonly italic: boolean;
  /** The divine name, set in small capitals. */
  readonly divine: boolean;
}

/**
 * The runs of a verse as `Chapter.verseMarked` gives it. Footnote callers
 * and the marks around quotations carry nothing to draw and are dropped.
 */
export function markedRuns(marked: string): MarkedRun[] {
  const runs: MarkedRun[] = [];
  let wj = false;
  let added = false;
  let selah = false;
  let divine = false;
  let buffer = '';
  const flush = () => {
    if (buffer.length === 0) return;
    runs.push({ text: buffer, wj, italic: added || selah, divine });
    buffer = '';
  };
  for (let i = 0; i < marked.length; i++) {
    const char = marked[i];
    switch (char) {
      case Markup.wjStart:
      case Markup.wjEnd:
        flush();
        wj = char === Markup.wjStart;
        break;
      case Markup.addStart:
      case Markup.addEnd:
        flush();
        added = char === Markup.addStart;
        break;
      case Markup.selahStart:
      case Markup.selahEnd:
        flush();
        selah = char === Markup.selahStart;
        break;
      case Markup.divineStart:
      case Markup.divineEnd:
        flush();
        divine = char === Markup.divineStart;
        break;
      case Markup.quotationStart:
      case Markup.quotationEnd:
        break;
      case Markup.cell:
        buffer += ' ';
        break;
      case Markup.noteStart: {
        const end = marked.indexOf(Markup.noteEnd, i + 1);
        if (end >= 0) i = end;
        break;
      }
      default:
        buffer += char;
    }
  }
  flush();
  return runs;
}

/** A word, with the apostrophes and hyphens inside it. */
const word = /[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*/gu;

/** A word as it is compared: "LORD’s" and "Lord's" are the same word. */
function plain(text: string): string {
  return text.toLowerCase().replace(/’/g, "'");
}

/** A run cut into its words and what lies between them. */
export interface RunPiece {
  readonly text: string;
  /** Which word of the verse this is, counting from 0; -1 for what is not a word. */
  readonly word: number;
}

/**
 * The pieces of each run, in order, the words numbered through the whole
 * verse — the same numbering `wordsOf` gives.
 */
export function runPieces(runs: readonly MarkedRun[]): RunPiece[][] {
  let index = 0;
  return runs.map((run) => {
    const pieces: RunPiece[] = [];
    let cursor = 0;
    for (const match of run.text.matchAll(word)) {
      if (match.index > cursor) pieces.push({ text: run.text.substring(cursor, match.index), word: -1 });
      pieces.push({ text: match[0], word: index++ });
      cursor = match.index + match[0].length;
    }
    if (cursor < run.text.length) pieces.push({ text: run.text.substring(cursor), word: -1 });
    return pieces;
  });
}

/** The words of a verse, as they are compared. */
export function wordsOf(runs: readonly MarkedRun[]): string[] {
  const words: string[] = [];
  for (const run of runs) {
    for (const match of run.text.matchAll(word)) words.push(plain(match[0]));
  }
  return words;
}

/** Past this many cells the comparison is not worth the wait; nothing is marked. */
const tooMany = 250_000;

/**
 * Which words of `other` are not in `base`, read in order: the words a
 * reader of `base` would notice were different. Found by the longest run
 * of words the two have in common, in the same order; everything in
 * `other` outside it is marked.
 *
 * Returns the positions in `other`. Empty where either has no words, or
 * the two are too long to compare.
 */
export function differingWords(base: readonly string[], other: readonly string[]): Set<number> {
  const marked = new Set<number>();
  const n = base.length;
  const m = other.length;
  if (n === 0 || m === 0 || n * m > tooMany) return marked;
  // lengths[i][j]: the longest common run of base[i..] and other[j..].
  const width = m + 1;
  const lengths = new Uint16Array((n + 1) * width);
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      lengths[i * width + j] =
        base[i] === other[j]
          ? lengths[(i + 1) * width + j + 1] + 1
          : Math.max(lengths[(i + 1) * width + j], lengths[i * width + j + 1]);
    }
  }
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (base[i] === other[j]) {
      i++;
      j++;
    } else if (lengths[(i + 1) * width + j] >= lengths[i * width + j + 1]) {
      i++;
    } else {
      marked.add(j++);
    }
  }
  for (; j < m; j++) marked.add(j);
  return marked;
}

/**
 * Whether marking differences between two translations means anything:
 * between two languages every word differs, and marking all of them says
 * nothing.
 */
export function comparable(languageA: string, languageB: string): boolean {
  const primary = (tag: string) => tag.toLowerCase().split(/[-_]/)[0];
  return primary(languageA) === primary(languageB);
}
