import { createContext, type ComponentChildren, type VNode } from 'preact';
import { useContext, useEffect, useRef, useState } from 'preact/hooks';
import { ChangeNotifier, useNotifier } from '../../infra/changeNotifier';
import { IconButton, TextButton } from './buttons';

/**
 * Flutter's Navigator, bottom sheets, dialogs, menus and snackbars, as one
 * stack of overlays over the root screen.
 *
 * Every pushed thing — a screen, a sheet, a dialog, a menu — is one entry
 * in a stack and one entry in the browser's history, so the Android back
 * button and the browser's back arrow close the top one, which is what a
 * reader expects of an installed app. `push` answers a promise that
 * settles with whatever `pop(result)` is given, so a sheet can be awaited
 * the way `showModalBottomSheet` is.
 */
export type OverlayKind = 'screen' | 'sheet' | 'dialog' | 'menu';

export interface OverlayOptions {
  /** Tapping the scrim or pressing Escape closes it. Default true. */
  dismissible?: boolean;
  /** A sheet that fills the height, as `isScrollControlled` + full height. */
  full?: boolean;
  /** Where a menu is anchored: the element it drops from. */
  anchor?: HTMLElement | { x: number; y: number };
  /** Extra class for the container. */
  class?: string;
  /** A name for the history entry, for debugging. */
  name?: string;
}

interface Entry {
  id: number;
  kind: OverlayKind;
  node: VNode;
  options: OverlayOptions;
  resolve: (value: unknown) => void;
  exiting: boolean;
  settled: boolean;
}

export interface OverlayHandle {
  /** Closes this overlay, settling its promise with `result`. */
  close(result?: unknown): void;
  id: number;
  kind: OverlayKind;
}

const OverlayContext = createContext<OverlayHandle | null>(null);

/** The handle of the overlay the calling component is in, to close it. */
export function useOverlay(): OverlayHandle {
  const handle = useContext(OverlayContext);
  if (!handle) {
    return { close: () => nav.pop(), id: 0, kind: 'screen' };
  }
  return handle;
}

class OverlayStack extends ChangeNotifier {
  entries: Entry[] = [];
  private nextId = 1;
  private exitTimers = new Map<number, ReturnType<typeof setTimeout>>();
  private historyReady = false;

  /** Hooks into the browser's history. Called once by the host. */
  attachHistory(): void {
    if (this.historyReady || typeof history === 'undefined') return;
    this.historyReady = true;
    history.replaceState({ owDepth: 0 }, '');
    addEventListener('popstate', (event) => {
      const e = event as PopStateEvent;
      const depth = typeof e.state?.owDepth === 'number' ? e.state.owDepth : 0;
      // The browser went back (or forward past where we were): bring the
      // stack to the depth history says, without touching history again.
      while (this.live.length > depth) this.settle(this.live[this.live.length - 1], undefined);
      if (depth > this.live.length) {
        // Forward into an entry we no longer have: step back out of it.
        history.go(this.live.length - depth);
      }
    });
    addEventListener('keydown', (event) => {
      const e = event as KeyboardEvent;
      if (e.key !== 'Escape') return;
      const top = this.top;
      if (top && top.options.dismissible !== false) {
        e.preventDefault();
        this.pop();
      }
    });
  }

  get live(): Entry[] {
    return this.entries.filter((e) => !e.exiting);
  }

  get top(): Entry | undefined {
    const live = this.live;
    return live[live.length - 1];
  }

  push<T>(kind: OverlayKind, node: VNode, options: OverlayOptions = {}): Promise<T | undefined> {
    return new Promise<T | undefined>((resolve) => {
      const entry: Entry = {
        id: this.nextId++,
        kind,
        node,
        options,
        resolve: resolve as (v: unknown) => void,
        exiting: false,
        settled: false,
      };
      this.entries.push(entry);
      if (this.historyReady) history.pushState({ owDepth: this.live.length }, '');
      this.notifyListeners();
    });
  }

  /** Closes the top overlay with `result`. */
  pop(result?: unknown): void {
    const top = this.top;
    if (!top) return;
    this.close(top.id, result);
  }

  /** Closes a specific overlay — and everything above it. */
  close(id: number, result?: unknown): void {
    const index = this.live.findIndex((e) => e.id === id);
    if (index < 0) return;
    const live = this.live;
    const removing = live.length - index;
    for (let i = live.length - 1; i >= index; i--) this.settle(live[i], i === index ? result : undefined);
    if (this.historyReady && typeof history.state?.owDepth === 'number' && history.state.owDepth === live.length) {
      // History is in step with the stack: step it back to match. If it is
      // not, the popstate that got us here already did.
      history.go(-removing);
    }
  }

  /** Whether anything but the root screen is showing. */
  get isEmpty(): boolean {
    return this.live.length === 0;
  }

  /** Pops until only screens remain: closes every sheet, dialog and menu. */
  dismissTransient(): void {
    const transient = this.live.filter((e) => e.kind !== 'screen');
    if (transient.length === 0) return;
    this.close(transient[0].id);
  }

  private settle(entry: Entry, result: unknown): void {
    if (entry.settled) return;
    entry.settled = true;
    entry.exiting = true;
    entry.resolve(result);
    this.notifyListeners();
    this.exitTimers.set(
      entry.id,
      setTimeout(() => {
        this.entries = this.entries.filter((e) => e !== entry);
        this.exitTimers.delete(entry.id);
        this.notifyListeners();
      }, entry.kind === 'screen' ? 200 : 220),
    );
  }
}

export const overlays = new OverlayStack();

/** Flutter's `Navigator.of(context)`, app-wide. */
export const nav = {
  /** Pushes a full screen; settles when it is popped. */
  push<T = void>(screen: VNode, options: OverlayOptions = {}): Promise<T | undefined> {
    return overlays.push<T>('screen', screen, { dismissible: false, ...options });
  },
  pop(result?: unknown): void {
    overlays.pop(result);
  },
  /** Whether a screen or overlay is above the root. */
  get canPop(): boolean {
    return !overlays.isEmpty;
  },
};

export function showSheet<T = void>(sheet: VNode, options: OverlayOptions = {}): Promise<T | undefined> {
  return overlays.push<T>('sheet', sheet, options);
}

export function showDialog<T = void>(dialog: VNode, options: OverlayOptions = {}): Promise<T | undefined> {
  return overlays.push<T>('dialog', dialog, options);
}

export function showMenu<T = void>(menu: VNode, anchor: HTMLElement | { x: number; y: number }, options: OverlayOptions = {}): Promise<T | undefined> {
  return overlays.push<T>('menu', menu, { anchor, ...options });
}

// ------------------------------------------------------------- snackbars

export interface SnackBarOptions {
  action?: { label: string; onPressed: () => void };
  /** Milliseconds. Default 4000; 0 keeps it until dismissed. */
  duration?: number;
  showClose?: boolean;
}

interface Snack extends SnackBarOptions {
  id: number;
  message: string;
  exiting: boolean;
}

class SnackBarQueue extends ChangeNotifier {
  current: Snack | null = null;
  private queue: Snack[] = [];
  private nextId = 1;
  private timer: ReturnType<typeof setTimeout> | null = null;

  show(message: string, options: SnackBarOptions = {}): void {
    const snack: Snack = { id: this.nextId++, message, exiting: false, ...options };
    if (this.current && !this.current.exiting) {
      this.queue.push(snack);
      this.hide();
      return;
    }
    this.present(snack);
  }

  hide(): void {
    if (!this.current || this.current.exiting) return;
    if (this.timer) clearTimeout(this.timer);
    this.current.exiting = true;
    this.notifyListeners();
    this.timer = setTimeout(() => {
      this.current = null;
      this.notifyListeners();
      const next = this.queue.shift();
      if (next) this.present(next);
    }, 160);
  }

  clear(): void {
    this.queue = [];
    this.hide();
  }

  private present(snack: Snack): void {
    this.current = snack;
    this.notifyListeners();
    const duration = snack.duration ?? 4000;
    if (duration > 0) this.timer = setTimeout(() => this.hide(), duration);
  }
}

export const snackBars = new SnackBarQueue();

/** Flutter's `ScaffoldMessenger.showSnackBar`. */
export function showSnackBar(message: string, options?: SnackBarOptions): void {
  snackBars.show(message, options);
}

// ----------------------------------------------------------------- host

/**
 * Renders the overlay stack and the snackbar. Mounted once, by the app,
 * above the root screen.
 */
export function OverlayHost() {
  useNotifier(overlays, snackBars);
  useEffect(() => overlays.attachHistory(), []);
  const entries = overlays.entries;
  const live = overlays.live;
  const topScreen = [...live].reverse().find((e) => e.kind === 'screen');
  const topId = live[live.length - 1]?.id;
  // Entries under the top screen are hidden so the page underneath is not
  // painted; hidden rather than unmounted, so their scroll and state keep.
  return (
    <>
      <div class="m3-overlay-root">
        {entries.map((entry) => {
          const handle: OverlayHandle = { id: entry.id, kind: entry.kind, close: (r) => overlays.close(entry.id, r) };
          const covered =
            entry.kind === 'screen' ? topScreen !== undefined && topScreen.id !== entry.id && !entry.exiting : false;
          const belowTopScreen = topScreen !== undefined && entry.id < topScreen.id && entry.kind !== 'screen';
          const hidden = covered || belowTopScreen;
          return (
            <OverlayContext.Provider value={handle} key={entry.id}>
              <OverlayFrame entry={entry} hidden={hidden} isTop={entry.id === topId} />
            </OverlayContext.Provider>
          );
        })}
      </div>
      <SnackBarHost />
    </>
  );
}

function OverlayFrame({ entry, hidden, isTop }: { entry: Entry; hidden: boolean; isTop: boolean }) {
  const { kind, options, exiting } = entry;
  const ref = useRef<HTMLDivElement>(null);
  // Focus goes into a new dialog or sheet, and the page under it is inert.
  useEffect(() => {
    if (kind === 'screen' || exiting) return;
    const first = ref.current?.querySelector<HTMLElement>('input, textarea, [autofocus], button');
    if (first && (first as HTMLInputElement).autofocus) first.focus();
  }, [kind, exiting]);
  const hiddenStyle = hidden ? 'visibility:hidden' : undefined;
  const inertAttr = hidden || !isTop ? { inert: true } : {};
  const dismiss = () => {
    if (options.dismissible !== false) overlays.close(entry.id);
  };
  if (kind === 'screen') {
    return (
      <div
        class={`m3-screen m3-overlay-screen${exiting ? ' m3-screen--exit' : ' m3-screen--enter'}${options.class ? ` ${options.class}` : ''}`}
        style={hiddenStyle}
        {...inertAttr}
        ref={ref}
      >
        {entry.node}
      </div>
    );
  }
  if (kind === 'menu') {
    return (
      <div style={hiddenStyle} {...inertAttr} ref={ref}>
        <div class="m3-scrim" style="background:transparent" onClick={dismiss} />
        <MenuPositioner anchor={options.anchor} exiting={exiting} cls={options.class}>
          {entry.node}
        </MenuPositioner>
      </div>
    );
  }
  if (kind === 'dialog') {
    return (
      <div style={hiddenStyle} {...inertAttr} ref={ref}>
        <div class={`m3-scrim${exiting ? ' m3-scrim--exit' : ''}`} onClick={dismiss} />
        <div class={`m3-dialog${exiting ? ' m3-dialog--exit' : ''}${options.class ? ` ${options.class}` : ''}`} role="dialog" aria-modal="true">
          {entry.node}
        </div>
      </div>
    );
  }
  return (
    <div style={hiddenStyle} {...inertAttr} ref={ref}>
      <div class={`m3-scrim${exiting ? ' m3-scrim--exit' : ''}`} onClick={dismiss} />
      <div class={`m3-sheet${options.full ? ' m3-sheet--full' : ''}${exiting ? ' m3-sheet--exit' : ''}${options.class ? ` ${options.class}` : ''}`} role="dialog" aria-modal="true">
        {entry.node}
      </div>
    </div>
  );
}

function MenuPositioner({ anchor, exiting, cls, children }: { anchor?: HTMLElement | { x: number; y: number }; exiting: boolean; cls?: string; children: ComponentChildren }) {
  const ref = useRef<HTMLDivElement>(null);
  const [style, setStyle] = useState('visibility:hidden');
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const host = el.offsetParent as HTMLElement | null;
    const hostRect = host?.getBoundingClientRect() ?? { left: 0, top: 0, width: innerWidth, height: innerHeight };
    let x: number;
    let y: number;
    let right: number | null = null;
    if (anchor instanceof HTMLElement) {
      const r = anchor.getBoundingClientRect();
      x = r.left - hostRect.left;
      y = r.bottom - hostRect.top;
      // A menu from a button at the right edge opens leftwards.
      if (r.left + el.offsetWidth > hostRect.left + hostRect.width - 8) {
        right = hostRect.width - (r.right - hostRect.left);
      }
    } else if (anchor) {
      x = anchor.x - hostRect.left;
      y = anchor.y - hostRect.top;
    } else {
      x = 16;
      y = 16;
    }
    const maxY = hostRect.height - el.offsetHeight - 8;
    if (y > maxY) y = Math.max(8, maxY);
    const maxX = hostRect.width - el.offsetWidth - 8;
    if (right === null && x > maxX) x = Math.max(8, maxX);
    setStyle(right === null ? `left:${x}px;top:${y}px` : `right:${right}px;top:${y}px`);
  }, [anchor]);
  return (
    <div ref={ref} class={`m3-menu${exiting ? ' m3-menu--exit' : ''}${cls ? ` ${cls}` : ''}`} style={style} role="menu">
      {children}
    </div>
  );
}

function SnackBarHost() {
  const snack = snackBars.current;
  if (!snack) return null;
  return (
    <div class="m3-snackbar-host">
      <div class={`m3-snackbar${snack.exiting ? ' m3-snackbar--exit' : ''}`} role="status">
        <span class="m3-snackbar__text">{snack.message}</span>
        {snack.action && (
          <TextButton
            onClick={() => {
              snack.action!.onPressed();
              snackBars.hide();
            }}
          >
            {snack.action.label}
          </TextButton>
        )}
        {snack.showClose && <IconButton icon="close" label="Dismiss" onClick={() => snackBars.hide()} />}
      </div>
    </div>
  );
}
