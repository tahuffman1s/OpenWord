import { openDB, type DBSchema, type IDBPDatabase } from 'idb';
import { BibFile } from '../model/bibFile';
import { saveBytes } from './saveFile';

/** One file on the shelf, as the store describes it. */
export class ShelfFile {
  readonly path: string;

  /** The first bytes of the file — enough for a `.bib` header, no more. */
  readonly head: Uint8Array;

  readonly size: number;
  readonly modified: Date;

  constructor(init: { path: string; head: Uint8Array; size: number; modified: Date }) {
    this.path = init.path;
    this.head = init.head;
    this.size = init.size;
    this.modified = init.modified;
  }
}

/**
 * The little the shelf needs of a filesystem.
 *
 * Pulling it out of `Shelf` keeps the storage out of the widget tree. The
 * Flutter app keeps a directory of files; the web has no filesystem a
 * page can write to, so here the shelf is kept in IndexedDB — locally, in
 * the browser, uploaded nowhere — and `openShelfStore` answers null in a
 * browser without one.
 */
export interface ShelfStore {
  /** Files ending in `extension`, each with its first `headLength` bytes. */
  list(options: { extension: string; headLength: number }): Promise<ShelfFile[]>;

  read(path: string): Promise<Uint8Array>;

  /** Writes `bytes` as `name` on the shelf and answers its path. */
  write(name: string, bytes: Uint8Array): Promise<string>;

  delete(path: string): Promise<void>;

  /**
   * Writes a copy of a shelved file somewhere outside the shelf. On the
   * web that is handing the file to the reader — a save dialog, a share
   * sheet or a download — since a page has no second directory to copy
   * into.
   */
  copy(path: string, destination: string): Promise<void>;
}

/** Opens the shelf the browser keeps, or null where it has no IndexedDB. */
export async function openShelfStore(): Promise<ShelfStore | null> {
  return IdbShelfStore.open();
}

/** How a copy leaves the shelf: `saveBytes` in the browser, something else in a test. */
export type SaveFile = (name: string, bytes: Uint8Array, mime: string) => Promise<void>;

/** The MIME type a `.bib` is handed over as. */
export const bibMimeType = 'application/octet-stream';

interface TranslationRecord {
  name: string;
  bytes: ArrayBuffer;
  size: number;
  modified: number;
}

interface HeadRecord {
  name: string;
  head: ArrayBuffer;
  size: number;
  modified: number;
}

interface ShelfSchema extends DBSchema {
  translations: { key: string; value: TranslationRecord };
  heads: { key: string; value: HeadRecord };
}

/**
 * The shelf as an IndexedDB database.
 *
 * Database `openword`, object store `translations` keyed by file name,
 * each record the whole file. Listing the shelf must stay cheap — it is
 * done on every refresh, and a translation is megabytes — so the first
 * `headLength` bytes of each file are kept again in a small `heads`
 * store, and `list` reads that store alone: not a word of Scripture is
 * loaded to say what is on the shelf.
 */
export class IdbShelfStore implements ShelfStore {
  static readonly databaseName = 'openword';
  static readonly version = 1;

  /** How much of each file the `heads` store keeps: enough for a `.bib` header. */
  readonly headLength: number;

  private readonly save: SaveFile;

  constructor(
    private readonly db: IDBPDatabase<ShelfSchema>,
    options: { headLength?: number; save?: SaveFile } = {},
  ) {
    this.headLength = options.headLength ?? BibFile.maxHeaderLength;
    this.save = options.save ?? saveBytes;
  }

  /** Opens the database, or answers null where there is no IndexedDB. */
  static async open(options: { headLength?: number; save?: SaveFile } = {}): Promise<IdbShelfStore | null> {
    if (typeof indexedDB === 'undefined') return null;
    try {
      const db = await openDB<ShelfSchema>(IdbShelfStore.databaseName, IdbShelfStore.version, {
        upgrade(database) {
          if (!database.objectStoreNames.contains('translations')) {
            database.createObjectStore('translations', { keyPath: 'name' });
          }
          if (!database.objectStoreNames.contains('heads')) {
            database.createObjectStore('heads', { keyPath: 'name' });
          }
        },
      });
      return new IdbShelfStore(db, options);
    } catch (error) {
      console.warn(`OpenWord: could not open the shelf: ${String(error)}`);
      return null;
    }
  }

  async list(options: { extension: string; headLength: number }): Promise<ShelfFile[]> {
    const extension = options.extension.toLowerCase();
    const found: ShelfFile[] = [];
    for (const record of await this.db.getAll('heads')) {
      if (!record.name.toLowerCase().endsWith(extension)) continue;
      const head = new Uint8Array(record.head);
      found.push(
        new ShelfFile({
          path: record.name,
          // No more than was asked for; no more than was kept, either,
          // which is the one way this differs from reading a file.
          head: head.length > options.headLength ? head.subarray(0, options.headLength) : head,
          size: record.size,
          modified: new Date(record.modified),
        }),
      );
    }
    return found;
  }

  async read(path: string): Promise<Uint8Array> {
    const record = await this.db.get('translations', path);
    if (record === undefined) throw new Error(`${path} is not on the shelf`);
    return new Uint8Array(record.bytes);
  }

  async write(name: string, bytes: Uint8Array): Promise<string> {
    // Copies, so what is stored is exactly the file and not a view into
    // some larger buffer — and so a buffer the caller goes on using is
    // not the one the database holds.
    const whole = bytes.slice().buffer;
    const head = bytes.slice(0, Math.min(this.headLength, bytes.length)).buffer;
    const modified = Date.now();
    const transaction = this.db.transaction(['translations', 'heads'], 'readwrite');
    await Promise.all([
      transaction.objectStore('translations').put({ name, bytes: whole, size: bytes.length, modified }),
      transaction.objectStore('heads').put({ name, head, size: bytes.length, modified }),
      transaction.done,
    ]);
    return name;
  }

  async delete(path: string): Promise<void> {
    const transaction = this.db.transaction(['translations', 'heads'], 'readwrite');
    await Promise.all([
      transaction.objectStore('translations').delete(path),
      transaction.objectStore('heads').delete(path),
      transaction.done,
    ]);
  }

  async copy(path: string, destination: string): Promise<void> {
    await this.save(destination, await this.read(path), bibMimeType);
  }

  /** Closes the database; the store is not usable afterwards. */
  close(): void {
    this.db.close();
  }
}

/**
 * A shelf kept in memory: for tests, and for a browser with no IndexedDB,
 * where a translation can be read this session and is gone the next.
 */
export class MemoryShelfStore implements ShelfStore {
  private readonly files = new Map<string, { bytes: Uint8Array; modified: Date }>();

  /** What `copy` handed out, by destination. */
  readonly copies = new Map<string, Uint8Array>();

  async list(options: { extension: string; headLength: number }): Promise<ShelfFile[]> {
    const extension = options.extension.toLowerCase();
    const found: ShelfFile[] = [];
    for (const [name, file] of this.files) {
      if (!name.toLowerCase().endsWith(extension)) continue;
      found.push(
        new ShelfFile({
          path: name,
          head: file.bytes.subarray(0, Math.min(options.headLength, file.bytes.length)),
          size: file.bytes.length,
          modified: file.modified,
        }),
      );
    }
    return found;
  }

  async read(path: string): Promise<Uint8Array> {
    const file = this.files.get(path);
    if (file === undefined) throw new Error(`${path} is not on the shelf`);
    return file.bytes.slice();
  }

  async write(name: string, bytes: Uint8Array): Promise<string> {
    this.files.set(name, { bytes: bytes.slice(), modified: new Date() });
    return name;
  }

  async delete(path: string): Promise<void> {
    if (!this.files.delete(path)) throw new Error(`${path} is not on the shelf`);
  }

  async copy(path: string, destination: string): Promise<void> {
    this.copies.set(destination, await this.read(path));
  }
}
