import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
import { VitePWA } from 'vite-plugin-pwa';
import { fileURLToPath } from 'node:url';
import { versionPlugin } from './src/pwa/versionPlugin';

// The bundled Scripture, atlas, notes, references and originals are
// precached so the app is whole offline; the voice (57 MB) is fetched the
// first time Listen is used and kept in Cache Storage by the worker's
// runtime cache (see src/sw.ts).
const isolation = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'credentialless',
};

export default defineConfig({
  plugins: [
    preact(),
    // Writes dist/version.json before the worker's precache manifest is
    // made, so the app can say which build it is.
    versionPlugin(),
    VitePWA({
      // The worker is ours (src/sw.ts): precaching, the runtime caches, the
      // navigation fallback, push notifications and the update handshake.
      // The plugin builds it and injects the precache manifest.
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',
      registerType: 'prompt',
      injectRegister: false,
      manifest: false, // public/manifest.webmanifest is hand-written
      injectManifest: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2,ttf,bib,gz,json,wasm,webmanifest}'],
        // The voice and the ONNX runtime that runs it (15 MB) are fetched
        // the first time Listen is used and kept by the worker's runtime
        // caches, rather than downloaded by every reader at install.
        // Vite also emits the runtime's wasm beside the bundle that names it;
        // the worker loads the copy under /ort/ instead, so that one is left
        // out of the precache too.
        globIgnores: ['voice/**', 'ort/**', 'assets/ort-wasm-*.wasm', '**/*.map'],
        maximumFileSizeToCacheInBytes: 12 * 1024 * 1024,
        // Only Vite's own output (assets/name-HASH.ext) carries its version
        // in its name. The plugin's default treats everything under
        // assets/ that way, which would leave the Scripture, atlas and
        // references copied from public/assets/ without a revision — and a
        // new eng-web.bib would never replace the cached one.
        dontCacheBustURLsMatching: /^assets\/[^/]+-[\w-]{8}\.\w+$/,
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
    // The voice's test page (scripts/tts-smoke.mjs) is built only when
    // asked for, so it stays out of the production bundle. In dev Vite
    // serves it regardless.
    rollupOptions: process.env.OPENWORD_TTS_HARNESS
      ? { input: { main: 'index.html', ttsHarness: 'tts-harness.html' } }
      : undefined,
  },
  // Cross-origin isolation, as deploy/nginx.conf sends it: with it the
  // voice's runtime may use threads (SharedArrayBuffer), which is the
  // difference between speech made faster than it is heard and slower.
  server: { port: 5173, host: true, headers: isolation },
  preview: { headers: isolation },
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts', 'test/**/*.test.tsx'],
    setupFiles: ['test/setup.ts'],
    // Its files import each other without extensions, which Node will not
    // resolve; inlined, Vite does it.
    server: { deps: { inline: ['@material/material-color-utilities'] } },
  },
});
