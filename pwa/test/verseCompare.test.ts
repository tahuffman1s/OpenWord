import { describe, expect, it } from 'vitest';
import { Block, BlockStyle, Chapter, Markup } from '../src/model/bible';
import { comparable, differingWords, markedRuns, runPieces, wordsOf } from '../src/model/verseCompare';

const wj = (text: string) => `${Markup.wjStart}${text}${Markup.wjEnd}`;

describe('a verse with its marks kept', () => {
  const chapter = new Chapter({
    number: 3,
    notes: [],
    blocks: [
      new Block({
        style: BlockStyle.paragraph,
        segments: [
          { verse: 15, startsVerse: true, text: `Jesus answered, ${wj('“Most certainly')}` },
          { verse: 16, startsVerse: true, text: wj(`For God so loved${Markup.noteStart}2${Markup.noteEnd} the world,`) },
        ],
      }),
      new Block({ style: BlockStyle.heading, segments: [{ verse: 16, startsVerse: false, text: 'A heading' }] }),
      new Block({
        style: BlockStyle.poetry,
        segments: [{ verse: 16, startsVerse: false, text: wj('that he gave his only born Son,') }],
      }),
    ],
  });

  it('keeps the words of Jesus, drops footnote callers and headings', () => {
    const marked = chapter.verseMarked(16);
    expect(Markup.strip(marked)).toBe(chapter.verseText(16));
    expect(marked).not.toContain(Markup.noteStart);
    const runs = markedRuns(marked);
    expect(runs.every((run) => run.wj || run.text.trim().length === 0)).toBe(true);
    expect(runs.map((run) => run.text).join('')).toBe('For God so loved the world, that he gave his only born Son,');
  });

  it('marks only the part of a verse that Jesus says', () => {
    const runs = markedRuns(chapter.verseMarked(15));
    expect(runs).toEqual([
      { text: 'Jesus answered, ', wj: false, italic: false, divine: false },
      { text: '“Most certainly', wj: true, italic: false, divine: false },
    ]);
  });

  it('is empty for a verse the chapter does not have', () => {
    expect(chapter.verseMarked(99)).toBe('');
  });
});

describe('runs', () => {
  it('carry italics and the divine name', () => {
    const runs = markedRuns(
      `The ${Markup.divineStart}Lord${Markup.divineEnd} is ${Markup.addStart}my${Markup.addEnd} shepherd ${Markup.selahStart}Selah${Markup.selahEnd}`,
    );
    expect(runs.filter((run) => run.divine).map((run) => run.text)).toEqual(['Lord']);
    expect(runs.filter((run) => run.italic).map((run) => run.text)).toEqual(['my', 'Selah']);
  });

  it('number their words through the verse, as wordsOf does', () => {
    const runs = markedRuns(`He said, ${wj('“Don’t be afraid.”')}`);
    const pieces = runPieces(runs).flat();
    expect(pieces.filter((piece) => piece.word >= 0).map((piece) => piece.text)).toEqual(['He', 'said', 'Don’t', 'be', 'afraid']);
    expect(pieces.filter((piece) => piece.word >= 0).map((piece) => piece.word)).toEqual([0, 1, 2, 3, 4]);
    expect(wordsOf(runs)).toEqual(['he', 'said', "don't", 'be', 'afraid']);
    expect(pieces.map((piece) => piece.text).join('')).toBe('He said, “Don’t be afraid.”');
  });
});

describe('the words another translation words differently', () => {
  const words = (text: string) => wordsOf(markedRuns(text));
  const differing = (base: string, other: string) => {
    const otherWords = words(other);
    return [...differingWords(words(base), otherWords)].sort((a, b) => a - b).map((at) => otherWords[at]);
  };

  it('are none where the two agree, whatever the capitals and punctuation', () => {
    expect(differing('In the beginning, God created.', 'in the beginning God created')).toEqual([]);
  });

  it('are the ones outside what the two have in common', () => {
    expect(
      differing(
        'For God so loved the world, that he gave his only born Son',
        'For God so loved the world that He gave His one and only Son',
      ),
    ).toEqual(['one', 'and']);
  });

  it('are all of them where nothing is shared', () => {
    expect(differing('alpha beta', 'gamma delta')).toEqual(['gamma', 'delta']);
  });

  it('are none where either side is empty', () => {
    expect(differing('', 'some words')).toEqual([]);
    expect(differing('some words', '')).toEqual([]);
  });

  it('are only looked for within one language', () => {
    expect(comparable('en', 'en-GB')).toBe(true);
    expect(comparable('en', 'es')).toBe(false);
  });
});
