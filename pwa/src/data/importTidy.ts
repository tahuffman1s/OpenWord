import { BibFile } from '../model/bibFile';
import { Bible } from '../model/bible';
import { stripBoilerplate } from '../model/boilerplate';

/**
 * What sweeping a `.bib` would take out of it, and the file that would
 * replace it.
 */
export class TidyResult {
  /** The rewritten file, or null when there was nothing to take out. */
  readonly bytes: Uint8Array | null;

  /** The lines it would drop, so a reader can say whether they should go. */
  readonly removed: readonly string[];

  readonly failure: string | null;

  constructor(init: { bytes?: Uint8Array | null; removed?: readonly string[]; failure?: string | null } = {}) {
    this.bytes = init.bytes ?? null;
    this.removed = init.removed ?? [];
    this.failure = init.failure ?? null;
  }

  static failed(reason: string): TidyResult {
    return new TidyResult({ failure: reason });
  }

  get foundSomething(): boolean {
    return this.bytes !== null && this.removed.length > 0;
  }
}

/**
 * Sweeps an already-imported translation, working from the `.bib` alone.
 *
 * This matters more than it looks. An import is a stored file, and
 * updating the app never touches it — so every fix the importer gains is
 * unreachable for a translation already on the shelf, and the reader has
 * no way of knowing that the copy they are reading predates any of them.
 * Re-importing would fix it and needs the EPUB, which the app did not
 * keep. The rule this uses needs no EPUB: it asks only whether a line
 * belongs to no verse and repeats across books, and the `.bib` answers
 * both.
 *
 * Top-level, and taking nothing but bytes, because a worker cannot carry
 * a Bible across: a book of a version 2 file inflates when it is first
 * read, which is a closure, and a closure does not cross.
 */
export function tidyBib(bytes: Uint8Array): TidyResult {
  let bible: Bible;
  try {
    bible = BibFile.decode(bytes, true);
  } catch (error) {
    return TidyResult.failed(errorText(error));
  }

  const swept = stripBoilerplate(bible.books);
  if (swept.isEmpty) return new TidyResult();

  try {
    const out = BibFile.encode(
      new Bible({
        translation: bible.translation,
        books: [...swept.books],
        // Whatever the file carried stays with it: a tidy that dropped a
        // translation's own cross-references would be a poor trade.
        extras: bible.extras,
      }),
    );
    // Read it back before offering to replace anything.
    BibFile.decode(out, true);
    return new TidyResult({ bytes: out, removed: swept.removed });
  } catch (error) {
    return TidyResult.failed(errorText(error));
  }
}

/** Dart's `'$error'`. */
function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
