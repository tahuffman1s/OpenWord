/**
 * What ships inside the app — the Scripture, the maps, the notes, the
 * references, the originals — served as static files under /assets and
 * precached by the service worker, so after the first visit nothing here
 * needs the network.
 *
 * A test or a tool hands in its own loader that reads the repository's
 * assets directory instead.
 */
export interface AssetBundle {
  /** The bytes of an asset by its path, e.g. `assets/bible/eng-web.bib`. */
  load(path: string): Promise<Uint8Array>;
  /** An asset as text. */
  loadString(path: string): Promise<string>;
}

export class HttpAssetBundle implements AssetBundle {
  constructor(private readonly base = '/') {}

  async load(path: string): Promise<Uint8Array> {
    const response = await fetch(this.base + path.replace(/^\//, ''), { cache: 'force-cache' });
    if (!response.ok) throw new Error(`asset ${path} answered ${response.status}`);
    return new Uint8Array(await response.arrayBuffer());
  }

  async loadString(path: string): Promise<string> {
    return new TextDecoder().decode(await this.load(path));
  }
}

/** A bundle whose contents are given up front; for tests. */
export class MemoryAssetBundle implements AssetBundle {
  constructor(private readonly files: Map<string, Uint8Array | (() => Promise<Uint8Array>)>) {}

  async load(path: string): Promise<Uint8Array> {
    const entry = this.files.get(path);
    if (entry === undefined) throw new Error(`no asset ${path}`);
    return typeof entry === 'function' ? entry() : entry;
  }

  async loadString(path: string): Promise<string> {
    return new TextDecoder().decode(await this.load(path));
  }
}

/** The bundle the running app reads from. Tests replace it. */
export let rootBundle: AssetBundle = new HttpAssetBundle();

export function setRootBundle(bundle: AssetBundle): void {
  rootBundle = bundle;
}
