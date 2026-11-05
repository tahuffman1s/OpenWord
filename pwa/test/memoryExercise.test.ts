import { describe, expect, it } from 'vitest';
import { Cloze, MemoryExercise, TypedVerse, VerseSteps, VerseTiles, VerseWord } from '../src/model/memoryExercise';
import { seededRandom } from '../src/model/random';

describe('steps', () => {
  const john =
    'For God so loved the world, that he gave his only Son, that whoever ' +
    'believes in him should not perish, but have eternal life.';

  it('a long verse is built clause by clause, each on the last', () => {
    const steps = VerseSteps.of(john);
    expect(steps).toEqual([
      'For God so loved the world,',
      'For God so loved the world, that he gave his only Son,',
      'For God so loved the world, that he gave his only Son, that whoever believes in him should not perish,',
      john,
    ]);
  });

  it('a short verse, or one without clauses, is one step', () => {
    expect(VerseSteps.of('God said, "Let there be light."')).toEqual(['God said, "Let there be light."']);
    const run = 'one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen.';
    expect(VerseSteps.of(run)).toEqual([run]);
  });

  it('a stray word or two joins the clause before it', () => {
    const text = 'The Lord is my shepherd; I shall not want. He makes me lie down in green pastures. Amen.';
    expect(VerseSteps.of(text)[VerseSteps.of(text).length - 1]).toBe(text);
    expect(VerseSteps.of(text)).toHaveLength(3);
  });
});

const john =
  'For God so loved the world, that he gave his only born Son, that ' +
  'whoever believes in him should not perish, but have eternal life.';

describe('tiles', () => {
  it('a short verse is its words', () => {
    expect(VerseTiles.of('God said, "Let there be light."')).toEqual(['God', 'said,', '"Let', 'there', 'be', 'light."']);
  });

  it('a long verse is cut into phrases, at most twelve', () => {
    const tiles = VerseTiles.of(john);
    expect(tiles.length).toBeLessThanOrEqual(VerseTiles.maxTiles);
    expect(tiles.length).toBeGreaterThan(4);
    expect(tiles.join(' ')).toBe(john);
    // Runs end at clause breaks where one comes along.
    expect(tiles).toContain('loved the world,');
    for (const tile of tiles) {
      expect(tile.split(' ').length).toBeGreaterThanOrEqual(2);
    }
  });

  it('the order is checked against the verse itself', () => {
    const tiles = VerseTiles.of(john);
    expect(VerseTiles.inOrder(tiles, john)).toBe(true);
    expect(VerseTiles.inOrder([...tiles].reverse(), john)).toBe(false);
    expect(VerseTiles.inOrder(tiles.slice(1), john)).toBe(false);
  });
});

describe('blanks', () => {
  it('keep the punctuation around a word', () => {
    const word = VerseWord.parse('"world,"');
    expect(word.lead).toBe('"');
    expect(word.core).toBe('world');
    expect(word.trail).toBe(',"');
    expect(VerseWord.parse('don’t').core).toBe('don’t');
  });

  it('one word in five goes, the bank holds it and a wrong one', () => {
    const cloze = Cloze.make(john, seededRandom(1));
    expect(cloze.words).toHaveLength(25);
    expect(cloze.blanks).toHaveLength(5);
    expect(cloze.blanks).toEqual([...cloze.blanks].sort((a, b) => a - b));
    expect(cloze.bank).toHaveLength(10);
    for (let i = 0; i < cloze.blanks.length; i++) {
      expect(cloze.bank).toContain(cloze.answer(i));
      expect(cloze.answer(i).length).toBeGreaterThanOrEqual(3);
    }
    // Every wrong word is from the verse too.
    const cores = new Set(cloze.words.map((w) => w.core));
    expect(cloze.bank.every((w) => cores.has(w))).toBe(true);
  });

  it('is right only with every blank right', () => {
    const cloze = Cloze.make(john, seededRandom(2));
    const right: string[] = [];
    for (let i = 0; i < cloze.blanks.length; i++) right.push(cloze.answer(i));
    expect(cloze.check(right)).toBe(true);
    expect(cloze.check([...right].reverse())).toBe(right[0] === right[right.length - 1]);
    expect(cloze.check(right.slice(1))).toBe(false);
    expect(cloze.check([null, ...right.slice(1)])).toBe(false);
  });

  it('a short verse has one blank and a short bank', () => {
    const cloze = Cloze.make('Jesus wept.', seededRandom(3));
    expect(cloze.blanks).toHaveLength(1);
    expect(cloze.bank).toHaveLength(2);
  });
});

describe('written out', () => {
  it('case and punctuation are set aside', () => {
    expect(TypedVerse.matches('jesus wept', 'Jesus wept.')).toBe(true);
    expect(TypedVerse.matches('for god so loved the world', 'For God so loved the world,')).toBe(true);
  });

  it('a slip of one letter in a long word is forgiven', () => {
    expect(TypedVerse.matches('Jesus wepd.', 'Jesus wept.')).toBe(false);
    expect(TypedVerse.matches('whoever beleives', 'whoever believes')).toBe(true);
    expect(TypedVerse.matches('whoever belives', 'whoever believes')).toBe(true);
    expect(TypedVerse.matches('whoever belies', 'whoever believes')).toBe(false);
  });

  it('a word missing or added is wrong', () => {
    expect(TypedVerse.matches('Jesus wept a lot.', 'Jesus wept.')).toBe(false);
    expect(TypedVerse.matches('Jesus', 'Jesus wept.')).toBe(false);
    expect(TypedVerse.matches('', 'Jesus wept.')).toBe(false);
  });

  it('curly apostrophes are straight ones', () => {
    expect(TypedVerse.matches("don't", 'don’t')).toBe(true);
  });
});

describe('the exercise for a rung', () => {
  it('climbs from copying to writing out', () => {
    expect(MemoryExercise.forRung(0, true)).toBe(MemoryExercise.arrangeShown);
    expect(MemoryExercise.forRung(1, true)).toBe(MemoryExercise.fillBlanks);
    expect(MemoryExercise.forRung(2, true)).toBe(MemoryExercise.listenArrange);
    expect(MemoryExercise.forRung(2, false)).toBe(MemoryExercise.arrange);
    expect(MemoryExercise.forRung(3, true)).toBe(MemoryExercise.arrange);
    expect(MemoryExercise.forRung(4, true)).toBe(MemoryExercise.typeOut);
    expect(MemoryExercise.forRung(5, true)).toBe(MemoryExercise.listenArrange);
    expect(MemoryExercise.forRung(5, false)).toBe(MemoryExercise.arrange);
    expect(MemoryExercise.forRung(8, true)).toBe(MemoryExercise.typeOut);
  });

  it('only the first two show the text', () => {
    expect(MemoryExercise.values.filter((e) => e.showsText)).toEqual([MemoryExercise.arrangeShown, MemoryExercise.fillBlanks]);
  });
});
