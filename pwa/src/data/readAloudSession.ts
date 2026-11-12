import { ValueNotifier } from '../infra/changeNotifier';
import type { Reference } from '../model/bible';
import { hasWebAudio, speechAudioContext } from '../speech/audio';
import { ReadAloud, ReadAloudState } from './readAloud';

/**
 * Reading aloud as the system sees it: a media session, so it can go on
 * with the screen off and be paused or stepped from the lock screen, a
 * headset's buttons, or a car.
 *
 * In a browser that is the Media Session API: the page's metadata and
 * action handlers are what the lock screen, the notification shade, a
 * Bluetooth headset's buttons and a car's steering-wheel controls drive,
 * and that is the extent of it. A web app cannot be an Android Auto or
 * CarPlay app: a browser cannot register as a media app with a car, so
 * there is no browsable tree of books and chapters on the car's screen,
 * and no "play Psalm 23" said to it. Media keys, headsets and a car's
 * buttons work through the Media Session: play, pause, next and
 * previous.
 *
 * A media session is only active while the page is playing audio. The
 * voice's own Web Audio output counts, but between pieces — while the
 * next sentence is being made, or while paused — nothing plays, and a
 * browser may then let the session lapse and drop the lock-screen
 * controls. So while reading is active a silent buffer loops through the
 * same AudioContext at near-zero gain, which keeps the context running
 * and the session with it. Whether a browser treats that loop as audible
 * enough to count is its own business; Chrome on Android has, and where
 * one does not, the controls simply come back with the next piece.
 */

/** What the lock screen offers. */
export enum MediaControl {
  skipToPrevious,
  play,
  pause,
  skipToNext,
  stop,
}

export enum AudioProcessingState {
  idle,
  ready,
}

/** A headset's buttons, as they arrive. */
export enum MediaButton {
  media,
  next,
  previous,
}

export interface PlaybackState {
  controls: MediaControl[];
  processingState: AudioProcessingState;
  playing: boolean;
}

/** What the system shows: one item per chapter, titled by the verse. */
export interface MediaItem {
  id: string;
  title: string;
  album: string;
  artist: string;
  artUri: string | null;
}

/** The little of `navigator.mediaSession` the handler uses; a test hands in its own. */
export interface MediaSessionLike {
  metadata: MediaMetadata | null;
  playbackState: MediaSessionPlaybackState;
  setActionHandler(action: MediaSessionAction, handler: MediaSessionActionHandler | null): void;
}

const actionFor: Record<MediaControl, MediaSessionAction> = {
  [MediaControl.skipToPrevious]: 'previoustrack',
  [MediaControl.play]: 'play',
  [MediaControl.pause]: 'pause',
  [MediaControl.skipToNext]: 'nexttrack',
  [MediaControl.stop]: 'stop',
};

/**
 * Keeps the audio context, and so the media session, alive between the
 * voice's pieces: a second of silence, looped, at a gain no one can hear.
 */
class KeepAlive {
  private _source: AudioBufferSourceNode | null = null;
  private _gain: GainNode | null = null;

  start(): void {
    if (this._source !== null || !hasWebAudio()) return;
    try {
      const context = speechAudioContext();
      const buffer = context.createBuffer(1, context.sampleRate, context.sampleRate);
      const source = context.createBufferSource();
      source.buffer = buffer;
      source.loop = true;
      const gain = context.createGain();
      gain.gain.value = 0.0001;
      source.connect(gain);
      gain.connect(context.destination);
      source.start();
      this._source = source;
      this._gain = gain;
    } catch {
      // Without it the controls come and go with the pieces.
    }
  }

  stop(): void {
    try {
      this._source?.stop();
      this._source?.disconnect();
      this._gain?.disconnect();
    } catch {
      // Already stopped.
    }
    this._source = null;
    this._gain = null;
  }
}

export class ReadAloudHandler {
  /**
   * Made when the app starts, before there is anything to read; a voice
   * is bound to it when reading aloud begins. [describe] names the
   * session while it plays: the translation, say.
   */
  constructor(
    voice: ReadAloud | null = null,
    describe: (() => string) | null = null,
    session: MediaSessionLike | null | undefined = undefined,
  ) {
    this._describe = describe ?? (() => '');
    this._session = session === undefined ? ReadAloudHandler.platformSession() : session;
    if (voice !== null) this.bind(voice, this._describe);
    this._publish();
  }

  private _voice: ReadAloud | null = null;
  private _describe: () => string;
  private readonly _session: MediaSessionLike | null;
  private readonly _keepAlive = new KeepAlive();
  private readonly _listener = () => this._publish();

  /** What the lock screen is shown and offers, as last published. */
  readonly playbackState = new ValueNotifier<PlaybackState>(ReadAloudHandler.stateFor(null));
  readonly mediaItem = new ValueNotifier<MediaItem | null>(null);

  /** Draws a chapter's cover for the lock screen, where there is one. */
  private _artwork: ((chapter: Reference) => Promise<string | null>) | null = null;
  private readonly _art = new Map<string, string | null>();
  private readonly _drawing = new Set<string>();

  get voice(): ReadAloud | null {
    return this._voice;
  }

  /** The browser's session, where it has one. */
  static platformSession(): MediaSessionLike | null {
    if (typeof navigator === 'undefined' || !('mediaSession' in navigator)) return null;
    return navigator.mediaSession as MediaSessionLike;
  }

  /**
   * Hands the session to a voice. The session lasts as long as the app,
   * and a reader screen built again brings a voice of its own.
   */
  bind(
    voice: ReadAloud,
    describe: () => string,
    options: { artwork?: (chapter: Reference) => Promise<string | null> } = {},
  ): void {
    this._describe = describe;
    if (options.artwork !== undefined) {
      this._artwork = options.artwork;
      // Drawn again in the colours of the theme now in use.
      this._art.clear();
    }
    if (voice === this._voice) return;
    this._voice?.removeListener(this._listener);
    this._voice = voice;
    voice.addListener(this._listener);
    this._publish();
  }

  /** What the lock screen shows and offers, from the state of the voice. */
  static stateFor(voice: ReadAloud | null): PlaybackState {
    if (voice === null) return { controls: [], processingState: AudioProcessingState.idle, playing: false };
    return {
      controls: voice.isActive
        ? [
            MediaControl.skipToPrevious,
            voice.isPlaying ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ]
        : [],
      processingState: voice.isActive ? AudioProcessingState.ready : AudioProcessingState.idle,
      playing: voice.isPlaying,
    };
  }

  /** "Genesis 1:3", or the chapter while its name is announced. */
  static itemFor(voice: ReadAloud, album: string, art: string | null = null): MediaItem | null {
    const current = voice.current;
    if (current === null) return null;
    const title = current.verse === null ? ReadAloud.announcement(current).replace(/\./g, '') : current.label;
    return {
      // One item per chapter, so the system does not treat every verse as
      // a new track and restart its display.
      id: `${current.bookCode}/${current.chapter}`,
      title,
      album,
      artist: 'OpenWord',
      artUri: art,
    };
  }

  private _publish(): void {
    const voice = this._voice;
    const state = ReadAloudHandler.stateFor(voice);
    this.playbackState.value = state;
    this._publishState(state);
    if (voice === null) return;
    const current = voice.current;
    const key = current === null ? null : `${current.bookCode}/${current.chapter}`;
    const artwork = this._artwork;
    if (key !== null && artwork !== null && !this._art.has(key) && !this._drawing.has(key)) {
      this._drawing.add(key);
      // Drawn once per chapter, off the voice's path; the item is sent
      // again with its picture when the picture is ready.
      artwork(current!.withVerse(null)).then(
        (uri) => {
          this._drawing.delete(key);
          this._art.set(key, uri);
          if (uri !== null) this._publish();
        },
        () => {
          this._drawing.delete(key);
          this._art.set(key, null);
        },
      );
    }
    const item = ReadAloudHandler.itemFor(voice, this._describe(), key === null ? null : (this._art.get(key) ?? null));
    if (item !== null) {
      this.mediaItem.value = item;
      this._publishItem(item);
    }
  }

  private _publishState(state: PlaybackState): void {
    if (state.processingState === AudioProcessingState.ready) this._keepAlive.start();
    else this._keepAlive.stop();
    const session = this._session;
    if (session === null) return;
    try {
      session.playbackState =
        state.processingState === AudioProcessingState.idle ? 'none' : state.playing ? 'playing' : 'paused';
      const offered = new Set(state.controls);
      for (const control of [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.pause,
        MediaControl.skipToNext,
        MediaControl.stop,
      ]) {
        session.setActionHandler(actionFor[control], offered.has(control) ? this._handlerFor(control) : null);
      }
      // A headset's rocker, and a car's, often send seeks rather than
      // tracks: a verse either way.
      const active = state.processingState === AudioProcessingState.ready;
      session.setActionHandler('seekbackward', active ? () => this.skipToPrevious() : null);
      session.setActionHandler('seekforward', active ? () => this.skipToNext() : null);
    } catch (error) {
      // An action the browser does not know throws; the rest still work.
      console.warn('OpenWord: media session refused an action', error);
    }
  }

  private _handlerFor(control: MediaControl): MediaSessionActionHandler {
    switch (control) {
      case MediaControl.skipToPrevious:
        return () => this.skipToPrevious();
      case MediaControl.play:
        return () => this.play();
      case MediaControl.pause:
        return () => this.pause();
      case MediaControl.skipToNext:
        return () => this.skipToNext();
      case MediaControl.stop:
        return () => this.stop();
    }
  }

  private _publishItem(item: MediaItem): void {
    const session = this._session;
    if (session === null || typeof MediaMetadata === 'undefined') return;
    try {
      session.metadata = new MediaMetadata({
        title: item.title,
        artist: item.album,
        album: item.artist,
        artwork: item.artUri === null ? [] : [{ src: item.artUri, sizes: '600x600', type: 'image/png' }],
      });
    } catch (error) {
      console.warn('OpenWord: media session refused the item', error);
    }
  }

  async play(): Promise<void> {
    if (this.voice?.state === ReadAloudState.paused) this.voice.resume();
  }

  async pause(): Promise<void> {
    this.voice?.pause();
  }

  async stop(): Promise<void> {
    this.voice?.stop();
  }

  async skipToNext(): Promise<void> {
    this.voice?.skip(1);
  }

  async skipToPrevious(): Promise<void> {
    this.voice?.skip(-1);
  }

  /**
   * A headset's single button, or a tap on the notification's own play
   * button, arrives here.
   */
  async click(button: MediaButton = MediaButton.media): Promise<void> {
    const voice = this._voice;
    if (voice === null) return;
    switch (button) {
      case MediaButton.next:
        voice.skip(1);
        break;
      case MediaButton.previous:
        voice.skip(-1);
        break;
      case MediaButton.media:
        if (voice.isPlaying) voice.pause();
        else voice.resume();
        break;
    }
  }

  /** Lets go of a voice that is going away. */
  release(voice: ReadAloud): void {
    if (voice !== this._voice) return;
    voice.removeListener(this._listener);
    this._voice = null;
    this._publish();
  }
}

/** Whether this platform has a media session to hand reading aloud to. */
export function mediaSessionSupported(): boolean {
  return ReadAloudHandler.platformSession() !== null;
}

let _starting: Promise<ReadAloudHandler | null> | null = null;

/** Why the media session could not be started, when it could not. */
export let readAloudSessionError: string | null = null;

export function setReadAloudSessionError(error: string | null): void {
  readAloudSessionError = error;
}

/**
 * Starts the system's media session, once per run of the app. Called as
 * the app starts, and not awaited: the first frame does not wait on it.
 *
 * Never throws. If the session cannot be had, [readAloudSessionError]
 * says why, and reading aloud goes on with the app open.
 */
export function prepareReadAloudSession(): Promise<ReadAloudHandler | null> {
  return (_starting ??= startPlatformSession());
}

export type StartReadAloudSession = (
  voice: ReadAloud,
  describe: () => string,
  options?: { artwork?: (chapter: Reference) => Promise<string | null> },
) => Promise<ReadAloudHandler | null>;

/**
 * Binds [voice] to the system's media session, starting it if it was not
 * already. A seam, so a test runs without a platform.
 */
export let startReadAloudSession: StartReadAloudSession = async (voice, describe, options = {}) => {
  const session = await prepareReadAloudSession();
  session?.bind(voice, describe, options);
  return session;
};

export function setStartReadAloudSession(start: StartReadAloudSession): void {
  startReadAloudSession = start;
}

async function startPlatformSession(): Promise<ReadAloudHandler | null> {
  if (!mediaSessionSupported()) return null;
  try {
    return new ReadAloudHandler();
  } catch (error) {
    readAloudSessionError = `${error}`;
    console.warn(`OpenWord: no media session for reading aloud: ${error}`);
    return null;
  }
}
