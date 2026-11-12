import { expect } from 'vitest';
import type { ConfigureOptions, SpeakOptions, SpeechEngine } from '../src/data/readAloud';
import { SpeechVoice } from '../src/data/readAloud';

/** A promise with its resolver to hand. */
export class Completer<T = void> {
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

/** A speech engine that says nothing and finishes when told to. */
export class FakeSpeech implements SpeechEngine {
  readonly available: boolean;

  /** Whether it can hold what it is saying, as OpenWord's own voices can. */
  readonly pauses: boolean;
  readonly said: string[] = [];
  readonly rates: number[] = [];
  stops = 0;

  /** Where the last passage was to tell of reaching: its verses' starts. */
  breaks: readonly number[] = [];
  paused = 0;
  resumed = 0;

  constructor(options: { available?: boolean; pauses?: boolean } = {}) {
    this.available = options.available ?? true;
    this.pauses = options.pauses ?? false;
  }

  get canPause(): boolean {
    return this.pauses;
  }

  async pause(): Promise<void> {
    this.paused++;
  }

  async resume(): Promise<void> {
    this.resumed++;
  }

  private _saying: Completer<boolean> | null = null;

  get isAvailable(): boolean {
    return this.available;
  }

  /** Held open to keep configuring from finishing, as loading a model does. */
  configuring: Completer<void> | null = null;

  async configure(options: ConfigureOptions): Promise<void> {
    this.rates.push(options.rate);
    await this.configuring?.promise;
  }

  private _progress: ((offset: number) => void) | undefined;
  private _start: (() => void) | undefined;

  speak(text: string, options: SpeakOptions = {}): Promise<boolean> {
    this.said.push(text);
    this.breaks = options.breaks ?? [];
    this._progress = options.onProgress;
    this._start = options.onStart;
    return (this._saying = new Completer<boolean>()).promise;
  }

  /** Reports the voice as having begun what it was given. */
  begin(): void {
    this._start?.();
  }

  /** Reports the voice as having reached [words] in what it is saying. */
  reach(words: string): void {
    const at = this.said[this.said.length - 1].indexOf(words);
    expect(at, `"${words}" is not being said`).toBeGreaterThanOrEqual(0);
    this._progress?.(at);
  }

  /** Ends what is being said, as said to the end or not. */
  finish(toTheEnd = true): void {
    const saying = this._saying;
    this._saying = null;
    if (saying !== null && !saying.isCompleted) saying.complete(toTheEnd);
  }

  async stop(): Promise<void> {
    this.stops++;
    this.finish(false);
  }

  async voices(_language: string): Promise<SpeechVoice[]> {
    return [
      new SpeechVoice({ name: 'Serena', locale: 'en-GB' }),
      new SpeechVoice({ name: 'daniel', title: 'Daniel', locale: 'en-GB' }),
    ];
  }
}

/** Lets the controller's chain of awaits run through. */
export async function settle(): Promise<void> {
  for (let i = 0; i < 10; i++) {
    await new Promise<void>((resolve) => setTimeout(resolve, 0));
  }
}
