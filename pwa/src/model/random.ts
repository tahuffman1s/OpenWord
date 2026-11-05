/**
 * Dart's `Random`, as the port carries it: a source of numbers in [0, 1),
 * injected so that a test can fix what the app draws at random.
 *
 * `Math.random` is the default everywhere; `seededRandom` stands in for
 * `Random(seed)` where a test wants the same draw twice.
 */
export type RandomSource = () => number;

/** `Random.nextInt(max)`: an integer from 0 up to but not including `max`. */
export function nextInt(random: RandomSource, max: number): number {
  return Math.floor(random() * max);
}

/** `Random.nextBool()`. */
export function nextBool(random: RandomSource): boolean {
  return random() < 0.5;
}

/** Dart's `List.shuffle(random)`, in place and by the same walk. */
export function shuffle<T>(list: T[], random: RandomSource): T[] {
  let length = list.length;
  while (length > 1) {
    const pos = nextInt(random, length);
    length -= 1;
    const tmp = list[length];
    list[length] = list[pos];
    list[pos] = tmp;
  }
  return list;
}

/**
 * A small, fast generator (mulberry32) that gives the same run of numbers
 * for the same seed: what `Random(seed)` is for in the Dart tests.
 */
export function seededRandom(seed: number): RandomSource {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
