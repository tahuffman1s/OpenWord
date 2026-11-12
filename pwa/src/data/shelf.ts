import { ChangeNotifier } from '../infra/changeNotifier';
import { BibFile, BibFormatException } from '../model/bibFile';
import { Bible, TranslationInfo } from '../model/bible';
import { compareCodeUnits } from '../model/searchIndex';
import { EpubImport } from './epubImport';
import { TidyResult, tidyBib } from './importTidy';
import { openShelfStore, type ShelfFile, type ShelfStore } from './shelfStore';

/** A translation the reader brought themselves, as it sits on the shelf. */
export class ShelvedTranslation {
  readonly info: TranslationInfo;

  /** Where the `.bib` file is: its key in the store. */
  readonly path: string;

  /** How big the file is, for the reader deciding what to keep. */
  readonly bytes: number;

  readonly added: Date;

  constructor(init: { info: TranslationInfo; path: string; bytes: number; added: Date }) {
    this.info = init.info;
    this.path = init.path;
    this.bytes = init.bytes;
    this.added = init.added;
  }

  get readableSize(): string {
    const mb = 1024 * 1024;
    if (this.bytes >= mb) return `${(this.bytes / mb).toFixed(1)} MB`;
    return `${Math.round(this.bytes / 1024)} kB`;
  }
}

/**
 * The translations the reader has imported.
 *
 * Each one is a `.bib` file in a store of its own; the shelf is whatever
 * is in that store. There is no database of its own and no index file to
 * fall out of step: a `.bib` says what it holds in its own header, so
 * listing the shelf is reading a few dozen bytes of each file.
 */
export class Shelf extends ChangeNotifier {
  constructor(store: ShelfStore) {
    super();
    this.store = store;
  }

  /**
   * Opens the shelf the browser keeps, or answers null where it cannot —
   * a browser with no IndexedDB, where translations cannot be kept at all.
   */
  static async open(): Promise<Shelf | null> {
    const store = await openShelfStore();
    return store === null ? null : new Shelf(store);
  }

  /** Where the `.bib` files live. The app passes IndexedDB; tests pass memory. */
  readonly store: ShelfStore;

  private _translations: readonly ShelvedTranslation[] = [];
  private _loaded = false;

  get translations(): readonly ShelvedTranslation[] {
    return this._translations;
  }
  get isEmpty(): boolean {
    return this._translations.length === 0;
  }
  get loaded(): boolean {
    return this._loaded;
  }

  /** Reads the store. Cheap: only the header of each file. */
  async refresh(): Promise<void> {
    const found: ShelvedTranslation[] = [];
    try {
      const files = await this.store.list({
        extension: BibFile.extension,
        // The header is a few bytes plus the metadata it declares.
        headLength: BibFile.maxHeaderLength,
      });
      for (const file of files) {
        const shelved = this.describe(file);
        if (shelved !== null) found.push(shelved);
      }
    } catch (error) {
      console.warn(`OpenWord: could not read the shelf: ${String(error)}`);
    }

    found.sort((a, b) => compareCodeUnits(a.info.name.toLowerCase(), b.info.name.toLowerCase()));
    this._translations = found;
    this._loaded = true;
    this.notifyListeners();
  }

  byId(id: string): ShelvedTranslation | null {
    for (const translation of this._translations) {
      if (translation.info.id === id) return translation;
    }
    return null;
  }

  has(id: string): boolean {
    return this.byId(id) !== null;
  }

  /** Reads one of the shelved translations in full. */
  async read(id: string): Promise<Bible> {
    const shelved = this.byId(id);
    if (shelved === null) {
      throw new BibFormatException(`${id} is not on the shelf`);
    }
    return BibFile.decode(await this.store.read(shelved.path));
  }

  /**
   * A file this big is read on a worker of its own. Below it the work is
   * a few milliseconds, and staying put keeps tests — which run under
   * Node, where there is no worker — from needing one.
   */
  static readonly isolateAbove = 128 * 1024;

  /**
   * Takes a file the reader chose — a `.bib` or an EPUB — and puts a `.bib`
   * on the shelf. The EPUB is converted; a `.bib` is checked and copied.
   */
  async add(bytes: Uint8Array, fileName: string): Promise<ShelfResult> {
    const imported =
      bytes.length >= Shelf.isolateAbove && hasWorkers()
        ? await importOnWorker(bytes, fileName)
        : importFile(bytes, fileName);

    const encoded = imported.bytes;
    if (encoded === null) {
      return ShelfResult.failed(imported.failure ?? 'That file cannot be read.');
    }

    // Opening it happens here rather than on the worker: a Bible read from
    // a .bib file keeps a way of unpacking each book on demand, and a
    // closure cannot be sent between workers. It is cheap — the outline is
    // read and not a word of Scripture.
    let bible: Bible;
    try {
      bible = BibFile.decode(encoded);
    } catch (error) {
      return ShelfResult.failed(`That translation could not be read: ${errorText(error)}`);
    }

    try {
      await this.store.write(Shelf.fileName(bible.translation.id), encoded);
    } catch (error) {
      return ShelfResult.failed(`That translation could not be kept: ${errorText(error)}`);
    }
    await this.refresh();
    return new ShelfResult({
      translation: this.byId(bible.translation.id),
      bible,
      warnings: imported.warnings,
    });
  }

  /** The `.bib` file itself, for handing to a file picker or a share sheet. */
  async fileBytes(id: string): Promise<Uint8Array | null> {
    const shelved = this.byId(id);
    if (shelved === null) return null;
    return this.store.read(shelved.path);
  }

  /**
   * Writes a copy of a shelved translation somewhere else — sharing it, or
   * keeping it where a backup will find it. On the web, `path` is the name
   * the file is saved or shared as.
   */
  async copyTo(id: string, path: string): Promise<void> {
    const shelved = this.byId(id);
    if (shelved === null) return;
    await this.store.copy(shelved.path, path);
  }

  /**
   * What sweeping a shelved translation would take out of it. Nothing is
   * written: the reader is shown what would go first.
   */
  async tidy(id: string): Promise<TidyResult> {
    const shelved = this.byId(id);
    if (shelved === null) return TidyResult.failed('not on the shelf');
    let bytes: Uint8Array;
    try {
      bytes = await this.store.read(shelved.path);
    } catch (error) {
      return TidyResult.failed(errorText(error));
    }
    return bytes.length >= Shelf.isolateAbove && hasWorkers() ? tidyOnWorker(bytes) : tidyBib(bytes);
  }

  /** Puts a rewritten file in place of the one on the shelf. */
  async replace(id: string, bytes: Uint8Array): Promise<boolean> {
    try {
      await this.store.write(Shelf.fileName(id), bytes);
    } catch (error) {
      console.warn(`OpenWord: could not replace ${id}: ${errorText(error)}`);
      return false;
    }
    await this.refresh();
    return true;
  }

  async remove(id: string): Promise<void> {
    const shelved = this.byId(id);
    if (shelved === null) return;
    try {
      await this.store.delete(shelved.path);
    } catch (error) {
      console.warn(`OpenWord: could not remove ${id}: ${errorText(error)}`);
    }
    await this.refresh();
  }

  private describe(file: ShelfFile): ShelvedTranslation | null {
    try {
      return new ShelvedTranslation({
        info: BibFile.readInfo(file.head),
        path: file.path,
        bytes: file.size,
        added: file.modified,
      });
    } catch (error) {
      console.warn(`OpenWord: ${file.path} is not a readable .bib: ${errorText(error)}`);
      return null;
    }
  }

  static fileName(id: string): string {
    const safe = id.replace(/[^A-Za-z0-9._-]/g, '_');
    return `${safe}${BibFile.extension}`;
  }
}

/**
 * The `.bib` file `importFile` made, and what it had to say doing it.
 *
 * Only bytes come back. A Bible read from a `.bib` file carries a way of
 * unpacking each book when it is wanted, and that is a closure, which no
 * worker can send to another; the caller opens the bytes on its own side,
 * which costs the outline and nothing more.
 */
export class ImportedBible {
  /** The encoded `.bib`, ready to be written and reopened. Null on failure. */
  readonly bytes: Uint8Array | null;
  readonly warnings: readonly string[];
  readonly failure: string | null;

  constructor(init: { bytes?: Uint8Array | null; warnings?: readonly string[]; failure?: string | null } = {}) {
    this.bytes = init.bytes ?? null;
    this.warnings = init.warnings ?? [];
    this.failure = init.failure ?? null;
  }
}

/**
 * Reads a file the reader chose and encodes what it holds.
 *
 * Top-level, and doing both halves of the work, because a whole Bible takes
 * long enough at either to drop a second of frames: `Shelf.add` hands this
 * to a worker for anything but a small file.
 */
export function importFile(bytes: Uint8Array, fileName: string): ImportedBible {
  try {
    if (BibFile.looksLikeBib(bytes)) {
      // Already in the app's own format: check it reads — every chunk's
      // checksum, since this is the one moment the whole file is in hand —
      // and then keep it byte for byte rather than encoding it afresh.
      BibFile.decode(bytes, true);
      return new ImportedBible({ bytes });
    }

    const result = EpubImport.convert(bytes, fileName);
    const bible = result.bible;
    if (bible === null) {
      return new ImportedBible({
        failure: result.failure ?? 'That file cannot be read.',
        warnings: result.warnings,
      });
    }
    return new ImportedBible({
      bytes: BibFile.encode(bible),
      warnings: result.warnings,
    });
  } catch (error) {
    if (error instanceof BibFormatException) {
      return new ImportedBible({ failure: error.message });
    }
    return new ImportedBible({ failure: `That file could not be read: ${errorText(error)}` });
  }
}

/** What came of putting a file on the shelf. */
export class ShelfResult {
  readonly translation: ShelvedTranslation | null;

  /**
   * The Bible that was read, so the app can start reading it at once rather
   * than going back to the file it has just written.
   */
  readonly bible: Bible | null;

  /** What the conversion had to leave out, if anything. */
  readonly warnings: readonly string[];

  /** Null when it worked. */
  readonly failure: string | null;

  constructor(
    init: {
      translation?: ShelvedTranslation | null;
      bible?: Bible | null;
      warnings?: readonly string[];
      failure?: string | null;
    } = {},
  ) {
    this.translation = init.translation ?? null;
    this.bible = init.bible ?? null;
    this.warnings = init.warnings ?? [];
    this.failure = init.failure ?? null;
  }

  static failed(reason: string): ShelfResult {
    return new ShelfResult({ failure: reason });
  }

  get ok(): boolean {
    return this.bible !== null;
  }
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

// --------------------------------------------------------------- workers

/** What the shelf asks the worker to do. See `importWorker.ts`. */
export type ImportWorkerRequest =
  | { kind: 'import'; bytes: Uint8Array; fileName: string }
  | { kind: 'tidy'; bytes: Uint8Array };

/** What comes back: plain data, since a class does not cross. */
export type ImportWorkerReply =
  | { kind: 'import'; bytes: Uint8Array | null; warnings: string[]; failure: string | null }
  | { kind: 'tidy'; bytes: Uint8Array | null; removed: string[]; failure: string | null }
  | { kind: 'error'; message: string };

/** Whether this is a browser with Web Workers; Node, where the tests run, is not. */
function hasWorkers(): boolean {
  return typeof Worker !== 'undefined';
}

/**
 * Runs one request on a fresh module worker and tears it down after. An
 * import is a rare thing, and a worker kept around would hold the
 * importer's code in memory for the rest of the session for nothing.
 * Where the worker cannot be started at all, the work is done here.
 */
function runOnWorker(request: ImportWorkerRequest): Promise<ImportWorkerReply | null> {
  return new Promise((resolve) => {
    let worker: Worker;
    try {
      worker = new Worker(new URL('./importWorker.ts', import.meta.url), { type: 'module' });
    } catch (error) {
      console.warn(`OpenWord: no worker for the import, converting here: ${errorText(error)}`);
      resolve(null);
      return;
    }
    const finish = (reply: ImportWorkerReply | null): void => {
      worker.terminate();
      resolve(reply);
    };
    worker.onmessage = (event: MessageEvent<ImportWorkerReply>) => finish(event.data);
    worker.onerror = (event) => {
      console.warn(`OpenWord: the import worker failed, converting here: ${event.message}`);
      finish(null);
    };
    worker.postMessage(request);
  });
}

async function importOnWorker(bytes: Uint8Array, fileName: string): Promise<ImportedBible> {
  const reply = await runOnWorker({ kind: 'import', bytes, fileName });
  if (reply === null) return importFile(bytes, fileName);
  if (reply.kind === 'error') return new ImportedBible({ failure: `That file could not be read: ${reply.message}` });
  if (reply.kind !== 'import') return importFile(bytes, fileName);
  return new ImportedBible({ bytes: reply.bytes, warnings: reply.warnings, failure: reply.failure });
}

async function tidyOnWorker(bytes: Uint8Array): Promise<TidyResult> {
  const reply = await runOnWorker({ kind: 'tidy', bytes });
  if (reply === null) return tidyBib(bytes);
  if (reply.kind === 'error') return TidyResult.failed(reply.message);
  if (reply.kind !== 'tidy') return tidyBib(bytes);
  return new TidyResult({ bytes: reply.bytes, removed: reply.removed, failure: reply.failure });
}
