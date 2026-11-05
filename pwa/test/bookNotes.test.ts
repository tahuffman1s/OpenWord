import { expect, it } from 'vitest';
import { bookNotes } from '../src/data/bookNotes';
import { BookMeta, BookSection } from '../src/model/bookMeta';

it('covers exactly the books the bundled introductions do not', () => {
  // The Protestant canon is covered by the Aquifer introductions; these
  // notes exist for the deuterocanonical books alone.
  const deuterocanon = BookMeta.all.filter((book) => book.section === BookSection.deuterocanon).map((b) => b.code);
  expect(new Set(bookNotes.keys())).toEqual(new Set(deuterocanon));
});

it('no note is written for a book that does not exist', () => {
  for (const code of bookNotes.keys()) {
    expect(BookMeta.lookup(code), `unknown book ${code}`).toBeDefined();
  }
});

it('notes are filled in and short enough to read in a sheet', () => {
  for (const [code, note] of bookNotes) {
    expect(note.genre.trim().length, code).toBeGreaterThan(0);
    expect(note.attribution.trim().length, code).toBeGreaterThan(0);
    expect(note.setting.trim().length, code).toBeGreaterThan(0);
    expect(note.summary.trim().length, code).toBeGreaterThan(40);
    expect(note.summary.trim().length, code).toBeLessThan(400);
  }
});

it('authorship is hedged rather than asserted', () => {
  // A claim as firm as "by Solomon" would be a scholarly assertion the app
  // has no business making. Sirach is the exception the rule allows for: it
  // names its own author, so saying so is reporting the book, not taking a
  // side.
  for (const [code, note] of bookNotes) {
    const attribution = note.attribution.toLowerCase();
    expect(
      attribution.includes('anonymous') ||
        attribution.includes('ascribed') ||
        attribution.includes('presented as') ||
        attribution.includes('voice') ||
        attribution.includes('adaptation') ||
        attribution.includes('abridgement') ||
        attribution.includes('names himself'),
      `${code}: "${note.attribution}"`,
    ).toBe(true);
  }
});
