/**
 * The one AudioContext reading aloud plays through — the voice's pieces,
 * and the media session's keep-alive — shared so that pausing the voice
 * (suspending the context) and keeping the session alive agree.
 *
 * A browser will not let a page make a sound until the person has touched
 * it: an AudioContext made before that starts suspended, and on iOS stays
 * so unless it is resumed inside a gesture. Listen is a tap, but the voice
 * speaks only after its model has loaded, long after the tap is over. So
 * the context is made, or woken, on the first gesture anywhere on the
 * page, and from then on it may be resumed whenever the app likes.
 */

type AudioContextCtor = typeof AudioContext;

function audioContextCtor(): AudioContextCtor | null {
  if (typeof AudioContext !== 'undefined') return AudioContext;
  const legacy = (globalThis as { webkitAudioContext?: AudioContextCtor }).webkitAudioContext;
  return legacy ?? null;
}

/** Whether this browser has Web Audio at all. */
export function hasWebAudio(): boolean {
  return audioContextCtor() !== null;
}

let context: AudioContext | null = null;

/** The shared context, made the first time it is wanted. */
export function speechAudioContext(): AudioContext {
  if (context === null) {
    const Ctor = audioContextCtor();
    if (Ctor === null) throw new Error('this browser has no Web Audio');
    context = new Ctor();
  }
  return context;
}

/**
 * Wakes the context, inside a gesture where possible. Safe to call at any
 * time; never throws.
 */
export function unlockAudio(): void {
  try {
    const ctx = speechAudioContext();
    if (ctx.state !== 'running') void ctx.resume().catch(() => {});
  } catch {
    // No Web Audio here; nothing to wake.
  }
}

/** `navigator.audioSession`, where a browser has it: Safari, since 16.4. */
interface AudioSessionLike {
  type: string;
}

/**
 * Tells the system that what is playing is someone being read to, while
 * it is.
 *
 * On an iPhone a page's Web Audio is by default "ambient": the ring
 * switch silences it, and it stops when the screen locks. A chapter read
 * aloud is the other kind of sound — wanted with the phone on silent, in
 * a pocket — and Safari lets a page say so. Only while reading, though:
 * said for good, the first tap anywhere would stop the music someone
 * had on while they read.
 */
export function speechPlayback(on: boolean): void {
  try {
    const session = (navigator as Navigator & { audioSession?: AudioSessionLike }).audioSession;
    if (session === undefined) return;
    const wanted = on ? 'playback' : 'auto';
    if (session.type !== wanted) session.type = wanted;
  } catch {
    // Not a browser that has it, or not one that lets it be set.
  }
}

/**
 * A phone call, an alarm, or Siri takes the sound away and leaves the
 * context "interrupted" (Safari's word) or suspended; it does not always
 * give it back. Coming back to the page does.
 */
function wakeIfInterrupted(): void {
  if (context === null || document.visibilityState !== 'visible') return;
  if ((context.state as string) === 'interrupted') void context.resume().catch(() => {});
}

const gestures = ['pointerdown', 'touchend', 'keydown'] as const;

function onGesture(): void {
  unlockAudio();
  if (context?.state === 'running') {
    for (const type of gestures) document.removeEventListener(type, onGesture, true);
  }
}

if (typeof document !== 'undefined' && hasWebAudio()) {
  for (const type of gestures) document.addEventListener(type, onGesture, { capture: true, passive: true });
  document.addEventListener('visibilitychange', wakeIfInterrupted);
}
