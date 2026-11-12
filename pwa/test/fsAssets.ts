import { readFile } from 'node:fs/promises';
import type { AssetBundle } from '../src/infra/assets';

/** The repository's own assets directory, for tests that read what ships. */
export class FsAssetBundle implements AssetBundle {
  constructor(private readonly root = new URL('../../', import.meta.url)) {}
  async load(path: string): Promise<Uint8Array> {
    return new Uint8Array(await readFile(new URL(path, this.root)));
  }
  async loadString(path: string): Promise<string> {
    return new TextDecoder().decode(await this.load(path));
  }
}
