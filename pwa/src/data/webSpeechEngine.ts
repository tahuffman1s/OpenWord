import { SpeechVoice, type ConfigureOptions, type SpeakOptions, type SpeechEngine } from './readAloud';

/**
 * The browser's own voices, through the Web Speech API: what the native
 * app read with before it had a voice of its own, and what a browser that
 * cannot run the neural one still has.
 *
 * Its quirks, and what is done about them:
 *
 * - Chrome stops a long utterance dead after about fifteen seconds, with
 *   no error. A passage is cut into sentences of a few hundred characters
 *   at most and spoken one after another, each short enough to finish.
 * - `pause()` holds the voice on some platforms and ends it on others —
 *   Android Chrome drops the utterance — so `canPause` is false, and the
 *   reader stops and resumes from the word it had reached instead, which
 *   works everywhere.
 * - Boundary events, where the browser gives them, say which word the
 *   voice has reached; they feed `onProgress` with the offset in the whole
 *   text. Where it gives none (iOS Safari, some Android voices), the
 *   reader estimates the place from time, as it does for Samsung's engine.
 * - `getVoices()` is empty until the browser has loaded its list, which
 *   it announces with `voiceschanged`; the first call waits for it, a
 *   little.
 * - An utterance spoken right after `cancel()` is sometimes swallowed;
 *   a breath is left between them.
 */
export class WebSpeechEngine implements SpeechEngine {
  private readonly _synth: SpeechSynthesis | null;

  constructor(synth?: SpeechSynthesis | null) {
    this._synth = synth === undefined ? (typeof speechSynthesis !== 'undefined' ? speechSynthesis : null) : synth;
  }

  /** The longest utterance handed to the browser at once, in characters. */
  static readonly utteranceLength = 240;

  private _language = 'en';
  private _rate = 1.0;
  private _voice: SpeechSynthesisVoice | null = null;
  private _generation = 0;

  get isAvailable(): boolean {
    return this._synth !== null && typeof SpeechSynthesisUtterance !== 'undefined';
  }

  get canPause(): boolean {
    return false;
  }

  async configure(options: ConfigureOptions): Promise<void> {
    this._language = options.language;
    this._rate = options.rate;
    this._voice = null;
    if (options.voice == null) return;
    const voices = await this._allVoices();
    this._voice = voices.find((v) => v.name === options.voice || v.voiceURI === options.voice) ?? null;
  }

  async speak(text: string, options: SpeakOptions = {}): Promise<boolean> {
    const synth = this._synth;
    if (synth === null || !this.isAvailable || text.length === 0) return false;
    const generation = ++this._generation;
    if (synth.speaking || synth.pending) {
      synth.cancel();
      await new Promise<void>((resolve) => setTimeout(resolve, 60));
      if (generation !== this._generation) return false;
    }
    const pieces = WebSpeechEngine.utterances(text, options.breaks ?? []);
    let started = false;
    for (const [offset, words] of pieces) {
      if (generation !== this._generation) return false;
      const utterance = new SpeechSynthesisUtterance(words);
      utterance.lang = this._voice?.lang ?? this._language;
      utterance.rate = this._rate;
      if (this._voice !== null) utterance.voice = this._voice;
      const ended = await new Promise<boolean>((resolve) => {
        utterance.onstart = () => {
          if (generation !== this._generation) return;
          if (!started) {
            started = true;
            options.onStart?.();
          }
          options.onProgress?.(offset);
        };
        utterance.onboundary = (event) => {
          if (generation !== this._generation) return;
          if (event.name === 'word' || event.name === undefined) options.onProgress?.(offset + event.charIndex);
        };
        utterance.onend = () => resolve(true);
        // Interrupted, cancelled, or truly failed: none of them said to
        // the end, and the reader tells a hiccup from a dead voice itself.
        utterance.onerror = () => resolve(false);
        synth.speak(utterance);
      });
      if (!ended || generation !== this._generation) return false;
    }
    return true;
  }

  /**
   * Where [text] is cut to be handed to the browser a sentence or so at
   * a time, as offset and words: at every verse start in [breaks], at
   * every sentence end, and again at a space where a sentence is longer
   * than [utteranceLength].
   */
  static utterances(text: string, breaks: readonly number[] = []): [number, string][] {
    const bounds = new Set<number>();
    for (const at of breaks) if (at > 0 && at < text.length) bounds.add(at);
    for (const end of text.matchAll(/[.;:!?][”’"')]*\s+/g)) bounds.add(end.index + end[0].length);
    bounds.add(text.length);
    const result: [number, string][] = [];
    const add = (start: number, end: number) => {
      while (start < end && text.charCodeAt(start) === 0x20) start++;
      while (end > start && text.charCodeAt(end - 1) === 0x20) end--;
      if (end > start) result.push([start, text.substring(start, end)]);
    };
    let start = 0;
    for (const end of [...bounds].sort((a, b) => a - b)) {
      let from = start;
      while (end - from > WebSpeechEngine.utteranceLength) {
        const window = text.substring(from, from + WebSpeechEngine.utteranceLength);
        let at = Math.max(window.lastIndexOf(', '), window.lastIndexOf('; '));
        at = at > 0 ? at + 1 : window.lastIndexOf(' ');
        if (at <= 0) at = WebSpeechEngine.utteranceLength;
        add(from, from + at);
        from += at;
      }
      add(from, end);
      start = end;
    }
    return result;
  }

  async stop(): Promise<void> {
    this._generation++;
    this._synth?.cancel();
  }

  /** Holds the voice where the browser can; see [canPause] for why the reader does not rely on it. */
  async pause(): Promise<void> {
    this._synth?.pause();
  }

  async resume(): Promise<void> {
    this._synth?.resume();
  }

  /**
   * The browser's voices for [language], best first: those of the exact
   * locale before the rest of the language, the ones on the device before
   * those that need the network, and the default among them first.
   */
  async voices(language: string): Promise<SpeechVoice[]> {
    const wanted = language.toLowerCase();
    const base = wanted.split('-')[0];
    const all = await this._allVoices();
    const matching = all.filter((v) => v.lang.toLowerCase().split(/[-_]/)[0] === base);
    const score = (v: SpeechSynthesisVoice) =>
      (v.lang.toLowerCase().replace('_', '-') === wanted ? 0 : 4) + (v.localService ? 0 : 2) + (v.default ? 0 : 1);
    matching.sort((a, b) => score(a) - score(b) || a.name.localeCompare(b.name));
    return matching.map((v) => new SpeechVoice({ name: v.name, locale: v.lang.replace('_', '-'), title: v.name }));
  }

  private _voicesLoaded: Promise<SpeechSynthesisVoice[]> | null = null;

  private _allVoices(): Promise<SpeechSynthesisVoice[]> {
    const synth = this._synth;
    if (synth === null) return Promise.resolve([]);
    const now = synth.getVoices();
    if (now.length > 0) return Promise.resolve(now);
    return (this._voicesLoaded ??= new Promise<SpeechSynthesisVoice[]>((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        synth.removeEventListener?.('voiceschanged', finish);
        this._voicesLoaded = null;
        resolve(synth.getVoices());
      };
      synth.addEventListener?.('voiceschanged', finish);
      setTimeout(finish, 1500);
    }));
  }
}
