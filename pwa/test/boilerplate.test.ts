import { describe, expect, it } from 'vitest';
import { Block, BlockStyle, Book, Chapter } from '../src/model/bible';
import { stripBoilerplate } from '../src/model/boilerplate';
import { BookMeta } from '../src/model/bookMeta';

// Only the rule itself is tested here. The EPUB importer and the .bib
// tidier, which apply it, have tests of their own.

function book(code: string, chapters: string[][], firstVerse = 1): Book {
  return Book.of(
    BookMeta.lookup(code)!,
    chapters.map(
      (lines, i) =>
        new Chapter({
          number: i + 1,
          notes: [],
          blocks: lines.map(
            (line) =>
              new Block({
                style: BlockStyle.paragraph,
                segments: [
                  // A line ending in "!" is one that belongs to a verse.
                  { verse: line.endsWith('!') ? firstVerse : 0, startsVerse: line.endsWith('!'), text: line },
                ],
              }),
          ),
        }),
    ),
  );
}

describe('furniture is what repeats around every book', () => {
  it('text belonging to a verse is never touched', () => {
    // "Amen." ends book after book and is Scripture every time. It is
    // safe because it sits inside a verse, which puts it out of reach.
    const swept = stripBoilerplate([
      book('MAT', [['The book of the generations!', 'Amen.']]),
      book('MRK', [['The beginning of the gospel!', 'Amen.']]),
      book('LUK', [['Forasmuch as many!', 'Amen.']]),
    ]);
    // Standing on its own outside a verse, three times over, it goes.
    expect(swept.removed).toEqual(['Amen.']);
    for (const b of swept.books) expect(b.chapter(1)!.blocks).toHaveLength(1);

    const inVerse = stripBoilerplate([
      book('MAT', [['The generations. Amen.!']]),
      book('MRK', [['The gospel. Amen.!']]),
      book('LUK', [['Forasmuch as many. Amen.!']]),
    ]);
    expect(inVerse.removed).toEqual([]);
    expect(inVerse.isEmpty).toBe(true);
  });

  it('two books are not enough to condemn a line', () => {
    // A pair can share a line honestly. Three is where coincidence
    // stops being the likely explanation.
    const two = stripBoilerplate([
      book('MAT', [['Now to him that is of power', 'The gospel!']]),
      book('MRK', [['Now to him that is of power', 'The gospel!']]),
    ]);
    expect(two.removed).toEqual([]);
  });

  it('and repeating inside one book is not repeating across books', () => {
    // A psalm's superscription repeats a hundred times over and is
    // Scripture every time; Psalms is one book, and one is not three.
    const psalms = stripBoilerplate([
      book('PSA', [
        ['A Psalm of David.', 'Blessed is the man!'],
        ['A Psalm of David.', 'Why do the nations rage!'],
        ['A Psalm of David.', 'O LORD, how many are my foes!'],
      ]),
    ]);
    expect(psalms.removed).toEqual([]);
  });

  it('a blank is not a line', () => {
    // An edition that spaces its furniture out would otherwise have
    // every stanza break in the Bible counted as one thing.
    const spaced = stripBoilerplate(
      ['MAT', 'MRK', 'LUK'].map((code) =>
        Book.of(BookMeta.lookup(code)!, [
          new Chapter({
            number: 1,
            notes: [],
            blocks: [
              new Block({ style: BlockStyle.blank }),
              new Block({ style: BlockStyle.paragraph, segments: [{ verse: 1, startsVerse: true, text: 'Text.' }] }),
              new Block({ style: BlockStyle.blank }),
            ],
          }),
        ]),
      ),
    );
    expect(spaced.removed).toEqual([]);
    for (const b of spaced.books) {
      expect(b.chapter(1)!.blocks).toHaveLength(3);
    }
  });

  it('a heading is never furniture, and the furniture is listed longest first', () => {
    const books = ['2PE', '1JN', '2JN', '3JN'].map((code) =>
      Book.of(BookMeta.lookup(code)!, [
        new Chapter({
          number: 1,
          notes: [],
          blocks: [
            new Block({ style: BlockStyle.heading, segments: [{ verse: 0, startsVerse: false, text: 'Greeting' }] }),
            new Block({ style: BlockStyle.paragraph, segments: [{ verse: 1, startsVerse: true, text: 'Grace to you.' }] }),
            new Block({ style: BlockStyle.paragraph, segments: [{ verse: 0, startsVerse: false, text: 'ESV' }] }),
            new Block({ style: BlockStyle.paragraph, segments: [{ verse: 0, startsVerse: false, text: 'The Old Testament' }] }),
            new Block({ style: BlockStyle.paragraph, segments: [{ verse: 0, startsVerse: false, text: 'Show Last Hilite' }] }),
          ],
        }),
      ]),
    );
    const swept = stripBoilerplate(books);
    expect(swept.removed).toEqual(['The Old Testament', 'Show Last Hilite', 'ESV']);
    for (const b of swept.books) {
      expect(b.chapter(1)!.blocks.map((block) => block.style)).toEqual([BlockStyle.heading, BlockStyle.paragraph]);
    }
  });
});
