import { Reference, type Bible } from './bible';

/**
 * Verses worth knowing by heart, for a reader with nothing on the ladder
 * yet, or one wondering what to add next.
 *
 * The well-worn ones: the verses people reach for in comfort and in
 * trouble, the ones a child learns first. A translation that lacks one
 * simply does not offer it.
 */
export class SuggestedVerse {
  constructor(
    readonly reference: Reference,
    /** What the verse is for, in a word: what a list groups it under. */
    readonly theme: string,
  ) {}

  static readonly all: readonly SuggestedVerse[] = [
    new SuggestedVerse(new Reference('JHN', 3, 16), 'Love'),
    new SuggestedVerse(new Reference('PSA', 23, 1), 'Comfort'),
    new SuggestedVerse(new Reference('ROM', 8, 28), 'Trust'),
    new SuggestedVerse(new Reference('PHP', 4, 13), 'Strength'),
    new SuggestedVerse(new Reference('PRO', 3, 5), 'Trust'),
    new SuggestedVerse(new Reference('JER', 29, 11), 'Promise'),
    new SuggestedVerse(new Reference('ISA', 41, 10), 'Comfort'),
    new SuggestedVerse(new Reference('MAT', 11, 28), 'Comfort'),
    new SuggestedVerse(new Reference('PSA', 119, 105), 'Guidance'),
    new SuggestedVerse(new Reference('JOS', 1, 9), 'Strength'),
    new SuggestedVerse(new Reference('PHP', 4, 6), 'Peace'),
    new SuggestedVerse(new Reference('1CO', 13, 4), 'Love'),
    new SuggestedVerse(new Reference('GAL', 5, 22), 'Character'),
    new SuggestedVerse(new Reference('HEB', 11, 1), 'Faith'),
    new SuggestedVerse(new Reference('2TI', 3, 16), 'Scripture'),
    new SuggestedVerse(new Reference('EPH', 2, 8), 'Grace'),
    new SuggestedVerse(new Reference('ROM', 12, 2), 'Character'),
    new SuggestedVerse(new Reference('PSA', 46, 1), 'Comfort'),
    new SuggestedVerse(new Reference('MAT', 6, 33), 'Trust'),
    new SuggestedVerse(new Reference('JHN', 14, 6), 'Jesus'),
    new SuggestedVerse(new Reference('1JN', 1, 9), 'Grace'),
    new SuggestedVerse(new Reference('PSA', 27, 1), 'Strength'),
    new SuggestedVerse(new Reference('ISA', 40, 31), 'Strength'),
    new SuggestedVerse(new Reference('2CO', 5, 17), 'Grace'),
    new SuggestedVerse(new Reference('JHN', 1, 1), 'Jesus'),
    new SuggestedVerse(new Reference('GEN', 1, 1), 'Beginnings'),
    new SuggestedVerse(new Reference('PSA', 1, 1), 'Guidance'),
    new SuggestedVerse(new Reference('MAT', 28, 19), 'Mission'),
  ];

  /**
   * The suggestions `bible` has the text for, in the order above, with
   * the ones already being learnt left out.
   */
  static available(bible: Bible, alreadyLearning?: (reference: Reference) => boolean): SuggestedVerse[] {
    const out: SuggestedVerse[] = [];
    for (const suggestion of SuggestedVerse.all) {
      if (alreadyLearning?.(suggestion.reference) ?? false) continue;
      const text = bible
        .bookByCode(suggestion.reference.bookCode)
        ?.chapter(suggestion.reference.chapter)
        ?.verseText(suggestion.reference.verse!);
      if (text !== undefined && text.length > 0) out.push(suggestion);
    }
    return out;
  }
}
