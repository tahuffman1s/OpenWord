import { ChangeNotifier } from '../infra/changeNotifier';
import { parseIntStrict, Reference, type Chapter } from '../model/bible';

/** One of the voices reading aloud can be heard in. */
export class SpeechVoice {
  /** What the voice is chosen by, and kept in settings as. */
  readonly name: string;
  readonly locale: string;
  /** What to call it, where that is not its name. */
  readonly title: string | null;

  constructor(init: { name: string; locale: string; title?: string | null }) {
    this.name = init.name;
    this.locale = init.locale;
    this.title = init.title ?? null;
  }
}

export interface SpeakOptions {
  /**
   * Given the offset in the text of each place it reaches that it can
   * tell — for OpenWord's own voice, the start of each piece it is spoken
   * in.
   */
  onProgress?: (offset: number) => void;
  onStart?: () => void;
  /** The offsets it should tell of as it reaches them: where each verse begins. */
  breaks?: readonly number[];
}

export interface ConfigureOptions {
  language: string;
  rate: number;
  voice?: string | null;
}

/**
 * What reading aloud needs from whatever speaks. A seam, so a test can
 * drive playback without a device that talks.
 */
export interface SpeechEngine {
  /** Whether this platform can speak at all. */
  readonly isAvailable: boolean;

  configure(options: ConfigureOptions): Promise<void>;

  /**
   * Speaks [text]. Completes with true when it has been said to the end,
   * and false when it was stopped or failed. [onProgress] is given the
   * offset in [text] of each place it reaches that it can tell — for this
   * voice, the start of each piece it is spoken in — and [breaks] are the
   * offsets it should tell of as it reaches them: where each verse begins.
   */
  speak(text: string, options?: SpeakOptions): Promise<boolean>;

  stop(): Promise<void>;

  /** The voices for a language, best first. */
  voices(language: string): Promise<SpeechVoice[]>;

  /**
   * Whether [pause] holds the voice where it is, for [resume] to go on
   * from mid-word. Where it cannot, pausing stops the voice, and resuming
   * speaks again from the word it had reached.
   */
  readonly canPause: boolean;

  pause(): Promise<void>;

  resume(): Promise<void>;
}

/**
 * Where there is nothing to speak with — a browser without WebAssembly or
 * Web Audio, and no voices of its own — and nothing offers to.
 */
export class NoSpeechEngine implements SpeechEngine {
  get isAvailable(): boolean {
    return false;
  }

  get canPause(): boolean {
    return false;
  }

  async configure(_options: ConfigureOptions): Promise<void> {}

  async speak(_text: string, _options?: SpeakOptions): Promise<boolean> {
    return false;
  }

  async stop(): Promise<void> {}

  async pause(): Promise<void> {}

  async resume(): Promise<void> {}

  async voices(_language: string): Promise<SpeechVoice[]> {
    return [];
  }
}

export enum ReadAloudState {
  idle,
  playing,
  paused,
}

/**
 * Where listening got to: a verse, and how far into it, kept so that it
 * can be taken up again after the bar is closed or the app is.
 */
export class ListeningPlace {
  readonly verse: Reference;

  /** How far into the verse's spoken words. */
  readonly offset: number;

  /**
   * Whether the chapter was begun from its top, so that finishing it
   * still counts it as heard.
   */
  readonly fromTop: boolean;

  constructor(verse: Reference, options: { offset?: number; fromTop?: boolean } = {}) {
    this.verse = verse;
    this.offset = options.offset ?? 0;
    this.fromTop = options.fromTop ?? false;
  }

  /** Nothing heard yet: taking it up is the same as starting. */
  get atTop(): boolean {
    return (this.verse.verse ?? 1) <= 1 && this.offset === 0;
  }

  encode(): string {
    return `${this.verse.encode()}|${this.offset}|${this.fromTop ? 1 : 0}`;
  }

  static decode(raw: string | null | undefined): ListeningPlace | null {
    const parts = raw?.split('|');
    if (parts == null || parts.length !== 3) return null;
    const verse = Reference.decode(parts[0]);
    const offset = parseIntStrict(parts[1]);
    if (verse === null || verse.verse === null || offset === null) return null;
    return new ListeningPlace(verse, { offset, fromTop: parts[2] === '1' });
  }

  equals(other: ListeningPlace | null | undefined): boolean {
    return (
      other != null && other.verse.equals(this.verse) && other.offset === this.offset && other.fromTop === this.fromTop
    );
  }
}

/** One thing to say: a verse, or the name of a chapter as it begins. */
export class Utterance {
  constructor(
    /** Carries a verse, or none for a chapter's announcement. */
    readonly reference: Reference,
    readonly text: string,
  ) {}
}

export interface ReadAloudInit {
  engine: SpeechEngine;
  /** The chapter at a reference, from the translation being read. */
  chapterFor: (chapter: Reference) => Chapter | null | undefined;
  /** The chapter to go on to after this one, or null to stop. */
  nextChapter: (chapter: Reference) => Reference | null;
  /** Called when a whole chapter has been heard to its last verse. */
  onChapterHeard?: (chapter: Reference) => void;
  /**
   * Told where listening has got to as it moves from verse to verse, and
   * when it is paused or stopped, so that it can be kept; told null when
   * it has been heard to its end and there is nothing to take up. Not
   * told about reading a selection.
   */
  onPlace?: (place: ListeningPlace | null) => void;
  /** What time it is; a test sets it. */
  clock?: () => Date;
}

/**
 * Reads Scripture aloud, a verse at a time.
 *
 * It keeps its place by the verse, which is what lets the page follow
 * along and lets the reader step back a verse or on to the next; the
 * voice is handed passages of several verses at once, and the words the
 * platform reports reaching say which verse it is on. Pausing holds the
 * voice where it is, where the engine can; otherwise it stops the voice
 * and remembers the word it had reached, and resuming takes up from that
 * word, which every platform can do.
 */
export class ReadAloud extends ChangeNotifier {
  /** What time it is; a test sets it. */
  private readonly _clock: () => Date;

  readonly engine: SpeechEngine;

  /** The chapter at a reference, from the translation being read. */
  readonly chapterFor: (chapter: Reference) => Chapter | null | undefined;

  /** The chapter to go on to after this one, or null to stop. */
  readonly nextChapter: (chapter: Reference) => Reference | null;

  /** Called when a whole chapter has been heard to its last verse. */
  readonly onChapterHeard: ((chapter: Reference) => void) | null;

  /**
   * Told where listening has got to as it moves from verse to verse, and
   * when it is paused or stopped, so that it can be kept; told null when
   * it has been heard to its end and there is nothing to take up. Not
   * told about reading a selection.
   */
  readonly onPlace: ((place: ListeningPlace | null) => void) | null;
  private _lastPlace: ListeningPlace | null = null;

  private _state = ReadAloudState.idle;
  private _queue: Utterance[] = [];
  private _index = 0;
  private _stopAtEnd = false;
  private _startedAtTop = false;
  private _generation = 0;

  private _language = 'en';
  private _rate = 1.0;
  private _voice: string | null = null;

  /**
   * The settings last handed to the engine, so they are sent again only
   * when they change: looking a voice up is not free.
   */
  private _applied: { language: string; rate: number; voice: string | null } | null = null;

  /**
   * Handing them over, which for a voice of OpenWord's own means loading
   * its model; speaking waits for it.
   */
  private _applying: Promise<void> | null = null;

  constructor(init: ReadAloudInit) {
    super();
    this.engine = init.engine;
    this.chapterFor = init.chapterFor;
    this.nextChapter = init.nextChapter;
    this.onChapterHeard = init.onChapterHeard ?? null;
    this.onPlace = init.onPlace ?? null;
    this._clock = init.clock ?? (() => new Date());
  }

  private _apply(): Promise<void> {
    const wanted = { language: this._language, rate: this._rate, voice: this._voice };
    const applied = this._applied;
    if (
      applied !== null &&
      applied.language === wanted.language &&
      applied.rate === wanted.rate &&
      applied.voice === wanted.voice &&
      this._applying !== null
    ) {
      return this._applying;
    }
    this._applied = wanted;
    // One after another: a voice chosen while the last is still loading
    // waits for it.
    return (this._applying = (this._applying ?? Promise.resolve()).then(() =>
      this.engine.configure({ language: wanted.language, rate: wanted.rate, voice: wanted.voice }).catch(() => {
        // A voice or rate the platform refuses still leaves it able
        // to speak.
      }),
    ));
  }

  /**
   * Gets the voice ready before it is asked to speak — for one of
   * OpenWord's own, loading its model — so that Listen is heard at once.
   */
  prepare(): void {
    void this._apply();
  }

  error: string | null = null;

  /** Whether the verse being said is a second attempt at it. */
  private _retrying = false;

  /**
   * How far into the current verse the voice had got, from the words the
   * platform reports, so that resuming after a pause takes up that word
   * rather than starting the verse again.
   */
  private _resumeAt = 0;

  /**
   * Whether the engine is holding the passage, paused where it is, to go
   * on from there.
   */
  private _held = false;

  /**
   * The generation whose passage the engine has been given and not yet
   * finished.
   */
  private _saying = -1;

  /**
   * How long to wait, in milliseconds, before saying a verse again after
   * the engine did not finish it. A test shortens it.
   */
  static retryDelay = 400;

  get state(): ReadAloudState {
    return this._state;
  }

  get isActive(): boolean {
    return this._state !== ReadAloudState.idle;
  }

  get isPlaying(): boolean {
    return this._state === ReadAloudState.playing;
  }

  /**
   * What is being said, or was about to be when paused: a verse, or a
   * chapter with no verse while its name is announced.
   */
  get current(): Reference | null {
    return this.isActive && this._index < this._queue.length ? this._queue[this._index].reference : null;
  }

  /** Where to take up again, as it would be kept. */
  get place(): ListeningPlace | null {
    const verse = this.current;
    if (verse === null || verse.verse === null || this._stopAtEnd) return null;
    return new ListeningPlace(verse, { offset: this._resumeAt, fromTop: this._startedAtTop });
  }

  private _notePlace(): void {
    const place = this.place;
    if (place === null || place.equals(this._lastPlace)) return;
    this._lastPlace = place;
    this.onPlace?.(place);
  }

  override notifyListeners(): void {
    this._notePlace();
    super.notifyListeners();
  }

  /**
   * Lets go of a passage the engine is holding paused, when what is to be
   * said next is not what it holds.
   */
  private _release(): void {
    if (!this._held) return;
    this._held = false;
    this._generation++;
    void this.engine.stop();
  }

  /**
   * Sets how it sounds. Takes effect from the next verse, or at once when
   * something is being said.
   */
  configure(options: ConfigureOptions): void {
    const voice = options.voice ?? null;
    const changed = options.language !== this._language || options.rate !== this._rate || voice !== this._voice;
    this._language = options.language;
    this._rate = options.rate;
    this._voice = voice;
    if (!changed) return;
    if (this.isPlaying) {
      void this._speakCurrent(true);
    } else {
      // Held in the old voice; resuming says it again in the new one.
      this._release();
    }
  }

  /**
   * Starts reading at [from]: its verse, or the top of its chapter with
   * the chapter's name. With [only], reads those verses and stops.
   *
   * [offset] takes up the verse part way in, and [fromTop] says the
   * chapter was begun from its top before, for taking up a kept place.
   */
  play(from: Reference, options: { only?: Set<number> | null; offset?: number; fromTop?: boolean } = {}): void {
    const only = options.only ?? null;
    const offset = options.offset ?? 0;
    const fromTop = options.fromTop ?? false;
    this._release();
    const chapter = from.withVerse(null);
    const atTop = only === null && (from.verse ?? 1) <= 1 && offset === 0;
    this._stopAtEnd = only !== null;
    this._startedAtTop = atTop || (only === null && fromTop);
    this._queue = this._utterancesFor(chapter, { from: from.verse ?? 1, only, announce: atTop });
    this._index = 0;
    this._resumeAt = this._queue.length > 0 && this._queue[0].reference.equals(from) ? offset : 0;
    this.error = null;
    if (this._queue.length === 0) {
      this.stop();
      return;
    }
    this._state = ReadAloudState.playing;
    this.notifyListeners();
    void this._speakCurrent();
  }

  pause(): void {
    if (!this.isPlaying) return;
    this._cancelEstimator();
    if (this.engine.canPause && this._saying === this._generation) {
      // Held where it is, mid-word, to go on from there.
      this._held = true;
      this._state = ReadAloudState.paused;
      this.notifyListeners();
      void this.engine.pause();
      return;
    }
    // Where it had got to. Exact where the platform reports its words;
    // otherwise estimated from the time it has been speaking, and taken
    // back to the start of that sentence so that nothing is skipped.
    if (!this._passageHasProgress) {
      this._estimate();
      if (this._index < this._queue.length) {
        this._resumeAt = ReadAloud.sentenceStart(this._queue[this._index].text, this._resumeAt);
      }
    }
    this._cancelEstimator();
    this._generation++;
    this._state = ReadAloudState.paused;
    this.notifyListeners();
    void this.engine.stop();
  }

  resume(): void {
    if (this._state !== ReadAloudState.paused) return;
    this._state = ReadAloudState.playing;
    this.notifyListeners();
    if (this._held) {
      this._held = false;
      void this.engine.resume();
      return;
    }
    void this._speakCurrent();
  }

  stop(): void {
    if (this.isPlaying && !this._passageHasProgress) {
      this._estimate();
      if (this._index < this._queue.length) {
        this._resumeAt = ReadAloud.sentenceStart(this._queue[this._index].text, this._resumeAt);
      }
    }
    // Kept, to be taken up another time.
    this._notePlace();
    this._end();
  }

  private _end(): void {
    this._cancelEstimator();
    this._generation++;
    this._held = false;
    const wasActive = this.isActive;
    this._state = ReadAloudState.idle;
    this._queue = [];
    this._index = 0;
    if (wasActive) void this.engine.stop();
    this.notifyListeners();
  }

  /**
   * On to the next verse, or back to the one before. Stepping back from a
   * chapter's first verse says it again.
   */
  skip(delta: number): void {
    if (!this.isActive) return;
    this._release();
    // Stepping is from the verse the voice is on, as near as can be told.
    if (this.isPlaying && !this._passageHasProgress) this._estimate();
    this._resumeAt = 0;
    const next = Math.min(Math.max(this._index + delta, 0), this._queue.length - 1);
    if (delta > 0 && this._index + delta >= this._queue.length) {
      this._generation++;
      void this.engine.stop();
      this._advanceChapter(false);
      return;
    }
    this._index = next;
    this.notifyListeners();
    if (this.isPlaying) void this._speakCurrent(true);
  }

  override dispose(): void {
    this._cancelEstimator();
    this._generation++;
    if (this.isActive) void this.engine.stop();
    super.dispose();
  }

  /**
   * How much is handed to the voice at once, in characters.
   *
   * Not a verse at a time: a voice that starts and stops between every
   * verse clips the first syllable of many of them, most of all over
   * Bluetooth, which lets the link sleep in the gaps. Several verses go
   * together as one utterance. Where the platform reports each word as it
   * reaches it, that says which verse is being read, and a passage can be
   * long. Where it does not — Samsung's engine among others — the verse is
   * estimated from how long the voice has been speaking, and a passage is
   * kept to half a minute or so, so that the estimate never drifts far
   * before the next passage puts it right.
   */
  static readonly passageLength = 1200;
  static readonly estimatedPassageLength = 400;

  /**
   * Whether this platform reports the words it reaches: unknown until it
   * has read something.
   */
  private _reportsProgress: boolean | null = null;

  /**
   * How fast the voice speaks at normal pace, in characters a second: a
   * fair guess to begin with, then measured from each passage it finishes.
   */
  private _charsPerSecond = 14;

  // The passage being spoken, for estimating where the voice has got to.
  private _passageStarts: number[] = [];
  private _passageFirst = 0;
  private _passageTrim = 0;
  private _passageLength = 0;
  private _passageStartedAt: Date | null = null;
  private _passageHasProgress = false;
  private _estimator: ReturnType<typeof setInterval> | null = null;

  private _cancelEstimator(): void {
    if (this._estimator !== null) clearInterval(this._estimator);
    this._estimator = null;
  }

  /**
   * Moves the place along by the time the voice has been speaking, where
   * the platform does not say which word it is on.
   */
  private _estimate(): void {
    const startedAt = this._passageStartedAt;
    if (this._passageHasProgress || startedAt === null || this._passageStarts.length === 0) {
      return;
    }
    const seconds = (this._clock().getTime() - startedAt.getTime()) / 1000;
    const offset = Math.min(
      Math.max(Math.floor(seconds * this._charsPerSecond * this._rate), 0),
      this._passageLength > 0 ? this._passageLength - 1 : 0,
    );
    this._place(offset);
  }

  /** Takes an offset into the passage to the verse, and the place in it. */
  private _place(offset: number): void {
    const starts = this._passageStarts;
    let k = 0;
    while (k + 1 < starts.length && starts[k + 1] <= offset) {
      k++;
    }
    this._resumeAt = (k === 0 ? this._passageTrim : 0) + offset - starts[k];
    if (this._passageFirst + k !== this._index) {
      this._index = this._passageFirst + k;
      this.notifyListeners();
    }
  }

  /**
   * Where the sentence around [offset] in [text] begins, so that a place
   * that is only estimated is taken back to somewhere sensible to resume.
   */
  static sentenceStart(text: string, offset: number): number {
    if (offset <= 0 || offset > text.length) return 0;
    let start = 0;
    for (const end of text.matchAll(ReadAloud._sentenceEnd)) {
      const endAt = end.index + end[0].length;
      if (endAt > offset) break;
      start = endAt;
    }
    return start;
  }

  private static readonly _sentenceEnd = /[.;:!?][”’"')]*\s+/g;

  /** Test hook: estimate the place now, as the timer would. */
  debugEstimate(): void {
    this._estimate();
  }

  /**
   * Says a passage from the current verse on, and on to the next when it
   * is done.
   *
   * With [interrupt], whatever is being said is stopped first: some
   * platforms queue a second utterance behind the first rather than
   * replacing it.
   */
  private async _speakCurrent(interrupt = false): Promise<void> {
    const generation = ++this._generation;
    if (interrupt) await this.engine.stop();
    if (generation !== this._generation) return;
    await this._apply();
    if (generation !== this._generation) return;

    // The passage: this verse and those after it, as far as will go. After
    // a pause it takes up the verse at the word it had reached.
    const first = this._index;
    const firstText = this._queue[first].text;
    const trim = this._resumeAt > 0 && this._resumeAt < firstText.length ? this._resumeAt : 0;
    const starts: number[] = [];
    let passage = '';
    // An engine that makes its own speech is handed the rest of the
    // chapter at once: it cuts it up itself, a sentence ahead of what is
    // heard, and a new passage would start that from nothing.
    const length = this.engine.canPause
      ? 1 << 30
      : this._reportsProgress === true
        ? ReadAloud.passageLength
        : ReadAloud.estimatedPassageLength;
    let last = first;
    for (let i = first; i < this._queue.length; i++) {
      const text = i === first ? firstText.substring(trim) : this._queue[i].text;
      if (i > first && passage.length + 1 + text.length > length) break;
      if (i > first) passage += ' ';
      starts.push(passage.length);
      passage += text;
      last = i;
    }
    const text = passage;
    this._passageStarts = starts;
    this._passageFirst = first;
    this._passageTrim = trim;
    this._passageLength = text.length;
    this._passageHasProgress = false;
    // Counted from when the platform says it has begun, or from now where
    // it says nothing.
    this._passageStartedAt = this._clock();
    this._cancelEstimator();
    // A voice that makes its own speech tells where it is as it gets
    // there; estimating ahead of it, while it is still making the first
    // piece, would move the verse before a word had been heard.
    if (this._reportsProgress !== true && !this.engine.canPause) {
      this._estimator = setInterval(() => {
        if (generation === this._generation && this.isPlaying) this._estimate();
      }, 300);
    }
    this._saying = generation;
    const said = await this.engine.speak(text, {
      breaks: starts,
      onStart: () => {
        if (generation === this._generation) this._passageStartedAt = this._clock();
      },
      onProgress: (offset) => {
        if (generation !== this._generation) return;
        this._passageHasProgress = true;
        this._cancelEstimator();
        // Exact: this word, in its verse.
        this._place(offset);
      },
    });
    this._cancelEstimator();
    if (generation !== this._generation) return;
    this._saying = -1;
    const progressed = this._passageHasProgress;
    const startedAt = this._passageStartedAt;
    if (!said) {
      // Once is a hiccup — an engine still waking up, a stop reported
      // late — and the verse is simply said again. Twice running, the
      // device really is not speaking.
      if (!this._retrying) {
        this._retrying = true;
        await new Promise<void>((resolve) => setTimeout(resolve, ReadAloud.retryDelay));
        if (generation !== this._generation) return;
        void this._speakCurrent();
        return;
      }
      this._retrying = false;
      this.error = 'Could not read aloud. The device may have no voice for this translation’s language installed.';
      this.stop();
      return;
    }
    this._retrying = false;
    if (progressed) {
      this._reportsProgress = true;
    } else {
      this._reportsProgress ??= false;
      // How fast this voice really is, from a passage it has finished,
      // for the next estimate.
      const seconds = startedAt === null ? 0 : (this._clock().getTime() - startedAt.getTime()) / 1000;
      if (seconds >= 2 && text.length >= 40) {
        const measured = text.length / seconds / this._rate;
        this._charsPerSecond = (this._charsPerSecond + measured) / 2;
      }
    }
    this._resumeAt = 0;
    if (last + 1 < this._queue.length) {
      this._index = last + 1;
      this.notifyListeners();
      void this._speakCurrent();
      return;
    }
    this._index = last;
    this._advanceChapter(true);
  }

  private _advanceChapter(heardToEnd: boolean): void {
    const chapter = this._queue[0].reference.withVerse(null);
    if (heardToEnd && this._startedAtTop) this.onChapterHeard?.(chapter);
    const next = this._stopAtEnd ? null : this.nextChapter(chapter);
    if (next === null) {
      if (heardToEnd && !this._stopAtEnd) {
        // Heard to the end: nothing is left to take up.
        this._lastPlace = null;
        this.onPlace?.(null);
        this._end();
      } else {
        this.stop();
      }
      return;
    }
    this._queue = this._utterancesFor(next, { from: 1, announce: true });
    this._startedAtTop = true;
    this._index = 0;
    this._resumeAt = 0;
    if (this._queue.length === 0) {
      this.stop();
      return;
    }
    this.notifyListeners();
    if (this.isPlaying) void this._speakCurrent();
  }

  private _utterancesFor(
    chapterRef: Reference,
    options: { from: number; only?: Set<number> | null; announce: boolean },
  ): Utterance[] {
    const chapter = this.chapterFor(chapterRef);
    if (chapter == null) return [];
    const only = options.only ?? null;
    const result: Utterance[] = [];
    if (options.announce) result.push(new Utterance(chapterRef, ReadAloud.announcement(chapterRef)));
    for (let verse = options.from; verse <= chapter.verseCount; verse++) {
      if (only !== null && !only.has(verse)) continue;
      const text = ReadAloud.speakable(chapter.verseText(verse));
      if (text.length > 0) result.push(new Utterance(chapterRef.withVerse(verse), text));
    }
    return result;
  }

  /** "Genesis, chapter 1." A psalm is a psalm. */
  static announcement(chapter: Reference): string {
    switch (chapter.bookCode) {
      case 'PSA':
        return `Psalm ${chapter.chapter}.`;
      default:
        return `${chapter.bookName}, chapter ${chapter.chapter}.`;
    }
  }

  /**
   * The words as they should be heard.
   *
   * The divine name is printed in capitals to set it apart on the page,
   * and a voice reading "LORD" may spell it out letter by letter; it is
   * said as a word.
   */
  static speakable(text: string): string {
    return text
      .replace(ReadAloud._capitalName, (_m, name: string) => (name === 'LORD' ? 'Lord' : 'God'))
      .replace(/\s+/g, ' ')
      .trim();
  }

  private static readonly _capitalName = /\b(LORD|GOD)\b/g;
}
