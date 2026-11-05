import { Bible, Block, BlockStyle, Book, Chapter, Markup, TranslationInfo } from '../src/model/bible';
import { BookMeta } from '../src/model/bookMeta';

/**
 * The Dart tests' `parseFixture()`, built by hand rather than parsed from
 * USFX (the parser is ported separately): the same three books with the
 * same verses, so the model tests read the same text.
 */
export const testTranslation = new TranslationInfo({
  id: 'eng-web',
  name: 'Test Edition',
  abbreviation: 'TST',
  license: 'Public Domain',
  sourceUrl: 'https://example.invalid/',
});

const verse = (verse: number, text: string, startsVerse = true) => ({ verse, startsVerse, text });
const outside = (text: string) => ({ verse: 0, startsVerse: false, text });

export function sampleBible(): Bible {
  const genesis = Book.of(BookMeta.lookup('GEN')!, [
    new Chapter({
      number: 1,
      notes: ['1:1 Elohim.'],
      blocks: [
        new Block({ style: BlockStyle.heading, segments: [outside('The Creation')] }),
        new Block({ style: BlockStyle.reference, segments: [outside('(Psalms 1:1; Matthew 1)')] }),
        new Block({
          style: BlockStyle.paragraph,
          segments: [
            verse(1, `In the beginning, God${Markup.noteStart}0${Markup.noteEnd} created the heavens.`),
            verse(2, `The earth was ${Markup.addStart}formless${Markup.addEnd} and empty.`),
          ],
        }),
        new Block({ style: BlockStyle.paragraph, segments: [verse(3, 'God said, "Let there be light."')] }),
        new Block({
          style: BlockStyle.paragraph,
          indentFirstLine: false,
          segments: [verse(4, 'A paragraph set flush to the margin.')],
        }),
        new Block({ style: BlockStyle.paragraph, indent: 1, segments: [verse(5, 'An indented paragraph.')] }),
        new Block({ style: BlockStyle.speaker, segments: [outside('Eliphaz the Temanite')] }),
      ],
    }),
    new Chapter({
      number: 2,
      notes: [],
      blocks: [new Block({ style: BlockStyle.paragraph, segments: [verse(1, 'The second chapter.')] })],
    }),
  ]);
  const psalms = Book.of(BookMeta.lookup('PSA')!, [
    new Chapter({
      number: 1,
      notes: [],
      blocks: [
        new Block({ style: BlockStyle.heading, level: 1, segments: [outside('BOOK 1')] }),
        new Block({ style: BlockStyle.descriptiveTitle, segments: [outside('A Psalm by David.')] }),
        new Block({ style: BlockStyle.poetry, indent: 1, segments: [verse(1, 'Blessed is the man')] }),
        new Block({
          style: BlockStyle.poetry,
          indent: 2,
          segments: [verse(1, `who does not walk in the counsel of the wicked. ${Markup.selahStart}Selah.${Markup.selahEnd}`, false)],
        }),
        new Block({ style: BlockStyle.blank }),
        new Block({ style: BlockStyle.poetry, indent: 1, segments: [verse(2, 'But his delight is in the law.')] }),
      ],
    }),
  ]);
  const matthew = Book.of(BookMeta.lookup('MAT')!, [
    new Chapter({
      number: 1,
      notes: [],
      blocks: [
        new Block({
          style: BlockStyle.paragraph,
          segments: [verse(1, `He said, ${Markup.wjStart}Follow me.${Markup.wjEnd} Then they followed.`)],
        }),
      ],
    }),
  ]);
  return new Bible({ translation: testTranslation, books: [genesis, psalms, matthew] });
}
