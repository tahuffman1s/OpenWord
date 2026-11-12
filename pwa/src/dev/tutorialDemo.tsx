// A page to try the walkthrough and the install guide on their own:
//   npx vite --port 5201   →   http://localhost:5201/tutorial-demo.html
// Query parameters, for screenshots: ?card=3 opens the walkthrough on that
// card (0-based); ?guide=ios-safari opens the guide for that platform
// (&installed=1 for the "already installed" state, &prompt=1 to pretend
// the browser offered its prompt); ?dark=1 for the dark theme.
import { render } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import '../ui/m3/m3.css';
import { AppBar, Button, ListTile, OverlayHost, Screen, SectionHeader, TonalButton, applyScheme, installRipples, schemeFromSeed, showSnackBar } from '../ui/m3';
import { showTutorial } from '../ui/tutorial/tutorial';
import { detectPlatform, platformKey, showInstallGuide, type PlatformKey } from '../ui/tutorial/installGuide';
import { captureInstallPrompt, installPrompt } from '../pwa/install';
import { registerServiceWorker, useAppUpdates } from '../pwa/serviceWorker';
import { useNotifier } from '../infra/changeNotifier';
import { notificationPermission, requestNotificationPermission, showLocalNotification } from '../pwa/notifications';

const platforms: PlatformKey[] = [
  'ios-safari', 'ios-other', 'android-chrome', 'android-samsung', 'android-edge', 'android-firefox', 'android-other',
  'desktop-chromium', 'desktop-edge', 'desktop-safari', 'desktop-firefox', 'desktop-other',
];

const params = new URLSearchParams(location.search);
const dark = params.get('dark') === '1';
applyScheme(schemeFromSeed(0xff1b6c4f, dark ? 'dark' : 'light'));
installRipples();
captureInstallPrompt();
// In dev there is no /sw.js and this says so and carries on; in a build
// (vite preview) it registers the worker, so the update flow can be tried.
registerServiceWorker();

function Demo() {
  const [isDark, setDark] = useState(dark);
  const updates = useAppUpdates();
  useNotifier(installPrompt);
  const [permission, setPermission] = useState(notificationPermission());
  useEffect(() => {
    if (!updates.updateAvailable) return;
    showSnackBar('A new version of OpenWord is ready', { duration: 0, action: { label: 'Reload', onPressed: () => updates.applyUpdate() } });
  }, [updates.updateAvailable]);
  const detected = platformKey(detectPlatform());
  useEffect(() => {
    // After OverlayHost (a sibling, mounted after this) has subscribed to
    // the overlay stack; in the app the caller is its parent, so it has.
    const timer = setTimeout(() => {
      const card = params.get('card');
      const guide = params.get('guide');
      if (card !== null) void showTutorial((f) => showSnackBar(`Try: ${f}`), { initialCard: Number(card) });
      else if (guide !== null) {
        void showInstallGuide({
          platform: platforms.includes(guide as PlatformKey) ? (guide as PlatformKey) : undefined,
          installed: params.get('installed') === '1' ? true : undefined,
          promptAvailable: params.get('prompt') === '1' ? true : undefined,
        });
      }
    }, 0);
    return () => clearTimeout(timer);
  }, []);
  return (
    <Screen appBar={(s) => <AppBar scrolled={s} leading="none" title="Tutorial demo" subtitle={`Detected: ${detected}${installPrompt.available ? ' · prompt captured' : ''}`} />} padded>
      <SectionHeader>Walkthrough</SectionHeader>
      <div class="ow-row" style="flex-wrap:wrap">
        <Button onClick={() => showTutorial((f) => showSnackBar(`Try: ${f}`))}>Open tutorial</Button>
        <TonalButton onClick={() => showTutorial()}>Without "Try it"</TonalButton>
        <TonalButton onClick={() => showTutorial((f) => showSnackBar(`Try: ${f}`), { initialCard: 6 })}>Last card</TonalButton>
        <TonalButton onClick={() => { setDark(!isDark); applyScheme(schemeFromSeed(0xff1b6c4f, !isDark ? 'dark' : 'light')); }}>{isDark ? 'Light' : 'Dark'}</TonalButton>
      </div>
      <SectionHeader>Install guide</SectionHeader>
      <div class="ow-row" style="flex-wrap:wrap">
        <Button onClick={() => showInstallGuide()}>As detected</Button>
        <TonalButton onClick={() => showInstallGuide({ installed: true })}>Already installed</TonalButton>
        <TonalButton onClick={() => showInstallGuide({ promptAvailable: true })}>With prompt</TonalButton>
      </div>
      <SectionHeader>Service worker</SectionHeader>
      <ListTile
        icon="cloud_done"
        title={updates.supported ? (updates.updateAvailable ? 'Update waiting' : updates.offlineReady ? 'Ready to work offline' : 'Registered') : 'Not registered (dev, or unsupported)'}
        subtitle={updates.version ? `Version ${updates.version.version} · built ${updates.version.builtAt}${updates.version.commit ? ` · ${updates.version.commit}` : ''}` : 'No version.json'}
        trailing={<TonalButton onClick={() => updates.checkNow()} disabled={!updates.supported || updates.checking}>Check now</TonalButton>}
      />
      <ListTile
        icon="notifications"
        title={`Notifications: ${permission}`}
        trailing={
          <TonalButton
            onClick={async () => {
              setPermission(await requestNotificationPermission());
              const shown = await showLocalNotification('OpenWord', { body: 'A test notification', tag: 'demo', url: '/tutorial-demo.html' });
              showSnackBar(shown ? 'Notification shown' : 'Could not show a notification');
            }}
          >
            Test
          </TonalButton>
        }
      />
      <SectionHeader>Install guide, by platform</SectionHeader>
      {platforms.map((p) => (
        <ListTile key={p} icon={p.startsWith('ios') ? 'phone_iphone' : p.startsWith('android') ? 'smartphone' : 'desktop_windows'} title={p} onClick={() => showInstallGuide({ platform: p })} />
      ))}
    </Screen>
  );
}

render(
  <>
    <Demo />
    <OverlayHost />
  </>,
  document.getElementById('app')!,
);
