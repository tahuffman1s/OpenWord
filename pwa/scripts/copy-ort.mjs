// Copies the ONNX Runtime WebAssembly build the voice runs on out of
// node_modules into public/ort/, where the deployment serves it as static
// files and the worker finds it at /ort/ (see src/speech/ttsWorker.ts).
//
// Run from npm's postinstall and prebuild hooks; safe to run again. The
// files are git-ignored, like the voice itself.
import { copyFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const source = join(root, 'node_modules', 'onnxruntime-web', 'dist');
const target = join(root, 'public', 'ort');

// The plain build runs the voice on the processor; the asyncify one is the
// same runtime with its WebGPU kernels, for the graphics processor.
const files = [
  'ort-wasm-simd-threaded.wasm',
  'ort-wasm-simd-threaded.mjs',
  'ort-wasm-simd-threaded.asyncify.wasm',
  'ort-wasm-simd-threaded.asyncify.mjs',
];

if (!existsSync(source)) {
  console.error(`copy-ort: ${source} is missing; run npm install first`);
  process.exit(1);
}
mkdirSync(target, { recursive: true });
for (const name of files) {
  const from = join(source, name);
  const to = join(target, name);
  if (existsSync(to) && statSync(to).size === statSync(from).size) continue;
  copyFileSync(from, to);
  console.log(`copy-ort: ${name} -> public/ort/`);
}
