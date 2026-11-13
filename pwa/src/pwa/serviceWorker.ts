import { Workbox } from 'workbox-window';
import { ChangeNotifier, useNotifier, type Listener } from '../infra/changeNotifier';

/**
 * Registers the service worker (`src/sw.ts`, built to `/sw.js`), and moves
 * the app to a newer build when there is one.
 *
 * The worker is built with `skipWaiting` off: a new build installs, then
 * waits until `applyUpdate()` posts SKIP_WAITING, and the page reloads
 * once the new worker is in control, so every open tab moves to the new
 * version together instead of one tab running new code against another's
 * old caches.
 *
 * The switch is made without being asked, but not under the reader: a
 * build found already waiting when the app opens is switched to at once,
 * and one that arrives while it is open is switched to once the app has
 * been put down for a moment and nothing is being read aloud. "Reload" is
 * offered meanwhile for anyone who would rather not wait. An installed
 * app is seldom closed outright, which is the only other time a browser
 * lets a waiting worker in — so left to an offer nobody tapped, it stayed
 * on the build it was installed with.
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
/** How long the app must have been out of sight before a waiting build is switched to. */
const settledAfter = 15 * 1000;
/** No second switch unasked within this long of one, should the first not have taken. */
const switchAgainAfter = 5 * 60 * 1000;
const switchedKey = 'openword.update.switched';

/** What "Refresh cached copy" came to. */
export type RefreshOutcome = 'refreshed' | 'offline' | 'failed';

export class AppUpdates extends ChangeNotifier {
  private wb: Workbox | null = null;
  private registration: ServiceWorkerRegistration | null = null;
  private _updateAvailable = false;
  private _offlineReady = false;
  private _firstInstall = false;
  private _version: VersionInfo | null = null;
  private _supported = false;
  private _checking = false;
  private _refreshing = false;
  private hiddenSince: number | null = null;
  private settleTimer: ReturnType<typeof setTimeout> | undefined;
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

  /** Whether `refreshCachedCopy()` is in flight. */
  get refreshing(): boolean {
    return this._refreshing;
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
      // Arrived while the app was out of sight: counted from now.
      if (this.hiddenSince !== null) this.settle();
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
      // Waiting since an earlier visit, and the app has only now opened:
      // nothing is under way to interrupt.
      if (this._updateAvailable) this.applyUnasked();
    } catch (error) {
      console.warn('OpenWord: service worker registration failed', error);
      this._supported = false;
      this.notifyListeners();
    }
  }

  private schedule(): void {
    setInterval(() => void this.checkNow(), checkEvery);
    const seen = () => {
      if (document.visibilityState === 'visible') {
        // A page out of sight may have had its timers stopped: what the
        // timer would have done is done on the way back in.
        const away = this.hiddenSince === null ? 0 : Date.now() - this.hiddenSince;
        this.hiddenSince = null;
        clearTimeout(this.settleTimer);
        if (away >= settledAfter) this.applyUnasked();
        if (Date.now() - this.lastCheck > checkOnReturnAfter) void this.checkNow();
      } else {
        this.hiddenSince = Date.now();
        this.settle();
      }
    };
    document.addEventListener('visibilitychange', seen);
    if (document.visibilityState !== 'visible') seen();
  }

  /** Out of sight: a waiting build is switched to if the app stays there. */
  private settle(): void {
    clearTimeout(this.settleTimer);
    if (!this._updateAvailable) return;
    this.settleTimer = setTimeout(() => {
      if (this.hiddenSince !== null) this.applyUnasked();
    }, settledAfter);
  }

  /**
   * Switches to the waiting build without the reader having asked: not
   * while something is being read aloud, which a reload would cut off, and
   * not twice running, so a switch that does not take cannot turn into a
   * page reloading itself for ever.
   */
  private applyUnasked(): void {
    if (!this._updateAvailable || this.reloading || this._refreshing) return;
    if (typeof navigator !== 'undefined' && navigator.mediaSession?.playbackState === 'playing') return;
    try {
      const last = Number(sessionStorage.getItem(switchedKey) ?? 0);
      if (Date.now() - last < switchAgainAfter) return;
      sessionStorage.setItem(switchedKey, String(Date.now()));
    } catch {
      // No storage to keep count in: left to the Reload that is offered.
      return;
    }
    this.applyUpdate();
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

  /**
   * Throws away the copy of the app kept on this device and has it again
   * from the server: the newer build where there is one, else the same
   * build fetched afresh. The reader's own things — marks, notes, imported
   * translations, the voice — are not part of that copy and are left.
   * Reloads the page when it has worked.
   */
  async refreshCachedCopy(): Promise<RefreshOutcome> {
    const registration = this.registration;
    if (!registration || this._refreshing) return 'failed';
    this._refreshing = true;
    this.notifyListeners();
    try {
      // Nothing is thrown away until the server has answered. The query
      // keeps the worker from answering out of the very copy in question.
      try {
        const response = await fetch(`/version.json?fresh=${Date.now()}`, { cache: 'no-store' });
        if (!response.ok || typeof ((await response.json()) as Partial<VersionInfo>).version !== 'string') return 'offline';
      } catch {
        return 'offline';
      }
      await registration.update();
      const incoming = registration.installing ?? registration.waiting;
      if (incoming) {
        if (!(await installed(incoming))) return 'failed';
      } else {
        const active = registration.active;
        if (!active || (await refetched(active)) !== 0) return 'failed';
      }
      // The voice's runtime is kept apart from the build, under names
      // that do not change with it: fetched again when next listened to.
      await caches.delete('openword-ort').catch(() => false);
      if (incoming) {
        this._updateAvailable = true;
        this.applyUpdate();
      } else {
        this.reloadOnce();
      }
      return 'refreshed';
    } catch (error) {
      console.warn('OpenWord: could not refresh the cached copy', error);
      return 'failed';
    } finally {
      this._refreshing = false;
      this.notifyListeners();
    }
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

/** Waits for a worker to finish installing; false where it could not. */
function installed(worker: ServiceWorker): Promise<boolean> {
  return new Promise((resolve) => {
    const look = () => {
      if (worker.state === 'installing') return;
      worker.removeEventListener('statechange', look);
      resolve(worker.state !== 'redundant');
    };
    worker.addEventListener('statechange', look);
    look();
  });
}

/** Has the worker fetch its build's files again; answers how many it could not, -1 for none of them. */
function refetched(worker: ServiceWorker): Promise<number> {
  return new Promise((resolve) => {
    const channel = new MessageChannel();
    const timer = setTimeout(() => resolve(-1), 5 * 60 * 1000);
    channel.port1.onmessage = (event: MessageEvent<{ failed?: number }>) => {
      clearTimeout(timer);
      resolve(event.data?.failed ?? -1);
    };
    worker.postMessage({ type: 'REFRESH_PRECACHE' }, [channel.port2]);
  });
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
