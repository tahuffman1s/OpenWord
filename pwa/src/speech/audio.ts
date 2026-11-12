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

const gestures = ['pointerdown', 'touchend', 'keydown'] as const;

function onGesture(): void {
  unlockAudio();
  if (context?.state === 'running') {
    for (const type of gestures) document.removeEventListener(type, onGesture, true);
  }
}

if (typeof document !== 'undefined' && hasWebAudio()) {
  for (const type of gestures) document.addEventListener(type, onGesture, { capture: true, passive: true });
}
