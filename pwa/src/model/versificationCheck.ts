import { type Bible, Versification } from './bible';
import { BookSection } from './bookMeta';
import { englishVerseCounts } from './versificationTable';

/**
 * How a Bible's verse numbering compares with the one the app's own
 * verse-anchored data assumes.
 */
export class VersificationMatch {
  /** How many chapters were in both this Bible and the reference. */
  readonly compared: number;

  /** How many of those hold a different number of verses. */
  readonly differing: number;

  /** A few of them, worded for a reader. */
  readonly examples: readonly string[];

  constructor(init: { compared: number; differing: number; examples: readonly string[] }) {
    this.compared = init.compared;
    this.differing = init.differing;
    this.examples = init.examples;
  }

  get fraction(): number {
    return this.compared === 0 ? 0 : this.differing / this.compared;
  }

  /**
   * Too little of the Bible overlapped to say anything. A single-book
   * import, say, or one whose books were not recognised.
   */
  get isInconclusive(): boolean {
    return this.compared < VersificationMatch.minimumChapters;
  }

  /**
   * Whether this numbers its verses the way the bundled cross-references
   * and original-language layer do.
   */
  get matchesEnglish(): boolean {
    return !this.isInconclusive && this.fraction <= VersificationMatch.tolerance;
  }

  /** What to record in the file. */
  get versification(): string {
    return this.isInconclusive
      ? Versification.unknown
      : this.matchesEnglish
        ? Versification.english
        : Versification.other;
  }

  /**
   * Below this there is not enough overlap for a proportion to mean
   * anything; a Bible of one book would match or not on a handful of
   * chapters.
   */
  static readonly minimumChapters = 100;

  /**
   * Where the line sits, and why it sits there.
   *
   * Editions of the English Bible disagree with each other a little: the
   * three bundled here differ over 2 of 1189 chapters, 0.17%, which is
   * Romans' floating doxology. A different scheme is nothing like that
   * small — the Masoretic numbering counts a psalm's superscription as
   * its first verse, which moves something like a hundred chapters of the
   * Psalms on its own, and the Septuagint's psalm numbering moves more.
   * 2% is ten times the noise and a fraction of the signal.
   */
  static readonly tolerance = 0.02;

  toString(): string {
    return `${this.differing} of ${this.compared} chapters differ (${(this.fraction * 100).toFixed(1)}%)`;
  }
}

let referenceTable: Map<string, number[]> | null = null;

/**
 * Checks a Bible's verse numbering against the English Protestant scheme.
 *
 * This exists because everything anchored to a verse — the cross-
 * references, the Hebrew and Greek behind a verse — is anchored to one
 * numbering. Pointed at a Bible that numbers differently, they do not
 * fail; they quietly point at the wrong verse, which is worse. So an
 * import is measured against the scheme they assume, and where it does
 * not match, it is marked and they are withheld.
 *
 * Only the sixty-six books of the Protestant canon are compared. The
 * deuterocanonical books are numbered differently by English editions
 * that otherwise agree entirely, so including them would raise a false
 * alarm on an ordinary import.
 */
export const VersificationCheck = {
  get reference(): Map<string, number[]> {
    if (referenceTable === null) {
      referenceTable = new Map(
        Object.entries(englishVerseCounts).map(([code, counts]) => [
          code,
          counts.split(' ').map((part) => Number.parseInt(part, 10)),
        ]),
      );
    }
    return referenceTable;
  },

  against(bible: Bible): VersificationMatch {
    let compared = 0;
    let differing = 0;
    const examples: string[] = [];

    for (const book of bible.books) {
      if (book.section === BookSection.deuterocanon) continue;
      const expected = VersificationCheck.reference.get(book.code);
      if (expected === undefined) continue;

      const overlap = book.chapterCount < expected.length ? book.chapterCount : expected.length;
      for (let c = 1; c <= overlap; c++) {
        compared++;
        const found = book.verseCountAt(c);
        if (found === expected[c - 1]) continue;
        differing++;
        if (examples.length < 5) {
          examples.push(`${book.name} ${c} has ${found} ${found === 1 ? 'verse' : 'verses'}, not ${expected[c - 1]}`);
        }
      }

      // A book of the wrong length is a difference in itself, counted once
      // per chapter that is missing or spare.
      const extra = Math.abs(book.chapterCount - expected.length);
      if (extra > 0) {
        compared += extra;
        differing += extra;
        if (examples.length < 5) {
          examples.push(`${book.name} has ${book.chapterCount} chapters, not ${expected.length}`);
        }
      }
    }

    return new VersificationMatch({ compared, differing, examples });
  },
};
