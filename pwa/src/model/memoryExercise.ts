import { shuffle, type RandomSource } from './random';

/**
 * How a verse on the ladder is tested: the exercise a practice sets.
 *
 * The ladder is climbed by answering, not by saying one had it. A new
 * verse is copied out from tiles with the text in view, then the blanks
 * in it filled, then put together from its tiles unseen — from hearing
 * it, where the device can speak — and then written out in full.
 */
export class MemoryExercise {
  /** The verse shown; put its tiles in order beneath it. */
  static readonly arrangeShown = new MemoryExercise('arrangeShown', 'Put it together', 'Tap the tiles in order. The verse is above.');

  /** The verse with words missing; fill them from the bank. */
  static readonly fillBlanks = new MemoryExercise('fillBlanks', 'Fill the blanks', 'Tap a word for each gap, in order.');

  /** The verse heard, not seen; put its tiles in order. */
  static readonly listenArrange = new MemoryExercise('listenArrange', 'Tap what you hear', 'Listen, then tap the tiles in order.');

  /** The reference alone; put the tiles in order. */
  static readonly arrange = new MemoryExercise('arrange', 'From memory', 'Tap the tiles in the verse’s order.');

  /** The reference alone; write the verse. */
  static readonly typeOut = new MemoryExercise('typeOut', 'Write it out', 'Type the verse. Spelling slips are forgiven.');

  static readonly values: readonly MemoryExercise[] = [
    MemoryExercise.arrangeShown,
    MemoryExercise.fillBlanks,
    MemoryExercise.listenArrange,
    MemoryExercise.arrange,
    MemoryExercise.typeOut,
  ];

  private constructor(
    readonly name: string,
    readonly label: string,
    readonly instruction: string,
  ) {}

  /** Whether the exercise lets the verse be seen before it is answered. */
  get showsText(): boolean {
    return this === MemoryExercise.arrangeShown || this === MemoryExercise.fillBlanks;
  }

  /** Whether the exercise is answered from tiles rather than typed. */
  get usesTiles(): boolean {
    return this === MemoryExercise.arrangeShown || this === MemoryExercise.listenArrange || this === MemoryExercise.arrange;
  }

  /**
   * The exercise a verse on `rung` is ready for. Hearing it is asked
   * only where there is a voice to hear.
   */
  static forRung(rung: number, canListen: boolean): MemoryExercise {
    switch (rung) {
      case 0:
        return MemoryExercise.arrangeShown;
      case 1:
        return MemoryExercise.fillBlanks;
      case 2:
        return canListen ? MemoryExercise.listenArrange : MemoryExercise.arrange;
      case 3:
        return MemoryExercise.arrange;
      default:
        return rung % 2 !== 0 ? (canListen ? MemoryExercise.listenArrange : MemoryExercise.arrange) : MemoryExercise.typeOut;
    }
  }
}

const endsClause = /[,;:.!?]["”’]?$/;

function wordsOf(text: string): string[] {
  return text.split(' ').filter((w) => w.length > 0);
}

/**
 * The pieces a verse is put together from: its words, or runs of them
 * when there are too many words to lay out as tiles.
 *
 * Up to `maxTiles` tiles. A long verse is cut into runs of two or more
 * words, ending at a clause break where one comes along, so that the
 * tiles read as phrases rather than as a scatter of "the" and "and".
 */
export const VerseTiles = {
  maxTiles: 12,

  of(text: string): string[] {
    const words = wordsOf(text);
    if (words.length <= VerseTiles.maxTiles) return words;
    const size = Math.ceil(words.length / VerseTiles.maxTiles);
    const least = Math.max(2, Math.trunc(size / 2));
    const tiles: string[] = [];
    let run: string[] = [];
    for (const word of words) {
      run.push(word);
      const breaks = endsClause.test(word);
      if (run.length >= size || (breaks && run.length >= least)) {
        tiles.push(run.join(' '));
        run = [];
      }
    }
    if (run.length > 0) {
      // A short tail joins the tile before it rather than standing alone.
      if (run.length < least && tiles.length > 0) {
        tiles[tiles.length - 1] = `${tiles[tiles.length - 1]} ${run.join(' ')}`;
      } else {
        tiles.push(run.join(' '));
      }
    }
    return tiles;
  },

  /** Whether `chosen`, in that order, is the verse. */
  inOrder(chosen: readonly string[], text: string): boolean {
    return chosen.join(' ') === wordsOf(text).join(' ');
  },
};

/**
 * One word of a verse, with the punctuation around it kept apart, so
 * that a blank can stand for the word and keep its comma.
 */
export class VerseWord {
  constructor(
    readonly lead: string,
    readonly core: string,
    readonly trail: string,
  ) {}

  static parse(word: string): VerseWord {
    const match = VerseWord.shape.exec(word)!;
    return new VerseWord(match[1], match[2], match[3]);
  }

  private static readonly shape = /^([^\p{L}\p{N}]*)(.*?)([^\p{L}\p{N}]*)$/u;
}

/**
 * A verse with some of its words taken out, and a bank to fill them
 * from: the right words and as many wrong ones from the same verse.
 */
export class Cloze {
  readonly words: readonly VerseWord[];

  /** Indices into `words` of the blanks, in order. */
  readonly blanks: readonly number[];

  /** Words to fill the blanks from, shuffled. */
  readonly bank: readonly string[];

  constructor(init: { words: readonly VerseWord[]; blanks: readonly number[]; bank: readonly string[] }) {
    this.words = init.words;
    this.blanks = init.blanks;
    this.bank = init.bank;
  }

  /** One word in `every` blanked, at least one and at most `most`. */
  static make(text: string, random: RandomSource, options: { every?: number; most?: number } = {}): Cloze {
    const { every = 5, most = 6 } = options;
    const words = wordsOf(text).map(VerseWord.parse);
    const candidates: number[] = [];
    for (let i = 0; i < words.length; i++) {
      if (words[i].core.length >= 3) candidates.push(i);
    }
    shuffle(candidates, random);
    const count = Math.min(Math.max(Math.round(words.length / every), 1), most);
    const blanks = candidates.slice(0, count).sort((a, b) => a - b);
    const blanked = new Set(blanks.map((i) => words[i].core));
    const otherSet = new Set<string>();
    for (let i = 0; i < words.length; i++) {
      if (!blanks.includes(i) && words[i].core.length >= 3 && !blanked.has(words[i].core)) {
        otherSet.add(words[i].core);
      }
    }
    const others = shuffle([...otherSet], random);
    const bank = shuffle([...blanks.map((i) => words[i].core), ...others.slice(0, blanks.length)], random);
    return new Cloze({ words, blanks, bank });
  }

  /** The right word for the nth blank. */
  answer(blank: number): string {
    return this.words[this.blanks[blank]].core;
  }

  /** Whether `filled`, one word per blank in order, is right throughout. */
  check(filled: readonly (string | null)[]): boolean {
    if (filled.length !== this.blanks.length) return false;
    for (let i = 0; i < this.blanks.length; i++) {
      if (filled[i] !== this.answer(i)) return false;
    }
    return true;
  }
}

/**
 * Whether a verse written out is the verse: word for word once case and
 * punctuation are set aside, with one slip forgiven in any word of five
 * letters or more — a letter wrong, missing, added, or two swapped.
 */
export const TypedVerse = {
  matches(typed: string, text: string): boolean {
    const given = TypedVerse.words(typed);
    const wanted = TypedVerse.words(text);
    if (given.length !== wanted.length) return false;
    for (let i = 0; i < wanted.length; i++) {
      if (given[i] === wanted[i]) continue;
      if (wanted[i].length < 5 || TypedVerse.editDistance(given[i], wanted[i]) > 1) {
        return false;
      }
    }
    return true;
  },

  /**
   * The words of `text`, lower case, with everything but letters,
   * digits and apostrophes taken out.
   */
  words(text: string): string[] {
    return text
      .toLowerCase()
      .replace(/[’‘]/g, "'")
      .replace(/[^\p{L}\p{N}']+/gu, ' ')
      .split(' ')
      .filter((w) => w.length > 0);
  },

  /**
   * Edits to turn `a` into `b`, a swap of two neighbouring letters
   * counting as one.
   */
  editDistance(a: string, b: string): number {
    let before: number[] | null = null;
    let previous: number[] = Array.from({ length: b.length + 1 }, (_, j) => j);
    for (let i = 1; i <= a.length; i++) {
      const current: number[] = [i, ...new Array<number>(b.length).fill(0)];
      for (let j = 1; j <= b.length; j++) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1;
        let best = Math.min(Math.min(previous[j] + 1, current[j - 1] + 1), previous[j - 1] + cost);
        if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1] && before![j - 2] + 1 < best) {
          best = before![j - 2] + 1;
        }
        current[j] = best;
      }
      before = previous;
      previous = current;
    }
    return previous[b.length];
  },
};

/**
 * The clauses a long verse is built from, cumulatively: the first, then
 * the first two, and so on to the whole, so that each step rehearses
 * what came before it. A short verse is one step.
 */
export const VerseSteps = {
  /** Words from which a verse is built in steps. */
  minWords: 14,

  of(text: string): string[] {
    const words = wordsOf(text);
    if (words.length < VerseSteps.minWords) return [text];
    const parts: string[] = [];
    let run: string[] = [];
    for (const word of words) {
      run.push(word);
      if (/[,;:.!?]["”’]?$/.test(word) && run.length >= 3) {
        parts.push(run.join(' '));
        run = [];
      }
    }
    if (run.length > 0) {
      if (run.length < 3 && parts.length > 0) {
        parts[parts.length - 1] = `${parts[parts.length - 1]} ${run.join(' ')}`;
      } else {
        parts.push(run.join(' '));
      }
    }
    if (parts.length < 3) return [text];
    const steps: string[] = [];
    for (let k = 1; k <= parts.length; k++) steps.push(parts.slice(0, k).join(' '));
    return steps;
  },
};
