// Screenshots a page of the dev server in Chromium, for a look at the kit.
//   node scripts/shot.mjs <url> <out.png> [width] [height] [dark]
import { chromium } from './playwright.mjs';
const [url, out, w = '412', h = '915', dark] = process.argv.slice(2);
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: +w, height: +h }, deviceScaleFactor: 1, colorScheme: dark ? 'dark' : 'light' });
const page = await context.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(500);
await page.screenshot({ path: out, fullPage: false });
if (errors.length) console.log('errors:', errors.join('\n'));
await browser.close();
