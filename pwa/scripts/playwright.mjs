// Finds Playwright wherever it is installed, for the scripts here that
// drive a real browser. It is deliberately not one of the app's
// dependencies: the web image is built with `npm ci`, and a browser
// driver has no business in that.
//
//   PLAYWRIGHT_PATH=/path/to/node_modules/playwright   wins, if set
//   otherwise a `playwright` this directory can resolve, or a global one
//
// To get one:  npm install --no-save playwright && npx playwright install chromium
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const tried = [];

function load() {
  const candidates = [process.env.PLAYWRIGHT_PATH, 'playwright', '/opt/node-tools/node_modules/playwright'];
  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      return require(candidate);
    } catch (error) {
      tried.push(`${candidate}: ${error.code ?? error.message}`);
    }
  }
  throw new Error(
    `Playwright was not found (${tried.join('; ')}).\n` +
      'Install it with: npm install --no-save playwright && npx playwright install chromium',
  );
}

export const { chromium } = load();
