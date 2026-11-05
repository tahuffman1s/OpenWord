import { beforeAll, describe, expect, it } from 'vitest';
import { type AttachedLayers, attachStudyLayers, StudyLayers } from '../src/data/bibExport';
import { CrossReferences } from '../src/data/crossReferences';
import { BibFile, BibFormatException } from '../src/model/bibFile';
import { Bible, Reference } from '../src/model/bible';
import { BookSection } from '../src/model/bookMeta';
import { StrongsCodec, StrongsNumber, StrongsReader, trimOriginalsTo } from '../src/model/strongsCodec';
import { originalsCanon, originalsKeysOf } from '../src/model/strongsScope';
import { XrefCodec } from '../src/model/xrefCodec';
import { fixtureXrefs, packOriginals, packXrefs, sampleBible } from './fixtures';

const references = packXrefs(fixtureXrefs);
const refsOnly = (): StudyLayers => new StudyLayers({ crossReferences: references });

describe('a .bib saved with its cross-references in it', () => {
  let plain: Uint8Array;
  let withRefs: Uint8Array;

  beforeAll(() => {
    plain = BibFile.encode(sampleBible());
    withRefs = attachStudyLayers(plain, refsOnly()).bytes;
  });

  it('gains the chunk, and the Scripture is untouched', () => {
    expect(BibFile.tags(plain)).not.toContain(XrefCodec.chunkTag);
    expect(BibFile.tags(withRefs)).toContain(XrefCodec.chunkTag);

    const before = BibFile.decode(plain);
    const after = BibFile.decode(withRefs, true);
    expect(after.translation.id).toBe(before.translation.id);
    for (let i = 0; i < before.books.length; i++) {
      expect(after.books[i].code).toBe(before.books[i].code);
      expect(after.books[i].chapters.map((c) => c.verseText(1))).toEqual(
        before.books[i].chapters.map((c) => c.verseText(1)),
      );
    }
  });

  it('and the references read back as the app would read them', () => {
    const chunk = BibFile.decode(withRefs).extras.get(XrefCodec.chunkTag);
    expect(chunk).toBeDefined();
    const read = CrossReferences.fromChunk(chunk!);
    expect(read).not.toBeNull();
    expect(read!.forVerse(new Reference('GEN', 1, 1)).length).toBeGreaterThan(0);
  });

  it('is bigger by about what the references weigh', () => {
    expect(withRefs.length).toBeGreaterThan(plain.length);
    // The chunk is stored as it came, so the growth is its own size and
    // a chunk header, not a multiple of it.
    expect(withRefs.length - plain.length).toBeLessThan(references.length + 64);
  });

  it('and is the same bytes every time, as encoding is', () => {
    expect(attachStudyLayers(plain, refsOnly()).bytes).toEqual(withRefs);
  });

  it('keeps whatever chunks the file already carried', () => {
    // A rewrite that dropped a translation's own references would be the
    // worst kind of bug to find.
    const carrying = BibFile.encode(sampleBible(), { carry: new Map([['zzzz', new Uint8Array([1, 2, 3])]]) });
    const out = attachStudyLayers(carrying, refsOnly()).bytes;
    expect(BibFile.tags(out)).toEqual(expect.arrayContaining([XrefCodec.chunkTag, 'zzzz']));
    expect([...BibFile.decode(out).extras.get('zzzz')!]).toEqual([1, 2, 3]);
  });
});

describe('and refused rather than written wrong', () => {
  it('an empty set of references is not attached', () => {
    expect(() =>
      attachStudyLayers(BibFile.encode(sampleBible()), new StudyLayers({ crossReferences: packXrefs([]) })),
    ).toThrow(BibFormatException);
  });

  it('nor is anything that is not a set of references', () => {
    expect(() =>
      attachStudyLayers(
        BibFile.encode(sampleBible()),
        new StudyLayers({ crossReferences: new Uint8Array(64).fill(7) }),
      ),
    ).toThrow();
  });

  it('and a file that is not a .bib is not rewritten', () => {
    expect(() => attachStudyLayers(new Uint8Array(64).fill(7), refsOnly())).toThrow(BibFormatException);
  });
});

/**
 * The Hebrew and Greek travelling inside a `.bib`, which is what lets a
 * file stand on its own and what lets a differently-numbered Bible have
 * them at all.
 */
describe('a .bib saved with its Hebrew and Greek in it', () => {
  const originals = packOriginals();
  let plain: Uint8Array;
  let withOriginals: Uint8Array;
  let written: AttachedLayers;

  beforeAll(() => {
    plain = BibFile.encode(sampleBible());
    written = attachStudyLayers(plain, new StudyLayers({ originals }));
    withOriginals = written.bytes;
  });

  it('gains the chunk, and says what went in', () => {
    expect(BibFile.tags(plain)).not.toContain(StrongsCodec.chunkTag);
    expect(BibFile.tags(withOriginals)).toContain(StrongsCodec.chunkTag);
    expect(written.verses).toBeGreaterThan(0);
    expect(written.entries).toBeGreaterThan(0);
    // Nothing was asked of the references, so nothing was written.
    expect(written.references).toBe(0);
    expect(BibFile.tags(withOriginals)).not.toContain(XrefCodec.chunkTag);
  });

  it('and the words read back, pointing and parsing and all', () => {
    const chunk = BibFile.decode(withOriginals).extras.get(StrongsCodec.chunkTag);
    expect(chunk).toBeDefined();
    const layer = StrongsCodec.unpack(chunk!);

    const genesis = originalsCanon.indexOf('GEN');
    const words = layer.wordsAt(StrongsCodec.verseKey(genesis, 1, 1));
    expect(words.map((w) => w.text)).toEqual(['בְּרֵאשִׁית', 'בָּרָא', 'אֱלֹהִים']);
    expect(words[0].strongs!.key).toBe(new StrongsNumber('H', 7225).key);
    expect(words[0].morphology).toBe('Noun common feminine singular absolute');

    // The dictionary came too, or a number would be a number and
    // nothing else.
    const entry = layer.entryFor(new StrongsNumber('H', 7225));
    expect(entry).not.toBeNull();
    expect(entry!.renderings.length).toBeGreaterThan(0);
  });

  it('and the concordance names only verses the file has', () => {
    const layer = StrongsCodec.unpack(BibFile.decode(withOriginals).extras.get(StrongsCodec.chunkTag)!);
    const everywhere = layer.occurrences(new StrongsNumber('H', 430));
    expect(everywhere.length).toBeGreaterThan(0);
    for (const key of everywhere) {
      expect(layer.hasVerse(key), 'the concordance points at a verse the layer dropped').toBe(true);
    }
  });

  it('and the Scripture is untouched', () => {
    const before = BibFile.decode(plain);
    const after = BibFile.decode(withOriginals, true);
    expect(after.books.map((b) => b.code)).toEqual(before.books.map((b) => b.code));
    expect(after.bookByCode('GEN')!.chapter(1)!.verseText(1)).toBe(before.bookByCode('GEN')!.chapter(1)!.verseText(1));
  });

  it('both layers can sit in the same file', () => {
    const both = attachStudyLayers(plain, new StudyLayers({ crossReferences: packXrefs(fixtureXrefs), originals }));
    expect(BibFile.tags(both.bytes)).toEqual(expect.arrayContaining([XrefCodec.chunkTag, StrongsCodec.chunkTag]));
    expect(both.references).toBeGreaterThan(0);
    expect(both.verses).toBeGreaterThan(0);
  });
});

describe('a layer is cut to the verses the file has', () => {
  const originals = packOriginals();
  let whole: StrongsReader;

  beforeAll(() => {
    whole = StrongsCodec.unpack(originals);
  });

  it('a New Testament carries no Hebrew', () => {
    const full = sampleBible();
    const newTestament = new Bible({
      translation: full.translation,
      books: full.books.filter((book) => book.section === BookSection.newTestament),
    });
    expect(newTestament.books.length).toBeGreaterThan(0);

    const trimmed = StrongsReader.parse(trimOriginalsTo(whole, originalsKeysOf(newTestament)));

    const genesis = originalsCanon.indexOf('GEN');
    const matthew = originalsCanon.indexOf('MAT');
    expect(
      trimmed.hasVerse(StrongsCodec.verseKey(genesis, 1, 1)),
      'Genesis is not in this Bible, so its Hebrew is dead weight',
    ).toBe(false);
    expect(trimmed.hasVerse(StrongsCodec.verseKey(matthew, 1, 1))).toBe(true);

    // And the dictionary shrinks with it: an entry nothing left reaches
    // is carried for nobody.
    expect(trimmed.entryCount).toBeLessThan(whole.entryCount);
    expect(trimmed.entryFor(new StrongsNumber('H', 7225)), 'no word left in the file uses it').toBeNull();
    expect(trimmed.entryFor(new StrongsNumber('G', 976))).not.toBeNull();
  });

  it('and a Bible with nothing behind it is refused, not written empty', () => {
    const full = sampleBible();
    const deutero = new Bible({
      translation: full.translation,
      books: full.books.filter((book) => book.section === BookSection.deuterocanon),
    });
    if (deutero.books.length === 0) return;
    expect(() => attachStudyLayers(BibFile.encode(deutero), new StudyLayers({ originals }))).toThrow(
      BibFormatException,
    );
  });
});

it('nothing asked for is nothing written', () => {
  expect(() => attachStudyLayers(BibFile.encode(sampleBible()), new StudyLayers())).toThrow(BibFormatException);
});
