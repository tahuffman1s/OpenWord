import type { ComponentChildren } from 'preact';
import { useState } from 'preact/hooks';
import { useNotifier } from '../../infra/changeNotifier';
import { installPrompt, isStandalone, type InstallOutcome } from '../../pwa/install';
import { Button, Icon, Sheet, TonalButton, showSheet, showSnackBar, useOverlay } from '../m3';
import './tutorial.css';

/**
 * "Put OpenWord on your home screen": the steps for the browser the reader
 * is in, with the menu names and icons that browser uses, and the
 * browser's own install prompt as a button where it offers one.
 */
export type InstallOs = 'ios' | 'android' | 'macos' | 'windows' | 'linux' | 'chromeos' | 'other';
export type InstallBrowser = 'safari' | 'chrome' | 'edge' | 'firefox' | 'samsung' | 'brave' | 'arc' | 'opera' | 'other';

export interface Platform {
  os: InstallOs;
  browser: InstallBrowser;
  /** Phone or tablet. */
  mobile: boolean;
}

/** A platform the guide has steps for; the demo page picks one by name. */
export type PlatformKey =
  | 'ios-safari'
  | 'ios-other'
  | 'android-chrome'
  | 'android-samsung'
  | 'android-edge'
  | 'android-firefox'
  | 'android-other'
  | 'desktop-chromium'
  | 'desktop-edge'
  | 'desktop-safari'
  | 'desktop-firefox'
  | 'desktop-other';

/** Works out the platform from the user agent and the few hints beside it. */
export function detectPlatform(
  ua: string = typeof navigator === 'undefined' ? '' : navigator.userAgent,
  hints: { maxTouchPoints?: number; brave?: boolean; arc?: boolean; platform?: string } = defaultHints(),
): Platform {
  const touch = hints.maxTouchPoints ?? 0;
  const isIos = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && touch > 1);
  const isAndroid = /Android/.test(ua);
  let os: InstallOs = 'other';
  if (isIos) os = 'ios';
  else if (isAndroid) os = 'android';
  else if (/CrOS/.test(ua)) os = 'chromeos';
  else if (/Macintosh|Mac OS X/.test(ua)) os = 'macos';
  else if (/Windows/.test(ua)) os = 'windows';
  else if (/Linux|X11/.test(ua)) os = 'linux';

  let browser: InstallBrowser = 'other';
  if (isIos) {
    // Every browser on iOS is WebKit; they say who they are in the UA.
    if (/CriOS/.test(ua)) browser = 'chrome';
    else if (/FxiOS/.test(ua)) browser = 'firefox';
    else if (/EdgiOS/.test(ua)) browser = 'edge';
    else if (/OPT\//.test(ua)) browser = 'opera';
    else if (/Safari/.test(ua) || /AppleWebKit/.test(ua)) browser = 'safari';
  } else if (/SamsungBrowser/.test(ua)) browser = 'samsung';
  else if (/Edg(e|A|iOS)?\//.test(ua)) browser = 'edge';
  else if (/OPR\/|Opera/.test(ua)) browser = 'opera';
  else if (/Firefox\/|FxiOS/.test(ua)) browser = 'firefox';
  else if (hints.brave) browser = 'brave';
  else if (hints.arc) browser = 'arc';
  else if (/Chrome\/|CriOS/.test(ua)) browser = 'chrome';
  else if (/Safari\//.test(ua) && /AppleWebKit/.test(ua)) browser = 'safari';

  const mobile = isIos || isAndroid || /Mobile|Tablet/.test(ua);
  return { os, browser, mobile };
}

function defaultHints(): { maxTouchPoints?: number; brave?: boolean; arc?: boolean; platform?: string } {
  if (typeof navigator === 'undefined') return {};
  const nav = navigator as Navigator & { brave?: { isBrave?: unknown } };
  let arc = false;
  try {
    // Arc sets its palette as custom properties on the document.
    arc = getComputedStyle(document.documentElement).getPropertyValue('--arc-palette-title').trim() !== '';
  } catch {
    // No DOM.
  }
  return { maxTouchPoints: nav.maxTouchPoints, brave: typeof nav.brave?.isBrave === 'function', arc, platform: nav.platform };
}

/** Which set of steps fits the platform. */
export function platformKey(p: Platform): PlatformKey {
  if (p.os === 'ios') return p.browser === 'safari' ? 'ios-safari' : 'ios-other';
  if (p.os === 'android') {
    if (p.browser === 'chrome' || p.browser === 'brave' || p.browser === 'opera') return 'android-chrome';
    if (p.browser === 'samsung') return 'android-samsung';
    if (p.browser === 'edge') return 'android-edge';
    if (p.browser === 'firefox') return 'android-firefox';
    return 'android-other';
  }
  if (p.browser === 'edge') return 'desktop-edge';
  if (p.browser === 'chrome' || p.browser === 'brave' || p.browser === 'arc' || p.browser === 'opera' || p.os === 'chromeos') return 'desktop-chromium';
  if (p.browser === 'safari') return 'desktop-safari';
  if (p.browser === 'firefox') return 'desktop-firefox';
  return 'desktop-other';
}

// ------------------------------------------------------------------ steps

interface Step {
  icon?: string;
  /** Drawn inline instead of a kit icon. */
  glyph?: ComponentChildren;
  text: ComponentChildren;
}

interface Guide {
  title: string;
  /** What the reader is using, in words, under the title. */
  where: string;
  intro?: ComponentChildren;
  steps: Step[];
  /** No install on this platform: what to do instead. */
  noInstall?: boolean;
  /** A note about notifications, where it matters. */
  note?: ComponentChildren;
}

const Menu = ({ children }: { children: ComponentChildren }) => <span class="ow-install__menu">{children}</span>;

/** Chrome's install icon: a screen with an arrow down into it. */
const chromeInstallGlyph = (
  <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor" aria-hidden="true">
    <path d="M18 1.01 6 1c-1.1 0-2 .9-2 2v3h2V5h12v14H6v-1H4v3c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V3c0-1.1-.9-1.99-2-1.99zM10 15h2V8h2v7h2l-3 3-3-3z" />
  </svg>
);

const guides: Record<PlatformKey, Guide> = {
  'ios-safari': {
    title: 'Add to your Home Screen',
    where: 'Safari on iPhone and iPad',
    steps: [
      {
        icon: 'ios_share',
        text: (
          <>
            Tap <Menu>Share</Menu> — the square with an arrow, at the bottom of the screen (at the top on iPad).
          </>
        ),
      },
      {
        icon: 'add_to_home_screen',
        text: (
          <>
            Scroll down the sheet and tap <Menu>Add to Home Screen</Menu>.
          </>
        ),
      },
      {
        icon: 'check',
        text: (
          <>
            Tap <Menu>Add</Menu> in the corner. OpenWord is now an icon on your Home Screen.
          </>
        ),
      },
    ],
    note: 'Reminders and other notifications on iPhone and iPad reach only the installed app, on iOS 16.4 or later.',
  },
  'ios-other': {
    title: 'Open it in Safari first',
    where: 'Chrome, Firefox or another browser on iPhone and iPad',
    intro: 'On iPhone and iPad only Safari can add a web app to the Home Screen. It takes a moment:',
    steps: [
      { icon: 'content_copy', text: 'Copy this page’s address — the button below does it.' },
      { icon: 'public', text: 'Open Safari and paste it into the address bar.' },
      {
        icon: 'ios_share',
        text: (
          <>
            Tap <Menu>Share</Menu>, then <Menu>Add to Home Screen</Menu>, then <Menu>Add</Menu>.
          </>
        ),
      },
    ],
    note: 'Reminders and other notifications on iPhone and iPad reach only the installed app, on iOS 16.4 or later.',
  },
  'android-chrome': {
    title: 'Install OpenWord',
    where: 'Chrome on Android',
    steps: [
      {
        icon: 'more_vert',
        text: (
          <>
            Tap the <Menu>⋮</Menu> menu in the top corner.
          </>
        ),
      },
      {
        icon: 'add_to_home_screen',
        text: (
          <>
            Tap <Menu>Add to Home screen</Menu> — on newer versions it says <Menu>Install app</Menu>.
          </>
        ),
      },
      {
        icon: 'check',
        text: (
          <>
            Tap <Menu>Install</Menu>. The icon appears with your other apps.
          </>
        ),
      },
    ],
  },
  'android-samsung': {
    title: 'Install OpenWord',
    where: 'Samsung Internet',
    steps: [
      {
        icon: 'menu',
        text: (
          <>
            Tap the <Menu>≡</Menu> menu at the bottom right.
          </>
        ),
      },
      {
        icon: 'add_to_home_screen',
        text: (
          <>
            Tap <Menu>Add page to</Menu>, then <Menu>Home screen</Menu> — or <Menu>Install</Menu> when it is offered.
          </>
        ),
      },
      {
        icon: 'check',
        text: (
          <>
            Tap <Menu>Add</Menu>.
          </>
        ),
      },
    ],
  },
  'android-edge': {
    title: 'Install OpenWord',
    where: 'Edge on Android',
    steps: [
      {
        icon: 'more_horiz',
        text: (
          <>
            Tap the <Menu>⋯</Menu> menu at the bottom of the screen.
          </>
        ),
      },
      {
        icon: 'add_to_home_screen',
        text: (
          <>
            Tap <Menu>Add to phone</Menu>.
          </>
        ),
      },
      {
        icon: 'check',
        text: (
          <>
            Tap <Menu>Install</Menu>.
          </>
        ),
      },
    ],
  },
  'android-firefox': {
    title: 'Install OpenWord',
    where: 'Firefox on Android',
    steps: [
      {
        icon: 'more_vert',
        text: (
          <>
            Tap the <Menu>⋮</Menu> menu.
          </>
        ),
      },
      {
        icon: 'add_to_home_screen',
        text: (
          <>
            Tap <Menu>Install</Menu> — on older versions, <Menu>Add to Home screen</Menu>.
          </>
        ),
      },
      {
        icon: 'check',
        text: (
          <>
            Tap <Menu>Add</Menu>.
          </>
        ),
      },
    ],
  },
  'android-other': {
    title: 'Install OpenWord',
    where: 'Your browser on Android',
    steps: [
      { icon: 'more_vert', text: 'Open the browser’s menu.' },
      {
        icon: 'add_to_home_screen',
        text: (
          <>
            Look for <Menu>Install</Menu>, <Menu>Install app</Menu> or <Menu>Add to Home screen</Menu>.
          </>
        ),
      },
      { icon: 'check', text: 'Confirm, and the icon appears with your other apps.' },
    ],
  },
  'desktop-chromium': {
    title: 'Install OpenWord',
    where: 'Chrome, Brave, Arc and other Chromium browsers',
    steps: [
      {
        glyph: chromeInstallGlyph,
        text: (
          <>
            Click the install icon at the right end of the address bar — a screen with an arrow — and then <Menu>Install</Menu>.
          </>
        ),
      },
      {
        icon: 'more_vert',
        text: (
          <>
            No icon there? Open the <Menu>⋮</Menu> menu, then <Menu>Cast, save and share</Menu> → <Menu>Install page as app…</Menu>
            (in older versions <Menu>Install OpenWord…</Menu>).
          </>
        ),
      },
      { icon: 'desktop_windows', text: 'OpenWord opens in its own window and is listed with your other apps.' },
    ],
  },
  'desktop-edge': {
    title: 'Install OpenWord',
    where: 'Microsoft Edge',
    steps: [
      {
        glyph: chromeInstallGlyph,
        text: (
          <>
            Click the install icon at the right end of the address bar, then <Menu>Install</Menu>.
          </>
        ),
      },
      {
        icon: 'more_horiz',
        text: (
          <>
            Or open the <Menu>⋯</Menu> menu, then <Menu>Apps</Menu> → <Menu>Install this site as an app</Menu>.
          </>
        ),
      },
      { icon: 'desktop_windows', text: 'OpenWord opens in its own window and appears in the Start menu or Dock.' },
    ],
  },
  'desktop-safari': {
    title: 'Add to the Dock',
    where: 'Safari on macOS Sonoma or later',
    steps: [
      {
        icon: 'ios_share',
        text: (
          <>
            Click <Menu>File</Menu> in the menu bar, then <Menu>Add to Dock…</Menu> — or <Menu>Share</Menu> in the toolbar, then{' '}
            <Menu>Add to Dock</Menu>.
          </>
        ),
      },
      {
        icon: 'check',
        text: (
          <>
            Click <Menu>Add</Menu>. OpenWord appears in the Dock and in Launchpad.
          </>
        ),
      },
    ],
    note: 'Needs macOS Sonoma (14) or later. On an earlier macOS, Chrome or Edge can install it instead.',
  },
  'desktop-firefox': {
    title: 'Firefox does not install web apps',
    where: 'Firefox on a desktop',
    noInstall: true,
    intro: 'Firefox on a desktop has no way to install a web app, but OpenWord works just the same in a tab, offline included.',
    steps: [
      {
        icon: 'bookmark_add',
        text: (
          <>
            Bookmark it: press <Menu>Ctrl</Menu> + <Menu>D</Menu> (<Menu>⌘</Menu> + <Menu>D</Menu> on a Mac), or pin the tab.
          </>
        ),
      },
      {
        glyph: chromeInstallGlyph,
        text: 'For an icon of its own and its own window, open this page in Chrome or Edge and install it from there.',
      },
    ],
  },
  'desktop-other': {
    title: 'Install OpenWord',
    where: 'Your browser',
    steps: [
      { glyph: chromeInstallGlyph, text: 'Look for an install icon at the right end of the address bar, or an Install entry in the browser’s menu.' },
      { icon: 'bookmark_add', text: 'If there is none, a bookmark does nicely: OpenWord works the same in a tab, offline included.' },
    ],
  },
};

// ------------------------------------------------------------------ sheet

export interface InstallGuideProps {
  /** Forces a platform's steps, for the demo page. */
  platform?: PlatformKey;
  /** Forces the "already installed" state, for the demo page. */
  installed?: boolean;
  /** Pretends the browser offered its prompt, for the demo page. */
  promptAvailable?: boolean;
}

export function InstallGuide({ platform, installed, promptAvailable }: InstallGuideProps) {
  useNotifier(installPrompt);
  const overlay = useOverlay();
  const key = platform ?? platformKey(detectPlatform());
  const guide = guides[key];
  const isInstalled = installed ?? (installPrompt.installed || isStandalone());
  const canPrompt = promptAvailable ?? installPrompt.available;
  const [outcome, setOutcome] = useState<InstallOutcome | 'working' | null>(null);
  const isIos = key.startsWith('ios');

  const runPrompt = async () => {
    setOutcome('working');
    const result = promptAvailable && !installPrompt.available ? 'accepted' : await installPrompt.prompt();
    setOutcome(result);
    if (result === 'accepted') showSnackBar('Installing OpenWord…');
  };

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(location.href.split('?')[0]);
      showSnackBar('Address copied — paste it in Safari');
    } catch {
      showSnackBar(location.href.split('?')[0]);
    }
  };

  return (
    <Sheet>
      <div class="ow-install">
        <div class="ow-install__hero">
          <div class="ow-tut__blob ow-tut__blob--primary ow-install__blob">
            <Icon name={isInstalled ? 'check_circle' : 'add_to_home_screen'} size={40} />
          </div>
          <h2 class="m3-headline-small ow-install__title">{isInstalled ? 'You’re using the installed app' : guide.title}</h2>
          <div class="m3-body-medium m3-on-surface-variant">
            {isInstalled ? 'OpenWord is on your home screen and opens full screen, offline, with everything in place.' : guide.where}
          </div>
        </div>

        {!isInstalled && canPrompt && (
          <div class="ow-install__prompt">
            <Button icon="install_mobile" onClick={runPrompt} disabled={outcome === 'working'}>
              Install OpenWord
            </Button>
            {outcome === 'accepted' && (
              <div class="m3-body-medium ow-install__outcome">
                <Icon name="check_circle" size={20} /> Installing — you’ll find it with your other apps in a moment.
              </div>
            )}
            {outcome === 'dismissed' && <div class="m3-body-medium m3-on-surface-variant ow-install__outcome">No problem — you can install it any time from Settings.</div>}
            {outcome === 'unavailable' && <div class="m3-body-medium m3-on-surface-variant ow-install__outcome">The browser’s prompt is not available right now; the steps below do the same.</div>}
            <div class="m3-body-small m3-on-surface-variant" style="margin-top:4px">
              Or by hand:
            </div>
          </div>
        )}

        {!isInstalled && (
          <>
            {guide.intro && <p class="m3-body-medium ow-install__intro">{guide.intro}</p>}
            <ol class="ow-install__steps">
              {guide.steps.map((step, i) => (
                <li class="ow-install__step" key={i}>
                  <span class="ow-install__step-n">{i + 1}</span>
                  <span class="ow-install__step-icon">{step.glyph ?? <Icon name={step.icon ?? 'check'} />}</span>
                  <span class="m3-body-medium ow-install__step-text">{step.text}</span>
                </li>
              ))}
            </ol>
            {key === 'ios-other' && (
              <div class="ow-install__prompt">
                <TonalButton icon="content_copy" onClick={copyLink}>
                  Copy the address
                </TonalButton>
              </div>
            )}
          </>
        )}

        {!guide.noInstall && (
          <div class="ow-install__gets">
            <div class="m3-title-small">What you get</div>
            <ul class="ow-install__list">
              <li>
                <Icon name="smartphone" size={20} /> An icon on your home screen or desktop
              </li>
              <li>
                <Icon name="crop_free" size={20} /> Full screen, with no browser bar
              </li>
              <li>
                <Icon name="wifi_off" size={20} /> Works entirely offline
              </li>
              <li>
                <Icon name="bolt" size={20} /> Opens faster, and keeps your place
              </li>
            </ul>
          </div>
        )}

        {(guide.note || isIos) && !isInstalled && (
          <div class="ow-install__note m3-body-small">
            <Icon name="info_outlined" size={18} />
            <span>{guide.note}</span>
          </div>
        )}

        <div class="ow-install__actions">
          <Button variant={isInstalled ? 'filled' : 'text'} onClick={() => overlay.close()}>
            {isInstalled ? 'Great' : 'Done'}
          </Button>
        </div>
      </div>
    </Sheet>
  );
}

/** Opens the guide as a sheet; settles when it is closed. */
export function showInstallGuide(props: InstallGuideProps = {}): Promise<void> {
  return showSheet<void>(<InstallGuide {...props} />, { name: 'install-guide' }).then(() => undefined);
}
