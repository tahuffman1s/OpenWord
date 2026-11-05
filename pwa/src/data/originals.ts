import { type AssetBundle, rootBundle } from '../infra/assets';
import { type Bible, Reference } from '../model/bible';
import { BookMeta, BookSection } from '../model/bookMeta';
import {
  type OriginalWord,
  StrongsCodec,
  type StrongsEntry,
  type StrongsNumber,
  type StrongsReader,
} from '../model/strongsCodec';

/**
 * The Hebrew and Greek behind the English, with Strong's numbers.
 *
 * Keyed by verse rather than by word, which is what lets it work under any
 * translation — the ones that ship, and any the reader imports. The words
 * of Genesis 1:1 are the same whichever English is on top of them.
 */
export class Originals {
  constructor(bundle?: AssetBundle) {
    this.bundle = bundle ?? rootBundle;
  }

  /** A layer already in hand, which has no bundle to go back to. */
  private static over(reader: StrongsReader): Originals {
    const own = new Originals();
    own.bundle = null;
    own.reader = reader;
    return own;
  }

  /**
   * The Hebrew and Greek a translation brought with it, in its own `strg`
   * chunk.
   *
   * A layer of its own is better than the bundled one in the way that
   * matters most: it is keyed to that translation's own verse numbering,
   * so it is right even where the bundled layer would hand back the words
   * of a neighbouring verse. Answers null where the bytes are not
   * readable, so a bad chunk costs the originals and nothing else.
   */
  static async fromChunk(bytes: Uint8Array): Promise<Originals | null> {
    try {
      const reader = decodeOriginals(bytes);
      return reader.verseCount === 0 ? null : Originals.over(reader);
    } catch (error) {
      console.warn(`OpenWord: a translation's own Hebrew and Greek are unreadable: ${error}`);
      return null;
    }
  }

  /**
   * The original-language layer to use for a translation: its own where
   * its file carries one, the bundled layer where its numbering allows
   * (`anchored`), and none at all otherwise.
   *
   * The same rule the Flutter reader applies in its `_originalLanguages`
   * getter. Unpacking a translation's own layer is measured in megabytes,
   * so it is read eagerly when the translation changes rather than when a
   * verse is first tapped.
   */
  static async forTranslation(bible: Bible, bundled: Originals, anchored: boolean): Promise<Originals | null> {
    const chunk = bible.extras.get(Originals.chunkTag);
    const own = chunk === undefined ? null : await Originals.fromChunk(chunk);
    return own ?? (anchored ? bundled : null);
  }

  /** The tag a translation's own layer travels under. */
  static readonly chunkTag = StrongsCodec.chunkTag;

  static readonly assetPath = 'assets/strongs/originals.ows.gz';

  static readonly attribution =
    'Hebrew from the Open Scriptures Hebrew Bible (CC BY 4.0); Greek from ' +
    'the Byzantine Majority Text, Robinson–Pierpont (public domain); ' +
    "Strong's dictionaries from Open Scriptures (CC BY-SA 4.0).";

  /**
   * Below this the asset was unpacked where it stood in Flutter, so a
   * fixture did not wait on an isolate. The PWA decodes inline either way
   * and leaves a worker to the caller; the threshold is kept for whoever
   * adds one.
   */
  static readonly isolateAbove = 64 * 1024;

  private bundle: AssetBundle | null;
  private reader: StrongsReader | null = null;
  private loading: Promise<StrongsReader | null> | null = null;

  /** The layer itself, where it has been read. */
  get strongsReader(): StrongsReader | null {
    return this.reader;
  }

  get isLoaded(): boolean {
    return this.reader !== null;
  }

  load(): Promise<StrongsReader | null> {
    const loaded = this.reader;
    if (loaded !== null) return Promise.resolve(loaded);
    return (this.loading ??= this.read().then((reader) => {
      this.reader = reader;
      return reader;
    }));
  }

  /** The original words of a verse, in their own order. */
  wordsFor(reference: Reference): OriginalWord[] {
    const reader = this.reader;
    const verse = reference.verse;
    if (reader === null || verse === null) return [];
    const book = canon.indexOf(reference.bookCode);
    if (book < 0) return [];
    return reader.wordsAt(StrongsCodec.verseKey(book, reference.chapter, verse));
  }

  /**
   * Whether a verse has an original behind it at all. The deuterocanonical
   * books do not: they are neither in the Hebrew Bible nor the Greek New
   * Testament as this app carries them.
   */
  hasOriginal(reference: Reference): boolean {
    return this.wordsFor(reference).length > 0;
  }

  entryFor(number: StrongsNumber): StrongsEntry | null {
    return this.reader?.entryFor(number) ?? null;
  }

  occurrenceCount(number: StrongsNumber): number {
    return this.reader?.occurrenceCount(number) ?? 0;
  }

  /** Every verse a number occurs in, as references. */
  occurrences(number: StrongsNumber): Reference[] {
    const reader = this.reader;
    if (reader === null) return [];
    const found: Reference[] = [];
    for (const key of reader.occurrences(number)) {
      const reference = Originals.referenceFor(key);
      if (reference !== null) found.push(reference);
    }
    return found;
  }

  /**
   * Which of a verse's original words an English word most likely came
   * from.
   *
   * Strong's lists the words the King James translators used for each
   * number, so a tapped word is looked for in those lists. It is a guess
   * where the translation is not the KJV, so where nothing matches this
   * answers nothing rather than something plausible.
   */
  matchesFor(words: readonly OriginalWord[], englishWord: string): number[] {
    const needle = englishWord.toLowerCase().replace(/[^a-z'\-]/g, '');
    if (needle.length < 2) return [];

    const exact: number[] = [];
    const stemmed: number[] = [];
    for (let i = 0; i < words.length; i++) {
      const number = words[i].strongs;
      if (number === null) continue;
      const entry = this.entryFor(number);
      if (entry === null) continue;
      for (const rendering of entry.renderings) {
        if (rendering === needle) {
          exact.push(i);
          break;
        }
        if (Originals.sameStem(rendering, needle)) {
          stemmed.push(i);
          break;
        }
      }
    }
    return exact.length > 0 ? exact : stemmed;
  }

  /**
   * Rough English stemming: enough to tie "loved" to "love" and "waters"
   * to "water", and no more. Getting clever here would produce confident
   * wrong answers.
   */
  private static sameStem(a: string, b: string): boolean {
    const rootA = Originals.stem(a);
    const rootB = Originals.stem(b);
    if (rootA.length < 3 || rootB.length < 3) return false;
    if (rootA === rootB) return true;
    // English drops a silent e before -ed and -ing: "create" and "created"
    // stem to "create" and "creat", which are the same word.
    return rootA === `${rootB}e` || rootB === `${rootA}e`;
  }

  private static stem(word: string): string {
    for (const ending of ['ing', 'edly', 'est', 'eth', 'ed', 'es', 's']) {
      if (word.length > ending.length + 2 && word.endsWith(ending)) {
        return word.substring(0, word.length - ending.length);
      }
    }
    return word;
  }

  private static referenceFor(key: number): Reference | null {
    const book = Math.trunc(key / 1000000);
    if (book < 0 || book >= canon.length) return null;
    return new Reference(canon[book], Math.trunc(key / 1000) % 1000, key % 1000);
  }

  private async read(): Promise<StrongsReader | null> {
    const bundle = this.bundle;
    if (bundle === null) return this.reader;
    try {
      const bytes = await bundle.load(Originals.assetPath);
      return decodeOriginals(bytes);
    } catch (error) {
      console.warn(`OpenWord: could not read the original languages: ${error}`);
      return null;
    }
  }
}

const canon: readonly string[] = BookMeta.all
  .filter((meta) => meta.section !== BookSection.deuterocanon)
  .map((meta) => meta.code);

/**
 * Unpacks the asset. Top-level and free of the DOM, so a worker can import
 * it.
 *
 * What comes back is a reader over the bytes rather than four hundred
 * thousand objects: a verse is decoded when it is looked at.
 */
export function decodeOriginals(bytes: Uint8Array): StrongsReader {
  return StrongsCodec.unpack(bytes);
}
