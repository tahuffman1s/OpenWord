/**
 * A small typed key-value store for the stores, over localStorage — or
 * over a map, for tests and for a browser that refuses storage.
 *
 * Every value is kept as JSON under a prefixed key, so an int stays an int
 * and a list stays a list when it is read back.
 */
export interface KeyValueStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
  key(index: number): string | null;
  readonly length: number;
}

export class MemoryStorage implements KeyValueStorage {
  private readonly map = new Map<string, string>();
  getItem(key: string): string | null {
    return this.map.get(key) ?? null;
  }
  setItem(key: string, value: string): void {
    this.map.set(key, value);
  }
  removeItem(key: string): void {
    this.map.delete(key);
  }
  key(index: number): string | null {
    return [...this.map.keys()][index] ?? null;
  }
  get length(): number {
    return this.map.size;
  }
}

export class Prefs {
  static readonly prefix = 'openword.';

  constructor(private readonly storage: KeyValueStorage) {}

  /** The browser's storage, or memory where it cannot be had. */
  static open(): Prefs {
    try {
      const storage = globalThis.localStorage;
      const probe = `${Prefs.prefix}__probe`;
      storage.setItem(probe, '1');
      storage.removeItem(probe);
      return new Prefs(storage);
    } catch {
      return new Prefs(new MemoryStorage());
    }
  }

  static memory(): Prefs {
    return new Prefs(new MemoryStorage());
  }

  private read(key: string): unknown {
    const raw = this.storage.getItem(Prefs.prefix + key);
    if (raw === null) return undefined;
    try {
      return JSON.parse(raw);
    } catch {
      return raw;
    }
  }

  private write(key: string, value: unknown): void {
    this.storage.setItem(Prefs.prefix + key, JSON.stringify(value));
  }

  containsKey(key: string): boolean {
    return this.storage.getItem(Prefs.prefix + key) !== null;
  }

  getInt(key: string): number | null {
    const v = this.read(key);
    return typeof v === 'number' && Number.isInteger(v) ? v : typeof v === 'number' ? Math.trunc(v) : null;
  }

  getDouble(key: string): number | null {
    const v = this.read(key);
    return typeof v === 'number' ? v : null;
  }

  getBool(key: string): boolean | null {
    const v = this.read(key);
    return typeof v === 'boolean' ? v : null;
  }

  getString(key: string): string | null {
    const v = this.read(key);
    return typeof v === 'string' ? v : null;
  }

  getStringList(key: string): string[] | null {
    const v = this.read(key);
    return Array.isArray(v) && v.every((e) => typeof e === 'string') ? (v as string[]) : null;
  }

  setInt(key: string, value: number): void {
    this.write(key, Math.trunc(value));
  }
  setDouble(key: string, value: number): void {
    this.write(key, value);
  }
  setBool(key: string, value: boolean): void {
    this.write(key, value);
  }
  setString(key: string, value: string): void {
    this.write(key, value);
  }
  setStringList(key: string, value: string[]): void {
    this.write(key, value);
  }

  remove(key: string): void {
    this.storage.removeItem(Prefs.prefix + key);
  }

  /** Every key kept, without the prefix. */
  keys(): string[] {
    const found: string[] = [];
    for (let i = 0; i < this.storage.length; i++) {
      const k = this.storage.key(i);
      if (k && k.startsWith(Prefs.prefix)) found.push(k.substring(Prefs.prefix.length));
    }
    return found;
  }

  clear(): void {
    for (const k of this.keys()) this.remove(k);
  }
}
