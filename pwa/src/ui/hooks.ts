import { useEffect, useState } from 'preact/hooks';

/** Whether a media query matches, kept up to date. */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => (typeof matchMedia === 'function' ? matchMedia(query).matches : false));
  useEffect(() => {
    const m = matchMedia(query);
    const update = () => setMatches(m.matches);
    update();
    m.addEventListener('change', update);
    return () => m.removeEventListener('change', update);
  }, [query]);
  return matches;
}

/** Runs an async loader once and gives its result (or error). */
export function useAsync<T>(load: () => Promise<T>, deps: unknown[] = []): { value: T | undefined; error: unknown; loading: boolean } {
  const [state, setState] = useState<{ value: T | undefined; error: unknown; loading: boolean }>({ value: undefined, error: undefined, loading: true });
  useEffect(() => {
    let live = true;
    setState((s) => ({ ...s, loading: true }));
    load().then(
      (value) => live && setState({ value, error: undefined, loading: false }),
      (error) => live && setState({ value: undefined, error, loading: false }),
    );
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return state;
}

/** A value that follows the window's size, debounced to animation frames. */
export function useWindowSize(): { width: number; height: number } {
  const [size, setSize] = useState({ width: innerWidth, height: innerHeight });
  useEffect(() => {
    let frame = 0;
    const onResize = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => setSize({ width: innerWidth, height: innerHeight }));
    };
    addEventListener('resize', onResize);
    return () => removeEventListener('resize', onResize);
  }, []);
  return size;
}
