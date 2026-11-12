// Screenshots each screen of the library demo (library-demo.html) at phone,
// dark phone and wide sizes. Start the dev server first:
//   npx vite --port 5204
//   OUT=/tmp/library-demo/ node scripts/library-demo-shots.mjs [filter]
import { chromium } from './playwright.mjs';
const base = process.env.BASE ?? 'http://localhost:5204/library-demo.html';
import { mkdirSync } from 'node:fs';
const out = process.env.OUT ?? '/tmp/library-demo/';
mkdirSync(out, { recursive: true });
const filter = process.argv[2] ?? '';
const pages = [
  ['demo', ''],
  ['library-learn', 'open=library&tab=0'],
  ['library-progress', 'open=library&tab=1'],
  ['library-saved', 'open=library&tab=2'],
  ['library-learn-empty', 'open=library&tab=0&empty=1'],
  ['library-saved-empty', 'open=library&tab=2&empty=1'],
  ['memory-meet', 'open=memory&seed=3'],
  ['plans', 'open=plans'],
  ['plans-empty', 'open=plans&empty=1'],
  ['plan-days', 'open=days'],
  ['quiz', 'open=quiz&kind=whichBook&seed=4'],
  ['quiz-finish', 'open=quiz&kind=finishVerse&seed=4'],
  ['settings', 'open=settings'],
  ['licences', 'open=licences'],
  ['sheet-goal', 'open=library&sheet=goal'],
  ['sheet-badges', 'open=library&tab=1&sheet=badges'],
  ['sheet-sleep', 'open=settings&sheet=sleep'],
  ['sheet-suggestions', 'open=library&sheet=suggestions'],
  ['sheet-import', 'open=settings&sheet=import'],
  ['sheet-voice', 'open=settings&sheet=voice'],
];
const sizes = [
  ['phone', 412, 915, false],
  ['phone-dark', 412, 915, true],
  ['wide', 1280, 800, false],
];
const browser = await chromium.launch();
const problems = [];
for (const [size, width, height, dark] of sizes) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, colorScheme: dark ? 'dark' : 'light' });
  for (const [name, query] of pages) {
    if (filter && !name.includes(filter)) continue;
    const page = await context.newPage();
    page.on('pageerror', (e) => problems.push(`${name}/${size} pageerror: ${e}`));
    page.on('console', (m) => {
      if (m.type() === 'error') problems.push(`${name}/${size} console: ${m.text()}`);
    });
    await page.goto(`${base}?${query}${dark ? '&dark=1' : ''}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(900);
    await page.screenshot({ path: `${out}${name}-${size}.png` });
    await page.close();
  }
  await context.close();
}
await browser.close();
console.log(problems.length ? problems.join('\n') : 'no console errors');
