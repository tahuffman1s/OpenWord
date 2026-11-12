// Copies the bundled assets (Scripture, maps, notes, references, originals,
// fonts, licences) from ../assets into public/assets so Vite serves them at
// /assets/... and the service worker precaches them. public/assets is
// git-ignored; the repository's assets/ stays the one source.
import { cpSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const source = join(root, '..', 'assets');
const target = join(root, 'public', 'assets');
if (!existsSync(source)) {
  console.error(`no assets directory at ${source}`);
  process.exit(1);
}
rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });
for (const dir of ['bible', 'fonts', 'licences', 'maps', 'notes', 'refs', 'strongs']) {
  cpSync(join(source, dir), join(target, dir), { recursive: true });
}
console.log(`synced assets into ${target}`);
