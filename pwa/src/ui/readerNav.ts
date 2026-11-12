import { openFromTutorial } from '../app/openFlow';
import type { Reference } from '../model/bible';
import { overlays } from './m3/overlay';
import type { PlanReading } from './plansScreen';

/**
 * How the screens stacked over the reader send it somewhere.
 *
 * In the Flutter app every screen pops with a `Reference` and the reader,
 * which pushed it, goes there. The screens here still close with that
 * result, so a reader that awaits `nav.push` is answered as before. But a
 * reader can also register one function, and then any screen — the
 * library, a round of questions, a practice session, a friend's feed —
 * can send it somewhere outright: `openReference` closes whatever is above
 * the reader and hands it the place. A plan's chapter goes the same way
 * with the plan day it was opened from, so the reader can offer to tick
 * it off at the end (`_planFocus` in the Dart).
 */
export type ReaderGoTo = (reference: Reference, plan?: PlanReading) => void;

let readerGoTo: ReaderGoTo | null = null;

/** Called by the reader once it is on screen. Returns how to unregister. */
export function registerReaderGoTo(goTo: ReaderGoTo): () => void {
  readerGoTo = goTo;
  return () => {
    if (readerGoTo === goTo) readerGoTo = null;
  };
}

/** Whether a reader has registered to be sent places. */
export function hasReader(): boolean {
  return readerGoTo !== null;
}

/** Closes every screen, sheet and dialog above the reader. */
function backToReader(): void {
  const bottom = overlays.live[0];
  if (bottom !== undefined) overlays.close(bottom.id);
}

/**
 * Shows `reference` in the reader, closing whatever is over it. Until a
 * reader has registered there is nowhere to go; the navigator is asked for
 * instead, which the reader opens once it is on screen.
 */
export function openReference(reference: Reference): void {
  backToReader();
  if (readerGoTo !== null) readerGoTo(reference);
  else openFromTutorial('navigator');
}

/**
 * As `openReference`, where a reader has registered; where none has,
 * nothing is done and false is answered, for a screen that closes with the
 * reference instead and leaves it to whoever pushed it.
 */
export function openInReader(reference: Reference): boolean {
  if (readerGoTo === null) return false;
  backToReader();
  readerGoTo(reference);
  return true;
}

/**
 * Opens a plan's chapter in the reader, which is told the plan day it
 * came from. The reader decides whether the translation has the chapter.
 */
export function openPlanReading(reading: PlanReading): void {
  backToReader();
  if (readerGoTo !== null) readerGoTo(reading.chapter, reading);
  else openFromTutorial('navigator');
}

/** As `openPlanReading`, where a reader has registered; false where none has. */
export function openPlanInReader(reading: PlanReading): boolean {
  if (readerGoTo === null) return false;
  backToReader();
  readerGoTo(reading.chapter, reading);
  return true;
}
