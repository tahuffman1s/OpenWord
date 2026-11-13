import { useEffect, useMemo, useState } from 'preact/hooks';
import { useNotifier } from '../infra/changeNotifier';
import { Prefs } from '../infra/prefs';
import { rootBundle } from '../infra/assets';
import { Settings } from '../data/settings';
import { ReadingStore } from '../data/marks';
import { LibraryController } from '../data/library';
import { Shelf } from '../data/shelf';
import { AccountController } from '../data/account';
import { neuralVoices } from '../data/neuralVoices';
import { registerServiceWorker, type AppUpdates } from '../pwa/serviceWorker';
import { hasSeenTutorial, markTutorialSeen, showTutorial } from '../ui/tutorial/tutorial';
import { showInstallGuide } from '../ui/tutorial/installGuide';
import { Icon, LinearProgress, OverlayHost, installRipples, showSnackBar, watchTheme } from '../ui/m3';
import { ReaderScreen } from '../ui/readerScreen';
import { AppScope, setGlobalScope, type AppScopeValue } from './scope';
import { openFromTutorial } from './openFlow';

interface Booted extends AppScopeValue {
  prefs: Prefs;
}

/** Loads the stores the whole app reads from. */
async function boot(): Promise<Booted> {
  const prefs = Prefs.open();
  const settings = await Settings.load(prefs);
  const reading = await ReadingStore.load({ prefs });
  // The imported translations, read from this browser's own storage before
  // anything is loaded: the one being read may be one of them, and a shelf
  // not yet listed would send the library looking for it among the bundled
  // files instead.
  const shelf = await Shelf.open();
  try {
    await shelf?.refresh();
  } catch (error) {
    console.warn('OpenWord: no shelf for imported translations', error);
  }
  const library = new LibraryController({ bundle: rootBundle, shelf });
  // Reading the Scripture takes a fraction of a second; start it while the
  // first frame is being built.
  void library.load(settings.translationId);
  const updates = registerServiceWorker();
  const account = new AccountController({ prefs, reading });
  void account.start();
  return { prefs, settings, reading, library, updates, account };
}

export function App() {
  const [booted, setBooted] = useState<Booted | null>(null);
  const [failure, setFailure] = useState<string | null>(null);

  useEffect(() => {
    installRipples();
    boot().then(setBooted, (error) => {
      console.error('OpenWord: could not start', error);
      setFailure(`OpenWord could not start: ${error}`);
    });
  }, []);

  if (!booted) return <Splash message={failure} />;
  return <Started booted={booted} />;
}

function Started({ booted }: { booted: Booted }) {
  const { settings, library, updates } = booted;
  useNotifier(settings, library, updates);
  const scope = useMemo<AppScopeValue>(() => booted, [booted]);
  useEffect(() => setGlobalScope(scope), [scope]);

  // The palette follows the seed colour and the system's light or dark.
  useEffect(
    () => watchTheme(() => ({ seed: settings.seedColor, mode: settings.themeMode })),
    [settings.seedColor, settings.themeMode, settings],
  );

  // A new build, once the service worker has it: offered now, and taken
  // up unasked once the app has been put down (src/pwa/serviceWorker.ts).
  useEffect(() => {
    if (!updates.updateAvailable) return;
    showSnackBar('A new version of OpenWord is ready', {
      duration: 10000,
      action: { label: 'Reload', onPressed: () => updates.applyUpdate() },
    });
  }, [updates.updateAvailable, updates]);

  // First launch: the walkthrough, once the text is there to try things on.
  useEffect(() => {
    if (!library.isReady || hasSeenTutorial(booted.prefs)) return;
    markTutorialSeen(booted.prefs);
    void showTutorial((feature) => openFromTutorial(feature));
  }, [library.isReady, booted.prefs]);

  // The voice, fetched once the app has settled, so that the first Listen
  // has it in hand rather than sixty megabytes to wait for.
  useEffect(() => {
    if (!library.isReady) return;
    const timer = setTimeout(() => neuralVoices.prefetch(), 8000);
    return () => clearTimeout(timer);
  }, [library.isReady]);

  // A home-screen shortcut, or a link into a feature.
  useEffect(() => {
    if (!library.isReady) return;
    const open = new URLSearchParams(location.search).get('open');
    if (!open) return;
    history.replaceState(history.state, '', location.pathname);
    if (open === 'install') void showInstallGuide();
    else openFromTutorial(open);
  }, [library.isReady]);

  return (
    <AppScope value={scope}>
      {library.isReady ? <ReaderScreen /> : <Splash message={library.errorMessage} />}
      <OverlayHost />
    </AppScope>
  );
}

/** Shows until the Scripture is decoded, and the error if it never is. */
function Splash({ message }: { message: string | null | undefined }) {
  return (
    <div class="ow-splash">
      <div class="ow-splash__mark">
        <Icon name="auto_stories" size={48} />
      </div>
      <div class="ow-splash__title">OpenWord</div>
      {message ? <div class="m3-body-medium m3-error">{message}</div> : <div style="width:120px"><LinearProgress /></div>}
    </div>
  );
}
