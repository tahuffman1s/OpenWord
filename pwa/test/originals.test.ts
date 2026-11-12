import { describe, expect, it } from 'vitest';
import { decodeOriginals, Originals } from '../src/data/originals';
import { Reference } from '../src/model/bible';
import { StrongsCodec, StrongsEntry, StrongsNumber } from '../src/model/strongsCodec';
import { packOriginals } from './fixtures';
import { FsAssetBundle } from './fsAssets';

class Bundle {
  loads = 0;
  constructor(private readonly bytes: Uint8Array) {}
  async load(key: string): Promise<Uint8Array> {
    this.loads++;
    if (key !== Originals.assetPath) throw new Error(`no ${key}`);
    return this.bytes;
  }
  async loadString(key: string): Promise<string> {
    return new TextDecoder().decode(await this.load(key));
  }
}

async function loaded(): Promise<Originals> {
  const originals = new Originals(new Bundle(packOriginals()));
  await originals.load();
  return originals;
}

describe("a Strong's number", () => {
  it('is a language and a number, and reads both ways', () => {
    const number = new StrongsNumber('H', 430);
    expect(number.label).toBe('H430');
    expect(number.isHebrew).toBe(true);
    expect(StrongsNumber.fromKey(number.key).equals(number)).toBe(true);

    const greek = new StrongsNumber('G', 2316);
    expect(greek.isHebrew).toBe(false);
    expect(StrongsNumber.fromKey(greek.key)).toEqual(greek);
    // The two spaces must not collide: H2316 is not G2316.
    expect(greek.key === new StrongsNumber('H', 2316).key).toBe(false);
  });

  it('is parsed from what a reader would type', () => {
    expect(StrongsNumber.parse('H7225')).toEqual(new StrongsNumber('H', 7225));
    expect(StrongsNumber.parse('g2316')).toEqual(new StrongsNumber('G', 2316));
    expect(StrongsNumber.parse(' H 430 ')).toEqual(new StrongsNumber('H', 430));
    expect(StrongsNumber.parse('H0430')).toEqual(new StrongsNumber('H', 430));
    expect(StrongsNumber.parse('430')).toBeNull();
    expect(StrongsNumber.parse('Hello')).toBeNull();
    expect(StrongsNumber.parse('H0')).toBeNull();
  });
});

describe("Strong's usage lists", () => {
  const entry = (usage: string) =>
    new StrongsEntry({
      number: new StrongsNumber('H', 1),
      lemma: '',
      transliteration: '',
      pronunciation: '',
      derivation: '',
      definition: '',
      kjvUsage: usage,
    });

  it('are read past their editorial marks', () => {
    // Strong's writes "God (gods) (-dess, -ly)"; splitting on the comma
    // inside the brackets would give "god -dess", which matches nothing.
    const renderings = entry('angels, [idiom] exceeding, God (gods) (-dess, -ly), judges.').renderings;
    expect(renderings).toEqual(expect.arrayContaining(['angels', 'god', 'judges']));
    expect(entry('angels, God (gods) (-dess, -ly).').renderings).not.toContain('god -dess');
    // A bare X means "not rendered literally" and is not a word.
    expect(entry('X exceeding, God').renderings).toEqual(['exceeding', 'god']);
    expect(entry('(be-) love(-ed).').renderings).toEqual(['love']);
  });

  it('shows the first few as a gloss line', () => {
    expect(entry('angels, [idiom] exceeding, God (gods) (-dess, -ly), judges, mighty.').renderedAs).toBe(
      'angels, exceeding, god',
    );
  });
});

describe('the original behind a verse', () => {
  it('is found under any translation, by reference', async () => {
    const originals = await loaded();

    const words = originals.wordsFor(new Reference('GEN', 1, 1));
    expect(words).toHaveLength(3);
    expect(words[0].text).toBe('בְּרֵאשִׁית');
    expect(words[0].strongs).toEqual(new StrongsNumber('H', 7225));
    expect(words[0].morphology).toBe('Noun common feminine singular absolute');
    expect(words[2].strongs).toEqual(new StrongsNumber('H', 430));

    const greek = originals.wordsFor(new Reference('MAT', 1, 1));
    expect(greek).toHaveLength(1);
    expect(greek[0].text).toBe('βίβλος');
    expect(greek[0].strongs).toEqual(new StrongsNumber('G', 976));
  });

  it('is absent where there is none, without complaint', async () => {
    const originals = await loaded();

    expect(originals.wordsFor(new Reference('GEN', 1, 2))).toEqual([]);
    expect(originals.hasOriginal(new Reference('GEN', 1, 2))).toBe(false);
    expect(originals.hasOriginal(new Reference('GEN', 1, 1))).toBe(true);
    // The deuterocanon is neither Hebrew Bible nor Greek New Testament.
    expect(originals.wordsFor(new Reference('TOB', 1, 1))).toEqual([]);
    // A chapter reference is not a verse.
    expect(originals.wordsFor(new Reference('GEN', 1))).toEqual([]);
  });

  it('a missing asset leaves the app working, quietly', async () => {
    const originals = new Originals(new Bundle(new Uint8Array(0)));
    await originals.load();

    expect(originals.isLoaded).toBe(false);
    expect(originals.wordsFor(new Reference('GEN', 1, 1))).toEqual([]);
    expect(originals.entryFor(new StrongsNumber('H', 430))).toBeNull();
    expect(originals.occurrences(new StrongsNumber('H', 430))).toEqual([]);
  });

  it('is read once, however many times it is asked for', async () => {
    const bundle = new Bundle(packOriginals());
    const originals = new Originals(bundle);

    await Promise.all([originals.load(), originals.load()]);
    await originals.load();

    expect(bundle.loads).toBe(1);
  });
});

describe('the dictionary', () => {
  it("gives what Strong's says, not a summary of it", async () => {
    const originals = await loaded();

    const entry = originals.entryFor(new StrongsNumber('H', 430))!;
    expect(entry.lemma).toBe('אֱלֹהִים');
    expect(entry.transliteration).toBe('ʼĕlôhîym');
    expect(entry.definition).toContain('supreme God');
    expect(entry.derivation).toContain('H433');
    expect(entry.kjvUsage).toContain('judges');
    expect(originals.entryFor(new StrongsNumber('H', 9999))).toBeNull();
  });
});

describe('the concordance', () => {
  it('lists every verse a word is in, in order', async () => {
    const originals = await loaded();

    const god = new StrongsNumber('H', 430);
    expect(originals.occurrenceCount(god)).toBe(2);
    expect(originals.occurrences(god).map((r) => r.label)).toEqual(['Genesis 1:1', 'Genesis 1:3']);

    // A word in one verse is counted once, not once per word.
    expect(originals.occurrenceCount(new StrongsNumber('H', 7225))).toBe(1);
    expect(originals.occurrenceCount(new StrongsNumber('G', 976))).toBe(1);
    expect(originals.occurrenceCount(new StrongsNumber('H', 9999))).toBe(0);
  });
});

describe('tying an English word to the original', () => {
  it('matches through the King James renderings', async () => {
    const originals = await loaded();
    const words = originals.wordsFor(new Reference('GEN', 1, 1));

    // "God" is among the KJV renderings of H430, which is the third word.
    expect(originals.matchesFor(words, 'God')).toEqual([2]);
    expect(originals.matchesFor(words, 'god')).toEqual([2]);
    expect(originals.matchesFor(words, 'beginning')).toEqual([0]);
    // "created" stems to "create", which is how H1254 is rendered.
    expect(originals.matchesFor(words, 'created')).toEqual([1]);
  });

  it('answers nothing rather than something plausible', async () => {
    const originals = await loaded();
    const words = originals.wordsFor(new Reference('GEN', 1, 1));

    expect(originals.matchesFor(words, 'the')).toEqual([]);
    expect(originals.matchesFor(words, 'heavens')).toEqual([]);
    expect(originals.matchesFor(words, '')).toEqual([]);
    expect(originals.matchesFor(words, 'a')).toEqual([]);
  });
});

describe('a translation that brings its own', () => {
  it('reads it out of the chunk, gzipped or not', async () => {
    const own = await Originals.fromChunk(packOriginals());
    expect(own).not.toBeNull();
    expect(own!.isLoaded).toBe(true);
    expect(own!.wordsFor(new Reference('GEN', 1, 1))).toHaveLength(3);

    const raw = await Originals.fromChunk(StrongsCodec.inflate(packOriginals()));
    expect(raw!.wordsFor(new Reference('MAT', 1, 1))).toHaveLength(1);
  });

  it('a chunk that is not a layer costs only the layer', async () => {
    expect(await Originals.fromChunk(new Uint8Array([1, 2, 3, 4]))).toBeNull();
    expect(await Originals.fromChunk(new Uint8Array(0))).toBeNull();
  });
});

describe('the asset that ships', () => {
  it('holds both testaments', async () => {
    const reader = decodeOriginals(await new FsAssetBundle().load(Originals.assetPath));
    expect(reader.verseCount).toBeGreaterThan(30000);
    expect(reader.entryCount).toBeGreaterThan(14000);

    // Genesis 1:1, word for word.
    const genesis = reader.wordsAt(StrongsCodec.verseKey(0, 1, 1));
    expect(genesis).toHaveLength(7);
    expect(genesis[0].strongs).toEqual(new StrongsNumber('H', 7225));
    expect(genesis[0].morphology).toContain('Noun');
    expect(genesis[2].strongs).toEqual(new StrongsNumber('H', 430));

    // John 3:16 — book 42 in the canon, and the Greek is accented.
    const john = reader.wordsAt(StrongsCodec.verseKey(42, 3, 16));
    expect(john.length).toBeGreaterThan(20);
    expect(john[0].text).toBe('Οὕτως');
    expect(john.some((word) => word.strongs?.equals(new StrongsNumber('G', 2316)))).toBe(true);

    // The versification map did its work: Malachi 4 is Hebrew 3, and the
    // English chapter 4 must still have its words.
    expect(reader.wordsAt(StrongsCodec.verseKey(38, 4, 1)).length).toBeGreaterThan(0);
    // Joel 2:28 is Hebrew 3:1.
    expect(reader.wordsAt(StrongsCodec.verseKey(28, 2, 28)).length).toBeGreaterThan(0);
    // Psalm 51:1 is Hebrew 51:3 — the superscription is counted there.
    expect(reader.wordsAt(StrongsCodec.verseKey(18, 51, 1)).length).toBeGreaterThan(0);

    const god = reader.entryFor(new StrongsNumber('H', 430))!;
    expect(god.lemma).toBe('אֱלֹהִים');
    expect(god.renderings).toContain('god');
    expect(reader.occurrenceCount(new StrongsNumber('H', 430))).toBeGreaterThan(2000);

    const theos = reader.entryFor(new StrongsNumber('G', 2316))!;
    expect(theos.lemma).toBe('θεός');
    expect(theos.transliteration.length).toBeGreaterThan(0);
  });

  it('gives Hebrew for Genesis 1:1 and Greek for John 1:1 through the loader', async () => {
    const originals = new Originals(new FsAssetBundle());
    await originals.load();

    const hebrew = originals.wordsFor(new Reference('GEN', 1, 1));
    expect(hebrew[0].strongs!.isHebrew).toBe(true);
    expect(/\p{Script=Hebrew}/u.test(hebrew[0].text)).toBe(true);

    const greek = originals.wordsFor(new Reference('JHN', 1, 1));
    expect(greek.length).toBeGreaterThan(5);
    expect(greek.every((word) => word.strongs === null || !word.strongs.isHebrew)).toBe(true);
    expect(/\p{Script=Greek}/u.test(greek[0].text)).toBe(true);
    expect(greek.some((word) => word.strongs?.equals(new StrongsNumber('G', 3056)))).toBe(true); // λόγος
  });
});
