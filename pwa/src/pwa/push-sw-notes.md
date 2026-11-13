# Push and the service worker

vite-plugin-pwa has two ways of making the worker:

- **`generateSW`** (what `vite.config.ts` used at first): Workbox writes the
  whole worker from the `workbox: { … }` options. There is no way to add
  code to it — no `push` handler, no `notificationclick`, no `message`
  handler of our own. `importScripts` could pull a second file in, but a
  script imported that way is not in the precache manifest and cannot be
  typed or bundled with the rest.
- **`injectManifest`**: we write the worker ourselves (`src/sw.ts`), with
  the Workbox modules as ordinary imports, and the plugin builds it and
  injects the precache manifest at `self.__WB_MANIFEST`. Everything the
  `generateSW` options did has an equivalent call in the worker:

  | `workbox` option                    | in `src/sw.ts`                                             |
  |-------------------------------------|------------------------------------------------------------|
  | `globPatterns`, `globIgnores`, `maximumFileSizeToCacheInBytes` | `injectManifest: { … }` in `vite.config.ts` (the glob still runs at build) |
  | precaching                          | `precacheAndRoute(self.__WB_MANIFEST)`                     |
  | `cleanupOutdatedCaches`             | `cleanupOutdatedCaches()`                                  |
  | `clientsClaim`                      | `clientsClaim()`                                           |
  | `skipWaiting: false`                | nothing — `self.skipWaiting()` only on the SKIP_WAITING message |
  | `navigateFallback` + denylist       | `registerRoute(new NavigationRoute(createHandlerBoundToURL('/index.html'), { denylist }))` |
  | `runtimeCaching` entries            | `registerRoute(pattern, new CacheFirst({ plugins: [...] }))` |

So the config now uses `strategies: 'injectManifest'`, `srcDir: 'src'`,
`filename: 'sw.ts'`, and the worker is `src/sw.ts`. The page side
(`src/pwa/serviceWorker.ts`) is the same either way: `workbox-window`
registers `/sw.js`, reports a waiting worker, and posts SKIP_WAITING when
the reader taps Reload, or by itself once the app has been put down.

## What the worker handles

- `push`: the payload is JSON — `{ title, body, url, tag, icon }` — and is
  shown as a notification with the app icon. A payload that is not JSON is
  shown as its text.
- `notificationclick`: closes the notification and focuses an open window
  of the app at the payload's `url` (navigating it there), or opens one.
- `message` `{ type: 'SKIP_WAITING' }`: the waiting worker activates.
- `message` `{ type: 'REFRESH_PRECACHE' }`: every precached file is fetched
  again and replaced; the count that failed is answered on the message's port.

## What a reminder needs

A browser cannot fire a notification at a chosen time with nothing running.
A reminder before a streak breaks therefore comes as a push from the
server: the app subscribes (`subscribeToPush(vapidPublicKey)` in
`src/pwa/notifications.ts`), sends the subscription JSON and the reader's
reminder time to the server, and the server sends a push at that time when
the day's learning is not done. Where push is not to be had (an iOS tab, a
browser without it, permission refused), `reminderDueNow(time, lastDone)`
tells the app to show a banner when it is next opened.

iOS shows web push only for an app added to the home screen (iOS 16.4+),
which is why the install guide says so.
