import { gzipSync } from 'fflate';
import { describe, expect, it } from 'vitest';
import { BookIntro, BookIntros } from '../src/data/bookIntros';
import { FixtureBundle, fixtureIntros } from './fixtures';
import { FsAssetBundle } from './fsAssets';

describe('parsing', () => {
  it('splits an introduction into its sections', () => {
    const intro = BookIntro.parse(fixtureIntros.GEN);

    expect(intro.lead).toBe('Genesis is a book of **beginnings**.');
    expect(intro.sections.map((section) => section.title)).toEqual(['Setting', 'Author']);
    expect(intro.sections[0].body).toBe('It opens in Ur of the Chaldees.');
  });

  it('keeps sub-headings inside the section they belong to', () => {
    const intro = BookIntro.parse(fixtureIntros.GEN);

    // "Genres" is underlined with dashes, which is the level below.
    expect(intro.sections.at(-1)!.body).toContain('Genres');
    expect(intro.sections.at(-1)!.body).toContain('Narrative, with');
  });

  it('an introduction with no headings is all lead', () => {
    const intro = BookIntro.parse(fixtureIntros.PSA);

    expect(intro.lead).toBe('A collection of prayers and songs.');
    expect(intro.sections).toEqual([]);
    expect(intro.isEmpty).toBe(false);
  });

  it('hash headings split it too', () => {
    const intro = BookIntro.parse('Lead.\n\n# Author\n\nAnonymous.');

    expect(intro.lead).toBe('Lead.');
    expect(intro.sections).toHaveLength(1);
    expect(intro.sections[0].title).toBe('Author');
    expect(intro.sections[0].body).toBe('Anonymous.');
  });

  it('nothing at all parses to nothing', () => {
    expect(BookIntro.parse('').isEmpty).toBe(true);
  });
});

it('reads the introductions out of the bundle', async () => {
  const bundle = new FixtureBundle();
  const intros = new BookIntros(bundle);

  expect(await intros.forBook('GEN')).toContain('beginnings');
  expect(await intros.forBook('gen')).toContain('beginnings');
});

it('has nothing for a book the resource does not cover', async () => {
  const intros = new BookIntros(new FixtureBundle());

  // The deuterocanon is outside the Aquifer set; the app falls back to its
  // own short notes there.
  expect(await intros.forBook('TOB')).toBeNull();
});

it('reads the asset once, however many books are asked for', async () => {
  const bundle = new FixtureBundle();
  const intros = new BookIntros(bundle);

  await Promise.all([intros.forBook('GEN'), intros.forBook('PSA'), intros.forBook('GEN')]);

  expect(bundle.loaded.filter((key) => key === BookIntros.assetPath)).toHaveLength(1);
});

it('nothing is loaded until a book is asked for', async () => {
  const bundle = new FixtureBundle();
  const intros = new BookIntros(bundle);

  expect(intros.loaded('GEN')).toBeNull();
  expect(bundle.loaded).toEqual([]);

  await intros.forBook('GEN');
  expect(intros.loaded('GEN')).not.toBeNull();
});

it('a missing or unreadable asset is not fatal', async () => {
  const missing = new BookIntros(new FixtureBundle({ assets: new Map() }));
  expect(await missing.forBook('GEN')).toBeNull();

  const rubbish = new BookIntros(
    new FixtureBundle({
      assets: new Map([[BookIntros.assetPath, gzipSync(new TextEncoder().encode('["not a map"]'))]]),
    }),
  );
  expect(await rubbish.forBook('GEN')).toBeNull();
});

it('the asset that ships introduces every book of the Protestant canon', async () => {
  const intros = new BookIntros(new FsAssetBundle());

  const genesis = await intros.forBook('GEN');
  expect(genesis).not.toBeNull();
  const parsed = BookIntro.parse(genesis!);
  expect(parsed.isEmpty).toBe(false);
  expect(parsed.sections.length).toBeGreaterThan(0);

  expect(await intros.forBook('REV')).not.toBeNull();
  expect(await intros.forBook('TOB')).toBeNull();
});
