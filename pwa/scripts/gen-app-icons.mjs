// Draws the app's icons — the open book of the splash screen on the
// theme's primary container — and writes the PNGs the manifest names.
// The Flutter app only ever had the framework's default logo.
//
//   node scripts/gen-app-icons.mjs      (needs Playwright's Chromium)
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  ({ chromium } = require('/opt/node-tools/node_modules/playwright'));
}
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const glyph = readFileSync(join(root, 'node_modules/@material-design-icons/svg/round/auto_stories.svg'), 'utf8')
  .replace(/^<svg[^>]*>/, '')
  .replace(/<\/svg>\s*$/, '');

// Seed 0xFF6750A4: primary 40 on a primary-container 90 field.
const field = ['#EADDFF', '#D9C6FF'];
const ink = '#4F378B';

/** `inset` is the fraction of the canvas the glyph leaves clear on each side. */
function svg(size, { radius, inset }) {
  const g = size * (1 - 2 * inset);
  const o = size * inset;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs><linearGradient id="f" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${field[0]}"/><stop offset="1" stop-color="${field[1]}"/></linearGradient></defs>
  <rect width="${size}" height="${size}" rx="${size * radius}" fill="url(#f)"/>
  <g transform="translate(${o} ${o}) scale(${g / 24})" fill="${ink}">${glyph}</g>
</svg>`;
}

const outputs = [
  // "any" icons: rounded square, as a launcher without a mask shows them.
  ['icons/Icon-192.png', 192, { radius: 0.22, inset: 0.2 }],
  ['icons/Icon-512.png', 512, { radius: 0.22, inset: 0.2 }],
  // Maskable: full bleed, the glyph inside the 80% safe zone.
  ['icons/Icon-maskable-192.png', 192, { radius: 0, inset: 0.26 }],
  ['icons/Icon-maskable-512.png', 512, { radius: 0, inset: 0.26 }],
  // iOS rounds the corners itself and wants no transparency.
  ['icons/apple-touch-icon.png', 180, { radius: 0, inset: 0.2 }],
  ['icons/badge-96.png', 96, { radius: 0.5, inset: 0.2 }],
  ['favicon.png', 64, { radius: 0.22, inset: 0.16 }],
];

mkdirSync(join(root, 'public/icons'), { recursive: true });
const browser = await chromium.launch();
for (const [file, size, shape] of outputs) {
  const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
  await page.setContent(`<body style="margin:0;background:transparent">${svg(size, shape)}</body>`);
  await page.screenshot({ path: join(root, 'public', file), omitBackground: true });
  await page.close();
}
await browser.close();
console.log(`wrote ${outputs.length} icons`);
