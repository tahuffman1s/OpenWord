import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
import { VitePWA } from 'vite-plugin-pwa';
import { fileURLToPath } from 'node:url';

// The bundled Scripture, atlas, notes, references and originals are
// precached so the app is whole offline; the voice (57 MB) is fetched the
// first time Listen is used and kept in Cache Storage by the worker's
// runtime cache (see src/sw.ts).
export default defineConfig({
  plugins: [
    preact(),
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
        globIgnores: ['voice/**', '**/*.map'],
        maximumFileSizeToCacheInBytes: 12 * 1024 * 1024,
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
  server: { port: 5173, host: true },
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts', 'test/**/*.test.tsx'],
    setupFiles: ['test/setup.ts'],
  },
});
