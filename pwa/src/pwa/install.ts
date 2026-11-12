import { ChangeNotifier, type Listener } from '../infra/changeNotifier';

/**
 * The browser's "install this app" prompt, caught and kept.
 *
 * Chromium fires `beforeinstallprompt` once, early, and only if nothing has
 * called `preventDefault` on it is the browser's own mini-infobar shown.
 * We catch it as soon as the page runs (`captureInstallPrompt()` from
 * `main`, before the first render), keep the event, and let the install
 * guide fire it from a button of our own. Safari and Firefox never fire
 * it; there the guide explains the menu steps instead.
 */
export type InstallOutcome = 'accepted' | 'dismissed' | 'unavailable';

/** The event Chromium fires; not in lib.dom yet. */
export interface BeforeInstallPromptEvent extends Event {
  readonly platforms: string[];
  readonly userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
  prompt(): Promise<void>;
}

/** Whether the page is running as an installed app rather than in a tab. */
export function isStandalone(): boolean {
  if (typeof window === 'undefined') return false;
  try {
    if (matchMedia('(display-mode: standalone)').matches) return true;
    if (matchMedia('(display-mode: window-controls-overlay)').matches) return true;
    if (matchMedia('(display-mode: fullscreen)').matches) return true;
    if (matchMedia('(display-mode: minimal-ui)').matches) return true;
  } catch {
    // matchMedia missing: not a browser we know.
  }
  // iOS Safari's own flag for a home-screen web app.
  const nav = navigator as Navigator & { standalone?: boolean };
  if (nav.standalone === true) return true;
  // Android's TWA / "Add to Home screen" from some browsers.
  return typeof document !== 'undefined' && document.referrer.startsWith('android-app://');
}

export class InstallPrompt extends ChangeNotifier {
  private event: BeforeInstallPromptEvent | null = null;
  private _installed = false;
  private captured = false;

  // `useNotifier` subscribes in an effect, after the component's first
  // render. Anything that changed in between — and here things change
  // within milliseconds of the page loading — would never reach it, so a
  // listener added after the first change is called once to catch up.
  private changes = 0;
  private readonly lateListeners = new Set<Listener>();

  override notifyListeners(): void {
    this.changes++;
    super.notifyListeners();
  }

  override addListener(listener: Listener): void {
    super.addListener(listener);
    if (this.changes === 0) return;
    this.lateListeners.add(listener);
    queueMicrotask(() => {
      if (this.lateListeners.delete(listener)) listener();
    });
  }

  override removeListener(listener: Listener): void {
    this.lateListeners.delete(listener);
    super.removeListener(listener);
  }

  /** Whether the browser has offered an install prompt we can fire. */
  get available(): boolean {
    return this.event !== null && !this._installed;
  }

  /** Whether the app is installed: it told us, or we are running as it. */
  get installed(): boolean {
    return this._installed || isStandalone();
  }

  /** Starts listening. Safe to call more than once; only the first counts. */
  capture(): void {
    if (this.captured || typeof window === 'undefined') return;
    this.captured = true;
    window.addEventListener('beforeinstallprompt', (e) => {
      e.preventDefault();
      this.event = e as BeforeInstallPromptEvent;
      this.notifyListeners();
    });
    window.addEventListener('appinstalled', () => {
      this._installed = true;
      this.event = null;
      this.notifyListeners();
    });
    try {
      const media = matchMedia('(display-mode: standalone)');
      media.addEventListener('change', () => this.notifyListeners());
    } catch {
      // No matchMedia: nothing to watch.
    }
    if (isStandalone()) this._installed = true;
  }

  /**
   * Shows the browser's install dialog and answers with what the reader
   * chose. The caught event can be used once; after a dismissal Chromium
   * fires `beforeinstallprompt` again later, and we catch that too.
   */
  async prompt(): Promise<InstallOutcome> {
    const event = this.event;
    if (!event) return 'unavailable';
    this.event = null;
    this.notifyListeners();
    try {
      await event.prompt();
      const choice = await event.userChoice;
      if (choice.outcome === 'accepted') {
        this._installed = true;
        this.notifyListeners();
        return 'accepted';
      }
      return 'dismissed';
    } catch (error) {
      console.warn('OpenWord: install prompt failed', error);
      return 'unavailable';
    }
  }
}

/** The one prompt, app-wide. */
export const installPrompt = new InstallPrompt();

/**
 * Call from `main` before the first render, so the event is not missed:
 * the browser fires it as soon as the manifest checks out, which can be
 * before the app's modules have all loaded.
 */
export function captureInstallPrompt(): InstallPrompt {
  installPrompt.capture();
  return installPrompt;
}
