import { describe, expect, it } from 'vitest';
import { BibFile } from '../src/model/bibFile';
import { Bible, Block, BlockStyle, Book, Chapter, TranslationInfo, Versification, type VerseSegment } from '../src/model/bible';
import { BookMeta, BookSection } from '../src/model/bookMeta';
import { VersificationCheck, VersificationMatch } from '../src/model/versificationCheck';
import { FsAssetBundle } from './fsAssets';

/** A Bible of `books`, each chapter holding `verses` verses. */
function bibleOf(books: Map<string, number[]>): Bible {
  return new Bible({
    translation: new TranslationInfo({ id: 'x', name: 'X', abbreviation: 'X', license: '', sourceUrl: '' }),
    books: [...books].map(([code, counts]) =>
      Book.of(
        BookMeta.lookup(code)!,
        counts.map((verses, c) => {
          const segments: VerseSegment[] = [];
          for (let v = 1; v <= verses; v++) segments.push({ verse: v, startsVerse: true, text: 'x' });
          return new Chapter({ number: c + 1, blocks: [new Block({ style: BlockStyle.paragraph, segments })], notes: [] });
        }),
      ),
    ),
  });
}

/** The reference itself, which must of course match. */
const english = (): Map<string, number[]> => new Map([...VersificationCheck.reference].map(([k, v]) => [k, [...v]]));

describe('measuring a Bible against the English numbering', () => {
  it('the reference matches itself exactly', () => {
    const match = VersificationCheck.against(bibleOf(english()));

    expect(match.differing).toBe(0);
    expect(match.compared).toBe(1189);
    expect(match.matchesEnglish).toBe(true);
    expect(match.versification).toBe(Versification.english);
  });

  it('an ordinary English edition matches', () => {
    // Editions differ over Romans' floating doxology and little else.
    const nearly = english();
    nearly.get('ROM')![13] = 26;
    nearly.get('ROM')![15] = 25;

    const match = VersificationCheck.against(bibleOf(nearly));

    expect(match.differing).toBe(2);
    expect(match.fraction).toBeLessThan(VersificationMatch.tolerance);
    expect(match.versification).toBe(Versification.english);
  });

  it('a Bible that counts psalm superscriptions does not', () => {
    // What the Masoretic numbering does: the superscription is verse 1,
    // so most of the Psalms run one longer.
    const masoretic = english();
    const psalms = masoretic.get('PSA')!;
    for (let i = 0; i < psalms.length; i++) psalms[i] += 1;

    const match = VersificationCheck.against(bibleOf(masoretic));

    expect(match.differing).toBe(150);
    expect(match.fraction).toBeGreaterThan(VersificationMatch.tolerance);
    expect(match.matchesEnglish).toBe(false);
    expect(match.versification).toBe(Versification.other);
    expect(match.examples[0]).toContain('Psalms');
    expect(match.toString()).toMatch(/^150 of 1189 chapters differ \(12\.6%\)$/);
  });

  it('a book of the wrong length counts against it', () => {
    // Joel is 3 chapters in English and 4 in Hebrew.
    const joel = english();
    joel.get('JOL')!.push(21);

    const match = VersificationCheck.against(bibleOf(joel));

    expect(match.differing).toBe(1);
    expect(match.examples).toHaveLength(1);
    expect(match.examples[0]).toContain('chapters');
  });

  it('too small a Bible says nothing rather than guessing', () => {
    const match = VersificationCheck.against(bibleOf(new Map([['JHN', english().get('JHN')!]])));

    expect(match.isInconclusive).toBe(true);
    expect(match.matchesEnglish).toBe(false);
    expect(match.versification).toBe(Versification.unknown);
  });

  it('the deuterocanon is left out of the comparison', () => {
    // English editions disagree over these while agreeing entirely about
    // the rest, so counting them would raise a false alarm.
    const withExtra = english();
    withExtra.set('TOB', [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]);

    const match = VersificationCheck.against(bibleOf(withExtra));

    expect(match.compared).toBe(1189);
    expect(match.differing).toBe(0);
    expect(match.versification).toBe(Versification.english);
  });
});

describe('what the app does with the answer', () => {
  it('only a measured mismatch withholds the verse-anchored layers', () => {
    expect(Versification.mayAnchorEnglish(Versification.english)).toBe(true);
    // Every file written before this was checked says nothing, and must
    // keep working as it did.
    expect(Versification.mayAnchorEnglish(Versification.unknown)).toBe(true);
    expect(Versification.mayAnchorEnglish(Versification.other)).toBe(false);
  });

  it('it survives a round trip through a .bib file', () => {
    const bible = new Bible({
      translation: bibleOf(new Map()).translation.copyWith({ versification: Versification.other }),
      books: [...bibleOf(new Map([['GEN', english().get('GEN')!]])).books],
    });

    const info = BibFile.readInfo(BibFile.encode(bible));
    expect(info.versification).toBe(Versification.other);
    expect(Versification.mayAnchorEnglish(info.versification)).toBe(false);
  });
});

describe('the shipped table', () => {
  it('covers the Protestant canon and nothing else', () => {
    expect(VersificationCheck.reference.size).toBe(66);
    for (const code of VersificationCheck.reference.keys()) {
      const meta = BookMeta.lookup(code);
      expect(meta, `${code} is not a book`).toBeDefined();
      expect(meta!.section).not.toBe(BookSection.deuterocanon);
    }
    let chapters = 0;
    for (const counts of VersificationCheck.reference.values()) chapters += counts.length;
    expect(chapters).toBe(1189);
  });

  it('every translation the app ships matches it', async () => {
    const bundle = new FsAssetBundle();
    for (const id of ['eng-web', 'eng-bsb', 'eng-gb-webbe']) {
      const bible = BibFile.decode(await bundle.load(`assets/bible/${id}.bib`));
      const match = VersificationCheck.against(bible);
      expect(match.versification, `${id}: ${match}`).toBe(Versification.english);
    }
  });
});
