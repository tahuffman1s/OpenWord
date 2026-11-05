import { gunzipSync } from 'fflate';
import { type AssetBundle, rootBundle } from '../infra/assets';
import type { Bible, Reference } from '../model/bible';
import { BookMeta, BookSection } from '../model/bookMeta';
import { type XrefAnchor, XrefCodec, type XrefEntry } from '../model/xrefCodec';

/**
 * Where else in Scripture a verse is taken up.
 *
 * Three hundred thousand references, from the Treasury of Scripture
 * Knowledge, each hung on the phrase of the verse that prompted it. Read on
 * demand and kept afterwards: nothing wants them until a verse is opened.
 */
export class CrossReferences {
  /**
   * `undefined` means "no bundle given, so use the app's"; `null` means
   * "no bundle at all", which is what a set handed over as bytes has.
   */
  constructor(bundle?: AssetBundle | null) {
    this.bundle = bundle === undefined ? rootBundle : bundle;
  }

  /**
   * The references a translation brought with it, in its own `xref`
   * chunk, already in hand.
   *
   * A set of its own is better than the bundled one in every way that
   * matters: it is anchored to that translation's own verse numbering, so
   * it is right even where the bundled English set would land on the
   * wrong verse, and it needs no asset. Answers null where the bytes are
   * not readable, so a bad chunk costs the references and nothing else.
   */
  static fromChunk(bytes: Uint8Array): CrossReferences | null {
    try {
      const entries = XrefCodec.unpack(bytes);
      if (entries.length === 0) return null;
      const own = new CrossReferences(null);
      own.byVerse = new Map(entries.map((entry) => [entry.key, entry]));
      return own;
    } catch (error) {
      console.warn(`OpenWord: a translation's own references are unreadable: ${error}`);
      return null;
    }
  }

  /**
   * The cross-references to use for a translation: its own where its file
   * brought them, the bundled English set where its numbering allows
   * (`anchored`), and none at all otherwise.
   *
   * The same rule the Flutter reader applies in its `_references` getter;
   * here so every screen that wants references makes the same choice.
   */
  static forTranslation(bible: Bible, bundled: CrossReferences, anchored: boolean): CrossReferences | null {
    const chunk = bible.extras.get(CrossReferences.chunkTag);
    const own = chunk === undefined ? null : CrossReferences.fromChunk(chunk);
    return own ?? (anchored ? bundled : null);
  }

  static readonly assetPath = 'assets/refs/xrefs.owx.gz';

  /** The tag a translation's own references travel under. */
  static readonly chunkTag = XrefCodec.chunkTag;

  /** Shown wherever the references are, as the licence requires. */
  static readonly attribution =
    'Cross-references from CrossReferences.org, after the Treasury of Scripture Knowledge, CC BY 4.0.';

  /**
   * Anything smaller than this was decoded where it stood in Flutter, so
   * that a test fixture did not wait on an isolate. The PWA decodes inline
   * either way and leaves a worker to the caller; the threshold is kept
   * for whoever adds one.
   */
  static readonly isolateAbove = 64 * 1024;

  private readonly bundle: AssetBundle | null;
  private byVerse: Map<number, XrefEntry> | null = null;
  private loading: Promise<Map<number, XrefEntry>> | null = null;

  get isLoaded(): boolean {
    return this.byVerse !== null;
  }

  load(): Promise<Map<number, XrefEntry>> {
    const loaded = this.byVerse;
    if (loaded !== null) return Promise.resolve(loaded);
    return (this.loading ??= this.read().then((entries) => {
      this.byVerse = entries;
      return entries;
    }));
  }

  /**
   * The anchors of one verse, or nothing where it has none. Answers only
   * what is already in memory; call `load` first.
   */
  forVerse(reference: Reference): XrefAnchor[] {
    const entries = this.byVerse;
    const verse = reference.verse;
    if (entries === null || verse === null) return [];
    const book = CrossReferences.indexOfBook(reference.bookCode);
    if (book < 0) return [];
    return entries.get(XrefCodec.keyOf(book, reference.chapter, verse))?.anchors ?? [];
  }

  /**
   * How many passages a verse points at, for the reader deciding whether to
   * open them.
   */
  countFor(reference: Reference): number {
    let total = 0;
    for (const anchor of this.forVerse(reference)) {
      total += anchor.ranges.length;
    }
    return total;
  }

  private async read(): Promise<Map<number, XrefEntry>> {
    const bundle = this.bundle;
    if (bundle === null) return new Map();
    try {
      const bytes = await bundle.load(CrossReferences.assetPath);
      const entries = decodeCrossReferences(bytes);
      return new Map(entries.map((entry) => [entry.key, entry]));
    } catch (error) {
      console.warn(`OpenWord: could not read the cross-references: ${error}`);
      return new Map();
    }
  }

  /** The canonical position of a book, which is how the asset numbers them. */
  static indexOfBook(code: string): number {
    return canon.indexOf(code);
  }

  static bookAt(index: number): string | null {
    return index >= 0 && index < canon.length ? canon[index] : null;
  }
}

const canon: readonly string[] = BookMeta.all
  .filter((meta) => meta.section !== BookSection.deuterocanon)
  .map((meta) => meta.code);

/**
 * Unpacks the asset. Top-level and free of the DOM, so a worker can import
 * it.
 */
export function decodeCrossReferences(bytes: Uint8Array): XrefEntry[] {
  return XrefCodec.decode(gunzipSync(bytes));
}
