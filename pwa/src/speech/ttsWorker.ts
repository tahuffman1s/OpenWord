/**
 * The voice's model, run on a worker of its own so that making speech never
 * holds up the screen: onnxruntime-web runs the network, and eSpeak NG
 * from the `phonemizer` package makes the phonemes.
 *
 * The network runs on the graphics processor where there is one (WebGPU),
 * and on the processor (WebAssembly) where there is not, or where the
 * graphics processor turns out not to make speech: see `load`.
 *
 * Messages in:
 *   { type: 'load', files: { model, voices, tokens }, wasmPaths?, backends?, prove? }
 *       model, voices: ArrayBuffer; tokens: string. Answered by
 *       { type: 'ready', phonemizer: boolean, backend, refused, timings }
 *       once the session is made, or { type: 'error', message }.
 *       `phonemizer` says whether eSpeak loaded here; if not, every
 *       'speak' must carry its phonemes, made on the main thread.
 *       `backend` is what the model runs on, and `refused` what was tried
 *       before it and why it would not do.
 *   { type: 'speak', id, text, sid, speed, phonemes? }
 *       Answered by { type: 'audio', id, samples: Float32Array,
 *       sampleRate, ms } with the samples' buffer transferred, by
 *       { type: 'error', id, message, backendFailed? }, or by
 *       { type: 'cancelled', id }. `backendFailed` says the graphics
 *       processor gave something that is not sound: the voice wants
 *       loading again without it.
 *       `speed` is the rate over the speaker's prior, as the engine
 *       sends it; the prior is multiplied back in here.
 *   { type: 'cancel', id }   Drops a request not yet begun.
 *   { type: 'close' }        Frees the model.
 *
 * Requests are made one at a time, in order; `ms` is how long the model
 * took, for the engine's "falling behind" measure.
 */
import type * as Ort from 'onnxruntime-web';

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

/** What runs the network: the graphics processor, or the processor. */
export type Backend = 'webgpu' | 'wasm';

export interface LoadMessage {
  type: 'load';
  files: { model: ArrayBuffer; voices: ArrayBuffer; tokens: string };
  /** Where the runtime's `.wasm` is served from; `/ort/` by default. */
  wasmPaths?: string;
  /** What to try, in order. Default: the graphics processor, then the processor. */
  backends?: readonly Backend[];
  /**
   * Whether the graphics processor is made to say a word, and listened
   * to, before it is trusted: the first time on a device. A driver that
   * runs the network wrongly gives silence or noise, not an error.
   */
  prove?: boolean;
  /** A graphics processor drawn in software counts as one. For tests. */
  softwareGpu?: boolean;
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
  | { type: 'ready'; phonemizer: boolean; backend: Backend; refused: { backend: Backend; why: string }[]; timings: LoadTimings }
  | { type: 'error'; id?: number; message: string; backendFailed?: boolean }
  | { type: 'audio'; id: number; samples: Float32Array<ArrayBuffer>; sampleRate: number; ms: number }
  | { type: 'cancelled'; id: number };

const scope = self as unknown as DedicatedWorkerGlobalScope;

type Runtime = typeof Ort;

let ort: Runtime | null = null;
let session: Ort.InferenceSession | null = null;
let backend: Backend = 'wasm';
let tokens: Map<number, number> | null = null;
let voices: Float32Array | null = null;
let phonemesFor: ((text: string) => Promise<string>) | null = null;

const queue: SpeakMessage[] = [];
let busy = false;

function reply(message: WorkerReply, transfer: Transferable[] = []): void {
  scope.postMessage(message, transfer);
}

/** Gives up on [work] after [ms], so that a thing that hangs is found out. */
function within<T>(work: Promise<T>, ms: number, what: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${what} did not answer in ${Math.round(ms / 1000)} s`)), ms);
    work.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}

/**
 * Why this device's graphics processor will not be used, or null where
 * it may be. One drawn in software (SwiftShader, llvmpipe) is slower than
 * the processor it is drawn on, so it does not count.
 */
async function gpuRefusal(softwareAllowed: boolean): Promise<string | null> {
  const gpu = (navigator as Navigator & { gpu?: GpuLike }).gpu;
  if (gpu === undefined) return 'this browser has no WebGPU on a worker';
  let adapter: GpuAdapterLike | null = null;
  try {
    adapter = await within(gpu.requestAdapter(), 5000, 'the graphics processor');
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
  if (adapter === null) return 'no graphics adapter';
  if (softwareAllowed) return null;
  const info = adapter.info;
  const named = `${info?.vendor ?? ''} ${info?.architecture ?? ''} ${info?.device ?? ''} ${info?.description ?? ''}`.toLowerCase();
  if (adapter.isFallbackAdapter === true || /swiftshader|llvmpipe|software|basic render/.test(named)) {
    return 'the graphics adapter is drawn in software';
  }
  return null;
}

/** The little of WebGPU that is asked here; the runtime does the rest. */
interface GpuLike {
  requestAdapter(): Promise<GpuAdapterLike | null>;
}
interface GpuAdapterLike {
  isFallbackAdapter?: boolean;
  info?: { vendor?: string; architecture?: string; device?: string; description?: string };
}

/** The runtime's files for a backend, as scripts/copy-ort.mjs names them. */
const runtimeFile: Record<Backend, string> = {
  // The WebGPU build is a different binary: the same runtime with its
  // graphics kernels, and able to wait on the GPU from inside a run.
  webgpu: 'ort-wasm-simd-threaded.asyncify',
  wasm: 'ort-wasm-simd-threaded',
};

/** Loads the runtime for [wanted] and makes the session on it. */
async function startOn(wanted: Backend, message: LoadMessage, timings: LoadTimings): Promise<void> {
  const runtime: Runtime =
    wanted === 'webgpu'
      ? ((await import('onnxruntime-web/webgpu')) as unknown as Runtime)
      : ((await import('onnxruntime-web/wasm')) as unknown as Runtime);
  const wasm = runtime.env.wasm;
  // Only the binary is fetched from there: the bundle we import carries its
  // own loader, and Vite will not serve a module out of public/ in dev.
  const prefix = message.wasmPaths ?? '/ort/';
  const file = runtimeFile[wanted];
  const binary = new URL(`${prefix}${file}.wasm`, scope.location.href).href;
  // In a build, the loader is taken from there too. With threads the
  // runtime starts its workers from its loader's own address; bundled into
  // this file, that address is this worker, and a second copy of it sits
  // waiting to be told to load a voice instead of doing sums: the first
  // run never returns. Served as a file of its own, the loader starts
  // itself. The dev server will not hand a module out of public/, and
  // does not bundle, so there the one imported is used.
  wasm.wasmPaths = import.meta.env.PROD
    ? { wasm: binary, mjs: new URL(`${prefix}${file}.mjs`, scope.location.href).href }
    : { wasm: binary };
  // Threads need SharedArrayBuffer, which needs the page to be cross-origin
  // isolated: deploy/nginx.conf sends the two headers for it. Where a
  // browser or a server does not, one thread it is. On the graphics
  // processor the few operations left to the processor are small, and one
  // thread spares a phone the memory the others would each be given.
  wasm.numThreads =
    wanted === 'wasm' && scope.crossOriginIsolated
      ? Math.min(4, Math.max(1, (navigator.hardwareConcurrency || 2) - 1))
      : 1;
  wasm.proxy = false;
  timings.threads = wasm.numThreads;
  const started = performance.now();
  const made = await runtime.InferenceSession.create(new Uint8Array(message.files.model), {
    executionProviders: [wanted],
    graphOptimizationLevel: message.optimization ?? 'all',
  });
  timings.session = performance.now() - started;
  ort = runtime;
  session = made;
  backend = wanted;
}

/** Lets a session that will not do go, with what it held. */
async function letGo(): Promise<void> {
  const old = session;
  session = null;
  ort = null;
  try {
    await old?.release();
  } catch {
    // Gone either way.
  }
}

async function load(message: LoadMessage): Promise<{ timings: LoadTimings; refused: { backend: Backend; why: string }[] }> {
  const timings: LoadTimings = { threads: 1, session: 0, phonemizer: 0 };
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
      // out now rather than on the first verse — and given a time to
      // answer in: on some phones it has been seen never to.
      await within(module.phonemesFor('Hello.'), 12000, 'eSpeak');
      phonemesFor = module.phonemesFor;
    } catch (error) {
      console.warn('OpenWord: eSpeak will not run on the worker; phonemes come from the page', error);
      phonemesFor = null;
    }
    timings.phonemizer = performance.now() - started;
  })();

  const refused: { backend: Backend; why: string }[] = [];
  const order = message.backends ?? ['webgpu', 'wasm'];
  for (const wanted of order) {
    try {
      if (wanted === 'webgpu') {
        const why = await gpuRefusal(message.softwareGpu === true);
        if (why !== null) throw new Error(why);
      }
      await startOn(wanted, message, timings);
      if (wanted === 'webgpu' && message.prove === true) {
        // Its first word, listened to. Also the run that compiles its
        // shaders, which someone waiting to hear would otherwise sit
        // through on the first sentence.
        const said = await synthesise('həlˈoʊ.', 0, 1);
        const why = notSpeech(said);
        if (why !== null) throw new Error(why);
      }
      break;
    } catch (error) {
      await letGo();
      refused.push({ backend: wanted, why: error instanceof Error ? error.message : String(error) });
    }
  }
  if (session === null) {
    await espeak;
    throw new Error(refused.map((r) => `${r.backend}: ${r.why}`).join('; ') || 'nothing to run the voice on');
  }
  await espeak;
  warmWanted = message.warm !== false;
  return { timings, refused };
}

/**
 * Why [samples] are not a voice saying something, or null where they are.
 * A graphics driver that gets an operation wrong does not say so: the
 * numbers that come back are not numbers, or are nothing at all.
 */
export function notSpeech(samples: Float32Array): string | null {
  if (samples.length < kittenMeta.sampleRate / 10) return 'the graphics processor gave no sound';
  let sum = 0;
  for (let i = 0; i < samples.length; i++) {
    const value = samples[i];
    if (!Number.isFinite(value)) return 'the graphics processor gave numbers that are not sound';
    sum += value * value;
  }
  if (Math.sqrt(sum / samples.length) < 0.003) return 'the graphics processor gave silence';
  return null;
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

/** The graphics processor has stopped making sound; the voice wants loading without it. */
class BackendFailure extends Error {}

async function synthesise(phonemes: string, sid: number, speed: number): Promise<Float32Array> {
  if (!session || !ort || !tokens || !voices) throw new Error('the voice is not loaded');
  const ids = tokenIds(phonemes, tokens);
  if (!hasContent(ids)) return new Float32Array(0);
  // A piece is a sentence or less, far short of the model's limit; cut
  // to it all the same, keeping the wrapping, rather than hand it more.
  const trimmed =
    ids.length > kittenMeta.maxTokenLen
      ? [...ids.slice(0, kittenMeta.maxTokenLen - 2), kittenMeta.endId, kittenMeta.padId]
      : ids;
  const row = styleRow(trimmed);
  const feeds: Record<string, Ort.Tensor> = {
    input_ids: new ort.Tensor('int64', BigInt64Array.from(trimmed.map((id) => BigInt(id))), [1, trimmed.length]),
    style: new ort.Tensor('float32', styleVector(voices, sid, row), [1, kittenMeta.styleDim]),
    speed: new ort.Tensor('float32', new Float32Array([modelSpeed(speed, sid)]), [1]),
  };
  const out = await session.run(feeds);
  const waveform = out['waveform'];
  if (!waveform) throw new Error('the model gave no waveform');
  const samples = waveform.data as Float32Array;
  if (backend === 'webgpu') {
    // Looked at before it is trimmed and levelled, which would hide it.
    for (let i = 0; i < samples.length; i += 97) {
      if (!Number.isFinite(samples[i])) throw new BackendFailure('the graphics processor gave numbers that are not sound');
    }
  }
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
        // A graphics device taken away — the tab was in the background, the
        // driver fell over — fails every run after it the same way.
        const lost = backend === 'webgpu' && (error instanceof BackendFailure || /device.*lost|GPUDevice|WebGPU/i.test(String(error)));
        reply({ type: 'error', id: request.id, message: String(error), ...(lost ? { backendFailed: true } : {}) });
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
        ({ timings, refused }) => {
          reply({ type: 'ready', phonemizer: phonemesFor !== null, backend, refused, timings });
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
