import { gzipSync } from 'fflate';
import { describe, expect, it } from 'vitest';
import { CrossReferences, decodeCrossReferences } from '../src/data/crossReferences';
import { BibFile } from '../src/model/bibFile';
import { Reference } from '../src/model/bible';
import { FormatException } from '../src/model/byteIo';
import { XrefAnchor, XrefCodec, XrefEntry, XrefRange } from '../src/model/xrefCodec';
import { fixtureXrefs, packXrefs, sampleBible } from './fixtures';
import { FsAssetBundle } from './fsAssets';

/** A fixture in the real shape: two anchors on Genesis 1:1. */
const fixtureEntries = (): XrefEntry[] => [
  new XrefEntry({
    book: 0,
    chapter: 1,
    verse: 1,
    anchors: [
      new XrefAnchor({
        phrase: 'beginning',
        ranges: [
          new XrefRange({ book: 42, chapter: 1, verse: 1, endVerse: 3 }),
          new XrefRange({ book: 57, chapter: 1, verse: 10, endVerse: 10 }),
        ],
      }),
      new XrefAnchor({
        phrase: 'God',
        ranges: [new XrefRange({ book: 18, chapter: 19, verse: 1, endVerse: 1 })],
      }),
    ],
  }),
  new XrefEntry({
    book: 42,
    chapter: 3,
    verse: 16,
    anchors: [
      new XrefAnchor({
        phrase: 'loved',
        ranges: [new XrefRange({ book: 44, chapter: 5, verse: 8, endVerse: 8 })],
      }),
    ],
  }),
];

const packed = (entries: XrefEntry[]) => gzipSync(XrefCodec.encode(entries));

class Bundle {
  loads = 0;
  constructor(private readonly bytes: Uint8Array) {}
  async load(key: string): Promise<Uint8Array> {
    this.loads++;
    if (key !== CrossReferences.assetPath) throw new Error(`no ${key}`);
    return this.bytes;
  }
  async loadString(key: string): Promise<string> {
    return new TextDecoder().decode(await this.load(key));
  }
}

describe('the binary the references ship in', () => {
  it('survives a round trip', () => {
    const restored = XrefCodec.decode(XrefCodec.encode(fixtureEntries()));

    expect(restored).toHaveLength(2);
    const genesis = restored[0];
    expect(genesis.book).toBe(0);
    expect(genesis.chapter).toBe(1);
    expect(genesis.verse).toBe(1);
    expect(genesis.anchors.map((a) => a.phrase)).toEqual(['beginning', 'God']);
    expect(genesis.passages).toBe(3);

    const first = genesis.anchors[0].ranges[0];
    expect(first.book).toBe(42);
    expect(first.verse).toBe(1);
    expect(first.endVerse).toBe(3);
    expect(first.isRange).toBe(true);
    expect(genesis.anchors[0].ranges[1].isRange).toBe(false);
  });

  it('a phrase repeated across verses is stored once', () => {
    // The table of phrases is what keeps 300,000 references to a megabyte.
    const many: XrefEntry[] = [];
    for (let verse = 1; verse <= 200; verse++) {
      many.push(
        new XrefEntry({
          book: 0,
          chapter: 1,
          verse,
          anchors: [
            new XrefAnchor({
              phrase: 'the LORD God of Israel',
              ranges: [new XrefRange({ book: 1, chapter: 2, verse: 3, endVerse: 3 })],
            }),
          ],
        }),
      );
    }

    const bytes = XrefCodec.encode(many);
    expect(bytes.length).toBeLessThan(200 * 'the LORD God of Israel'.length);
    expect(XrefCodec.decode(bytes).at(-1)!.anchors[0].phrase).toBe('the LORD God of Israel');
  });

  it('something that is not the asset is refused', () => {
    expect(() => XrefCodec.decode(new Uint8Array([1, 2, 3, 4, 5]))).toThrow(FormatException);
  });

  it('a future version is refused by number', () => {
    const bytes = XrefCodec.encode(fixtureEntries());
    bytes[3] = XrefCodec.version + 1;
    expect(() => XrefCodec.decode(bytes)).toThrow(FormatException);
  });
});

describe('looking them up', () => {
  it('a verse finds its anchors, and one without them finds none', async () => {
    const xrefs = new CrossReferences(new Bundle(packed(fixtureEntries())));
    await xrefs.load();

    expect(xrefs.isLoaded).toBe(true);
    const anchors = xrefs.forVerse(new Reference('GEN', 1, 1));
    expect(anchors.map((a) => a.phrase)).toEqual(['beginning', 'God']);
    expect(xrefs.countFor(new Reference('GEN', 1, 1))).toBe(3);
    expect(xrefs.forVerse(new Reference('GEN', 1, 2))).toEqual([]);
    expect(xrefs.countFor(new Reference('GEN', 1, 2))).toBe(0);
    expect(xrefs.forVerse(new Reference('JHN', 3, 16))).toHaveLength(1);
  });

  it('a chapter reference with no verse asks for nothing', async () => {
    const xrefs = new CrossReferences(new Bundle(packed(fixtureEntries())));
    await xrefs.load();

    expect(xrefs.forVerse(new Reference('GEN', 1))).toEqual([]);
  });

  it('nothing is read twice', async () => {
    const bundle = new Bundle(packed(fixtureEntries()));
    const xrefs = new CrossReferences(bundle);

    await Promise.all([xrefs.load(), xrefs.load()]);
    await xrefs.load();

    expect(bundle.loads).toBe(1);
  });

  it('a missing asset leaves the app working, quietly', async () => {
    const xrefs = new CrossReferences(new Bundle(new Uint8Array(0)));
    await xrefs.load();

    expect(xrefs.forVerse(new Reference('GEN', 1, 1))).toEqual([]);
  });

  it('the deuterocanon is not in the numbering', () => {
    // The asset numbers the sixty-six, so Tobit has no index and asking
    // for it must not answer with some other book's references.
    expect(CrossReferences.indexOfBook('GEN')).toBe(0);
    expect(CrossReferences.indexOfBook('MAL')).toBe(38);
    expect(CrossReferences.indexOfBook('MAT')).toBe(39);
    expect(CrossReferences.indexOfBook('REV')).toBe(65);
    expect(CrossReferences.indexOfBook('TOB')).toBe(-1);
    expect(CrossReferences.bookAt(65)).toBe('REV');
    expect(CrossReferences.bookAt(66)).toBeNull();
    expect(CrossReferences.bookAt(-1)).toBeNull();
  });
});

describe('the asset that ships', () => {
  it('is readable and covers the canon', async () => {
    const entries = decodeCrossReferences(await new FsAssetBundle().load(CrossReferences.assetPath));
    expect(entries.length).toBeGreaterThan(20000);

    const byKey = new Map(entries.map((entry) => [entry.key, entry]));
    const genesis = byKey.get(XrefCodec.keyOf(0, 1, 1))!;
    expect(genesis.anchors.length).toBeGreaterThan(0);
    expect(genesis.anchors[0].phrase.length).toBeGreaterThan(0);

    // John 3:16 is the best-known verse in the book; it has references.
    expect(byKey.get(XrefCodec.keyOf(42, 3, 16))!.passages).toBeGreaterThan(0);

    // Every range points somewhere inside the canon. Checked in one pass and
    // asserted once: an `expect` per range is tens of thousands of matcher
    // calls, which is slow enough to time out under a full-suite run.
    const astray: string[] = [];
    for (const entry of entries.slice(0, 2000)) {
      for (const anchor of entry.anchors) {
        for (const range of anchor.ranges) {
          if (range.book < 0 || range.book > 65 || range.chapter <= 0 || range.verse <= 0 || range.endVerse < range.verse) {
            astray.push(`${entry.key}: ${range.book} ${range.chapter}:${range.verse}-${range.endVerse}`);
          }
        }
      }
    }
    expect(astray).toEqual([]);
  }, 20000);

  it('answers Psalm 23:1 through the loader', async () => {
    const xrefs = new CrossReferences(new FsAssetBundle());
    await xrefs.load();

    expect(xrefs.isLoaded).toBe(true);
    expect(xrefs.countFor(new Reference('PSA', 23, 1))).toBeGreaterThan(0);
    expect(xrefs.forVerse(new Reference('PSA', 23, 1))[0].phrase.length).toBeGreaterThan(0);
    expect(xrefs.forVerse(new Reference('TOB', 1, 1))).toEqual([]);
  });
});

describe('a translation that brings its own', () => {
  it('reads them out of the chunk, with no asset anywhere', () => {
    const own = CrossReferences.fromChunk(packXrefs(fixtureXrefs));

    expect(own).not.toBeNull();
    expect(own!.forVerse(new Reference('GEN', 1, 1))).toHaveLength(1);
    expect(own!.countFor(new Reference('GEN', 1, 1))).toBe(2);
    expect(own!.forVerse(new Reference('GEN', 1, 2))).toEqual([]);
  });

  it('a chunk that is not a set of references costs only the set', () => {
    expect(CrossReferences.fromChunk(new Uint8Array([1, 2, 3, 4]))).toBeNull();
    expect(CrossReferences.fromChunk(new Uint8Array(0))).toBeNull();
  });

  it('an empty set is no set', () => {
    expect(CrossReferences.fromChunk(packXrefs([]))).toBeNull();
  });

  it('a .bib keeps them through a rewrite', () => {
    const refs = packXrefs(fixtureXrefs);
    const bible = sampleBible();

    const attached = BibFile.encode(bible, { carry: new Map([[XrefCodec.chunkTag, refs]]) });
    expect(BibFile.tags(attached)).toContain('xref');

    // Re-encoding what was read must not drop them: the Bible carries
    // the chunks it came with.
    const reopened = BibFile.decode(attached);
    expect(reopened.extras.get(XrefCodec.chunkTag)).toBeDefined();
    const again = BibFile.encode(reopened);
    expect(BibFile.tags(again)).toContain('xref');
    expect(
      CrossReferences.fromChunk(BibFile.decode(again).extras.get(XrefCodec.chunkTag)!)!.forVerse(
        new Reference('GEN', 1, 1),
      ),
    ).toHaveLength(1);
  });

  it('and they can be dropped deliberately', () => {
    const attached = BibFile.decode(
      BibFile.encode(sampleBible(), { carry: new Map([[XrefCodec.chunkTag, packXrefs(fixtureXrefs)]]) }),
    );

    expect(BibFile.tags(BibFile.encode(attached, { carry: new Map() }))).not.toContain('xref');
  });

  it('is preferred over the bundled set, which is withheld where the numbering differs', () => {
    const bundled = new CrossReferences(null);
    const plain = sampleBible();
    expect(CrossReferences.forTranslation(plain, bundled, true)).toBe(bundled);
    expect(CrossReferences.forTranslation(plain, bundled, false)).toBeNull();

    const withOwn = BibFile.decode(
      BibFile.encode(plain, { carry: new Map([[XrefCodec.chunkTag, packXrefs(fixtureXrefs)]]) }),
    );
    const chosen = CrossReferences.forTranslation(withOwn, bundled, false);
    expect(chosen).not.toBe(bundled);
    expect(chosen!.countFor(new Reference('GEN', 1, 1))).toBe(2);
  });
});
