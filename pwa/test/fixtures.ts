import { gzipSync } from 'fflate';
import { Atlas } from '../src/data/atlas';
import { BookIntros } from '../src/data/bookIntros';
import { CrossReferences } from '../src/data/crossReferences';
import { Originals } from '../src/data/originals';
import type { AssetBundle } from '../src/infra/assets';
import { BibFile } from '../src/model/bibFile';
import {
  Bible,
  Block,
  BlockStyle,
  Book,
  Chapter,
  Markup,
  TranslationInfo,
  type VerseSegment,
} from '../src/model/bible';
import { BookMeta } from '../src/model/bookMeta';
import { OriginalWord, StrongsCodec, StrongsEntry, StrongsNumber, StrongsWriter } from '../src/model/strongsCodec';
import { XrefAnchor, XrefCodec, XrefEntry, XrefRange } from '../src/model/xrefCodec';

/**
 * The TypeScript twin of `test/fixtures.dart`. The Dart tests parse a small
 * USFX document; the USFX parser is build tooling and is not ported, so
 * `sampleBible()` builds the very Bible that parse yields, block for block,
 * as `lib/src/data/usfx_parser.dart` lays it out.
 */

export const testTranslation = new TranslationInfo({
  id: 'eng-web',
  name: 'Test Edition',
  abbreviation: 'TST',
  license: 'Public Domain',
  sourceUrl: 'https://example.invalid/',
});

export const otherTranslation = new TranslationInfo({
  id: 'eng-bsb',
  name: 'Other Edition',
  abbreviation: 'OTH',
  license: 'Public Domain',
  sourceUrl: 'https://example.invalid/other',
});

const seg = (verse: number, startsVerse: boolean, text: string): VerseSegment => ({ verse, startsVerse, text });

const meta = (code: string) => BookMeta.lookup(code)!;

/**
 * A small Bible exercising every structure the reader lays out: prose
 * paragraphs, poetry indent levels, psalm titles, section headings, parallel
 * passage references, stanza breaks, footnotes, translator additions, Selah
 * and words of Jesus. Front matter, book titles and introductions are what
 * the USFX parser drops, so they are simply not here.
 *
 * Genesis has two chapters (five verses, then one), Psalm 1 is poetry under
 * a book division and a superscription, and Matthew 1:1 carries words of
 * Jesus.
 */
export function sampleBible(): Bible {
  const genesis = Book.of(meta('GEN'), [
    new Chapter({
      number: 1,
      blocks: [
        new Block({ style: BlockStyle.heading, level: 2, segments: [seg(0, false, 'The Creation')] }),
        new Block({ style: BlockStyle.reference, segments: [seg(0, false, '(Psalms 1:1; Matthew 1)')] }),
        new Block({
          style: BlockStyle.paragraph,
          segments: [
            seg(1, true, `In the beginning, God${Markup.noteStart}0${Markup.noteEnd} created the heavens.`),
            seg(2, true, `The earth was ${Markup.addStart}formless${Markup.addEnd} and empty.`),
          ],
        }),
        new Block({ style: BlockStyle.paragraph, segments: [seg(3, true, 'God said, "Let there be light."')] }),
        new Block({
          style: BlockStyle.paragraph,
          indentFirstLine: false,
          segments: [seg(4, true, 'A paragraph set flush to the margin.')],
        }),
        new Block({
          style: BlockStyle.paragraph,
          indent: 1,
          indentFirstLine: false,
          segments: [seg(5, true, 'An indented paragraph.')],
        }),
        // A speaker line after verse 5 carries that verse's number, as the
        // parser stamps whichever verse it is inside.
        new Block({ style: BlockStyle.speaker, segments: [seg(5, false, 'Eliphaz the Temanite')] }),
      ],
      notes: ['Elohim.'],
    }),
    new Chapter({
      number: 2,
      blocks: [new Block({ style: BlockStyle.paragraph, segments: [seg(1, true, 'The second chapter.')] })],
      notes: [],
    }),
  ]);

  const psalms = Book.of(meta('PSA'), [
    new Chapter({
      number: 1,
      blocks: [
        new Block({ style: BlockStyle.heading, level: 1, segments: [seg(0, false, 'BOOK 1')] }),
        new Block({ style: BlockStyle.descriptiveTitle, segments: [seg(0, false, 'A Psalm by David.')] }),
        new Block({ style: BlockStyle.poetry, indent: 1, segments: [seg(1, true, 'Blessed is the man')] }),
        new Block({
          style: BlockStyle.poetry,
          indent: 2,
          segments: [
            seg(1, false, `who does not walk in the counsel of the wicked. ${Markup.selahStart}Selah.${Markup.selahEnd}`),
          ],
        }),
        new Block({ style: BlockStyle.blank }),
        new Block({ style: BlockStyle.poetry, indent: 1, segments: [seg(2, true, 'But his delight is in the law.')] }),
      ],
      notes: [],
    }),
  ]);

  const matthew = Book.of(meta('MAT'), [
    new Chapter({
      number: 1,
      blocks: [
        new Block({
          style: BlockStyle.paragraph,
          segments: [seg(1, true, `He said, ${Markup.wjStart}Follow me.${Markup.wjEnd} Then they followed.`)],
        }),
      ],
      notes: [],
    }),
  ]);

  return new Bible({ translation: testTranslation, books: [genesis, psalms, matthew] });
}

/** The same books in a second translation, for the compare view. */
export function otherSampleBible(): Bible {
  const paragraph = (...segments: VerseSegment[]) => new Block({ style: BlockStyle.paragraph, segments });
  return new Bible({
    translation: otherTranslation,
    books: [
      Book.of(meta('GEN'), [
        new Chapter({
          number: 1,
          blocks: [
            paragraph(
              seg(1, true, 'At the first God made the heaven and the earth.'),
              seg(2, true, 'And the earth was waste and without form.'),
              seg(3, true, 'And God said, Let there be light.'),
            ),
          ],
          notes: [],
        }),
        new Chapter({ number: 2, blocks: [paragraph(seg(1, true, 'Chapter two, differently worded.'))], notes: [] }),
      ]),
      Book.of(meta('PSA'), [
        new Chapter({
          number: 1,
          blocks: [
            paragraph(
              seg(1, true, 'Happy is the man who does not go in the company of sinners.'),
              seg(2, true, 'But his delight is in the law of the Lord.'),
            ),
          ],
          notes: [],
        }),
      ]),
      Book.of(meta('MAT'), [
        new Chapter({
          number: 1,
          blocks: [paragraph(seg(1, true, 'He said, Come after me. And they went with him.'))],
          notes: [],
        }),
      ]),
    ],
  });
}

/**
 * One book with a chapter long enough to need scrolling, for testing jumps
 * to a verse far down the page. Verses flow together inside a paragraph, as
 * prose does, so only the first verse of each paragraph is an anchor.
 */
export function longSampleBible(options: { verses?: number; chapters?: number; versesPerParagraph?: number } = {}): Bible {
  const verses = options.verses ?? 80;
  const chapters = options.chapters ?? 1;
  const versesPerParagraph = options.versesPerParagraph ?? 1;
  const built: Chapter[] = [];
  for (let chapter = 1; chapter <= chapters; chapter++) {
    const blocks: Block[] = [];
    let segments: VerseSegment[] = [];
    for (let verse = 1; verse <= verses; verse++) {
      if (verse % versesPerParagraph === 1 || versesPerParagraph === 1) {
        if (segments.length > 0) blocks.push(new Block({ style: BlockStyle.paragraph, segments }));
        segments = [];
      }
      segments.push(
        seg(
          verse,
          true,
          `Chapter ${chapter} verse ${verse} of a passage written to be tall enough that reaching its end takes some scrolling.`,
        ),
      );
    }
    if (segments.length > 0) blocks.push(new Block({ style: BlockStyle.paragraph, segments }));
    built.push(new Chapter({ number: chapter, blocks, notes: [] }));
  }
  return new Bible({ translation: testTranslation, books: [Book.of(meta('GEN'), built)] });
}

/**
 * Cross-references over the books the fixture Bible holds: Genesis 1:1
 * points at Psalms and Matthew, both of which are in it.
 */
export const fixtureXrefs: XrefEntry[] = [
  new XrefEntry({
    book: CrossReferences.indexOfBook('GEN'),
    chapter: 1,
    verse: 1,
    anchors: [
      new XrefAnchor({
        phrase: 'In the beginning',
        ranges: [
          new XrefRange({ book: CrossReferences.indexOfBook('PSA'), chapter: 1, verse: 1, endVerse: 1 }),
          new XrefRange({ book: CrossReferences.indexOfBook('MAT'), chapter: 1, verse: 1, endVerse: 1 }),
        ],
      }),
    ],
  }),
];

/**
 * Hebrew behind Genesis 1:1 and Greek behind Matthew 1:1, with the two
 * dictionary entries they need — enough to drive the whole chain from a
 * verse to a concordance.
 */
export function buildFixtureOriginals(): Uint8Array {
  const writer = new StrongsWriter();
  const genesis = CrossReferences.indexOfBook('GEN');
  const matthew = CrossReferences.indexOfBook('MAT');

  writer.addVerse(StrongsCodec.verseKey(genesis, 1, 1), [
    new OriginalWord({
      text: 'בְּרֵאשִׁית',
      strongs: new StrongsNumber('H', 7225),
      morphology: 'Noun common feminine singular absolute',
    }),
    new OriginalWord({
      text: 'בָּרָא',
      strongs: new StrongsNumber('H', 1254),
      morphology: 'Verb qal perfect third person masculine singular',
    }),
    new OriginalWord({
      text: 'אֱלֹהִים',
      strongs: new StrongsNumber('H', 430),
      morphology: 'Noun common masculine plural absolute',
    }),
  ]);
  // The same word again, so the concordance has more than one verse in it.
  writer.addVerse(StrongsCodec.verseKey(genesis, 1, 3), [
    new OriginalWord({
      text: 'אֱלֹהִים',
      strongs: new StrongsNumber('H', 430),
      morphology: 'Noun common masculine plural absolute',
    }),
  ]);
  writer.addVerse(StrongsCodec.verseKey(matthew, 1, 1), [
    new OriginalWord({
      text: 'βίβλος',
      strongs: new StrongsNumber('G', 976),
      morphology: 'Noun nominative singular feminine',
    }),
  ]);

  writer.addEntry(
    new StrongsEntry({
      number: new StrongsNumber('H', 7225),
      lemma: 'רֵאשִׁית',
      transliteration: 'rêʼshîyth',
      pronunciation: "ray-sheeth'",
      derivation: 'from the same as H7218;',
      definition: 'the first, in place, time, order or rank',
      kjvUsage: 'beginning, chief(-est), first(-fruits, part, time).',
    }),
  );
  writer.addEntry(
    new StrongsEntry({
      number: new StrongsNumber('H', 1254),
      lemma: 'בָּרָא',
      transliteration: 'bârâʼ',
      pronunciation: "baw-raw'",
      derivation: 'a primitive root;',
      definition: '(absolutely) to create',
      kjvUsage: 'choose, create (creator), cut down, dispatch.',
    }),
  );
  writer.addEntry(
    new StrongsEntry({
      number: new StrongsNumber('H', 430),
      lemma: 'אֱלֹהִים',
      transliteration: 'ʼĕlôhîym',
      pronunciation: "el-o-heem'",
      derivation: 'plural of H433;',
      definition: 'gods in the ordinary sense; but specifically used of the supreme God',
      kjvUsage: 'angels, [idiom] exceeding, God (gods) (-dess, -ly), judges, [idiom] mighty.',
    }),
  );
  writer.addEntry(
    new StrongsEntry({
      number: new StrongsNumber('G', 976),
      lemma: 'βίβλος',
      transliteration: 'bíblos',
      pronunciation: '',
      derivation: 'properly, the inner bark of the papyrus plant;',
      definition: 'a sheet or scroll of writing',
      kjvUsage: 'book.',
    }),
  );
  return writer.build();
}

/** The cross-references in the shape the asset takes: gzipped binary. */
export function packXrefs(entries: readonly XrefEntry[]): Uint8Array {
  return gzipSync(XrefCodec.encode(entries));
}

/** The original-language layer, in the shape the asset takes. */
export function packOriginals(): Uint8Array {
  return gzipSync(buildFixtureOriginals());
}

export function packJson(value: unknown): Uint8Array {
  return gzipSync(new TextEncoder().encode(JSON.stringify(value)));
}

/** The book introductions in the shape the asset uses: gzipped JSON. */
export function packIntros(intros: Record<string, string>): Uint8Array {
  return packJson(intros);
}

/**
 * An `AssetBundle` serving the fixtures the way the real bundle serves the
 * shipped translations: `.bib` files, and the gzipped notes, atlas,
 * references and originals. Records every path asked for.
 */
export class FixtureBundle implements AssetBundle {
  readonly assets: Map<string, Uint8Array>;
  readonly loaded: string[] = [];

  constructor(options: { assets?: Map<string, Uint8Array>; bible?: Bible } = {}) {
    this.assets =
      options.assets ??
      new Map<string, Uint8Array>([
        [`assets/bible/${testTranslation.id}.bib`, BibFile.encode(options.bible ?? sampleBible())],
        [`assets/bible/${otherTranslation.id}.bib`, BibFile.encode(otherSampleBible())],
        [BookIntros.assetPath, packIntros(fixtureIntros)],
        [Atlas.assetPath, packJson(fixtureAtlas)],
        [CrossReferences.assetPath, packXrefs(fixtureXrefs)],
        [Originals.assetPath, packOriginals()],
      ]);
  }

  async load(path: string): Promise<Uint8Array> {
    this.loaded.push(path);
    const data = this.assets.get(path);
    if (data === undefined) {
      throw new Error(`Fixture bundle has no asset "${path}"`);
    }
    return data;
  }

  async loadString(path: string): Promise<string> {
    return new TextDecoder().decode(await this.load(path));
  }
}

/**
 * Stand-ins for the bundled introductions, in the shape the real ones take:
 * a lead paragraph, then underlined top-level sections, one of them with a
 * sub-heading below it.
 */
export const fixtureIntros: Record<string, string> = {
  GEN:
    'Genesis is a book of **beginnings**.\n' +
    '\n' +
    'Setting\n' +
    '=======\n' +
    '\n' +
    'It opens in Ur of the Chaldees.\n' +
    '\n' +
    'Author\n' +
    '======\n' +
    '\n' +
    'Traditionally Moses.\n' +
    '\n' +
    'Genres\n' +
    '------\n' +
    '\n' +
    'Narrative, with genealogies.\n',
  PSA: 'A collection of prayers and songs.\n',
};

/**
 * A stand-in atlas in the shape the real asset takes: two places in the
 * fixture's first book, with the verses naming them, a scrap of coastline
 * and a river.
 */
export const fixtureAtlas: Record<string, unknown> = {
  version: 2,
  bounds: [30000, 28000, 40000, 36000],
  detail: [34000, 31000, 36000, 33000],
  places: [
    ['Bethel', 'settlement', 35220, 31930, 1000, 'Beitin', 'Beth-el|Luz', 'twelve miles north of Jerusalem', 71],
    ['Ai', 'settlement|ruin', 35270, 31917, 300, 'et-Tell', '', '', 39],
  ],
  chapters: {
    'GEN 1': [[0, 1]],
    'GEN 2': [
      [0, 2, 5],
      [1, 5],
    ],
  },
  land: [[34000, 31000, 36000, 31000, 36000, 33000, 34000, 33000]],
  lakes: [],
  rivers: [[35000, 31000, 35100, 32000, 35200, 33000]],
  fineLand: [[34500, 31500, 35500, 31500, 35500, 32500, 34500, 32500]],
  fineLakes: [],
  fineRivers: [],
  urban: [[35200, 31900, 35240, 31900, 35240, 31940, 35200, 31940]],
  towns: [
    [35213, 31768, 0, 'Jerusalem'],
    [35300, 32000, 7, 'Beitin'],
  ],
};
