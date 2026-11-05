/**
 * Opens a feature by name — from the tutorial's "Try it", a home-screen
 * shortcut (`/?open=learn`), or a notification's link. The reader screen
 * registers its openers here once it is on screen, since the sheets and
 * screens belong to it.
 */
export type Feature =
  | 'navigator'
  | 'listen'
  | 'library'
  | 'learn'
  | 'plans'
  | 'search'
  | 'friends'
  | 'settings'
  | 'install'
  | 'account'
  | string;

type Opener = (feature: Feature) => boolean | void;

let opener: Opener | null = null;
const pending: Feature[] = [];

export function registerFeatureOpener(open: Opener): () => void {
  opener = open;
  while (pending.length) open(pending.shift()!);
  return () => {
    if (opener === open) opener = null;
  };
}

export function openFromTutorial(feature: Feature): void {
  if (opener) opener(feature);
  else pending.push(feature);
}
