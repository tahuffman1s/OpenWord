import type { ComponentType } from 'preact';
import { openFromTutorial } from '../app/openFlow';

/**
 * The social screens are written apart from these and may not be in the
 * tree yet. They are looked for rather than imported, so that a build
 * without them still stands: `import.meta.glob` answers nothing for a file
 * that is not there, where an `import` would fail to compile.
 */
const streakCards = import.meta.glob<Record<string, unknown>>('./social/streakCard.tsx', { eager: true });
const socialScreens = import.meta.glob<Record<string, unknown>>('./social/socialScreen.tsx', { eager: true });

function exported<T>(modules: Record<string, Record<string, unknown>>, name: string): T | null {
  for (const module of Object.values(modules)) {
    const value = module[name];
    if (value !== undefined) return value as T;
  }
  return null;
}

/** Friends' streaks beside your own, on the Progress tab; nothing where the social screens are absent. */
export function FriendStreaksCard() {
  const Card = exported<ComponentType>(streakCards, 'FriendStreaksCard');
  return Card === null ? null : <Card />;
}

/** Whether `<FriendStreaksCard/>` has anything behind it. */
export const hasFriendStreaksCard = exported<ComponentType>(streakCards, 'FriendStreaksCard') !== null;

/**
 * Opens a part of the social screens — `'account'`, `'friends'` — or, where
 * they are absent, asks whoever has registered for the feature by name.
 */
export function openSocial(section: string): void {
  const open = exported<(section: string) => unknown>(socialScreens, 'openSocial');
  if (open !== null) void open(section);
  else openFromTutorial(section);
}
