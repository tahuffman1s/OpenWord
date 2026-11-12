// Writes public/manifest-dark.webmanifest from public/manifest.webmanifest:
// the same app, in the dark scheme's colours. Android colours an installed
// app's bottom system bar from the manifest's theme_color, so the page
// links whichever of the two matches what it is showing (see
// useManifestFor in src/ui/m3/theme.ts). Generated, so the two cannot
// drift apart, and git-ignored.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const light = JSON.parse(readFileSync(join(root, 'public/manifest.webmanifest'), 'utf8'));
// The surface of the default seed, dark: what index.html's theme-color says.
const dark = { ...light, background_color: '#141218', theme_color: '#141218' };
writeFileSync(join(root, 'public/manifest-dark.webmanifest'), JSON.stringify(dark, null, 2) + '\n');
console.log('wrote public/manifest-dark.webmanifest');
