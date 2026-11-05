/// <reference lib="webworker" />
import { clientsClaim } from 'workbox-core';
import { cleanupOutdatedCaches, createHandlerBoundToURL, precacheAndRoute } from 'workbox-precaching';
import { NavigationRoute, registerRoute } from 'workbox-routing';
import { CacheFirst, StaleWhileRevalidate } from 'workbox-strategies';
import { CacheableResponsePlugin } from 'workbox-cacheable-response';
import { ExpirationPlugin } from 'workbox-expiration';
import { RangeRequestsPlugin } from 'workbox-range-requests';

/**
 * OpenWord's service worker, built by vite-plugin-pwa in `injectManifest`
 * mode: the precache manifest (every built file, the bundled Scripture,
 * atlas, references and originals among them — see `injectManifest` in
 * `vite.config.ts`) is injected at `self.__WB_MANIFEST`, and the rest is
 * ours: the runtime caches, the navigation fallback, push notifications
 * and the update handshake.
 *
 * It does not skip waiting on its own: a new build installs and waits
 * until the page, having shown "A new version is ready — Reload", posts
 * SKIP_WAITING (`src/pwa/serviceWorker.ts`).
 */
declare const self: ServiceWorkerGlobalScope & { __WB_MANIFEST: Array<{ url: string; revision: string | null } | string> };

/** What the server sends in a push: all optional but the title. */
interface PushPayload {
  title?: string;
  body?: string;
  url?: string;
  tag?: string;
  icon?: string;
  badge?: string;
}

const appIcon = '/icons/Icon-192.png';

// ---------------------------------------------------------------- caches

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();
clientsClaim();

// Navigations get the app shell, except the API and the health check.
registerRoute(
  new NavigationRoute(createHandlerBoundToURL('/index.html'), {
    denylist: [/^\/api\//, /^\/healthz$/],
  }),
);

// The voice (57 MB) is fetched the first time Listen is used and kept;
// the browser asks for it in ranges, which the plugin answers from cache.
registerRoute(
  ({ url }) => url.origin === self.location.origin && /\/voice\/.*/.test(url.pathname),
  new CacheFirst({
    cacheName: 'openword-voice',
    plugins: [new CacheableResponsePlugin({ statuses: [0, 200] }), new RangeRequestsPlugin(), new ExpirationPlugin({ maxEntries: 8 })],
  }),
);

// Friends' avatars: shown at once from cache, refreshed behind.
registerRoute(
  ({ url }) => /\/api\/users\/[^/]+\/avatar/.test(url.pathname),
  new StaleWhileRevalidate({
    cacheName: 'openword-avatars',
    plugins: [new ExpirationPlugin({ maxEntries: 200, maxAgeSeconds: 30 * 24 * 3600 })],
  }),
);

// ---------------------------------------------------------------- update

self.addEventListener('message', (event) => {
  const data = event.data as { type?: string } | undefined;
  if (data?.type === 'SKIP_WAITING') void self.skipWaiting();
});

// ------------------------------------------------------------------ push

self.addEventListener('push', (event) => {
  const payload = parsePush(event.data);
  const title = payload.title ?? 'OpenWord';
  const options: NotificationOptions = {
    body: payload.body,
    tag: payload.tag,
    icon: payload.icon ?? appIcon,
    badge: payload.badge ?? appIcon,
    data: { url: payload.url ?? '/' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data as { url?: string } | undefined;
  const target = new URL(data?.url ?? '/', self.location.origin).href;
  event.waitUntil(openOrFocus(target));
});

function parsePush(data: PushMessageData | null): PushPayload {
  if (!data) return {};
  try {
    const json = data.json() as unknown;
    if (json && typeof json === 'object') return json as PushPayload;
  } catch {
    // Not JSON: show the text as the body.
  }
  try {
    return { body: data.text() };
  } catch {
    return {};
  }
}

/** Brings an open window of the app to `url`, or opens one there. */
async function openOrFocus(url: string): Promise<void> {
  const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  const sameOrigin = windows.filter((c) => new URL(c.url).origin === self.location.origin);
  // A window already at the url, else any window of ours, navigated there.
  const exact = sameOrigin.find((c) => c.url === url);
  const client = exact ?? sameOrigin[0];
  if (client) {
    try {
      const focused = await client.focus();
      if (!exact && 'navigate' in focused) await focused.navigate(url);
      return;
    } catch {
      // Focus refused (some browsers, without a user gesture): open instead.
    }
  }
  await self.clients.openWindow(url);
}
