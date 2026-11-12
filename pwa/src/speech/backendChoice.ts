/**
 * Which of the two ways of running the voice this device is given: its
 * graphics processor (WebGPU) or its processor (WebAssembly), and what
 * has been learnt here about each.
 *
 * The graphics processor is tried first. On a phone it is the difference
 * between speech made faster than it is heard and slower: Safari will not
 * give a page the threads the processor needs to keep up, and has had
 * WebGPU since iOS 26. But a browser saying it has WebGPU is not the
 * same as the model running on it, and the ways it goes wrong are not all
 * errors that can be caught:
 *
 * - A driver that gets an operation wrong gives silence or noise. So the
 *   first time on a device the worker makes it say a word and listens
 *   (`prove`), and what it finds is kept here.
 * - A phone short of memory does not fail the load: iOS ends the page.
 *   So a mark is left before a load and wiped when it comes back; a mark
 *   found still standing at the next launch means the page did not live
 *   through it, and after that has happened twice the backend it was
 *   trying is passed over.
 * - A graphics processor may simply be slower than the processor it sits
 *   beside. The pace each is seen to keep is kept, and the quicker is
 *   put first.
 *
 * Kept in localStorage, per browser: a verdict belongs to the browser
 * that earned it, so one from another version of it is forgotten.
 */
import type { KeyValueStorage } from '../infra/prefs';
import type { Backend } from './ttsWorker';

export interface BackendPlan {
  /** What the worker is to try, in order. Empty: the voice cannot run here. */
  backends: Backend[];
  /** Whether the graphics processor must be heard to speak before it is trusted. */
  prove: boolean;
}

interface Verdict {
  /** `ok` once it has loaded and spoken; `bad` once it has failed to. */
  state?: 'ok' | 'bad';
  /** When it was found bad, so that a page that merely died is tried again in time. */
  since?: number;
  /** Whether `bad` came from the page dying rather than from an error. */
  died?: boolean;
  /** Seconds taken per second of speech, smoothed; above 1 it cannot keep up. */
  pace?: number;
}

interface Kept {
  /** The browser these were learnt in. */
  agent: string;
  webgpu?: Verdict;
  wasm?: Verdict;
  /** A load that has begun and not been seen to end. */
  trying?: { backend: Backend; count: number };
}

const key = 'openword.voice.backends.v1';

/** How many loads a page may fail to come back from before the backend is passed over. */
const deathsAllowed = 2;

/** A backend given up on because the page died is tried again after this long. */
const retryAfterMs = 14 * 24 * 60 * 60 * 1000;

/** Above this pace speech is made more slowly than it is heard. */
const tooSlow = 1.05;

export class BackendChoice {
  constructor(
    private readonly storage: KeyValueStorage | null,
    private readonly env: { agent: string; hasGpu: boolean; now?: () => number },
  ) {}

  /** This browser's, or one that remembers nothing where storage is refused. */
  static forThisBrowser(): BackendChoice {
    let storage: KeyValueStorage | null = null;
    try {
      storage = typeof localStorage === 'undefined' ? null : localStorage;
    } catch {
      storage = null;
    }
    const nav = typeof navigator === 'undefined' ? undefined : navigator;
    return new BackendChoice(storage, {
      agent: nav?.userAgent ?? '',
      hasGpu: nav !== undefined && 'gpu' in nav && (nav as { gpu?: unknown }).gpu != null,
    });
  }

  private now(): number {
    return (this.env.now ?? Date.now)();
  }

  private read(): Kept {
    try {
      const raw = this.storage?.getItem(key);
      if (raw != null) {
        const kept = JSON.parse(raw) as Kept;
        if (kept !== null && typeof kept === 'object' && kept.agent === this.env.agent) return kept;
      }
    } catch {
      // Unreadable: begun again.
    }
    return { agent: this.env.agent };
  }

  private write(kept: Kept): void {
    try {
      this.storage?.setItem(key, JSON.stringify(kept));
    } catch {
      // Storage full or refused: learnt again next time.
    }
  }

  private usable(kept: Kept, backend: Backend): boolean {
    if (backend === 'webgpu' && !this.env.hasGpu) return false;
    const verdict = kept[backend];
    if (verdict?.state !== 'bad') return true;
    // An error is believed until the browser changes. A page that died
    // may have died of something else, so that is believed for a while.
    return verdict.died === true && this.now() - (verdict.since ?? 0) > retryAfterMs;
  }

  /**
   * What to try now. A load left unfinished by a page that did not come
   * back is counted against the backend it was trying first.
   */
  plan(): BackendPlan {
    const kept = this.read();
    const trying = kept.trying;
    if (trying !== undefined && trying.count >= deathsAllowed) {
      kept[trying.backend] = { ...kept[trying.backend], state: 'bad', died: true, since: this.now() };
      delete kept.trying;
      this.write(kept);
    }
    const backends = (['webgpu', 'wasm'] as const).filter((backend) => this.usable(kept, backend));
    // The processor first, where the graphics processor has been heard to
    // fall behind and the processor has not been found slower still.
    const gpu = kept.webgpu?.pace;
    const cpu = kept.wasm?.pace;
    if (backends.length === 2 && gpu !== undefined && gpu > tooSlow && (cpu === undefined || cpu < gpu)) {
      backends.reverse();
    }
    return { backends: [...backends], prove: backends.includes('webgpu') && kept.webgpu?.state !== 'ok' };
  }

  /** A load is about to begin: the mark is left. */
  begin(plan: BackendPlan): void {
    const first = plan.backends[0];
    if (first === undefined) return;
    const kept = this.read();
    const count = kept.trying?.backend === first ? kept.trying.count + 1 : 1;
    kept.trying = { backend: first, count };
    this.write(kept);
  }

  /** The load came back: the mark is wiped, and what was found is kept. */
  loaded(backend: Backend, refused: readonly { backend: Backend; why: string }[]): void {
    const kept = this.read();
    delete kept.trying;
    for (const { backend: failed } of refused) {
      // Its absence is not a failure: `plan` asks the browser each time.
      if (failed === 'webgpu' && !this.env.hasGpu) continue;
      kept[failed] = { ...kept[failed], state: 'bad', died: false, since: this.now() };
    }
    kept[backend] = { ...kept[backend], state: 'ok' };
    delete kept[backend]!.died;
    delete kept[backend]!.since;
    this.write(kept);
  }

  /** The load failed with an error, which is not the page dying: only the mark goes. */
  failed(): void {
    const kept = this.read();
    if (kept.trying === undefined) return;
    delete kept.trying;
    this.write(kept);
  }

  /** A backend that had been speaking has stopped making sound. */
  broke(backend: Backend): void {
    const kept = this.read();
    kept[backend] = { ...kept[backend], state: 'bad', died: false, since: this.now() };
    this.write(kept);
  }

  /** The pace a backend is seen to keep, once enough has been made to say. */
  paced(backend: Backend, pace: number): void {
    if (!Number.isFinite(pace) || pace <= 0) return;
    const kept = this.read();
    kept[backend] = { ...kept[backend], pace: Math.round(pace * 100) / 100 };
    this.write(kept);
  }

  /** Whether the voice can run here at all, by anything not yet ruled out. */
  get canRun(): boolean {
    return this.plan().backends.length > 0;
  }
}
