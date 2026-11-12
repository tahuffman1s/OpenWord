import { describe, expect, it, vi } from 'vitest';

// The card's "Colour" style reads the Material kit's palette, whose colour
// library does not load under Node; nothing tested here draws.
vi.mock('../src/ui/m3', () => ({
  currentScheme: () => ({}),
  hexOf: () => '#000000',
}));

import { CardStyle, VerseCard, cardStyleLabel, cardStyles, wrapLines } from '../src/ui/verseShare';

describe('a verse as a picture', () => {
  it('longer passages are set smaller on a card', () => {
    expect(VerseCard.fontSizeFor('short')).toBeGreaterThan(VerseCard.fontSizeFor('x'.repeat(500)));
  });

  it('steps down through five sizes and no further', () => {
    const sizes = [100, 200, 400, 600, 5000].map((length) => VerseCard.fontSizeFor('x'.repeat(length)));

    expect(sizes).toEqual([25, 21, 17.5, 15, 13]);
    expect(VerseCard.fontSizeFor('x'.repeat(120))).toBe(25);
    expect(VerseCard.fontSizeFor('x'.repeat(121))).toBe(21);
  });

  it('is the portrait shape social apps show without cropping', () => {
    expect(VerseCard.size.width * VerseCard.pixelRatio).toBe(1080);
    expect(VerseCard.size.height * VerseCard.pixelRatio).toBe(1350);
  });

  it('comes in four styles, each with a name', () => {
    expect(cardStyles).toEqual([CardStyle.paper, CardStyle.night, CardStyle.colour, CardStyle.dawn]);
    expect(cardStyles.map((style) => cardStyleLabel[style])).toEqual(['Paper', 'Night', 'Colour', 'Dawn']);
  });

  it('breaks the words into lines no wider than the card', () => {
    // Every letter as wide as the next: ten to a line.
    const lines = wrapLines('For God so loved the world, that he gave', 10, (line) => line.length);

    expect(lines).toEqual(['For God so', 'loved the', 'world,', 'that he', 'gave']);
    expect(lines.every((line) => line.length <= 10)).toBe(true);
  });

  it('a word longer than the line stands on a line of its own', () => {
    expect(wrapLines('a Mahershalalhashbaz b', 6, (line) => line.length)).toEqual(['a', 'Mahershalalhashbaz', 'b']);
  });
});
