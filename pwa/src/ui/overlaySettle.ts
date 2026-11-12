import type { VNode } from 'preact';
import { nav, overlays, showDialog, showSheet, type OverlayOptions } from './m3';

/**
 * Opening one thing as another closes.
 *
 * The overlay stack keeps the browser's history in step with itself: a
 * sheet closed from a button steps history back, and that step lands a
 * moment later, as a `popstate`. Something opened in that moment — the
 * cross-references from the verse sheet's own button, the concordance from
 * a Strong's entry — pushes its history entry before the step back has
 * landed, the step then lands on the wrong entry, and the stack, told it
 * is back at the bottom, closes what was just opened.
 *
 * Closing one thing and opening another in the same breath is something
 * the reader does everywhere. So what the reader opens, it opens
 * through these: they wait for a step back that is still on its way, and
 * are otherwise the kit's own `showSheet`, `showDialog` and `nav.push`.
 */

/** Whether the stack has closed something whose step back in history has yet to land. */
function stepBackPending(): boolean {
  if (typeof history === 'undefined') return false;
  const depth: unknown = history.state?.owDepth;
  return typeof depth === 'number' && depth > overlays.live.length;
}

/** Resolves once history has caught up with the overlays that have closed. */
export function historySettled(): Promise<void> {
  if (!stepBackPending()) return Promise.resolve();
  return new Promise<void>((resolve) => {
    const finish = () => {
      clearTimeout(timer);
      removeEventListener('popstate', onPop);
      resolve();
    };
    // The stack's own listener was added first, so by now it has seen this
    // step — and may have asked for another.
    const onPop = () => {
      if (!stepBackPending()) finish();
    };
    // A step that never lands must not leave the reader waiting on it.
    const timer = setTimeout(finish, 600);
    addEventListener('popstate', onPop);
  });
}

export async function openSheet<T = void>(sheet: VNode, options: OverlayOptions = {}): Promise<T | undefined> {
  await historySettled();
  return showSheet<T>(sheet, options);
}

export async function openDialog<T = void>(dialog: VNode, options: OverlayOptions = {}): Promise<T | undefined> {
  await historySettled();
  return showDialog<T>(dialog, options);
}

export async function openScreen<T = void>(screen: VNode, options: OverlayOptions = {}): Promise<T | undefined> {
  await historySettled();
  return nav.push<T>(screen, options);
}
