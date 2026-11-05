// Proves the voice end to end in Chromium: starts Vite, opens
// tts-harness.html, and checks that the worker made a verse's worth of
// speech out of the real model files in public/voice/.
//
//   node scripts/tts-smoke.mjs            (dev server)
//   node scripts/tts-smoke.mjs --preview  (vite preview of a build made
//                                          with OPENWORD_TTS_HARNESS=1)
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const port = Number(process.env.TTS_SMOKE_PORT ?? 5177);
const preview = process.argv.includes('--preview');

const server = spawn(
  'npx',
  preview
    ? ['vite', 'preview', '--port', String(port), '--strictPort']
    : ['vite', '--port', String(port), '--strictPort'],
  {
    cwd: root,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, OPENWORD_TTS_HARNESS: '1' },
    // Its own process group, so that killing it takes vite with it, not
    // only the npx shim in front of it.
    detached: true,
  },
);
server.stdout.on('data', (d) => process.stdout.write(`[vite] ${d}`));
server.stderr.on('data', (d) => process.stderr.write(`[vite] ${d}`));

const url = `http://localhost:${port}/tts-harness.html`;

async function waitForServer() {
  for (let i = 0; i < 100; i++) {
    try {
      const response = await fetch(url);
      if (response.ok) return;
    } catch {
      // Not up yet.
    }
    await new Promise((r) => setTimeout(r, 300));
  }
  throw new Error(`vite did not answer on ${port}`);
}

let failed = false;
try {
  await waitForServer();
  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('console', (m) => console.log(`[page:${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => console.log(`[page:error] ${e.message}`));
  page.on('requestfailed', (r) => console.log(`[page:requestfailed] ${r.url()} ${r.failure()?.errorText}`));
  page.on('response', (r) => {
    if (r.status() >= 400) console.log(`[page:http ${r.status()}] ${r.url()}`);
  });
  await page.goto(url);
  const handle = await page.waitForFunction(() => window.__ttsResult, null, { timeout: 240_000 });
  const result = await handle.jsonValue();
  await browser.close();

  console.log('\nsmoke result', result);
  const checks = [
    [!result.error, `no error (${result.error ?? ''})`],
    [result.durationSeconds >= 2 && result.durationSeconds <= 6, `duration ${result.durationSeconds.toFixed(2)} s in [2, 6]`],
    [result.rms > 0.01, `rms ${result.rms.toFixed(4)} > 0.01`],
  ];
  for (const [ok, what] of checks) {
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`);
    if (!ok) failed = true;
  }
  console.log(
    `synthesis ${result.synthMs.toFixed(0)} ms for ${result.durationSeconds.toFixed(2)} s of speech ` +
      `(${(result.synthMs / 1000 / result.durationSeconds).toFixed(2)}× real time); ` +
      `load ${result.loadMs.toFixed(0)} ms; eSpeak on worker: ${result.phonemizerOnWorker}; ` +
      `device voices listed: ${result.deviceVoices}`,
  );
} catch (error) {
  console.error('smoke failed:', error);
  failed = true;
} finally {
  try {
    process.kill(-server.pid, 'SIGTERM');
  } catch {
    server.kill('SIGTERM');
  }
}
process.exit(failed ? 1 : 0);
