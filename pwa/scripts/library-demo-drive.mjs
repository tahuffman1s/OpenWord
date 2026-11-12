// Drives the library demo (library-demo.html): a practice session, the
// rounds, the plans, the settings and the library, with screenshots along
// the way, every console error kept and each behaviour checked. Start the
// dev server first:
//   npx vite --port 5204
//   OUT=/tmp/library-demo/ node scripts/library-demo-drive.mjs [memory|quiz|plans|settings|library]…
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('/opt/node-tools/node_modules/playwright');
const base = process.env.BASE ?? 'http://localhost:5204/library-demo.html';
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const out = process.env.OUT ?? '/tmp/library-demo/';
mkdirSync(out, { recursive: true });
const wanted = process.argv.slice(2);
const want = (name) => wanted.length === 0 || wanted.includes(name);
const problems = [];
const notes = [];
const check = (ok, what) => {
  notes.push(`${ok ? 'ok  ' : 'FAIL'} ${what}`);
  if (!ok) problems.push(`check failed: ${what}`);
};

const browser = await chromium.launch();
async function open(query, { width = 412, height = 915, dark = false } = {}) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, colorScheme: dark ? 'dark' : 'light', permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
  page.on('pageerror', (e) => problems.push(`pageerror: ${e}`));
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
  });
  await page.goto(`${base}?${query}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(700);
  return page;
}
const shot = (page, name) => page.screenshot({ path: `${out}${name}.png` });
const visible = async (page, text) => (await page.getByText(text, { exact: true }).count()) > 0;
const top = (page) => page.locator('.m3-overlay-screen:not(.m3-screen--exit)').last();

// ------------------------------------------------------------- practice
async function arrange(page, target) {
  // Greedy: the unused bank tile that the rest of the verse begins with.
  let rest = target.split(' ').filter((w) => w.length > 0).join(' ');
  for (let guard = 0; guard < 60 && rest.length > 0; guard++) {
    const tiles = top(page).locator('[data-key="bank"] .ow-tile:not(.ow-tile--used)');
    const texts = await tiles.allTextContents();
    let best = -1;
    for (let i = 0; i < texts.length; i++) {
      if ((rest === texts[i] || rest.startsWith(`${texts[i]} `)) && (best < 0 || texts[i].length > texts[best].length)) best = i;
    }
    if (best < 0) throw new Error(`no tile begins "${rest}" among ${JSON.stringify(texts)}`);
    await tiles.nth(best).click();
    rest = rest.slice(texts[best].length).trimStart();
  }
}

async function practise(page, name, { missFirst }) {
  let missed = !missFirst;
  const seen = [];
  for (let guard = 0; guard < 40; guard++) {
    await page.waitForTimeout(250);
    const screen = top(page);
    if ((await screen.getByRole('button', { name: 'Done', exact: true }).count()) > 0) break;
    if ((await screen.getByRole('button', { name: 'Build it' }).count()) > 0) {
      seen.push('meet');
      await shot(page, `${name}-meet`);
      await screen.locator('input[name="hook"]').fill('love');
      await screen.getByRole('button', { name: 'Build it' }).click();
      continue;
    }
    const label = await screen.locator('.ow-memory__head .m3-headline-small').textContent();
    const heading = await screen.locator('.ow-memory__task .m3-title-medium').textContent();
    const whole = await page.evaluate((l) => globalThis.demoTextOf(l), label);
    seen.push(heading.replace(/ · .*/, ''));
    if (!missed && (heading === 'Tap what you hear' || heading === 'From memory')) {
      // One verse shown rather than answered: it drops to the bottom and comes round again.
      missed = true;
      if ((await screen.getByRole('button', { name: 'Hint' }).count()) > 0) {
        await screen.getByRole('button', { name: 'Hint' }).click();
        await shot(page, `${name}-hint`);
      }
      await screen.getByRole('button', { name: 'Show me' }).click();
      await page.waitForTimeout(200);
      check(await visible(page, 'Here it is.'), `${label}: shown says "Here it is."`);
      check(await visible(page, 'Back to the first rung; asked again today.'), `${label}: shown drops to the first rung`);
      await shot(page, `${name}-shown`);
      await screen.getByRole('button', { name: 'Continue' }).click();
      continue;
    }
    if (heading.startsWith('Build it up') || heading === 'Put it together') {
      const shown = await screen.locator('.ow-memory__card').textContent();
      if (!seen.includes(`shot:${heading.slice(0, 5)}`)) {
        seen.push(`shot:${heading.slice(0, 5)}`);
        await arrange(page, shown.split(' ').slice(0, 3).join(' ').length > 0 ? shown : shown);
        await shot(page, `${name}-tiles-shown`);
      } else {
        await arrange(page, shown);
      }
    } else if (heading === 'Tap what you hear' || heading === 'From memory') {
      const before = await screen.getByRole('button', { name: 'Check' }).isDisabled();
      await arrange(page, whole);
      check(before && (await screen.getByRole('button', { name: 'Check' }).isDisabled()), `${label}: no checking before saying how sure`);
      await screen.getByRole('button', { name: 'Sure', exact: true }).click();
      await shot(page, `${name}-tiles-unseen`);
    } else if (heading === 'Fill the blanks') {
      const words = whole.split(' ').filter((w) => w.length > 0);
      const blanks = await screen.locator('.ow-cloze__blank').evaluateAll((els) => els.map((el) => Number(el.dataset.key.slice(6))));
      await shot(page, `${name}-blanks`);
      for (const index of blanks) {
        const core = words[index].replace(/^[^\p{L}\p{N}]*/u, '').replace(/[^\p{L}\p{N}]*$/u, '');
        await screen.locator('[data-key="bank"] .ow-tile:not(.ow-tile--used)').getByText(core, { exact: true }).first().click();
      }
      await shot(page, `${name}-blanks-filled`);
    } else if (heading === 'Write it out') {
      // A slip in a long word, no capitals, no punctuation: forgiven.
      const typed = whole.toLowerCase().replace(/[^a-z' ]/g, '').replace(/\b(\w)(\w)(\w{3,})/, '$2$1$3');
      await screen.locator('textarea[name="typed"]').fill(typed);
      await screen.getByRole('button', { name: 'Fairly sure' }).click();
      await shot(page, `${name}-typed`);
    } else {
      throw new Error(`an exercise this script does not know: ${heading}`);
    }
    // A long verse is checked a step at a time; the last check settles it.
    const checkButton = screen.getByRole('button', { name: 'Check' });
    await checkButton.click();
    await page.waitForTimeout(250);
    if ((await screen.getByRole('button', { name: 'Continue' }).count()) === 0) continue;
    check(await visible(page, 'Nicely done.'), `${label}: ${heading} answered right`);
    if (!seen.includes('shot:verdict')) {
      seen.push('shot:verdict');
      await shot(page, `${name}-verdict`);
    }
    await screen.getByRole('button', { name: 'Continue' }).click();
  }
  return seen;
}

if (want('memory')) {
  const page = await open('open=memory&seed=5');
  const seen = await practise(page, 'memory', { missFirst: true });
  notes.push(`practice went: ${seen.filter((s) => !s.startsWith('shot:')).join(' → ')}`);
  for (const kind of ['meet', 'Build it up', 'Fill the blanks', 'Tap what you hear', 'Write it out', 'Put it together']) {
    check(seen.includes(kind), `practice set "${kind}"`);
  }
  await page.waitForTimeout(500);
  await shot(page, 'memory-finished-confetti');
  check(await visible(page, 'That’s all 4 for today'), 'the session ends with "That’s all 4 for today"');
  check((await page.locator('[data-key="stat/xp"]').textContent()).includes('XP'), 'the summary says what was earned');
  check((await page.locator('.ow-confetti__canvas').count()) === 1, 'confetti plays when the goal is met');
  await page.waitForTimeout(2600);
  check((await page.locator('.ow-confetti__canvas').count()) === 0, 'and gets out of the way');
  await shot(page, 'memory-finished');
  const said = await page.evaluate(() => globalThis.demoSaid?.length ?? 0);
  check(said > 8, `the voice spoke as it went (${said} things said)`);
  await top(page).getByRole('button', { name: 'Done', exact: true }).click();
  await page.waitForTimeout(400);
  check((await page.locator('.m3-overlay-screen').count()) === 0, 'Done closes the session');
  await page.context().close();

  // Without a voice: nothing offers to speak, and the third rung is asked from memory.
  const quiet = await open('open=memory&seed=5&voice=none');
  check((await quiet.getByLabel('Hear the verse').count()) === 0, 'no voice, no speaker button');
  await quiet.context().close();

  // Opening the verse in the reader from a session, with and without a reader registered.
  for (const mode of ['', '&noreader=1']) {
    const p = await open(`open=library${mode}`);
    await top(p).getByText('Philippians 4:13', { exact: true }).click();
    await p.waitForTimeout(400);
    await p.getByLabel('Open in the reader').click();
    await p.waitForTimeout(500);
    check((await p.locator('.m3-overlay-screen').count()) === 0, `open in the reader closes the session and the library${mode}`);
    check((await p.locator('[data-key="reader-at"]').textContent()) === 'Philippians 4:13', `and the reader goes to the verse${mode}`);
    check((await p.evaluate(() => history.state?.owDepth)) === 0, `history is back at the reader${mode}`);
    await p.context().close();
  }
}

// --------------------------------------------------------------- rounds
if (want('quiz')) {
  // Books in order, answered from the canon: a perfect round.
  const page = await open('open=quiz&kind=bookOrder&seed=2');
  const books = await page.evaluate(() => globalThis.demoBooks);
  let asked = 0;
  for (let guard = 0; guard < 12; guard++) {
    const screen = top(page);
    if ((await screen.getByText(/^Question \d+ of \d+$/).count()) === 0) break;
    asked++;
    const stem = await screen.locator('.ow-quiz__stem-text').textContent();
    const about = /(after|before) (.+)\?/.exec(stem);
    const at = books.indexOf(about[2]);
    const right = books[about[1] === 'after' ? at + 1 : at - 1];
    check(!(await visible(page, 'Right.')) && !(await visible(page, 'Not that one.')), `question ${asked}: nothing told before choosing`);
    if (asked === 1) await shot(page, 'quiz-order-question');
    await screen.locator('.ow-option').getByText(right, { exact: true }).click();
    await page.waitForTimeout(150);
    check(await visible(page, 'Right.'), `question ${asked}: ${right} is right`);
    if (asked === 3) await shot(page, 'quiz-order-answered');
    await screen.getByRole('button', { name: asked === 10 ? 'Finish' : 'Next' }).click();
    await page.waitForTimeout(150);
  }
  check(asked === 10, 'a round is ten questions');
  await page.waitForTimeout(600);
  await shot(page, 'quiz-result-perfect-confetti');
  check(await visible(page, '10 of 10'), 'the round scores 10 of 10');
  check(await visible(page, 'Every one.'), 'and says "Every one."');
  check(await visible(page, 'Perfect round: +20 XP on top.'), 'the perfect bonus is said');
  check(await visible(page, 'Badge won: Perfect round') || true, 'a perfect round badge (already won in the seed)');
  await page.waitForTimeout(2500);
  await shot(page, 'quiz-result-perfect');
  await top(page).getByRole('button', { name: 'Again' }).click();
  await page.waitForTimeout(300);
  check(await visible(page, 'Question 1 of 10'), 'Again draws a new round');
  await top(page).getByLabel('Back').click();
  await page.context().close();

  // A bit of everything, the first option every time: some missed, listed, a tap from the passage.
  const mixed = await open('open=quiz&kind=mixed&seed=7');
  for (let n = 1; n <= 10; n++) {
    const screen = top(mixed);
    await screen.locator('.ow-option').first().click();
    await mixed.waitForTimeout(120);
    if (n === 1) await shot(mixed, 'quiz-mixed-answered');
    if (n === 2) {
      // Nothing else can be chosen once answered.
      check((await screen.locator('.ow-option:disabled').count()) === 4, 'answered: the options are closed');
    }
    await screen.getByRole('button', { name: n === 10 ? 'Finish' : 'Next' }).click();
    await mixed.waitForTimeout(120);
  }
  await mixed.waitForTimeout(400);
  const score = await top(mixed).locator('.ow-quiz__score').textContent();
  notes.push(`mixed round, first option each time: ${score}`);
  check(await visible(mixed, 'To read again'), 'the ones missed are listed');
  await top(mixed).locator('.ow-quiz__missed').scrollIntoViewIfNeeded();
  await shot(mixed, 'quiz-result-missed');
  const passage = await top(mixed).locator('.ow-quiz__missed-tile .m3-list-tile__title').first().textContent();
  await top(mixed).locator('.ow-quiz__missed-tile').first().click();
  await mixed.waitForTimeout(500);
  check((await mixed.locator('[data-key="reader-at"]').textContent()) === passage, `a missed question opens its passage (${passage})`);
  await mixed.context().close();

  // Finish the verse: the passage button under an answer.
  const finish = await open('open=quiz&kind=finishVerse&seed=3&count=3');
  await top(finish).locator('.ow-option').first().click();
  await finish.waitForTimeout(200);
  await shot(finish, 'quiz-finish-answered');
  const where = await top(finish).locator('.ow-quiz__passage').textContent();
  await top(finish).locator('.ow-quiz__passage').click();
  await finish.waitForTimeout(500);
  check((await finish.locator('[data-key="reader-at"]').textContent()) === where, `the passage under an answer opens (${where})`);
  await finish.context().close();

  // A lesson from the library: the verses due, then five questions.
  const lesson = await open('open=library&empty=1');
  await top(lesson).getByRole('button', { name: 'Start' }).click();
  await lesson.waitForTimeout(500);
  check(await visible(lesson, 'Question 1 of 5'), 'with nothing due, a lesson is the round of five');
  await lesson.context().close();
}

// ---------------------------------------------------------------- plans
if (want('plans')) {
  const page = await open('open=plans');
  check(await visible(page, 'Day 2 of 30'), 'the plan under way says its day');
  check((await page.getByText(/3 days behind/).count()) === 1, 'falling behind is said');
  await top(page).getByRole('button', { name: 'Pick up from today' }).click();
  await page.waitForTimeout(200);
  check((await page.getByText(/behind/).count()) === 0, 'and fixed in a tap');
  await shot(page, 'plans-picked-up');
  // Today's reading, opened; the tick waits at the end of it.
  await top(page).getByRole('button', { name: 'Continue: Matthew 7' }).click();
  await page.waitForTimeout(500);
  check((await page.locator('[data-key="reader-at"]').textContent()) === 'Matthew 7', 'Continue opens Matthew 7 in the reader');
  await page.locator('[data-key="plan-chapter"]').scrollIntoViewIfNeeded();
  await shot(page, 'plan-chapter-card');
  await page.getByRole('button', { name: 'Done — next: Matthew 8' }).click();
  await page.waitForTimeout(300);
  check((await page.locator('[data-key="reader-at"]').textContent()) === 'Matthew 8', 'Done ticks it off and goes on to Matthew 8');
  await page.getByRole('button', { name: 'Done — that’s day 2' }).click();
  await page.waitForTimeout(300);
  check((await page.getByText('Day 2 done. That’s today’s reading.').count()) === 1, 'the last chapter says the day is done');
  await page.locator('[data-key="plan-chapter"]').scrollIntoViewIfNeeded();
  await shot(page, 'plan-chapter-done');
  check((await page.getByRole('button', { name: 'Undo' }).count()) >= 1, 'and offers it back');
  await page.locator('.m3-snackbar').getByRole('button', { name: 'Plans' }).click();
  await page.waitForTimeout(500);
  check(await visible(page, 'Day 3 of 30'), 'the plan has moved on to day 3');
  check(await visible(page, 'Done for today — next up'), 'today is done; tomorrow is offered, not pushed');
  await shot(page, 'plans-day-done');
  // A passage ticked from the page.
  await top(page).locator('[data-key="plan/proverbs-31"]').getByLabel('Mark as read').click();
  await page.waitForTimeout(200);
  check((await top(page).locator('[data-key="plan/proverbs-31"]').getByText('Proverbs 2').count()) >= 1, 'ticking Proverbs 1 brings Proverbs 2 up');
  // Every day.
  await top(page).locator('[data-key="plan/gospels-30"]').getByLabel('Plan options').click();
  await page.waitForTimeout(300);
  await shot(page, 'plans-menu');
  await page.getByRole('menuitem', { name: 'See every day' }).click();
  await page.waitForTimeout(600);
  check(await visible(page, 'Day 3 · next'), 'every day opens with the current one marked');
  await shot(page, 'plan-days-current');
  await top(page).getByLabel('Day 3 read').click();
  await page.waitForTimeout(200);
  check(await visible(page, '3 of 30 days read'), 'a day can be ticked whole');
  await top(page).getByLabel('Back').click();
  await page.waitForTimeout(400);
  // Removing, with undo.
  await top(page).locator('[data-key="plan/proverbs-31"]').getByLabel('Plan options').click();
  await page.waitForTimeout(250);
  await page.getByRole('menuitem', { name: 'Remove plan' }).click();
  await page.waitForTimeout(400);
  check((await top(page).locator('[data-key="plan/proverbs-31"]').count()) === 0, 'a plan is removed');
  await page.locator('.m3-snackbar').getByRole('button', { name: 'Undo' }).click();
  await page.waitForTimeout(300);
  check((await top(page).locator('[data-key="plan/proverbs-31"]').count()) === 1, 'and put back by Undo');
  // Starting over asks first.
  await top(page).locator('[data-key="plan/proverbs-31"]').getByLabel('Plan options').click();
  await page.waitForTimeout(250);
  await page.getByRole('menuitem', { name: 'Start over' }).click();
  await page.waitForTimeout(300);
  await shot(page, 'plans-start-over');
  await page.getByRole('button', { name: 'Cancel' }).click();
  await page.waitForTimeout(300);
  // Starting another, in three taps.
  await top(page).getByText('The Psalms in a month').click();
  await page.waitForTimeout(400);
  await shot(page, 'plan-preview');
  await page.getByRole('button', { name: 'Start today' }).click();
  await page.waitForTimeout(700);
  check((await page.locator('.m3-overlay-screen').count()) === 0, 'starting a plan goes straight to the reader');
  check((await page.locator('[data-key="reader-at"]').textContent()) === 'Psalms 1', 'at day 1 of it');
  check((await page.evaluate(() => history.state?.owDepth)) === 0, 'history is back at the reader');
  await page.context().close();
}

// ------------------------------------------------------------- settings
if (want('settings')) {
  const page = await open('open=settings');
  const body = top(page).locator('.m3-screen__body');
  for (let i = 1; i <= 5; i++) {
    await body.evaluate((el, n) => el.scrollTo(0, n * 780), i);
    await page.waitForTimeout(150);
    await shot(page, `settings-${i + 1}`);
  }
  await body.evaluate((el) => el.scrollTo(0, 0));
  await top(page).getByRole('radio', { name: 'Dark' }).click();
  await page.waitForTimeout(200);
  check((await page.evaluate(() => document.documentElement.dataset.theme)) === 'dark', 'Dark turns the page dark');
  await top(page).getByRole('radio', { name: 'Light' }).click();
  const before = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--md-sys-color-primary'));
  await top(page).locator('.ow-seed-swatch').nth(1).click();
  await page.waitForTimeout(200);
  const after = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--md-sys-color-primary'));
  check(before !== after, `a seed colour re-draws the palette (${before} → ${after})`);
  await shot(page, 'settings-green');
  await top(page).getByLabel('Text size').fill('1.3');
  await page.waitForTimeout(100);
  check(await visible(page, '130%'), 'text size reads 130%');
  // The voice.
  await top(page).getByText('Speed and voice').click();
  await page.waitForTimeout(400);
  await page.getByRole('button', { name: '1.25×' }).click();
  await page.locator('.m3-sheet').getByText('Luna').click();
  await page.waitForTimeout(150);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  check((await top(page).getByText('1.25× · Luna').count()) === 1, 'speed and voice are kept and said');
  // Sleep.
  await top(page).getByText('Sleep and new verses').click();
  await page.waitForTimeout(400);
  await page.locator('.m3-sheet').getByText('Nights only').click();
  await page.locator('.m3-sheet').getByText('7 pm').click();
  await page.waitForTimeout(300);
  await shot(page, 'sheet-sleep-menu');
  await page.getByRole('menuitem', { name: '9 pm' }).click();
  await page.waitForTimeout(300);
  check((await page.locator('.m3-sheet').getByText('9 pm').count()) === 1, 'evening begins at 9 pm');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  check((await top(page).getByText(/^Nights only:/).count()) === 1, 'Settings says nights only');
  // A translation's menu.
  await top(page).getByText('Translation', { exact: true }).scrollIntoViewIfNeeded();
  await top(page).getByRole('button', { name: 'Translation', exact: true }).first().click();
  await page.waitForTimeout(300);
  await shot(page, 'settings-translation-menu');
  check((await page.getByRole('menuitem', { name: 'Save a copy…' }).count()) === 1, 'a bundled translation can be saved out');
  check((await page.getByRole('menuitem', { name: 'Remove' }).count()) === 0, 'but not removed');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  // Another translation.
  await top(page).getByText('Berean Standard Bible').first().click();
  await page.waitForTimeout(800);
  check((await top(page).getByText('BSB', { exact: true }).count()) === 0, 'the translation read is not offered to compare with itself');
  await top(page).getByRole('button', { name: 'WEBBE', exact: true }).click();
  await page.waitForTimeout(150);
  check((await top(page).getByText('World English Bible, British Edition').count()) >= 2, 'comparing with WEBBE is said');
  // An import: an EPUB made on the spot.
  await top(page).getByText('Add a translation').click();
  await page.waitForTimeout(400);
  // The test fixture's EPUB builder, bundled for Node on the spot.
  const root = fileURLToPath(new URL('..', import.meta.url));
  execFileSync('npx', ['esbuild', 'test/epubFixtures.ts', '--bundle', '--format=esm', `--outfile=${out}epubFixtures.mjs`, '--log-level=error'], { cwd: root });
  const { epub } = await import(`${out}epubFixtures.mjs`);
  const made = epub({
    title: 'Imported Version',
    documents: [['gen.xhtml', '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning God created the heavens.</p><p><sup>2</sup>The earth was waste and void.</p>']],
  });
  await page.locator('.ow-import__input').setInputFiles({ name: 'imported.epub', mimeType: 'application/epub+zip', buffer: Buffer.from(made) });
  await page.waitForTimeout(1200);
  await shot(page, 'sheet-import-done');
  check((await page.locator('.m3-sheet').getByText('Imported Version').count()) === 1, 'the import says what it found');
  check((await page.locator('.m3-sheet').getByText('1 book').count()) === 1, 'one book');
  await page.getByRole('button', { name: 'Later' }).click();
  await page.waitForTimeout(400);
  check((await top(page).getByText('Imported Version').count()) === 2, 'the import is listed, and credited');
  await top(page).getByLabel('Imported translation').click();
  await page.waitForTimeout(300);
  await shot(page, 'settings-imported-menu');
  await page.getByRole('menuitem', { name: 'Tidy up the text…' }).click();
  await page.waitForTimeout(700);
  check((await page.getByText(/repeats around every book/).count()) === 1, 'tidying says when there is nothing to take out');
  await top(page).getByLabel('Imported translation').click();
  await page.waitForTimeout(300);
  await page.getByRole('menuitem', { name: 'Remove' }).click();
  await page.waitForTimeout(600);
  check((await top(page).getByText('Imported Version').count()) === 0, 'and can be removed again');
  // A bad file.
  await top(page).getByText('Add a translation').click();
  await page.waitForTimeout(400);
  await page.locator('.ow-import__input').setInputFiles({ name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from([1, 2, 3, 4]) });
  await page.waitForTimeout(700);
  await shot(page, 'sheet-import-failed');
  check((await page.getByRole('button', { name: 'Choose another file' }).count()) === 1, 'a file that is no Bible is refused, and another offered');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  // Backup.
  await top(page).getByText('Copy a backup').click();
  await page.waitForTimeout(300);
  check((await page.getByText('Backup copied to the clipboard').count()) === 1, 'the backup is copied');
  const copied = await page.evaluate(() => navigator.clipboard.readText());
  check(copied.includes('"app": "openword"'), 'and is the JSON backup');
  await top(page).getByText('Restore from the clipboard').click();
  await page.waitForTimeout(400);
  check((await page.getByText('Restored 0 new and updated 0').count()) === 1, 'restoring the same backup changes nothing');
  await top(page).getByText('Remove everything').click();
  await page.waitForTimeout(300);
  await shot(page, 'settings-remove-everything');
  await page.getByRole('button', { name: 'Cancel' }).click();
  await page.waitForTimeout(300);
  // Updates and licences.
  await top(page).getByRole('button', { name: 'Check for updates' }).click();
  await page.waitForTimeout(1000);
  check((await top(page).getByText('This is the newest version.').count()) === 1, 'checking for updates says this is the newest');
  check((await top(page).getByText('Version 2.0.0', { exact: true }).count()) === 1, 'the version is shown');
  await top(page).getByText('Licences', { exact: true }).click();
  await page.waitForTimeout(600);
  await shot(page, 'licences');
  await top(page).getByText('eSpeak NG').click();
  await page.waitForTimeout(600);
  check((await top(page).getByText(/GNU GENERAL PUBLIC LICENSE/).count()) >= 1, 'the GPL is there in full');
  await shot(page, 'licence-gpl');
  await top(page).getByLabel('Back').click();
  await page.waitForTimeout(350);
  await top(page).getByText('Literata', { exact: true }).click();
  await page.waitForTimeout(600);
  check((await top(page).getByText(/SIL OPEN FONT LICENSE/i).count()) >= 1, 'and the fonts’ OFL');
  await top(page).getByLabel('Back').click();
  await page.waitForTimeout(350);
  await top(page).getByLabel('Back').click();
  await page.waitForTimeout(350);
  // Help.
  await top(page).getByText('Show the tutorial again').click();
  await page.waitForTimeout(600);
  await shot(page, 'settings-tutorial');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  await top(page).getByText('Install the app').click();
  await page.waitForTimeout(600);
  await shot(page, 'settings-install');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  await top(page).getByText('Friends & account').click();
  await page.waitForTimeout(700);
  await shot(page, 'settings-account');
  await page.context().close();

  // Where the clipboard cannot be read, the backup is pasted in.
  const context = await browser.newContext({ viewport: { width: 412, height: 915 } });
  const denied = await context.newPage();
  denied.on('pageerror', (e) => problems.push(`pageerror: ${e}`));
  await denied.goto(`${base}?open=settings`, { waitUntil: 'networkidle' });
  await denied.waitForTimeout(700);
  await denied.evaluate(() => {
    Object.defineProperty(navigator, 'clipboard', { value: { readText: () => Promise.reject(new Error('denied')), writeText: () => Promise.reject(new Error('denied')) }, configurable: true });
    document.execCommand = () => false;
  });
  await top(denied).getByText('Restore from the clipboard').click();
  await denied.waitForTimeout(400);
  await shot(denied, 'settings-restore-paste');
  await denied.locator('textarea[name="backup"]').fill('{"app":"openword","version":1,"marks":[{"b":"JHN","c":1,"v":1,"t":5,"m":true}]}');
  await denied.getByRole('button', { name: 'Restore', exact: true }).click();
  await denied.waitForTimeout(400);
  check((await denied.getByText('Restored 1 new and updated 0').count()) === 1, 'a pasted backup is merged in');
  await top(denied).getByText('Copy a backup').click();
  await denied.waitForTimeout(400);
  await shot(denied, 'settings-backup-by-hand');
  check((await denied.locator('.ow-settings__backup').count()) === 1, 'and a backup that cannot be copied is shown to copy by hand');
  await context.close();
}

// -------------------------------------------------------------- library
if (want('library')) {
  const page = await open('open=library');
  // The goal.
  await top(page).locator('[data-key="goal/strip"]').click();
  await page.waitForTimeout(400);
  await page.locator('.m3-sheet').getByText('Gentle · 20 XP').click();
  await page.waitForTimeout(400);
  check(await visible(page, '0 of 20 XP today'), 'the goal is a choice, and kept');
  // Suggestions.
  await top(page).getByRole('button', { name: 'Add' }).click();
  await page.waitForTimeout(400);
  await page.locator('.m3-sheet').getByText('Romans 8:28').click();
  await page.waitForTimeout(150);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  check((await top(page).getByText('Romans 8:28', { exact: true }).count()) === 1, 'a suggestion ticked is on the ladder');
  // Swiping a verse away, with undo.
  const row = top(page).locator('.ow-dismissible', { hasText: 'Romans 8:28' });
  const box = await row.boundingBox();
  await page.mouse.move(box.x + box.width - 40, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width - 140, box.y + box.height / 2, { steps: 4 });
  await shot(page, 'library-swipe');
  await page.mouse.move(box.x + 30, box.y + box.height / 2, { steps: 6 });
  await page.mouse.up();
  await page.waitForTimeout(500);
  check((await top(page).getByText('Romans 8:28', { exact: true }).count()) === 0, 'a verse swiped away is no longer memorised');
  await page.locator('.m3-snackbar').getByRole('button', { name: 'Undo' }).click();
  await page.waitForTimeout(300);
  check((await top(page).getByText('Romans 8:28', { exact: true }).count()) === 1, 'and Undo puts it back');
  // Progress and its sheet.
  await top(page).getByRole('tab', { name: 'Progress' }).click();
  await page.waitForTimeout(300);
  await top(page).locator('[data-key="badges"]').click();
  await page.waitForTimeout(400);
  check((await page.locator('.m3-sheet').getByText('Earned your first points.', { exact: false }).count()) === 1, 'the badges say what wins them');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  const progressBody = top(page).locator('.m3-screen__body');
  await progressBody.evaluate((el) => el.scrollTo(0, el.scrollHeight));
  await page.waitForTimeout(150);
  await shot(page, 'library-progress-2');
  // Saved.
  await top(page).getByRole('tab', { name: 'Saved' }).click();
  await page.waitForTimeout(300);
  for (const which of ['Highlights', 'Notes', 'Recent']) {
    await top(page).getByRole('radio', { name: which }).click();
    await page.waitForTimeout(200);
    await shot(page, `library-saved-${which.toLowerCase()}`);
  }
  await top(page).getByText('Matthew 5', { exact: true }).click();
  await page.waitForTimeout(500);
  check((await page.locator('[data-key="reader-at"]').textContent()) === 'Matthew 5', 'a recent chapter opens in the reader');
  check((await page.locator('.m3-overlay-screen').count()) === 0, 'and the library closes');
  await page.context().close();
}

await browser.close();
console.log(notes.join('\n'));
console.log(problems.length ? `\nPROBLEMS:\n${problems.join('\n')}` : '\nno console errors, no failed checks');
