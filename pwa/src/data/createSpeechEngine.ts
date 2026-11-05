import { NeuralModel, neuralVoices } from './neuralVoices';
import { NoSpeechEngine, type ConfigureOptions, type SpeakOptions, type SpeechEngine, type SpeechVoice } from './readAloud';
import { WebSpeechEngine } from './webSpeechEngine';

/**
 * OpenWord's own voice and the browser's, behind one engine: a voice
 * named `openword:…` — or none chosen — is spoken by the neural engine,
 * as the native app does (`NeuralModel.chosen` picks its first speaker
 * for no name), and any other name is one of the device's voices, spoken
 * by the browser. The voice picker lists the Kitten speakers first and
 * the device's after them.
 *
 * The native app has only the neural engine now; it offered the device's
 * voices before that existed, and a browser that cannot run the model
 * still has them, so here both are kept.
 */
export class RoutedSpeechEngine implements SpeechEngine {
  private _current: SpeechEngine;

  constructor(
    /** The neural engine, or null where the browser cannot run it. */
    readonly neural: SpeechEngine | null,
    /** The browser's own voices. */
    readonly device: SpeechEngine,
  ) {
    this._current = neural ?? device;
  }

  get isAvailable(): boolean {
    return (this.neural?.isAvailable ?? false) || this.device.isAvailable;
  }

  get canPause(): boolean {
    return this._current.canPause;
  }

  /** Which engine a voice name means. */
  engineFor(voice: string | null | undefined): SpeechEngine {
    if (NeuralModel.parse(voice) !== null) return this.neural ?? this.device;
    if (voice == null) return this.neural ?? this.device;
    return this.device.isAvailable ? this.device : (this.neural ?? this.device);
  }

  async configure(options: ConfigureOptions): Promise<void> {
    const next = this.engineFor(options.voice);
    if (next !== this._current) {
      await this._current.stop();
      this._current = next;
    }
    await next.configure(options);
  }

  speak(text: string, options?: SpeakOptions): Promise<boolean> {
    return this._current.speak(text, options);
  }

  async stop(): Promise<void> {
    await this._current.stop();
  }

  pause(): Promise<void> {
    return this._current.pause();
  }

  resume(): Promise<void> {
    return this._current.resume();
  }

  /** Kitten's speakers first, then whatever the browser has for the language. */
  async voices(language: string): Promise<SpeechVoice[]> {
    const own = this.neural === null ? [] : await this.neural.voices(language);
    const device = this.device.isAvailable ? await this.device.voices(language) : [];
    return [...own, ...device];
  }
}

/**
 * Makes the engine the reader speaks with: OpenWord's own voice, where
 * it can run, with the browser's voices beside it. A test puts a silent
 * one in its place.
 */
export let createSpeechEngine: () => SpeechEngine = () => {
  const neural = neuralVoices.isSupported ? neuralVoices.engine() : null;
  const device = new WebSpeechEngine();
  if (neural === null && !device.isAvailable) return new NoSpeechEngine();
  return new RoutedSpeechEngine(neural, device);
};

export function setCreateSpeechEngine(create: () => SpeechEngine): void {
  createSpeechEngine = create;
}
