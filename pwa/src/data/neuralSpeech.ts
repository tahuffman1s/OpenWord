import { speechAudioContext } from '../speech/audio';
import { levelled as levelledSamples, limited as limitedSamples } from '../speech/kitten';
import { BackendChoice } from '../speech/backendChoice';
import type { Backend, WorkerReply, WorkerRequest } from '../speech/ttsWorker';
import { NeuralModel, type VoiceFiles } from './neuralVoices';
import type { ConfigureOptions, SpeakOptions, SpeechEngine, SpeechVoice } from './readAloud';

/**
 * Speaks with a neural model in the browser, through onnxruntime-web.
 *
 * The model runs on a worker of its own, one piece of the text at a
 * time, a piece ahead of what is being heard; each piece is played as it
 * is ready, as an AudioBufferSourceNode scheduled to begin the moment the
 * one before it ends, so that there is no gap to hear between them.
 *
 * Unlike the platform's voices it can truly pause: the audio simply
 * stops where it is and goes on from there, mid-word — the AudioContext
 * is suspended, and resumed.
 */
export class NeuralSpeechEngine implements SpeechEngine {
  /** Settles once the model is in the cache, where [files] can read it. */
  readonly ready: () => Promise<void>;

  /** The model's files, fresh buffers for a worker to be handed. */
  readonly files: (model: NeuralModel) => Promise<VoiceFiles>;

  /**
   * Told, once for each model, when this device makes its speech more
   * slowly than it is heard, so that there will be pauses.
   */
  readonly onFallingBehind: ((model: NeuralModel) => void) | null;
  private readonly _toldSlow = new Set<NeuralModel>();

  /** What runs the model; a test hands in its own. */
  private readonly _startSynthesiser: (model: NeuralModel, files: VoiceFiles) => Promise<Synthesiser>;

  /** Where the pieces are played; a test hands in its own. */
  private readonly _audioContext: () => AudioContext;

  private _synth: Synthesiser | null = null;
  private _model: NeuralModel | null = null;
  private _speaker = 0;
  private _speed = 1.0;

  /**
   * Made when first wanted: an engine is made for every reader screen,
   * and most are never asked to speak.
   */
  private _context: AudioContext | null = null;
  private _reading: Reading | null = null;

  constructor(init: {
    ready: () => Promise<void>;
    files: (model: NeuralModel) => Promise<VoiceFiles>;
    onFallingBehind?: (model: NeuralModel) => void;
    startSynthesiser?: (model: NeuralModel, files: VoiceFiles) => Promise<Synthesiser>;
    audioContext?: () => AudioContext;
  }) {
    this.ready = init.ready;
    this.files = init.files;
    this.onFallingBehind = init.onFallingBehind ?? null;
    this._startSynthesiser = init.startSynthesiser ?? ((model, files) => Synthesiser.start(model, files));
    this._audioContext = init.audioContext ?? speechAudioContext;
  }

  get isAvailable(): boolean {
    return true;
  }

  get canPause(): boolean {
    return true;
  }

  /** Loading one model after another, never two at once. */
  private _configuring: Promise<void> = Promise.resolve();

  configure(options: ConfigureOptions): Promise<void> {
    const next = this._configuring.then(() => this._configure(options));
    this._configuring = next.catch(() => {});
    return next;
  }

  private async _configure(options: ConfigureOptions): Promise<void> {
    const [model, speaker] = NeuralModel.chosen(options.voice);
    this._speaker = speaker.id;
    this._speed = options.rate / speaker.prior;
    await this.ready();
    this._preparePlayers();
    if (model !== this._model || this._synth === null) {
      await this.stop();
      this._synth?.close();
      this._synth = null;
      this._model = null;
      this._synth = await this._startSynthesiser(model, await this.files(model));
      this._model = model;
    }
  }

  /**
   * Played as speech, through the one audio context reading aloud has:
   * the media session keeps it awake between pieces (see
   * readAloudSession.ts), and the browser, not the app, decides about
   * the silent switch and the screen.
   */
  private _preparePlayers(): void {
    if (this._context !== null) return;
    this._context = this._audioContext();
  }

  async speak(text: string, options: SpeakOptions = {}): Promise<boolean> {
    this._reading?.cancel();
    let from = 0;
    for (let attempt = 0; ; attempt++) {
      const synth = this._synth;
      const context = this._context;
      if (synth === null || context === null) return false;
      const reading = (this._reading = new Reading({
        text: text.substring(from),
        breaks: (options.breaks ?? []).map((at) => at - from).filter((at) => at >= 0),
        synth,
        context,
        speaker: this._speaker,
        speed: this._speed,
        onProgress: options.onProgress === undefined ? undefined : ((base) => (offset: number) => options.onProgress!(base + offset))(from),
        onStart: attempt === 0 ? options.onStart : undefined,
        onHeard: () => this._checkPace(),
      }));
      const said = await reading.run();
      const mine = this._reading === reading;
      if (mine) this._reading = null;
      // The graphics processor gave out part way: the voice is loaded
      // again without it, and goes on from the piece it had reached,
      // rather than leave the reader with a chapter that stopped.
      if (said || !mine || reading.cancelled || !synth.backendFailed || attempt > 0) return said;
      from += reading.reached;
      try {
        await this._reload();
      } catch {
        return false;
      }
    }
  }

  /** Starts the model afresh, on whatever is now thought best. */
  private async _reload(): Promise<void> {
    const model = this._model;
    if (model === null) throw new Error('no voice to load again');
    this._synth?.close();
    this._synth = null;
    this._synth = await this._startSynthesiser(model, await this.files(model));
  }

  private _checkPace(): void {
    const model = this._model;
    if (model !== null && (this._synth?.fallingBehind ?? false) && !this._toldSlow.has(model)) {
      this._toldSlow.add(model);
      this.onFallingBehind?.(model);
    }
  }

  async stop(): Promise<void> {
    this._reading?.cancel();
    this._reading = null;
  }

  async pause(): Promise<void> {
    this._reading?.pause();
  }

  async resume(): Promise<void> {
    this._reading?.resume();
  }

  async voices(_language: string): Promise<SpeechVoice[]> {
    return NeuralModel.kitten.voices;
  }

  /**
   * Where [text] is cut to be voiced a piece at a time, as the offset of
   * each piece and its words.
   *
   * At the end of every sentence, and a sentence longer than a piece may
   * be again at a comma, or failing that a space. Nothing is heard until
   * the first piece has been made whole, so the first is short — [first]
   * characters at most — and each after it may be twice the one before,
   * up to [longest]: the voice starts almost at once, and the pieces grow
   * while it is being made ahead of what is heard.
   *
   * A piece also begins at every offset in [breaks] — where each verse
   * begins — so that the voice says which verse it is on the moment it
   * reaches it, at whatever speed.
   */
  static pieces(
    text: string,
    options: { breaks?: readonly number[]; first?: number; longest?: number } = {},
  ): [number, string][] {
    const breaks = options.breaks ?? [];
    const first = options.first ?? 40;
    const longest = options.longest ?? 160;
    const result: [number, string][] = [];
    const limit = () => Math.min(longest, first << Math.min(result.length, 8));
    const add = (start: number, end: number) => {
      while (start < end && text.charCodeAt(start) === 0x20) start++;
      while (end > start && text.charCodeAt(end - 1) === 0x20) end--;
      if (end > start) result.push([start, text.substring(start, end)]);
    };

    const cut = (start: number, end: number) => {
      while (end - start > limit()) {
        const size = limit();
        const window = text.substring(start, start + size);
        let at = Math.max(window.lastIndexOf(', '), window.lastIndexOf('; '));
        if (at > Math.trunc(size / 3)) {
          at++;
        } else {
          // At a space, but not straight after a little word that leans on
          // the next: "God created | the heavens", not "created the |".
          at = window.lastIndexOf(' ');
          let earlier = at;
          while (earlier > Math.trunc(size / 3)) {
            const before = window.lastIndexOf(' ', earlier - 1);
            const word = window.substring(before + 1, earlier).toLowerCase();
            if (!NeuralSpeechEngine._leaning.has(word)) break;
            earlier = before;
          }
          if (earlier > Math.trunc(size / 3)) at = earlier;
        }
        if (at <= 0) at = size;
        add(start, start + at);
        start += at;
      }
      add(start, end);
    };

    const bounds = new Set<number>();
    for (const at of breaks) if (at > 0 && at < text.length) bounds.add(at);
    for (const end of text.matchAll(NeuralSpeechEngine._sentenceEnd)) bounds.add(end.index + end[0].length);
    bounds.add(text.length);
    let start = 0;
    for (const end of [...bounds].sort((a, b) => a - b)) {
      cut(start, end);
      start = end;
    }
    return result;
  }

  /**
   * A piece as it is handed to the voice. Cut short of its sentence's
   * end, a piece with no punctuation after its last word loses that word
   * a third of the time — swallowed, or said as something else — which
   * a comma, telling the voice the phrase ends there, puts right.
   */
  static voiced(piece: string): string {
    return NeuralSpeechEngine._endsPhrase.test(piece) ? piece : `${piece},`;
  }

  private static readonly _endsPhrase = /[.,;:!?—–-][”’"')\]]*$/;

  private static readonly _sentenceEnd = /[.;:!?][”’"')]*\s+/g;

  private static readonly _leaning: ReadonlySet<string> = new Set([
    'a',
    'an',
    'and',
    'as',
    'at',
    'but',
    'by',
    'for',
    'from',
    'his',
    'her',
    'in',
    'into',
    'its',
    'my',
    'nor',
    'o',
    'of',
    'on',
    'or',
    'our',
    'that',
    'the',
    'their',
    'thy',
    'to',
    'upon',
    'with',
    'your',
  ]);
}

/** A promise with its resolver to hand. */
class Completer<T = void> {
  readonly promise: Promise<T>;
  private _resolve!: (value: T) => void;
  private _done = false;
  constructor() {
    this.promise = new Promise<T>((resolve) => {
      this._resolve = resolve;
    });
  }
  get isCompleted(): boolean {
    return this._done;
  }
  complete(value: T): void {
    if (this._done) return;
    this._done = true;
    this._resolve(value);
  }
}

/** One passage being voiced: made, played, paused, or given up. */
class Reading {
  readonly synth: Synthesiser;
  readonly context: AudioContext;
  readonly speaker: number;
  readonly speed: number;
  readonly onProgress: ((offset: number) => void) | undefined;
  readonly onStart: (() => void) | undefined;

  /** After each piece has been heard. */
  readonly onHeard: (() => void) | undefined;
  readonly pieces: [number, string][];

  private readonly _made = new Map<number, Promise<Float32Array | null>>();
  private readonly _loaded = new Map<number, Promise<AudioBuffer | null>>();
  private readonly _cancelled = new Completer<void>();
  private _unpaused: Completer<void> | null = null;

  /** What has been scheduled and not yet heard to its end. */
  private readonly _playing = new Set<AudioBufferSourceNode>();

  /** When the next piece should begin, on the context's clock. */
  private _nextStart = 0;

  /** Whether this reading suspended the context, and should resume it. */
  private _suspended = false;

  constructor(init: {
    text: string;
    synth: Synthesiser;
    context: AudioContext;
    speaker: number;
    speed: number;
    onProgress?: (offset: number) => void;
    onStart?: () => void;
    onHeard?: () => void;
    breaks?: readonly number[];
  }) {
    this.synth = init.synth;
    this.context = init.context;
    this.speaker = init.speaker;
    this.speed = init.speed;
    this.onProgress = init.onProgress;
    this.onStart = init.onStart;
    this.onHeard = init.onHeard;
    this.pieces = NeuralSpeechEngine.pieces(init.text, { breaks: init.breaks ?? [] });
  }

  get cancelled(): boolean {
    return this._cancelled.isCompleted;
  }

  get paused(): boolean {
    return this._unpaused !== null;
  }

  /** Where in the text the piece last begun starts: where to go on from. */
  get reached(): number {
    return this._reached;
  }
  private _reached = 0;

  /** How many pieces are made ahead of the one being heard. */
  private static readonly _ahead = 3;

  /** The audio for a piece, made once. */
  private _make(i: number): Promise<Float32Array | null> {
    let made = this._made.get(i);
    if (made === undefined) {
      made = this.synth.say(NeuralSpeechEngine.voiced(this.pieces[i][1]), {
        speaker: this.speaker,
        speed: this.speed,
        owner: this,
      });
      this._made.set(i, made);
    }
    return made;
  }

  /** A piece made and put in a buffer, ready to start at once. */
  private _load(i: number): Promise<AudioBuffer | null> {
    let loaded = this._loaded.get(i);
    if (loaded === undefined) {
      loaded = this._make(i).then((samples) => {
        if (samples === null || this.cancelled) return null;
        if (samples.length === 0) return this.context.createBuffer(1, 1, this.synth.sampleRate);
        const buffer = this.context.createBuffer(1, samples.length, this.synth.sampleRate);
        buffer.copyToChannel(samples as Float32Array<ArrayBuffer>, 0);
        return buffer;
      });
      this._loaded.set(i, loaded);
    }
    return loaded;
  }

  async run(): Promise<boolean> {
    try {
      for (let i = 0; i < this.pieces.length; i++) {
        this._reached = this.pieces[i][0];
        const buffer = await this._load(i);
        if (buffer === null || this.cancelled) return false;
        // The next is loaded while this one plays, and those after it are
        // made, so that a slow sentence can borrow time from quick ones.
        if (i + 1 < this.pieces.length) void this._load(i + 1);
        for (let k = i + 2; k < this.pieces.length && k <= i + Reading._ahead; k++) {
          void this._make(k);
        }
        await this._whileUnpaused();
        if (this.cancelled) return false;
        const source = this.context.createBufferSource();
        source.buffer = buffer;
        source.connect(this.context.destination);
        const done = new Completer<void>();
        source.onended = () => {
          this._playing.delete(source);
          done.complete();
          if (!this.cancelled) {
            this._forget(i);
            this.onHeard?.();
          }
        };
        // Straight after the piece before it, where that is still
        // playing; otherwise now.
        const startAt = Math.max(this.context.currentTime, this._nextStart);
        this._playing.add(source);
        source.start(startAt);
        this._nextStart = startAt + buffer.duration;
        // Told of the piece as it is heard, not as it is scheduled.
        await this._until(startAt);
        if (this.cancelled) return false;
        if (i === 0) this.onStart?.();
        this.onProgress?.(this.pieces[i][0]);
        // The last is heard to its end before this is done; the others
        // only need to have begun, so that the next is scheduled behind
        // them while they play.
        if (i + 1 === this.pieces.length) {
          await Promise.race([done.promise, this._cancelled.promise]);
          if (this.cancelled) return false;
        }
      }
      return true;
    } catch {
      return false;
    } finally {
      for (const i of [...this._made.keys()]) this._forget(i);
    }
  }

  /** Waits until the context's clock reaches [time], or the reading is given up. */
  private async _until(time: number): Promise<void> {
    while (!this.cancelled && this.context.currentTime < time - 0.005) {
      if (this.paused) {
        await this._whileUnpaused();
        continue;
      }
      const wait = Math.max(5, (time - this.context.currentTime) * 1000);
      await Promise.race([new Promise<void>((resolve) => setTimeout(resolve, wait)), this._cancelled.promise]);
    }
  }

  /** The samples of a piece are let go once heard, or once no longer wanted. */
  private _forget(i: number): void {
    this._made.delete(i);
    this._loaded.delete(i);
  }

  private async _whileUnpaused(): Promise<void> {
    while (this._unpaused !== null && !this.cancelled) {
      await Promise.race([this._unpaused.promise, this._cancelled.promise]);
    }
  }

  pause(): void {
    if (this.cancelled || this.paused) return;
    this._unpaused = new Completer();
    if (this._playing.size > 0 && this.context.state === 'running') {
      this._suspended = true;
      void this.context.suspend().catch(() => {});
    }
  }

  resume(): void {
    const unpaused = this._unpaused;
    if (unpaused === null) return;
    this._unpaused = null;
    if (this._suspended) {
      this._suspended = false;
      void this.context.resume().catch(() => {});
    }
    unpaused.complete();
  }

  cancel(): void {
    if (this.cancelled) return;
    this._cancelled.complete();
    for (const source of [...this._playing]) {
      try {
        source.stop();
      } catch {
        // Not started, or already stopped.
      }
      source.disconnect();
    }
    this._playing.clear();
    if (this._suspended) {
      this._suspended = false;
      void this.context.resume().catch(() => {});
    }
    // What it asked for and no longer wants is not made.
    this.synth.forget(this);
  }
}

/** The worker, as the synthesiser drives it; a test hands in its own. */
export interface SynthesiserPort {
  postMessage(message: WorkerRequest, transfer?: Transferable[]): void;
  onmessage: ((event: MessageEvent<WorkerReply>) => void) | null;
  onerror: ((event: ErrorEvent) => void) | null;
  terminate(): void;
}

/**
 * The model, loaded on a worker of its own so that making speech never
 * holds up the screen.
 */
export class Synthesiser {
  private constructor(
    private readonly _worker: SynthesiserPort,
    private readonly _phonemesHere: ((text: string) => Promise<string>) | null,
    readonly sampleRate: number,
    /** What the model runs on: this device's graphics processor, or its processor. */
    readonly backend: Backend = 'wasm',
    private readonly _choice: BackendChoice | null = null,
  ) {}

  /**
   * Whether the graphics processor stopped making sound while this was
   * speaking; nothing more will come of it, and the engine starts another.
   */
  get backendFailed(): boolean {
    return this._backendFailed;
  }
  private _backendFailed = false;

  private readonly _waiting = new Map<number, Completer<Float32Array | null>>();
  private _next = 0;

  /**
   * Asked for and not yet sent. The worker is handed one at a time, so
   * that what is no longer wanted — after a skip, say — can be dropped
   * before it takes its turn, rather than keep the next words waiting.
   */
  private readonly _queue: SynthesiserRequest[] = [];
  private _busy = false;
  private _closed = false;

  /**
   * How long making speech takes against how long it lasts, smoothed
   * over the pieces made so far; above 1 it cannot keep up.
   */
  private _pace = 0;
  private _made = 0;

  /** Whether this device makes speech more slowly than it is heard. */
  get fallingBehind(): boolean {
    return this._made >= 4 && this._pace > 1.05;
  }

  /** The worker the app runs the model on. */
  static createWorker(): SynthesiserPort {
    return new Worker(new URL('../speech/ttsWorker.ts', import.meta.url), { type: 'module' });
  }

  static async start(
    model: NeuralModel,
    files: VoiceFiles,
    options: { createWorker?: () => SynthesiserPort; wasmPaths?: string; choice?: BackendChoice | null } = {},
  ): Promise<Synthesiser> {
    const choice = options.choice === undefined ? BackendChoice.forThisBrowser() : options.choice;
    const plan = choice?.plan() ?? { backends: ['wasm' as Backend], prove: false };
    if (plan.backends.length === 0) throw new Error('The voice could not be loaded: it has not run on this device');
    const worker = (options.createWorker ?? Synthesiser.createWorker)();
    const first = new Completer<WorkerReply | string>();
    let synth: Synthesiser | null = null;
    worker.onerror = (event) => {
      first.complete(`${event.message}`);
    };
    worker.onmessage = (event) => {
      const message = event.data;
      if (!first.isCompleted) {
        first.complete(message);
        return;
      }
      synth?._receive(message);
    };
    // Marked before it begins: a phone short of memory ends the page
    // rather than fail the load, and the mark is how that is known of.
    choice?.begin(plan);
    // A page closed on purpose while it loads is not a page that died:
    // leaving is told of, and being ended for want of memory is not.
    const leaving = () => choice?.failed();
    const page = typeof addEventListener === 'function' && typeof removeEventListener === 'function';
    if (page) addEventListener('pagehide', leaving);
    worker.postMessage(
      { type: 'load', files, wasmPaths: options.wasmPaths, backends: plan.backends, prove: plan.prove },
      [files.model, files.voices],
    );
    const answer = await first.promise;
    if (page) removeEventListener('pagehide', leaving);
    if (typeof answer === 'string' || answer.type !== 'ready') {
      choice?.failed();
      worker.terminate();
      const why = typeof answer === 'string' ? answer : answer.type === 'error' ? answer.message : answer.type;
      throw new Error(`The voice could not be loaded: ${why}`);
    }
    // eSpeak runs on the worker where it can; where it cannot, it runs
    // here and the phonemes go over with the words.
    const phonemesHere = answer.phonemizer
      ? null
      : async (text: string) => (await import('../speech/phonemes')).phonemesFor(text);
    if (phonemesHere !== null) console.warn(`OpenWord: ${model.title}'s phonemes are made on the page`);
    const backend = answer.backend ?? 'wasm';
    const refused = answer.refused ?? [];
    choice?.loaded(backend, refused);
    for (const { backend: failed, why } of refused) console.warn(`OpenWord: the voice will not run on ${failed}: ${why}`);
    return (synth = new Synthesiser(worker, phonemesHere, 24000, backend, choice));
  }

  private _receive(message: WorkerReply): void {
    switch (message.type) {
      case 'audio': {
        const lasts = message.samples.length / message.sampleRate;
        if (lasts > 0) {
          const pace = message.ms / 1000 / lasts;
          this._pace = this._made === 0 ? pace : this._pace * 0.7 + pace * 0.3;
          this._made++;
          // Kept once there is enough to judge by, and now and then after.
          if (this._made === 4 || this._made % 25 === 0) this._choice?.paced(this.backend, this._pace);
        }
        this._waiting.get(message.id)?.complete(message.samples);
        this._waiting.delete(message.id);
        break;
      }
      case 'error':
        if (message.id === undefined) return;
        console.warn(`OpenWord: the voice could not say a piece: ${message.message}`);
        if (message.backendFailed === true && !this._backendFailed) {
          this._backendFailed = true;
          this._choice?.broke(this.backend);
        }
        this._waiting.get(message.id)?.complete(null);
        this._waiting.delete(message.id);
        break;
      case 'cancelled':
        this._waiting.get(message.id)?.complete(null);
        this._waiting.delete(message.id);
        break;
      default:
        return;
    }
    this._busy = false;
    this._sendNext();
  }

  /**
   * Makes [text] into samples; null if it could not, or if [owner] no
   * longer wants it.
   */
  say(text: string, options: { speaker: number; speed: number; owner?: object }): Promise<Float32Array | null> {
    const id = this._next++;
    const waiting = new Completer<Float32Array | null>();
    if (this._closed) {
      waiting.complete(null);
      return waiting.promise;
    }
    this._waiting.set(id, waiting);
    this._queue.push({
      id,
      message: { type: 'speak', id, text, sid: options.speaker, speed: options.speed },
      owner: options.owner,
    });
    this._sendNext();
    return waiting.promise;
  }

  private _sendNext(): void {
    if (this._busy || this._queue.length === 0 || this._closed) return;
    this._busy = true;
    const request = this._queue.shift()!;
    if (this._phonemesHere === null) {
      this._worker.postMessage(request.message);
      return;
    }
    // Given a time to answer in: eSpeak has been seen to hang on a phone,
    // and a piece that fails is better than a reading that waits for ever.
    const phonemes = new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('eSpeak did not answer')), 15000);
      this._phonemesHere!(request.message.text).then(
        (made) => {
          clearTimeout(timer);
          resolve(made);
        },
        (error: unknown) => {
          clearTimeout(timer);
          reject(error);
        },
      );
    });
    phonemes.then(
      (phonemes) => {
        if (this._closed) return;
        this._worker.postMessage({ ...request.message, phonemes });
      },
      (error: unknown) => {
        console.warn('OpenWord: eSpeak could not say a piece', error);
        this._waiting.get(request.id)?.complete(null);
        this._waiting.delete(request.id);
        this._busy = false;
        this._sendNext();
      },
    );
  }

  /** Drops what [owner] asked for that has not yet been begun. */
  forget(owner: object): void {
    for (let i = this._queue.length - 1; i >= 0; i--) {
      const request = this._queue[i];
      if (request.owner !== owner) continue;
      this._queue.splice(i, 1);
      this._waiting.get(request.id)?.complete(null);
      this._waiting.delete(request.id);
    }
  }

  close(): void {
    if (this._closed) return;
    this._closed = true;
    this._worker.postMessage({ type: 'close' });
    this._queue.length = 0;
    for (const waiting of this._waiting.values()) waiting.complete(null);
    this._waiting.clear();
    // Let it free the model before it goes.
    setTimeout(() => this._worker.terminate(), 5000);
  }

  /** See `levelled` in src/speech/kitten.ts. */
  static levelled(samples: Float32Array, sampleRate: number, target = 0.14): Float32Array {
    return levelledSamples(samples, sampleRate, target);
  }

  /** See `limited` in src/speech/kitten.ts. */
  static limited(samples: Float32Array, ceiling = 0.95): Float32Array {
    return limitedSamples(samples, ceiling);
  }
}

interface SynthesiserRequest {
  id: number;
  message: Extract<WorkerRequest, { type: 'speak' }>;
  owner: object | undefined;
}
