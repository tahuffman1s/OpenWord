import { strToU8 } from 'fflate';
import { deleteDB } from 'idb';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { answer } from '../src/data/importWorker';
import { LibraryController } from '../src/data/library';
import { importFile, Shelf } from '../src/data/shelf';
import { IdbShelfStore, MemoryShelfStore, type ShelfStore } from '../src/data/shelfStore';
import { Translations } from '../src/data/translations';
import { BibFile, BibFormatException } from '../src/model/bibFile';
import { epub } from './epubFixtures';
import { FixtureBundle, sampleBible, testTranslation } from './fixtures';

const someEpub = (title = 'Test Standard Version'): Uint8Array =>
  epub({
    title,
    documents: [
      [
        'gen.xhtml',
        '<h1>Genesis</h1><h2>1</h2>' +
          '<p><sup>1</sup>In the beginning God created.</p>' +
          '<p><sup>2</sup>The earth was formless.</p>',
      ],
    ],
  });

/** The two stores the shelf can sit on, each put through the same paces. */
interface Backing {
  name: string;
  /** A fresh, empty store. */
  open(): Promise<ShelfStore>;
  /** The same store again, the way a new session would find it. */
  reopen(): Promise<ShelfStore>;
  /** Whether a file is still there, by its path. */
  exists(path: string): Promise<boolean>;
  /** What `copy` handed out under a name. */
  copied(destination: string): Uint8Array | undefined;
  close(): Promise<void>;
}

function memoryBacking(): Backing {
  let store: MemoryShelfStore;
  return {
    name: 'in memory',
    async open() {
      store = new MemoryShelfStore();
      return store;
    },
    async reopen() {
      return store;
    },
    async exists(path) {
      try {
        await store.read(path);
        return true;
      } catch {
        return false;
      }
    },
    copied: (destination) => store.copies.get(destination),
    async close() {},
  };
}

function idbBacking(): Backing {
  const copies = new Map<string, Uint8Array>();
  const opened: IdbShelfStore[] = [];
  const save = async (name: string, bytes: Uint8Array): Promise<void> => {
    copies.set(name, bytes);
  };
  const openStore = async (): Promise<IdbShelfStore> => {
    const store = await IdbShelfStore.open({ save });
    expect(store).not.toBeNull();
    opened.push(store!);
    return store!;
  };
  return {
    name: 'in IndexedDB',
    async open() {
      await deleteDB(IdbShelfStore.databaseName);
      return openStore();
    },
    reopen: openStore,
    async exists(path) {
      try {
        await opened[opened.length - 1].read(path);
        return true;
      } catch {
        return false;
      }
    },
    copied: (destination) => copies.get(destination),
    async close() {
      for (const store of opened) store.close();
      opened.length = 0;
      await deleteDB(IdbShelfStore.databaseName);
    },
  };
}

for (const backing of [memoryBacking(), idbBacking()]) {
  describe(`a shelf kept ${backing.name}`, () => {
    let shelf: Shelf;

    beforeEach(async () => {
      shelf = new Shelf(await backing.open());
      await shelf.refresh();
    });

    afterEach(() => backing.close());

    it('an empty store is an empty shelf', () => {
      expect(shelf.isEmpty).toBe(true);
      expect(shelf.loaded).toBe(true);
      expect(shelf.has('anything')).toBe(false);
    });

    it('an EPUB is converted and kept as a .bib', async () => {
      const result = await shelf.add(someEpub(), 'tsv.epub');

      expect(result.ok).toBe(true);
      expect(result.failure).toBeNull();
      const id = result.bible!.translation.id;
      expect(shelf.has(id)).toBe(true);
      expect(result.translation?.info.id).toBe(id);

      const path = shelf.byId(id)!.path;
      expect(path.endsWith('.bib')).toBe(true);
      const kept = await shelf.store.read(path);
      expect(BibFile.looksLikeBib(kept)).toBe(true);
      expect(shelf.byId(id)!.bytes).toBe(kept.length);
      expect(shelf.byId(id)!.readableSize.length).toBeGreaterThan(0);
    });

    it('what was written reads back as the same Scripture', async () => {
      const result = await shelf.add(someEpub(), 'tsv.epub');
      const read = await shelf.read(result.bible!.translation.id);

      expect(read.books).toHaveLength(1);
      expect(read.books[0].code).toBe('GEN');
      expect(read.books[0].chapter(1)!.verseText(2)).toBe('The earth was formless.');
      expect(read.translation.name).toBe('Test Standard Version');
    });

    it('a .bib is taken as it is, without conversion', async () => {
      const bytes = BibFile.encode(sampleBible());

      const result = await shelf.add(bytes, 'test.bib');

      expect(result.ok).toBe(true);
      expect(result.warnings).toEqual([]);
      expect(shelf.byId(testTranslation.id)).not.toBeNull();
      // Copied byte for byte rather than re-encoded.
      expect(await shelf.store.read(shelf.byId(testTranslation.id)!.path)).toEqual(bytes);
    });

    it('a new shelf finds what an earlier one left', async () => {
      await shelf.add(BibFile.encode(sampleBible()), 'test.bib');

      const reopened = new Shelf(await backing.reopen());
      await reopened.refresh();

      expect(reopened.translations).toHaveLength(1);
      expect(reopened.translations[0].info.abbreviation).toBe('TST');
      expect(reopened.translations[0].info.name).toBe(testTranslation.name);
    });

    it('the shelf is listed by name', async () => {
      await shelf.add(someEpub('Zebra Version'), 'z.epub');
      await shelf.add(someEpub('Alpha Version'), 'a.epub');

      expect(shelf.translations.map((shelved) => shelved.info.name)).toEqual(['Alpha Version', 'Zebra Version']);
    });

    it('importing the same file twice keeps one copy', async () => {
      await shelf.add(someEpub(), 'tsv.epub');
      await shelf.add(someEpub(), 'tsv-again.epub');

      expect(shelf.translations).toHaveLength(1);
    });

    it('tells its listeners when it changes', async () => {
      let told = 0;
      shelf.addListener(() => told++);

      await shelf.add(someEpub(), 'tsv.epub');

      expect(told).toBe(1);
    });

    it('removing takes the file with it', async () => {
      const result = await shelf.add(someEpub(), 'tsv.epub');
      const id = result.bible!.translation.id;
      const path = shelf.byId(id)!.path;

      await shelf.remove(id);

      expect(shelf.has(id)).toBe(false);
      expect(await backing.exists(path)).toBe(false);
      // Removing what is not there is not an error.
      await shelf.remove(id);
    });

    it('a copy can be kept somewhere else', async () => {
      const result = await shelf.add(someEpub(), 'tsv.epub');
      const id = result.bible!.translation.id;

      await shelf.copyTo(id, 'backup.bib');

      const copy = backing.copied('backup.bib');
      expect(copy).toBeDefined();
      expect(BibFile.decode(copy!).books).toHaveLength(1);
      expect(await shelf.fileBytes(id)).toEqual(copy);
      expect(await shelf.fileBytes('nope')).toBeNull();
    });

    it('a file that is neither is refused with a reason', async () => {
      const result = await shelf.add(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]), 'notes.txt');

      expect(result.ok).toBe(false);
      expect(result.failure).toContain('not an EPUB');
      expect(shelf.isEmpty).toBe(true);
    });

    it('a .bib of a version this app cannot read is refused', async () => {
      const bytes = BibFile.encode(sampleBible());
      bytes[3] = BibFile.version + 1;

      const result = await shelf.add(bytes, 'future.bib');

      expect(result.ok).toBe(false);
      expect(result.failure).toContain('version');
      expect(shelf.isEmpty).toBe(true);
    });

    it('a stray file in the store is passed over, not fatal', async () => {
      await shelf.add(someEpub(), 'tsv.epub');
      await shelf.store.write('rubbish.bib', strToU8('not scripture'));
      await shelf.store.write('notes.txt', strToU8('nor this'));

      await shelf.refresh();

      expect(shelf.translations).toHaveLength(1);
    });

    it('reading a translation that is not there says so', async () => {
      await expect(shelf.read('nope')).rejects.toThrow(BibFormatException);
    });

    it('a sweep is offered before anything is written, and replaces the file after', async () => {
      const result = await shelf.add(BibFile.encode(sampleBible()), 'test.bib');
      const id = result.bible!.translation.id;

      // The sample has no furniture in it, so there is nothing to offer.
      const tidied = await shelf.tidy(id);
      expect(tidied.failure).toBeNull();
      expect(tidied.foundSomething).toBe(false);
      expect((await shelf.tidy('nope')).failure).toBe('not on the shelf');

      // Replacing puts whatever is handed in under the same id.
      const replacement = BibFile.encode(sampleBible());
      expect(await shelf.replace(id, replacement)).toBe(true);
      expect(shelf.translations).toHaveLength(1);
      expect(await shelf.store.read(shelf.byId(id)!.path)).toEqual(replacement);
    });
  });
}

describe('listing the shelf is cheap', () => {
  it('reads only the head of each file', async () => {
    await deleteDB(IdbShelfStore.databaseName);
    const store = (await IdbShelfStore.open({ headLength: 32 }))!;
    try {
      await store.write('big.bib', new Uint8Array(100_000).fill(0x42));

      const listed = await store.list({ extension: '.bib', headLength: 16 });
      expect(listed).toHaveLength(1);
      expect(listed[0].size).toBe(100_000);
      // Never more than was asked for, and never more than was kept.
      expect(listed[0].head.length).toBe(16);
      expect((await store.list({ extension: '.bib', headLength: 1_000 }))[0].head.length).toBe(32);
      expect(await store.list({ extension: '.epub', headLength: 16 })).toEqual([]);
    } finally {
      store.close();
      await deleteDB(IdbShelfStore.databaseName);
    }
  });
});

describe('reading a big file off the UI thread', () => {
  // Only bytes come back from the worker. A Bible read from a .bib file
  // keeps a closure for unpacking each book on demand, and no worker can
  // send a closure to another — so what crosses is the file, and the
  // caller opens it on its own side.
  it('the file crosses the worker boundary, and reopens', () => {
    const imported = importFile(BibFile.encode(sampleBible()), 'test.bib');

    expect(imported.failure).toBeNull();
    expect(imported.bytes).not.toBeNull();

    const bible = BibFile.decode(imported.bytes!);
    expect(bible.books).toHaveLength(3);
    expect(bible.verseCount).toBe(sampleBible().verseCount);
    expect(bible.bookByCode('GEN')!.chapter(1)!.verseText(1)).toBe('In the beginning, God created the heavens.');
  });

  it('an EPUB comes back converted, with its warnings', () => {
    const imported = importFile(someEpub(), 'tsv.epub');

    expect(BibFile.decode(imported.bytes!).books[0].code).toBe('GEN');
  });

  it('a refusal comes back as a reason, not an exception', () => {
    const imported = importFile(new Uint8Array([1, 2, 3, 4]), 'notes.txt');

    expect(imported.bytes).toBeNull();
    expect(imported.failure).toContain('not an EPUB');
  });

  it('a damaged .bib is caught on the way in, not on the way out', () => {
    const bytes = BibFile.encode(sampleBible());
    bytes[bytes.length - 30] ^= 0x01;

    const imported = importFile(bytes, 'broken.bib');

    expect(imported.bytes).toBeNull();
    expect(imported.failure).not.toBeNull();
  });

  it('the worker answers in plain data, for either job', () => {
    const converted = answer({ kind: 'import', bytes: someEpub(), fileName: 'tsv.epub' });
    expect(converted.kind).toBe('import');
    if (converted.kind === 'import') {
      expect(converted.failure).toBeNull();
      expect(BibFile.decode(converted.bytes!).books[0].code).toBe('GEN');
    }

    const swept = answer({ kind: 'tidy', bytes: BibFile.encode(sampleBible()) });
    expect(swept.kind).toBe('tidy');
    if (swept.kind === 'tidy') {
      expect(swept.failure).toBeNull();
      expect(swept.bytes).toBeNull();
    }

    const refused = answer({ kind: 'import', bytes: new Uint8Array([1, 2, 3, 4]), fileName: 'notes.txt' });
    expect(refused.kind).toBe('import');
    if (refused.kind === 'import') expect(refused.failure).toContain('not an EPUB');
  });
});

describe('the library reads the shelf like anything else', () => {
  it('an imported translation can be loaded and compared', async () => {
    const shelf = new Shelf(new MemoryShelfStore());
    await shelf.refresh();
    const bundle = new FixtureBundle();
    const library = new LibraryController({ bundle, shelf });
    const result = await shelf.add(someEpub(), 'tsv.epub');
    const id = result.bible!.translation.id;

    expect(library.knows(id)).toBe(true);
    expect(library.isImported(id)).toBe(true);
    expect(library.infoFor(id).name).toBe('Test Standard Version');
    expect(library.available.map((translation) => translation.id)).toEqual(
      expect.arrayContaining([Translations.fallback.id, id]),
    );

    await library.load(id);
    expect(library.isReady).toBe(true);
    expect(library.bible!.books).toHaveLength(1);
    expect(library.bible!.books[0].code).toBe('GEN');
    // Nothing was asked of the asset bundle: the text came off the shelf.
    expect(bundle.loaded).toEqual([]);

    await library.loadComparison(testTranslation.id);
    expect(library.comparison!.translation.abbreviation).toBe('TST');
  });

  it('a library with no shelf is unchanged', () => {
    const library = new LibraryController({ bundle: new FixtureBundle() });

    expect(library.shelf).toBeNull();
    expect(library.isImported('whatever')).toBe(false);
    expect(library.available).toEqual([...Translations.all]);
  });
});
