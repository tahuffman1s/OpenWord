import { createContext, type ComponentChildren } from 'preact';
import { useContext } from 'preact/hooks';
import type { Settings } from '../data/settings';
import type { ReadingStore } from '../data/marks';
import type { LibraryController } from '../data/library';
import type { AppUpdates } from '../pwa/serviceWorker';
import type { AccountController } from '../data/account';

/**
 * Makes the app-wide stores available to the component tree, as a Preact
 * context.
 *
 * Each store is a `ChangeNotifier`; a component listens to the one it
 * cares about with `useNotifier(store)` rather than re-rendering the whole
 * app.
 */
export interface AppScopeValue {
  settings: Settings;
  library: LibraryController;
  reading: ReadingStore;
  updates: AppUpdates;
  /** Accounts, friends, achievements — present once the app has started them. */
  account: AccountController;
}

const AppScopeContext = createContext<AppScopeValue | null>(null);

export function AppScope({ value, children }: { value: AppScopeValue; children: ComponentChildren }) {
  return <AppScopeContext.Provider value={value}>{children}</AppScopeContext.Provider>;
}

export function useAppScope(): AppScopeValue {
  const scope = useContext(AppScopeContext);
  if (!scope) throw new Error('No AppScope found');
  return scope;
}

/** For code outside the component tree (sheets opened from stores, workers' callbacks). */
let globalScope: AppScopeValue | null = null;
export function setGlobalScope(scope: AppScopeValue): void {
  globalScope = scope;
}
export function appScope(): AppScopeValue {
  if (!globalScope) throw new Error('The app has not started');
  return globalScope;
}
