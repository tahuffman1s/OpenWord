/**
 * The voice's model, run on a worker of its own so that making speech never
 * holds up the screen — the native app's isolate (`Synthesiser._serve` in
 * neural_speech.dart), with sherpa-onnx swapped for onnxruntime-web and
 * eSpeak NG from the `phonemizer` package.
 *
 * Messages in:
 *   { type: 'load', files: { model, voices, tokens }, wasmPaths? }
 *       model, voices: ArrayBuffer; tokens: string. Answered by
 *       { type: 'ready', phonemizer: boolean, timings } once the session is
 *       made, or { type: 'error', message }. `phonemizer` says
 *       whether eSpeak loaded here; if not, every 'speak' must carry its
 *       phonemes, made on the main thread.
 *   { type: 'speak', id, text, sid, speed, phonemes? }
 *       Answered by { type: 'audio', id, samples: Float32Array,
 *       sampleRate, ms } with the samples' buffer transferred, by
 *       { type: 'error', id, message }, or by { type: 'cancelled', id }.
 *       `speed` is what the native app hands sherpa-onnx: the rate over
 *       the speaker's prior; the prior is multiplied back in here.
 *   { type: 'cancel', id }   Drops a request not yet begun.
 *   { type: 'close' }        Frees the model.
 *
 * Requests are made one at a time, in order; `ms` is how long the model
 * took, for the engine's "falling behind" measure.
 */
import * as ort from 'onnxruntime-web/wasm';

import {
  hasContent,
  kittenMeta,
  levelled,
  modelSpeed,
  parseTokens,
  parseVoices,
  styleRow,
  styleVector,
  tokenIds,
  trimSilence,
} from './kitten';

export interface LoadMessage {
  type: 'load';
  files: { model: ArrayBuffer; voices: ArrayBuffer; tokens: string };
  /** Where the runtime's `.wasm` is served from; `/ort/` by default. */
  wasmPaths?: string;
  /** How hard the runtime works over the graph before the first run. */
  optimization?: 'disabled' | 'basic' | 'extended' | 'all';
  /** Whether to run the model once before saying it is ready. Default true. */
  warm?: boolean;
}

/** How long each part of getting ready took, in milliseconds. */
export interface LoadTimings {
  threads: number;
  session: number;
  phonemizer: number;
}

export interface SpeakMessage {
  type: 'speak';
  id: number;
  text: string;
  sid: number;
  speed: number;
  /** Already made on the main thread, where the worker could not. */
  phonemes?: string;
}

export interface CancelMessage {
  type: 'cancel';
  id: number;
}

export interface CloseMessage {
  type: 'close';
}

export type WorkerRequest = LoadMessage | SpeakMessage | CancelMessage | CloseMessage;

export type WorkerReply =
  | { type: 'ready'; phonemizer: boolean; timings: LoadTimings }
  | { type: 'error'; id?: number; message: string }
  | { type: 'audio'; id: number; samples: Float32Array<ArrayBuffer>; sampleRate: number; ms: number }
  | { type: 'cancelled'; id: number };

const scope = self as unknown as DedicatedWorkerGlobalScope;

let session: ort.InferenceSession | null = null;
let tokens: Map<number, number> | null = null;
let voices: Float32Array | null = null;
let phonemesFor: ((text: string) => Promise<string>) | null = null;

const queue: SpeakMessage[] = [];
let busy = false;

function reply(message: WorkerReply, transfer: Transferable[] = []): void {
  scope.postMessage(message, transfer);
}

async function load(message: LoadMessage): Promise<LoadTimings> {
  const timings: LoadTimings = { threads: 1, session: 0, phonemizer: 0 };
  let mark = performance.now();
  const lap = (): number => {
    const now = performance.now();
    const took = now - mark;
    mark = now;
    return took;
  };
  const wasm = ort.env.wasm;
  // Only the binary is fetched from there: the bundle we import carries its
  // own loader, and Vite will not serve a module out of public/ in dev.
  const prefix = message.wasmPaths ?? '/ort/';
  const binary = new URL(`${prefix}ort-wasm-simd-threaded.wasm`, scope.location.href).href;
  // In a build, the loader is taken from there too. With threads the
  // runtime starts its workers from its loader's own address; bundled into
  // this file, that address is this worker, and a second copy of it sits
  // waiting to be told to load a voice instead of doing sums: the first
  // run never returns. Served as a file of its own, the loader starts
  // itself. The dev server will not hand a module out of public/, and
  // does not bundle, so there the one imported is used.
  wasm.wasmPaths = import.meta.env.PROD
    ? { wasm: binary, mjs: new URL(`${prefix}ort-wasm-simd-threaded.mjs`, scope.location.href).href }
    : { wasm: binary };
  // Threads need SharedArrayBuffer, which needs the page to be cross-origin
  // isolated: deploy/nginx.conf sends the two headers for it. Where a
  // browser or a server does not, one thread it is.
  wasm.numThreads = scope.crossOriginIsolated
    ? Math.min(4, Math.max(1, (navigator.hardwareConcurrency || 2) - 1))
    : 1;
  wasm.proxy = false;
  timings.threads = wasm.numThreads;
  tokens = parseTokens(message.files.tokens);
  voices = parseVoices(new Uint8Array(message.files.voices));
  // eSpeak is got ready while the model is: each is mostly a WebAssembly
  // module being compiled, which the browser does off this thread, so the
  // two overlap rather than queue.
  const espeak = (async () => {
    const started = performance.now();
    try {
      const module = await import('./phonemes');
      // Proven here, so that a build whose eSpeak wants a window is found
      // out now rather than on the first verse.
      await module.phonemesFor('Hello.');
      phonemesFor = module.phonemesFor;
    } catch (error) {
      console.warn('OpenWord: eSpeak will not run on the worker; phonemes come from the page', error);
      phonemesFor = null;
    }
    timings.phonemizer = performance.now() - started;
  })();
  session = await ort.InferenceSession.create(new Uint8Array(message.files.model), {
    executionProviders: ['wasm'],
    graphOptimizationLevel: message.optimization ?? 'all',
  });
  timings.session = lap();
  await espeak;
  warmWanted = message.warm !== false;
  return timings;
}

/** Whether to run the model once, unasked, when there is a quiet moment. */
let warmWanted = false;

/**
 * The first run of a model is slower than any after it, so it is had
 * while nothing is waiting to be heard — and only then. Someone who has
 * pressed Listen is waiting for the first words of the chapter, and a
 * "Hello." nobody hears would stand between them and it: the chapter's
 * first piece is the first run instead. A voice loaded ahead of being
 * asked for has the moment to spare.
 */
async function warm(): Promise<void> {
  if (!warmWanted || busy || queue.length > 0) return;
  warmWanted = false;
  busy = true;
  try {
    await synthesise(phonemesFor ? await phonemesFor('Hello.') : 'həlˈoʊ.', 0, 1);
  } catch {
    // Found out on the first real piece, if it matters.
  } finally {
    busy = false;
  }
  void serve();
}

async function synthesise(phonemes: string, sid: number, speed: number): Promise<Float32Array> {
  if (!session || !tokens || !voices) throw new Error('the voice is not loaded');
  const ids = tokenIds(phonemes, tokens);
  if (!hasContent(ids)) return new Float32Array(0);
  // A piece is a sentence or less, far short of the model's limit; cut
  // to it all the same, keeping the wrapping, rather than hand it more.
  const trimmed =
    ids.length > kittenMeta.maxTokenLen
      ? [...ids.slice(0, kittenMeta.maxTokenLen - 2), kittenMeta.endId, kittenMeta.padId]
      : ids;
  const row = styleRow(trimmed);
  const feeds: Record<string, ort.Tensor> = {
    input_ids: new ort.Tensor('int64', BigInt64Array.from(trimmed.map((id) => BigInt(id))), [1, trimmed.length]),
    style: new ort.Tensor('float32', styleVector(voices, sid, row), [1, kittenMeta.styleDim]),
    speed: new ort.Tensor('float32', new Float32Array([modelSpeed(speed, sid)]), [1]),
  };
  const out = await session.run(feeds);
  const waveform = out['waveform'];
  if (!waveform) throw new Error('the model gave no waveform');
  const samples = waveform.data as Float32Array;
  return levelled(trimSilence(samples, kittenMeta.sampleRate), kittenMeta.sampleRate);
}

async function serve(): Promise<void> {
  if (busy) return;
  busy = true;
  try {
    while (queue.length > 0) {
      const request = queue.shift()!;
      const started = performance.now();
      try {
        const phonemes = request.phonemes ?? (phonemesFor ? await phonemesFor(request.text) : null);
        if (phonemes === null) throw new Error('no phonemes for the piece, and no eSpeak to make them');
        const made = await synthesise(phonemes, request.sid, request.speed);
        // A copy of its own, so the buffer can leave with it.
        const whole = made.byteOffset === 0 && made.byteLength === made.buffer.byteLength;
        const samples = (whole ? made : made.slice()) as Float32Array<ArrayBuffer>;
        reply(
          {
            type: 'audio',
            id: request.id,
            samples,
            sampleRate: kittenMeta.sampleRate,
            ms: performance.now() - started,
          },
          [samples.buffer],
        );
      } catch (error) {
        reply({ type: 'error', id: request.id, message: String(error) });
      }
    }
  } finally {
    busy = false;
  }
}

scope.onmessage = (event: MessageEvent<WorkerRequest>) => {
  const message = event.data;
  switch (message.type) {
    case 'load':
      load(message).then(
        (timings) => {
          reply({ type: 'ready', phonemizer: phonemesFor !== null, timings });
          // Long enough for a piece already wanted to arrive and be first.
          setTimeout(() => void warm(), 150);
        },
        (error) => reply({ type: 'error', message: String(error) }),
      );
      break;
    case 'speak':
      warmWanted = false;
      queue.push(message);
      void serve();
      break;
    case 'cancel': {
      const at = queue.findIndex((request) => request.id === message.id);
      if (at >= 0) {
        queue.splice(at, 1);
        reply({ type: 'cancelled', id: message.id });
      }
      break;
    }
    case 'close':
      queue.length = 0;
      void session?.release();
      session = null;
      scope.close();
      break;
  }
};
