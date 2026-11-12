import type { Chapter, Reference } from './bible';

function sortedUnique(verses: Iterable<number>): number[] {
  return [...new Set(verses)].sort((a, b) => a - b);
}

/**
 * Several verses of one chapter chosen together, and how they are cited
 * and quoted.
 */
export const VerseSelection = {
  /**
   * The verses as a printed Bible cites them: "16–18, 20".
   *
   * Runs of consecutive verses collapse to a range; a gap starts a new
   * part, so a selection that skips a verse says so rather than claiming
   * it.
   */
  ranges(verses: Iterable<number>): string {
    const sorted = sortedUnique(verses);
    const parts: string[] = [];
    let i = 0;
    while (i < sorted.length) {
      let j = i;
      while (j + 1 < sorted.length && sorted[j + 1] === sorted[j] + 1) {
        j++;
      }
      parts.push(i === j ? `${sorted[i]}` : `${sorted[i]}–${sorted[j]}`);
      i = j + 1;
    }
    return parts.join(', ');
  },

  /** "John 3:16–18, 20". */
  citation(chapter: Reference, verses: Iterable<number>): string {
    return `${chapter.bookName} ${chapter.chapter}:${VerseSelection.ranges(verses)}`;
  },

  /**
   * The words of the verses, in order. Where the selection skips a verse
   * an ellipsis stands for it, as it would in a printed quotation.
   */
  text(chapter: Chapter, verses: Iterable<number>): string {
    const sorted = sortedUnique(verses);
    let buffer = '';
    let previous: number | null = null;
    for (const verse of sorted) {
      const words = chapter.verseText(verse).trim();
      if (words.length === 0) continue;
      if (previous !== null) {
        buffer += verse === previous + 1 ? ' ' : ' … ';
      }
      buffer += words;
      previous = verse;
    }
    return buffer;
  },

  /**
   * What is copied or shared as text: the words, then where they are
   * from and in which translation.
   */
  quotation(options: { chapter: Chapter; reference: Reference; verses: Iterable<number>; translation: string }): string {
    const verses = [...options.verses];
    const cite = VerseSelection.citation(options.reference, verses);
    return `${VerseSelection.text(options.chapter, verses)}\n\n— ${cite} (${options.translation})`;
  },
};
