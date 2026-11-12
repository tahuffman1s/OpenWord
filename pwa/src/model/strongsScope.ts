import type { Bible } from './bible';
import { BookMeta, BookSection } from './bookMeta';
import { StrongsCodec } from './strongsCodec';

/**
 * The books an original-language layer is keyed against, in the order its
 * verse keys number them.
 *
 * The deuterocanon is left out: those books are in neither the Hebrew
 * Bible nor the Greek New Testament as this app carries them, so they
 * have no original behind them to key.
 */
export const originalsCanon: readonly string[] = BookMeta.all
  .filter((meta) => meta.section !== BookSection.deuterocanon)
  .map((meta) => meta.code);

/**
 * Every verse of a Bible, as the keys an original-language layer uses.
 *
 * Free of the DOM so that a tool and a worker can both work this out,
 * and the one place that knows how a verse of a Bible maps to a key in
 * the layer — getting that wrong would silently hand back the words of
 * some other verse.
 */
export function originalsKeysOf(bible: Bible): Set<number> {
  const keys = new Set<number>();
  for (const book of bible.books) {
    const index = originalsCanon.indexOf(book.code);
    if (index < 0) continue;
    // From the outline, so working out what a Bible covers does not
    // unpack a word of it. A key that is asked for and is not in the
    // layer costs nothing: only what both have is kept.
    let position = 1;
    for (const number of book.chapterNumbers) {
      const verses = book.verseCountAt(position);
      for (let verse = 1; verse <= verses; verse++) {
        keys.add(StrongsCodec.verseKey(index, number, verse));
      }
      position++;
    }
  }
  return keys;
}
