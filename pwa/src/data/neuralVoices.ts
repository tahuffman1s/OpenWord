import { ChangeNotifier } from '../infra/changeNotifier';
import { hasWebAudio } from '../speech/audio';
import { BackendChoice } from '../speech/backendChoice';
import { NeuralSpeechEngine } from './neuralSpeech';
import { NoSpeechEngine, SpeechVoice, type SpeechEngine } from './readAloud';

/** One voice of a model: a speaker it was trained on. */
export class NeuralSpeaker {
  constructor(
    /** The speaker's number in the model. */
    readonly id: number,
    readonly name: string,
    readonly locale: string,
    /**
     * What the runtime multiplies this speaker's speed by, as the model
     * asks: its "speed prior". Divided back out, so that 1× is the pace
     * the voice was trained at, which sounds natural where the prior drags.
     */
    readonly prior = 1,
  ) {}
}

/** The files a model is made of, as they are handed to the worker. */
export interface VoiceFiles {
  model: ArrayBuffer;
  voices: ArrayBuffer;
  tokens: string;
}

/**
 * The voice OpenWord reads aloud with: an open neural text-to-speech
 * model, run in the browser with onnxruntime-web.
 *
 * It is fetched from `/voice/<archive>/` the first time it is needed and
 * kept in Cache Storage, so it comes over the network once. Nothing
 * leaves the device: the speech itself is made here.
 */
export class NeuralModel {
  /** Short and stable: it is part of the voice name kept in settings. */
  readonly id: string;
  readonly title: string;

  /** The directory the model is served from, named as sherpa-onnx names its archive. */
  readonly archive: string;

  /** The network itself, among its files. */
  readonly modelFile: string;

  readonly speakers: readonly NeuralSpeaker[];

  constructor(init: { id: string; title: string; archive: string; modelFile: string; speakers: NeuralSpeaker[] }) {
    this.id = init.id;
    this.title = init.title;
    this.archive = init.archive;
    this.modelFile = init.modelFile;
    this.speakers = init.speakers;
  }

  /** The files it is served as, beside [modelFile]. */
  get files(): { model: string; voices: string; tokens: string } {
    return { model: this.modelFile, voices: 'voices.bin', tokens: 'tokens.txt' };
  }

  /**
   * KittenTTS nano 0.8 (Apache-2.0), at full precision. The 8-bit edition
   * is half the size but now and then garbles a sound — KittenML itself
   * warns of it — and on the processors tried it is slower, not quicker:
   * turning its numbers back and forth costs more than it saves.
   */
  static readonly kitten = new NeuralModel({
    id: 'kitten',
    title: 'Kitten',
    archive: 'kitten-nano-en-v0_8-fp32',
    modelFile: 'model.fp32.onnx',
    // The priors are the model's own, from its metadata.
    speakers: [
      new NeuralSpeaker(1, 'Bella', 'en-US', 0.8),
      new NeuralSpeaker(0, 'Jasper', 'en-US', 0.8),
      new NeuralSpeaker(3, 'Luna', 'en-US', 0.8),
      new NeuralSpeaker(2, 'Bruno', 'en-US', 0.8),
      new NeuralSpeaker(5, 'Rosie', 'en-US', 0.8),
      new NeuralSpeaker(4, 'Hugo', 'en-US', 0.9),
      new NeuralSpeaker(7, 'Kiki', 'en-US', 0.8),
      new NeuralSpeaker(6, 'Leo', 'en-US', 0.8),
    ],
  });

  static readonly catalog: readonly NeuralModel[] = [NeuralModel.kitten];

  private static readonly _prefix = 'openword:';

  /** The name a voice of this model is kept by in settings. */
  voiceName(speaker: NeuralSpeaker): string {
    return `${NeuralModel._prefix}${this.id}:${speaker.id}`;
  }

  /**
   * The model and speaker a kept voice name means, or null for a name
   * this version does not know — a voice of the device's that an earlier
   * version read with, say.
   */
  static parse(voice: string | null | undefined): [NeuralModel, NeuralSpeaker] | null {
    if (voice == null || !voice.startsWith(NeuralModel._prefix)) return null;
    const parts = voice.substring(NeuralModel._prefix.length).split(':');
    if (parts.length !== 2) return null;
    const id = /^[+-]?\d+$/.test(parts[1]) ? Number.parseInt(parts[1], 10) : null;
    for (const model of NeuralModel.catalog) {
      if (model.id !== parts[0]) continue;
      for (const speaker of model.speakers) {
        if (speaker.id === id) return [model, speaker];
      }
    }
    return null;
  }

  /** The voice a kept name means, or the first voice where it means none. */
  static chosen(voice: string | null | undefined): [NeuralModel, NeuralSpeaker] {
    return NeuralModel.parse(voice) ?? [NeuralModel.kitten, NeuralModel.kitten.speakers[0]];
  }

  /** How the voices of this model are offered. */
  get voices(): SpeechVoice[] {
    return this.speakers.map(
      (speaker) => new SpeechVoice({ name: this.voiceName(speaker), title: speaker.name, locale: speaker.locale }),
    );
  }
}

/** How far the voice's download has got, for "Getting the voice… 34%". */
export interface VoiceProgress {
  received: number;
  total: number;
}

/**
 * The voice on this device, made ready to speak.
 *
 * Where the browser cannot run it — no WebAssembly, no Web Audio, no
 * workers — it is not supported, and only the device's own voices offer
 * to read aloud.
 */
export abstract class NeuralVoices extends ChangeNotifier {
  abstract get isSupported(): boolean;

  /**
   * Settles once the voice has been fetched into the cache, the first
   * time it is needed, or found already there.
   */
  abstract get ready(): Promise<void>;

  /** Speaks with the voice. Only called where [isSupported]. */
  abstract engine(): SpeechEngine;

  /**
   * Where this device has been found to make speech more slowly than it
   * is heard, so that reading pauses between sentences.
   */
  get fallingBehind(): boolean {
    return false;
  }

  /** How the download is going, while it is; null before and after. */
  get progress(): VoiceProgress | null {
    return null;
  }

  /** The runtime this device will be loading: the one worth fetching ahead. */
  get runtimeUrl(): string {
    return runtimeWasmUrl;
  }

  /**
   * Fetches the voice ahead of its being asked for, where that is a fair
   * thing to do with someone's connection: not when they have asked the
   * browser to save data, and not over a mobile network the browser knows
   * to be one. Quietly — a failure is tried again on Listen.
   */
  prefetch(): void {
    if (!this.isSupported || !mayFetchUnasked()) return;
    this.ready.catch(() => {});
    // And the runtime the voice runs on, megabytes of WebAssembly the
    // worker would otherwise fetch when Listen is pressed. Asked for
    // here, it is in the service worker's cache by then.
    try {
      void fetch(this.runtimeUrl).then(
        // Read to its end, so the copy the service worker keeps is whole.
        (response) => void response.arrayBuffer().catch(() => {}),
        () => {},
      );
    } catch {
      // No fetch here; the worker asks for it itself.
    }
  }
}

/** Where the ONNX runtime's WebAssembly is served from; see ttsWorker.ts. */
export const runtimeWasmUrl = '/ort/ort-wasm-simd-threaded.wasm';

/** The runtime's build for the graphics processor, served beside it. */
export const runtimeGpuWasmUrl = '/ort/ort-wasm-simd-threaded.asyncify.wasm';

interface NetworkInformation {
  saveData?: boolean;
  type?: string;
  effectiveType?: string;
}

/** Whether sixty megabytes may be fetched without being asked for. */
export function mayFetchUnasked(
  connection: NetworkInformation | undefined = (globalThis.navigator as { connection?: NetworkInformation } | undefined)
    ?.connection,
): boolean {
  if (connection === undefined) return true;
  if (connection.saveData === true) return false;
  if (connection.type === 'cellular') return false;
  const effective = connection.effectiveType;
  return effective === undefined || effective === '4g';
}

/** Fetch and Cache Storage, as the browser has them; a test hands in its own. */
export interface VoiceStore {
  fetch: typeof fetch;
  caches: CacheStorage | null;
}

/** Where the voice is kept, once fetched: the same cache the service worker uses for it. */
export const voiceCacheName = 'openword-voice';

/**
 * The voice fetched from the deployment's static files and kept in Cache
 * Storage, where the worker can be handed its bytes.
 */
export class WebNeuralVoices extends NeuralVoices {
  private readonly _base: string;
  private readonly _store: VoiceStore;

  constructor(options: { base?: string; store?: VoiceStore } = {}) {
    super();
    this._base = options.base ?? '/voice/';
    this._store =
      options.store ??
      ({
        fetch: (input, init) => fetch(input, init),
        caches: typeof caches !== 'undefined' ? caches : null,
      } satisfies VoiceStore);
  }

  /**
   * Everywhere with WebAssembly, a worker to run it on, and Web Audio to
   * hear it — less a device the model has been found not to run on at
   * all, which reads with its own voices instead (see backendChoice.ts).
   */
  override get isSupported(): boolean {
    return (
      typeof WebAssembly !== 'undefined' &&
      typeof Worker !== 'undefined' &&
      hasWebAudio() &&
      BackendChoice.forThisBrowser().canRun
    );
  }

  override get runtimeUrl(): string {
    return BackendChoice.forThisBrowser().plan().backends[0] === 'webgpu' ? runtimeGpuWasmUrl : runtimeWasmUrl;
  }

  /**
   * Fetched the first time it is asked for, and only once — or again,
   * if that failed.
   */
  override get ready(): Promise<void> {
    return (this._ready ??= this._download().catch((error: unknown) => {
      this._ready = null;
      throw error;
    }));
  }
  private _ready: Promise<void> | null = null;

  private _engine: NeuralSpeechEngine | null = null;
  private _fallingBehind = false;
  private _progress: VoiceProgress | null = null;
  private _progressNotified = 0;

  override get progress(): VoiceProgress | null {
    return this._progress;
  }

  /**
   * What a model's files add up to, for progress before a server says
   * how long each is: the Kitten files as they ship.
   */
  static readonly expectedBytes: Readonly<Record<string, number>> = {
    'kitten-nano-en-v0_8-fp32': 56768002 + 3276800 + 1064,
  };

  private _url(model: NeuralModel, file: string): string {
    return `${this._base}${model.archive}/${file}`;
  }

  /**
   * Fetches one of a model's files. The network itself is asked for as
   * `<name>.bin` first: a server behind Cloudflare is cached at the edge by
   * file extension, `.bin` is on that list and `.onnx` is not, and sixty
   * megabytes from the edge beats sixty megabytes up a home connection. A
   * server that does not answer to that name — the dev server, an older
   * deployment — is asked for the file as it is.
   */
  private async _fetchFile(model: NeuralModel, file: string): Promise<Response> {
    const url = this._url(model, file);
    if (file.endsWith('.onnx')) {
      try {
        const response = await this._store.fetch(`${url}.bin`);
        const type = response.headers.get('content-type') ?? '';
        if (response.ok && !type.startsWith('text/html')) return response;
        void response.body?.cancel().catch(() => {});
      } catch {
        // Asked for plainly, below.
      }
    }
    return this._store.fetch(url);
  }

  private async _cache(): Promise<Cache | null> {
    const store = this._store.caches;
    if (store === null) return null;
    try {
      return await store.open(voiceCacheName);
    } catch {
      // Storage refused — a private window, say. Fetched every time.
      return null;
    }
  }

  private async _download(): Promise<void> {
    const model = NeuralModel.kitten;
    const cache = await this._cache();
    const files = Object.values(model.files);
    const missing: string[] = [];
    for (const file of files) {
      const kept = cache === null ? undefined : await cache.match(this._url(model, file));
      if (kept === undefined) missing.push(file);
    }
    if (missing.length === 0) return;
    const expected = WebNeuralVoices.expectedBytes[model.archive] ?? 0;
    this._progress = { received: 0, total: expected };
    this._notifyProgress(true);
    try {
      let received = 0;
      let total = 0;
      const responses = await Promise.all(
        missing.map(async (file) => {
          const response = await this._fetchFile(model, file);
          if (!response.ok) throw new Error(`The voice could not be fetched: ${file} answered ${response.status}`);
          const length = Number(response.headers.get('content-length') ?? 0);
          total += length;
          return { file, response };
        }),
      );
      if (total > 0) this._progress = { received, total: Math.max(total, this._progress?.received ?? 0) };
      for (const { file, response } of responses) {
        const bytes = await this._read(response, (n) => {
          received += n;
          this._progress = { received, total: Math.max(this._progress?.total ?? 0, received) };
          this._notifyProgress(false);
        });
        if (cache !== null) {
          await cache.put(
            this._url(model, file),
            new Response(bytes.buffer as ArrayBuffer, {
              headers: {
                'content-type': file.endsWith('.txt') ? 'text/plain' : 'application/octet-stream',
                'content-length': String(bytes.byteLength),
              },
            }),
          );
        } else {
          this._uncached.set(file, bytes);
        }
      }
    } finally {
      this._progress = null;
      this._notifyProgress(true);
    }
  }

  /** What was fetched where there is no cache to keep it in. */
  private readonly _uncached = new Map<string, Uint8Array>();

  private async _read(response: Response, onChunk: (bytes: number) => void): Promise<Uint8Array> {
    const body = response.body;
    if (body === null) {
      const bytes = new Uint8Array(await response.arrayBuffer());
      onChunk(bytes.byteLength);
      return bytes;
    }
    const reader = body.getReader();
    const chunks: Uint8Array[] = [];
    let length = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      length += value.byteLength;
      onChunk(value.byteLength);
    }
    const bytes = new Uint8Array(length);
    let at = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, at);
      at += chunk.byteLength;
    }
    return bytes;
  }

  private _notifyProgress(always: boolean): void {
    const now = Date.now();
    if (!always && now - this._progressNotified < 150) return;
    this._progressNotified = now;
    this.notifyListeners();
  }

  /**
   * A model's files, out of the cache, as fresh buffers the worker can be
   * handed outright. Read again for every worker started, rather than
   * held: sixty megabytes is a lot to keep twice.
   */
  async files(model: NeuralModel): Promise<VoiceFiles> {
    await this.ready;
    const cache = await this._cache();
    const read = async (file: string): Promise<ArrayBuffer> => {
      const kept = cache === null ? undefined : await cache.match(this._url(model, file));
      if (kept !== undefined) return kept.arrayBuffer();
      const loose = this._uncached.get(file);
      if (loose !== undefined) return loose.slice().buffer as ArrayBuffer;
      const response = await this._fetchFile(model, file);
      if (!response.ok) throw new Error(`The voice could not be fetched: ${file} answered ${response.status}`);
      return response.arrayBuffer();
    };
    const [modelBytes, voices, tokens] = await Promise.all([
      read(model.files.model),
      read(model.files.voices),
      read(model.files.tokens).then((b) => new TextDecoder().decode(b)),
    ]);
    return { model: modelBytes, voices, tokens };
  }

  override engine(): SpeechEngine {
    if (!this.isSupported) return new NoSpeechEngine();
    return (this._engine ??= new NeuralSpeechEngine({
      ready: () => this.ready,
      files: (model) => this.files(model),
      onFallingBehind: () => {
        this._fallingBehind = true;
        this.notifyListeners();
      },
    }));
  }

  override get fallingBehind(): boolean {
    return this._fallingBehind;
  }
}

/** The voice in this browser. */
export function openNeuralVoices(): NeuralVoices {
  return new WebNeuralVoices();
}

/** The device's voice. A test puts its own in its place. */
export let neuralVoices: NeuralVoices = openNeuralVoices();

export function setNeuralVoices(voices: NeuralVoices): void {
  neuralVoices = voices;
}
