import { ChangeNotifier } from '../infra/changeNotifier';
import { ReadAloud, type SpeechEngine } from './readAloud';

/**
 * The voice in learning: says a verse, a tile, or any words, at the
 * reader's pace or slowly, and says whether it is speaking.
 *
 * Practice and the rounds speak the way a language app does — the verse
 * as it appears, a tile as it is tapped, the verse again once an answer
 * is checked — so this is the one place those screens come to. The
 * engine is told how to sound only when first asked to speak, since for
 * OpenWord's own voice that means loading its model.
 */
export class LearnVoice extends ChangeNotifier {
  readonly engine: SpeechEngine;
  readonly language: string;

  /** The reader's chosen pace, as reading aloud uses it. */
  readonly rate: number;
  readonly voice: string | null;

  constructor(init: { engine: SpeechEngine; language: string; rate: number; voice?: string | null }) {
    super();
    this.engine = init.engine;
    this.language = init.language;
    this.rate = init.rate;
    this.voice = init.voice ?? null;
  }

  /** How much slower "slowly" is. */
  static readonly slowFactor = 0.65;

  get isAvailable(): boolean {
    return this.engine.isAvailable;
  }

  private _speaking = false;
  get isSpeaking(): boolean {
    return this._speaking;
  }

  private _disposed = false;

  private _setSpeaking(value: boolean): void {
    if (this._disposed || this._speaking === value) return;
    this._speaking = value;
    this.notifyListeners();
  }

  private _appliedRate: number | null = null;
  private _applying: Promise<void> = Promise.resolve();
  private _generation = 0;

  private _apply(wanted: number): Promise<void> {
    if (this._appliedRate === wanted) return this._applying;
    this._appliedRate = wanted;
    return (this._applying = this._applying.then(() =>
      this.engine.configure({ language: this.language, rate: wanted, voice: this.voice }).catch(() => {}),
    ));
  }

  /**
   * Says [text], stopping whatever was being said. Completes when it has
   * been said, or cut short.
   */
  async say(text: string, options: { slow?: boolean } = {}): Promise<void> {
    if (!this.isAvailable || text.length === 0) return;
    const generation = ++this._generation;
    await this.engine.stop();
    await this._apply(options.slow ? this.rate * LearnVoice.slowFactor : this.rate);
    if (generation !== this._generation) return;
    this._setSpeaking(true);
    await this.engine.speak(ReadAloud.speakable(text));
    if (generation === this._generation) this._setSpeaking(false);
  }

  async stop(): Promise<void> {
    this._generation++;
    await this.engine.stop();
    this._setSpeaking(false);
  }

  override dispose(): void {
    this._disposed = true;
    this._generation++;
    void this.engine.stop();
    super.dispose();
  }
}
