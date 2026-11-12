import { Bible, Block, BlockStyle, Book, Chapter, Markup, TranslationInfo, type VerseSegment } from '../src/model/bible';
import { BookMeta } from '../src/model/bookMeta';

/**
 * The Dart tests' USFX fixture, as the model it parses to: Genesis with
 * two chapters, the first exercising a heading, a footnote, translator
 * additions and paragraph styles, and a Psalm. The USFX parser is not
 * ported yet; the verse texts here are what it would give.
 */
export const testTranslation = new TranslationInfo({
  id: 'eng-web',
  name: 'Test Edition',
  abbreviation: 'TST',
  license: 'Public Domain',
  sourceUrl: 'https://example.invalid/',
});

const seg = (verse: number, text: string, startsVerse = true): VerseSegment => ({ verse, startsVerse, text });

export function parseFixture(): Bible {
  const genesis1 = new Chapter({
    number: 1,
    notes: ['1:1 Elohim.'],
    blocks: [
      new Block({ style: BlockStyle.heading, level: 2, segments: [seg(0, 'The Creation', false)] }),
      new Block({ style: BlockStyle.reference, segments: [seg(0, '(Psalms 1:1; Matthew 1)', false)] }),
      new Block({
        style: BlockStyle.paragraph,
        segments: [
          seg(1, `In the beginning, God${Markup.noteStart}0${Markup.noteEnd} created the heavens.`),
          seg(2, `The earth was ${Markup.addStart}formless${Markup.addEnd} and empty.`),
        ],
      }),
      new Block({ style: BlockStyle.paragraph, segments: [seg(3, 'God said, "Let there be light."')] }),
      new Block({
        style: BlockStyle.paragraph,
        indentFirstLine: false,
        segments: [seg(4, 'A paragraph set flush to the margin.')],
      }),
      new Block({ style: BlockStyle.paragraph, indent: 1, segments: [seg(5, 'An indented paragraph.')] }),
      new Block({ style: BlockStyle.speaker, segments: [seg(5, 'Eliphaz the Temanite', false)] }),
    ],
  });
  const genesis2 = new Chapter({
    number: 2,
    notes: [],
    blocks: [new Block({ style: BlockStyle.paragraph, segments: [seg(1, 'The second chapter.')] })],
  });
  const psalm1 = new Chapter({
    number: 1,
    notes: [],
    blocks: [
      new Block({ style: BlockStyle.heading, level: 1, segments: [seg(0, 'BOOK 1', false)] }),
      new Block({ style: BlockStyle.descriptiveTitle, segments: [seg(0, 'A Psalm by David.', false)] }),
      new Block({ style: BlockStyle.poetry, indent: 1, segments: [seg(1, 'Blessed is the man')] }),
      new Block({
        style: BlockStyle.poetry,
        indent: 2,
        segments: [seg(1, `who does not walk in the counsel of the wicked. ${Markup.selahStart}Selah.${Markup.selahEnd}`, false)],
      }),
      new Block({ style: BlockStyle.blank }),
      new Block({ style: BlockStyle.poetry, indent: 1, segments: [seg(2, 'But his delight is in the law.')] }),
    ],
  });
  return new Bible({
    translation: testTranslation,
    books: [Book.of(BookMeta.lookup('GEN')!, [genesis1, genesis2]), Book.of(BookMeta.lookup('PSA')!, [psalm1])],
  });
}
