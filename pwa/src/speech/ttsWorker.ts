/**
 * The voice's model, run on a worker of its own so that making speech never
 * holds up the screen — the native app's isolate (`Synthesiser._serve` in
 * neural_speech.dart), with sherpa-onnx swapped for onnxruntime-web and
 * eSpeak NG from the `phonemizer` package.
 *
 * Messages in:
 *   { type: 'load', files: { model, voices, tokens }, wasmPaths? }
 *       model, voices: ArrayBuffer; tokens: string. Answered by
 *       { type: 'ready', phonemizer: boolean } once the session is made
 *       and warmed, or { type: 'error', message }. `phonemizer` says
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
  | { type: 'ready'; phonemizer: boolean }
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

async function load(message: LoadMessage): Promise<void> {
  const wasm = ort.env.wasm;
  // Only the binary is fetched from there: the bundle we import carries its
  // own loader, and Vite will not serve a module out of public/ in dev.
  const prefix = message.wasmPaths ?? '/ort/';
  wasm.wasmPaths = { wasm: new URL(`${prefix}ort-wasm-simd-threaded.wasm`, scope.location.href).href };
  // Threads need SharedArrayBuffer, which needs the page to be cross-origin
  // isolated; the deployment does not set COOP/COEP, so one thread it is.
  wasm.numThreads = scope.crossOriginIsolated
    ? Math.min(4, Math.max(1, (navigator.hardwareConcurrency || 2) - 1))
    : 1;
  wasm.proxy = false;
  tokens = parseTokens(message.files.tokens);
  voices = parseVoices(new Uint8Array(message.files.voices));
  session = await ort.InferenceSession.create(new Uint8Array(message.files.model), {
    executionProviders: ['wasm'],
    graphOptimizationLevel: 'all',
  });
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
  // The first run of a model is slower than any after it; it is had now,
  // while nothing is waiting to be heard.
  try {
    await synthesise(phonemesFor ? await phonemesFor('Hello.') : 'həlˈoʊ.', 0, 1);
  } catch {
    // Found out on the first real piece, if it matters.
  }
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
        () => reply({ type: 'ready', phonemizer: phonemesFor !== null }),
        (error) => reply({ type: 'error', message: String(error) }),
      );
      break;
    case 'speak':
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
