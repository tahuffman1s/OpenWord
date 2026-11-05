import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
import { VitePWA } from 'vite-plugin-pwa';
import { fileURLToPath } from 'node:url';

// The bundled Scripture, atlas, notes, references and originals are
// precached so the app is whole offline; the voice (57 MB) is fetched the
// first time Listen is used and kept in Cache Storage by the app itself.
export default defineConfig({
  plugins: [
    preact(),
    VitePWA({
      registerType: 'prompt',
      injectRegister: false,
      manifest: false, // public/manifest.webmanifest is hand-written
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2,ttf,bib,gz,json,wasm,webmanifest}'],
        globIgnores: ['voice/**', '**/*.map'],
        maximumFileSizeToCacheInBytes: 12 * 1024 * 1024,
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api\//, /^\/healthz$/],
        runtimeCaching: [
          {
            urlPattern: /\/voice\/.*/,
            handler: 'CacheFirst',
            options: {
              cacheName: 'openword-voice',
              expiration: { maxEntries: 8 },
              cacheableResponse: { statuses: [0, 200] },
              rangeRequests: true,
            },
          },
          {
            urlPattern: /\/api\/users\/[^/]+\/avatar/,
            handler: 'StaleWhileRevalidate',
            options: { cacheName: 'openword-avatars', expiration: { maxEntries: 200, maxAgeSeconds: 30 * 24 * 3600 } },
          },
        ],
        cleanupOutdatedCaches: true,
        clientsClaim: true,
        skipWaiting: false,
      },
      includeAssets: ['icons/*.png', 'favicon.png'],
    }),
  ],
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  worker: { format: 'es' },
  optimizeDeps: { exclude: ['onnxruntime-web', 'phonemizer'] },
  build: {
    target: 'es2022',
    sourcemap: false,
    chunkSizeWarningLimit: 1500,
    assetsInlineLimit: 0,
  },
  server: { port: 5173, host: true },
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts', 'test/**/*.test.tsx'],
    setupFiles: ['test/setup.ts'],
  },
});
