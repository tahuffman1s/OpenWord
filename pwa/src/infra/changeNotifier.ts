import { useEffect, useReducer } from 'preact/hooks';

export type Listener = () => void;

/**
 * Flutter's ChangeNotifier, so the stores port one for one: anything with
 * state the UI shows extends this and calls `notifyListeners()` after a
 * change, and a component reads it through `useNotifier`.
 */
export class ChangeNotifier {
  private readonly listeners = new Set<Listener>();
  private disposed = false;

  addListener(listener: Listener): void {
    this.listeners.add(listener);
  }

  removeListener(listener: Listener): void {
    this.listeners.delete(listener);
  }

  get hasListeners(): boolean {
    return this.listeners.size > 0;
  }

  notifyListeners(): void {
    if (this.disposed) return;
    for (const listener of [...this.listeners]) {
      try {
        listener();
      } catch (error) {
        console.error('OpenWord: a listener threw', error);
      }
    }
  }

  dispose(): void {
    this.disposed = true;
    this.listeners.clear();
  }
}

/** A value that tells its listeners when it changes. */
export class ValueNotifier<T> extends ChangeNotifier {
  constructor(private _value: T) {
    super();
  }
  get value(): T {
    return this._value;
  }
  set value(next: T) {
    if (Object.is(next, this._value)) return;
    this._value = next;
    this.notifyListeners();
  }
}

/**
 * Re-renders the calling component whenever any of the notifiers given
 * changes — Flutter's AnimatedBuilder, as a hook. Nulls are skipped, so a
 * component can listen to something that may not exist yet.
 */
export function useNotifier(...notifiers: (ChangeNotifier | null | undefined)[]): void {
  const [, bump] = useReducer((n: number) => n + 1, 0);
  useEffect(() => {
    const live = notifiers.filter((n): n is ChangeNotifier => n != null);
    const listener = () => bump(undefined as unknown as void);
    for (const n of live) n.addListener(listener);
    // A change between this component's render and this effect would
    // otherwise be lost: catch up once, now that we are listening.
    listener();
    return () => {
      for (const n of live) n.removeListener(listener);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, notifiers);
}
