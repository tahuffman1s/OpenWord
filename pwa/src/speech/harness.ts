/**
 * Proves the voice's pipeline end to end in a real browser: the worker,
 * the runtime's WebAssembly, eSpeak, the model files, and the device's own
 * voices. Loaded by tts-harness.html and read by scripts/tts-smoke.mjs,
 * which looks for `window.__ttsResult`. Not part of the app.
 */
import type { WorkerReply, WorkerRequest } from './ttsWorker';

interface HarnessResult {
  samples: number;
  durationSeconds: number;
  rms: number;
  synthMs: number;
  loadMs: number;
  phonemizerOnWorker: boolean;
  deviceVoices: number;
  error?: string;
}

declare global {
  interface Window {
    __ttsResult?: HarnessResult;
  }
}

const log = document.getElementById('log')!;
function say(line: string): void {
  log.textContent += line + '\n';
  console.log(line);
}

const base = '/voice/kitten-nano-en-v0_8-fp32/';
const verse = 'In the beginning God created the heavens and the earth.';

async function fetchBytes(name: string): Promise<ArrayBuffer> {
  const response = await fetch(base + name);
  if (!response.ok) throw new Error(`${name}: ${response.status}`);
  return response.arrayBuffer();
}

async function run(): Promise<HarnessResult> {
  const started = performance.now();
  const [model, voices, tokens] = await Promise.all([
    fetchBytes('model.fp32.onnx'),
    fetchBytes('voices.bin'),
    fetchBytes('tokens.txt').then((b) => new TextDecoder().decode(b)),
  ]);
  say(`fetched model ${model.byteLength} bytes, voices ${voices.byteLength} bytes`);

  const worker = new Worker(new URL('./ttsWorker.ts', import.meta.url), { type: 'module' });
  const send = (message: WorkerRequest, transfer: Transferable[] = []) => worker.postMessage(message, transfer);
  const next = () =>
    new Promise<WorkerReply>((resolve, reject) => {
      worker.onmessage = (event: MessageEvent<WorkerReply>) => resolve(event.data);
      worker.onerror = (event) => reject(new Error(event.message));
    });

  const ready = next();
  send({ type: 'load', files: { model, voices, tokens } }, [model, voices]);
  const loaded = await ready;
  if (loaded.type !== 'ready') throw new Error(`load: ${loaded.type === 'error' ? loaded.message : loaded.type}`);
  const loadMs = performance.now() - started;
  say(`worker ready in ${loadMs.toFixed(0)} ms; eSpeak on worker: ${loaded.phonemizer}`);

  let phonemes: string | undefined;
  if (!loaded.phonemizer) {
    const { phonemesFor } = await import('./phonemes');
    phonemes = await phonemesFor(verse);
    say(`phonemes from the page: ${phonemes}`);
  }

  const audio = next();
  send({ type: 'speak', id: 1, text: verse, sid: 1, speed: 1 / 0.8, phonemes });
  const made = await audio;
  if (made.type !== 'audio') throw new Error(`speak: ${made.type === 'error' ? made.message : made.type}`);
  let sum = 0;
  for (let i = 0; i < made.samples.length; i++) sum += made.samples[i] * made.samples[i];
  const rms = Math.sqrt(sum / Math.max(1, made.samples.length));
  const result: HarnessResult = {
    samples: made.samples.length,
    durationSeconds: made.samples.length / made.sampleRate,
    rms,
    synthMs: made.ms,
    loadMs,
    phonemizerOnWorker: loaded.phonemizer,
    deviceVoices: typeof speechSynthesis === 'undefined' ? -1 : speechSynthesis.getVoices().length,
  };
  say(JSON.stringify(result, null, 2));

  // Heard, where there is anyone to hear it.
  try {
    const context = new AudioContext({ sampleRate: made.sampleRate });
    const buffer = context.createBuffer(1, made.samples.length, made.sampleRate);
    buffer.copyToChannel(made.samples, 0);
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    source.start();
  } catch (error) {
    say(`no playback here: ${error}`);
  }
  send({ type: 'close' });
  return result;
}

run().then(
  (result) => {
    window.__ttsResult = result;
  },
  (error) => {
    say(`FAILED: ${error}`);
    window.__ttsResult = {
      samples: 0,
      durationSeconds: 0,
      rms: 0,
      synthMs: 0,
      loadMs: 0,
      phonemizerOnWorker: false,
      deviceVoices: -1,
      error: String(error),
    };
  },
);
