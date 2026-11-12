import { Workbox } from 'workbox-window';
import { ChangeNotifier, useNotifier, type Listener } from '../infra/changeNotifier';

/**
 * Registers the service worker (`src/sw.ts`, built to `/sw.js`) and tells
 * the app when a newer build is waiting, so it can offer "Reload" rather
 * than swapping the page out from under the reader.
 *
 * The worker is built with `skipWaiting` off: a new build installs, then
 * waits until `applyUpdate()` posts SKIP_WAITING, and the page reloads
 * once the new worker is in control, so every open tab moves to the new
 * version together instead of one tab running new code against another's
 * old caches.
 */
export interface VersionInfo {
  /** The package version, as `version.json` records it. */
  version: string;
  /** ISO timestamp of the build. */
  builtAt: string;
  /** The short commit hash the build was made from, when known. */
  commit?: string;
}

/** How often to ask the server whether there is a newer worker. */
const checkEvery = 60 * 60 * 1000;
/** A check on return to the tab, if the last was at least this long ago. */
const checkOnReturnAfter = 15 * 60 * 1000;

export class AppUpdates extends ChangeNotifier {
  private wb: Workbox | null = null;
  private registration: ServiceWorkerRegistration | null = null;
  private _updateAvailable = false;
  private _offlineReady = false;
  private _firstInstall = false;
  private _version: VersionInfo | null = null;
  private _supported = false;
  private _checking = false;
  private reloading = false;
  private reloaded = false;
  private lastCheck = 0;
  private registered = false;

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

  /** A newer build is installed and waiting; `applyUpdate()` switches to it. */
  get updateAvailable(): boolean {
    return this._updateAvailable;
  }

  /** A worker with the precache is in place: the app opens without a network. */
  get offlineReady(): boolean {
    return this._offlineReady;
  }

  /**
   * True only in the session in which the very first worker installed —
   * for saying "Ready to work offline" once, not on every launch.
   */
  get firstInstall(): boolean {
    return this._firstInstall;
  }

  /** The running build's version, once `version.json` has been read. */
  get version(): VersionInfo | null {
    return this._version;
  }

  /** Whether this browser has service workers and the worker could be registered. */
  get supported(): boolean {
    return this._supported;
  }

  /** Whether `checkNow()` is in flight. */
  get checking(): boolean {
    return this._checking;
  }

  /** The registration, for push subscriptions and local notifications. */
  getRegistration(): ServiceWorkerRegistration | null {
    return this.registration;
  }

  /** Waits for the registration; null where there is none (dev, or unsupported). */
  async whenRegistered(): Promise<ServiceWorkerRegistration | null> {
    if (this.registration) return this.registration;
    if (!this._supported || typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return null;
    try {
      return await navigator.serviceWorker.ready;
    } catch {
      return null;
    }
  }

  /** Registers once. */
  register(): void {
    if (this.registered) return;
    this.registered = true;
    void this.loadVersion();
    if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;
    void this.registerWorker();
  }

  private async registerWorker(): Promise<void> {
    // In dev the plugin does not emit /sw.js unless `devOptions.enabled`;
    // the dev server answers index.html for it, which cannot be a worker.
    if (import.meta.env.DEV && !(await swIsServed())) {
      console.warn('OpenWord: no /sw.js in dev; the service worker is not registered');
      return;
    }
    const wb = new Workbox('/sw.js', { scope: '/', type: 'classic' });
    this.wb = wb;
    wb.addEventListener('installed', (event) => {
      if (!event.isUpdate) {
        this._offlineReady = true;
        this._firstInstall = true;
        this.notifyListeners();
      }
    });
    wb.addEventListener('waiting', () => {
      this._updateAvailable = true;
      this.notifyListeners();
    });
    wb.addEventListener('controlling', (event) => {
      // A new worker took over: reload so the page runs its build. Only
      // after an update, not on the very first install, which controls
      // the page it was registered from without reloading it.
      if (!event.isUpdate && !this.reloading) return;
      this.reloadOnce();
    });
    wb.addEventListener('activated', (event) => {
      if (!event.isUpdate) {
        this._offlineReady = true;
        this.notifyListeners();
      }
    });
    try {
      const registration = await wb.register();
      this.registration = registration ?? null;
      this._supported = registration !== undefined;
      this.lastCheck = Date.now();
      // A worker from an earlier visit is already serving the precache.
      if (registration?.active && navigator.serviceWorker.controller) this._offlineReady = true;
      // A worker that was already waiting before this page loaded.
      if (registration?.waiting && navigator.serviceWorker.controller) {
        this._updateAvailable = true;
      }
      this.notifyListeners();
      this.schedule();
    } catch (error) {
      console.warn('OpenWord: service worker registration failed', error);
      this._supported = false;
      this.notifyListeners();
    }
  }

  private schedule(): void {
    setInterval(() => void this.checkNow(), checkEvery);
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible' && Date.now() - this.lastCheck > checkOnReturnAfter) {
        void this.checkNow();
      }
    });
  }

  /** Asks the server for a newer worker now. */
  async checkNow(): Promise<void> {
    if (!this.registration || this._checking) return;
    this._checking = true;
    this.lastCheck = Date.now();
    this.notifyListeners();
    try {
      await this.registration.update();
    } catch (error) {
      console.warn('OpenWord: update check failed', error);
    } finally {
      this._checking = false;
      this.notifyListeners();
    }
  }

  /**
   * Switches to the waiting build: tells it to skip waiting, and reloads
   * when it takes control. Does nothing when no build is waiting.
   */
  applyUpdate(): void {
    if (!this.wb || !this._updateAvailable) return;
    this.reloading = true;
    // If the controlling event does not come (a worker that was already
    // waiting when the page loaded, in some browsers), reload anyway.
    setTimeout(() => this.reloadOnce(), 3000);
    this.wb.messageSkipWaiting();
  }

  private reloadOnce(): void {
    if (this.reloaded) return;
    this.reloaded = true;
    location.reload();
  }

  private async loadVersion(): Promise<void> {
    if (typeof fetch !== 'function') return;
    try {
      // Through the worker's precache when there is one, so this is the
      // version of the build actually running, not the server's newest.
      const response = await fetch('/version.json');
      if (!response.ok) return;
      const data = (await response.json()) as Partial<VersionInfo>;
      if (typeof data.version === 'string') {
        this._version = { version: data.version, builtAt: data.builtAt ?? '', commit: data.commit };
        this.notifyListeners();
      }
    } catch {
      // Not there: the build did not write it, or we are offline before the
      // first install. Nothing to show.
    }
  }
}

async function swIsServed(): Promise<boolean> {
  try {
    const response = await fetch('/sw.js', { method: 'HEAD', cache: 'no-store' });
    const type = response.headers.get('content-type') ?? '';
    return response.ok && /javascript/.test(type);
  } catch {
    return false;
  }
}

/** The one updates notifier, app-wide. */
export const appUpdates = new AppUpdates();

/**
 * Registers the worker and answers the notifier the app watches. Call once
 * from `main`, after the first render so the page is interactive first.
 */
export function registerServiceWorker(): AppUpdates {
  appUpdates.register();
  return appUpdates;
}

/** The updates notifier, re-rendering the caller when it changes. */
export function useAppUpdates(): AppUpdates {
  useNotifier(appUpdates);
  return appUpdates;
}
