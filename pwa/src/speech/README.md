# The voice

How OpenWord reads aloud in the browser: the port of `lib/src/data/neural_speech.dart`,
with sherpa-onnx and audioplayers swapped for a Web Worker running onnxruntime-web and
the Web Audio API. The reader (`src/data/readAloud.ts`) and the engine
(`src/data/neuralSpeech.ts`) keep the Dart's structure and names; only the two leaf
layers — making the samples, and playing them — are new.

## The pipeline

```
text (a piece: one sentence or less, see NeuralSpeechEngine.pieces)
  │  main thread: Synthesiser.say → postMessage {type:'speak'}
  ▼
ttsWorker.ts
  │  phonemes.ts: clauses() → phonemize() (eSpeak NG, WASM) → joinPhonemes()
  │     "həlˈoʊ, wˈɜːld. hˈaʊ ɑːɹ juː?"   — punctuation put back, the model pauses on it
  │  kitten.ts: tokenIds() → [0, …ids…, 10, 0]; styleRow() = content tokens, max 399
  │             styleVector(voices.bin, speaker, row); modelSpeed() = rate (prior cancels)
  │  onnxruntime-web (wasm, 1 thread): input_ids int64 [1,T], style f32 [1,256], speed f32 [1]
  │     → waveform f32 [N] at 24 kHz
  │  kitten.ts: trimSilence() → levelled() → limited()
  ▼
  postMessage {type:'audio', samples (transferred), sampleRate, ms}
  │  main thread: Reading._load → AudioBuffer; AudioBufferSourceNode.start(at the end of
  │  the piece before); onProgress(offset) when it is heard; pause = AudioContext.suspend()
  ▼
speakers
```

- **Pieces.** The reader hands the engine the rest of the chapter at once (it `canPause`,
  so `ReadAloud` sets no passage limit). `NeuralSpeechEngine.pieces` cuts it at sentence
  ends and verse starts, the first piece short (40 chars) so speech starts at once, growing
  to 160. Three pieces are made ahead of the one being heard; the next is scheduled on the
  audio clock to begin exactly when the current one ends, so there is no gap unless the
  model falls behind.
- **Falling behind.** The worker reports how long each piece took; `Synthesiser` smooths
  `took / lasts` and after four pieces calls it `fallingBehind` above 1.05. `NeuralVoices`
  tells the UI once per model, as the Dart does. On the machine this was written on,
  single-threaded wasm made 4.2 s of speech in 3.3 s (0.8× real time).
- **Phonemes.** eSpeak runs on the worker where it can. The worker's `ready` reply says
  whether it loaded; if not, `Synthesiser` phonemizes on the main thread and sends the
  phonemes with each request (`speak.phonemes`). In Chromium it loads on the worker.
- **Speed.** The engine passes `rate / speaker.prior` exactly as the Dart does for
  sherpa-onnx, and `modelSpeed` multiplies the prior back in before the tensor is made, so
  1× is the pace the voice was trained at and the two apps sound the same.

## Worker protocol (`ttsWorker.ts`)

| In | Out |
|---|---|
| `{type:'load', files:{model: ArrayBuffer, voices: ArrayBuffer, tokens: string}, wasmPaths?}` | `{type:'ready', phonemizer: boolean}` or `{type:'error', message}` |
| `{type:'speak', id, text, sid, speed, phonemes?}` | `{type:'audio', id, samples: Float32Array, sampleRate: 24000, ms}`, `{type:'error', id, message}` or `{type:'cancelled', id}` |
| `{type:'cancel', id}` | `{type:'cancelled', id}` if it had not begun |
| `{type:'close'}` | — (frees the session, closes the worker) |

The worker serves one request at a time, in order. `Synthesiser` on the main thread keeps
its own queue and sends one at a time too, so a skip can drop requests before they are
sent (`forget(owner)`).

## The model files

`NeuralVoices` (`src/data/neuralVoices.ts`) fetches
`/voice/kitten-nano-en-v0_8-fp32/{model.fp32.onnx, voices.bin, tokens.txt}` on first use,
with progress through the notifier (`progress.received / total`, for "Getting the
voice… 34%"), and keeps them in Cache Storage under `openword-voice`. Each worker is handed
fresh buffers read from the cache (transferred, not copied), so the 60 MB is never held
twice.

To refresh the model files: they are the sherpa-onnx packaging of KittenML's
`kitten-tts-nano-0.8-fp32` (`model.fp32.onnx` metadata: `start_id=0, end_id=10, pad_id=0,
add_pad_after_end=1, style_dim=400×256, n_speakers=8, speaker_speed_priors=…`). Put the
three files in `public/voice/kitten-nano-en-v0_8-fp32/` (git-ignored; the Docker build
fetches them) and copy `tokens.txt` into `test/fixtures/`. If the metadata changes, update
`kittenMeta` in `kitten.ts` and the test. The ONNX Runtime wasm comes from
`node_modules/onnxruntime-web/dist` into `public/ort/` via `scripts/copy-ort.mjs`
(`postinstall`/`prebuild`); the worker fetches `/ort/ort-wasm-simd-threaded.wasm` and
carries its own JS loader (the `.mjs` is copied too, for a non-bundled ORT build).

## Proving it

`npm run tts:smoke` (`scripts/tts-smoke.mjs`) starts Vite, opens `tts-harness.html` in
headless Chromium, synthesises Genesis 1:1 with Bella and checks the duration (2–6 s) and
the RMS (> 0.01), printing the synthesis time. `vite build` leaves the harness out unless
`OPENWORD_TTS_HARNESS=1` is set; the dev server serves it regardless.

## Caveats

- **Threads.** onnxruntime-web uses one thread unless the page is cross-origin isolated.
  `deploy/nginx.conf` and the Vite dev and preview servers send the COOP/COEP headers
  for it, and `numThreads` is chosen from `crossOriginIsolated` at load (up to four).
  Threads make speech about a third faster. Where a browser is not isolated (Safari
  does not know `credentialless`), one thread is a little under real time on a laptop
  and may fall behind on an old phone, which the UI is told of.
- **The loader in a build.** With threads the runtime starts its workers from its
  loader's own URL. Bundled into `ttsWorker`, that URL is the worker itself and the
  first run never returns, so a production build points `wasmPaths.mjs` at the copy
  under `/ort/`. Test any change here against `vite preview`, not only `vite`.
- **Getting started quickly.** The voice files and the runtime are fetched in the
  background a few seconds after launch (not on a metered or data-saving connection),
  the model is not run once "to warm it" while someone is waiting to hear, and a
  reader who has listened before has the model loaded as the app opens.
- **iOS Safari.** The model (57 MB) plus the runtime's arena is a lot for a Safari tab;
  the worker releases the session on `close`, and the files are never held on the main
  thread. Web Audio there needs a user gesture before any sound: `src/speech/audio.ts`
  makes and resumes the shared AudioContext on the first tap anywhere on the page.
- **Media session.** Lock-screen and headset controls (`src/data/readAloudSession.ts`)
  are active only while the page plays audio; a silent loop at near-zero gain keeps the
  context running between pieces. Android Auto / CarPlay listing (car.dart) is not
  possible for a web page and is not ported.
- **Device voices.** `src/data/webSpeechEngine.ts` wraps `speechSynthesis` for browsers
  that cannot run the model, or when a device voice is chosen. It cannot pause reliably
  (`canPause` is false, so the reader resumes from the word reached), and Chrome's
  15-second cutoff is dodged by speaking one sentence at a time.
