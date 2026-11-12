// Opens a running OpenWord in a real browser and reads from it: the check
// curl cannot make. deploy/smoke.sh proves the stack answers; this proves
// the app that comes out of the web image actually starts, shows Scripture,
// goes where it is told, keeps itself for offline, and still reads with
// the network gone.
//
//   node scripts/image-smoke.mjs                       http://localhost:8080
//   node scripts/image-smoke.mjs https://openword.example
//
// CI runs it against the images it has just built, before publishing them.
import { chromium } from './playwright.mjs';

const base = (process.argv[2] ?? 'http://localhost:8080').replace(/\/$/, '');
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 412, height: 915 } });
const page = await context.newPage();

const problems = [];
page.on('pageerror', (error) => problems.push(`page error: ${error.message}`));
page.on('console', (message) => {
  if (message.type() === 'error') problems.push(`console error: ${message.text()}`);
});
page.on('response', (response) => {
  if (response.status() >= 400) problems.push(`HTTP ${response.status()}: ${response.url()}`);
});

let failed = 0;
async function check(name, fn) {
  try {
    await fn();
    console.log(`  ok    ${name}`);
  } catch (error) {
    failed++;
    console.log(`  FAIL  ${name}: ${String(error.message ?? error).split('\n')[0]}`);
  }
}
const visibleText = () => page.locator('body').innerText();

console.log(`Browser smoke test of ${base}`);

await check('the app starts and shows the walkthrough on a first visit', async () => {
  await page.goto(`${base}/`, { waitUntil: 'networkidle' });
  await page.getByRole('button', { name: 'Skip' }).click({ timeout: 20_000 });
});

await check('Genesis 1 is on the page', async () => {
  await page.waitForFunction(() => document.body.innerText.includes('In the beginning'), null, { timeout: 20_000 });
});

await check('the go-to field goes to John 3:16', async () => {
  await page.getByRole('button', { name: /Go to another place/ }).click();
  await page.locator('input').first().fill('jn 3:16');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => document.body.innerText.includes('For God so loved the world'), null, {
    timeout: 20_000,
  });
});

await check('a verse opens its sheet, with cross-references and the Greek', async () => {
  await page.getByText('For God so loved the world', { exact: false }).first().click();
  const sheet = page.locator('.m3-sheet');
  await sheet.getByText(/cross-references/).first().waitFor({ timeout: 20_000 });
  await sheet.getByRole('button', { name: /^Greek$/ }).waitFor({ timeout: 20_000 });
  await page.keyboard.press('Escape');
});

await check('the service worker has taken the page', async () => {
  await page.waitForFunction(
    async () => (await navigator.serviceWorker?.getRegistration())?.active?.state === 'activated',
    null,
    { timeout: 30_000 },
  );
});

await check('the place is kept, and it reads with the network gone', async () => {
  // Give the worker a moment to finish keeping the Scripture.
  await page.waitForTimeout(3000);
  await context.setOffline(true);
  await page.reload({ waitUntil: 'load' });
  await page.waitForFunction(() => document.body.innerText.includes('John 3'), null, { timeout: 20_000 });
  const text = await visibleText();
  if (!/For God so loved|Nicodemus/.test(text)) throw new Error('John 3 did not come back offline');
  await context.setOffline(false);
});

await check('nothing went wrong along the way', async () => {
  // Offline, the app is right to fail a request or two; those are not this check's business.
  const real = problems.filter((p) => !/ERR_INTERNET_DISCONNECTED|Failed to load resource/.test(p));
  if (real.length > 0) throw new Error([...new Set(real)].slice(0, 5).join(' | '));
});

await browser.close();
console.log(failed === 0 ? '\nall passed' : `\n${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
