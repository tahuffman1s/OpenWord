import { describe, expect, it } from 'vitest';
import { LibraryController, LibraryStatus } from '../src/data/library';
import { Translations } from '../src/data/translations';
import { BibFile } from '../src/model/bibFile';
import { FixtureBundle, otherTranslation, testTranslation } from './fixtures';
import { FsAssetBundle } from './fsAssets';

describe('the bundled translations', () => {
  it('every bundled translation has an asset path', () => {
    expect(Translations.all.length).toBeGreaterThan(0);
    for (const translation of Translations.all) {
      expect(Translations.assetFor(translation.id)).toBe(`assets/bible/${translation.id}.bib`);
      expect(translation.license).toBe('Public Domain');
    }
    expect(Translations.byId('nope').id).toBe(Translations.fallback.id);
  });

  it('every bundled asset really is the .bib it claims to be', async () => {
    // Reads the files that ship, not a fixture: a rebuilt asset that went
    // out under the wrong name or the wrong format would pass every other
    // test here.
    const bundle = new FsAssetBundle();
    for (const translation of Translations.all) {
      const bytes = await bundle.load(Translations.assetFor(translation.id));
      const head = bytes.subarray(0, BibFile.maxHeaderLength);

      expect(BibFile.looksLikeBib(head)).toBe(true);
      const info = BibFile.readInfo(head);
      expect(info.id).toBe(translation.id);
      expect(info.name).toBe(translation.name);
      expect(info.abbreviation).toBe(translation.abbreviation);
      expect(info.license).toBe(translation.license);
      expect(info.sourceUrl).toBe(translation.sourceUrl);
    }
  });

  it('a bundled .bib decodes into the whole translation', async () => {
    // One of the three, in full: the others are the same code path, and a
    // whole Bible is a second of work.
    const bytes = await new FsAssetBundle().load(Translations.assetFor(Translations.fallback.id));
    const bible = BibFile.decode(bytes);

    expect(bible.translation.id).toBe(Translations.fallback.id);
    expect(bible.books.length).toBeGreaterThan(66);
    expect(bible.verseCount).toBeGreaterThan(31000);
    expect(bible.bookByCode('JHN')!.chapter(3)!.verseText(16)).toContain('God so loved the world');
  });

  it('the library opens a bundled translation from the real assets', async () => {
    const library = new LibraryController({ bundle: new FsAssetBundle() });

    await library.load(Translations.bsb.id);

    expect(library.isReady).toBe(true);
    expect(library.translation.id).toBe(Translations.bsb.id);
    expect(library.bible!.bookByCode('JHN')!.chapter(3)!.verseText(16)).toContain('God so loved the world');
    // The outline is read; not a word of Genesis is unpacked for it.
    expect(library.bible!.bookByCode('GEN')!.isLoaded).toBe(false);
  });
});

describe('the library', () => {
  it('loads the bundled Scripture with no network at all', async () => {
    const bundle = new FixtureBundle();
    const library = new LibraryController({ bundle });
    expect(library.status).toBe(LibraryStatus.loading);

    await library.load(testTranslation.id);

    expect(library.status).toBe(LibraryStatus.ready);
    expect(library.isReady).toBe(true);
    expect(library.bible!.books).toHaveLength(3);
    expect(library.translation.abbreviation).toBe('TST');
    expect(bundle.loaded).toEqual([`assets/bible/${testTranslation.id}.bib`]);
  });

  it('falls back to the default translation when an asset is missing', async () => {
    const bundle = new FixtureBundle();
    const library = new LibraryController({ bundle });

    await library.load('eng-gb-webbe'); // not in the fixture bundle

    expect(library.isReady).toBe(true);
    expect(library.bible!.translation.id).toBe(Translations.fallback.id);
  });

  it('reports failure when even the default cannot be read', async () => {
    const library = new LibraryController({ bundle: new FixtureBundle({ assets: new Map() }) });

    await library.load(Translations.fallback.id);

    expect(library.status).toBe(LibraryStatus.failed);
    expect(library.isReady).toBe(false);
    expect(library.errorMessage).not.toBeNull();
  });

  it('tells its listeners as it goes', async () => {
    const library = new LibraryController({ bundle: new FixtureBundle() });
    const seen: LibraryStatus[] = [];
    library.addListener(() => seen.push(library.status));

    await library.load(testTranslation.id);

    expect(seen).toEqual([LibraryStatus.loading, LibraryStatus.ready]);
  });

  it('loads and drops the comparison translation on demand', async () => {
    const library = new LibraryController({ bundle: new FixtureBundle() });
    await library.load(testTranslation.id);
    expect(library.comparison).toBeNull();

    await library.loadComparison(otherTranslation.id);
    expect(library.comparison!.translation.abbreviation).toBe('OTH');
    expect(library.comparison!.bookByCode('GEN')!.chapter(1)!.verseText(1)).toBe(
      'At the first God made the heaven and the earth.',
    );

    library.clearComparison();
    expect(library.comparison).toBeNull();
  });

  it('comparing with the translation being read is a no-op', async () => {
    const library = new LibraryController({ bundle: new FixtureBundle() });
    await library.load(testTranslation.id);
    await library.loadComparison(testTranslation.id);
    expect(library.comparison).toBeNull();
  });

  it('switching translation drops a stale comparison', async () => {
    const library = new LibraryController({ bundle: new FixtureBundle() });
    await library.load(testTranslation.id);
    await library.loadComparison(otherTranslation.id);
    expect(library.comparison).not.toBeNull();

    await library.load(otherTranslation.id);
    expect(library.bible!.translation.id).toBe(otherTranslation.id);
    expect(library.comparison).toBeNull();
  });

  it('a comparison that cannot be read is simply not there', async () => {
    const library = new LibraryController({ bundle: new FixtureBundle() });
    await library.load(testTranslation.id);

    await library.loadComparison('eng-gb-webbe'); // not in the fixture bundle

    expect(library.comparison).toBeNull();
    expect(library.loadingComparison).toBe(false);
  });
});
