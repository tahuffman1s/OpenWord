# The voice

How OpenWord reads aloud in the browser. A neural text-to-speech model, KittenTTS, runs
on a Web Worker with onnxruntime-web — on the graphics processor (WebGPU) where there is
one, on the processor (WebAssembly) where there is not; eSpeak NG, compiled to WebAssembly in the
`phonemizer` package, turns the words into the sounds the model speaks; and the Web
Audio API plays what comes back. Three layers sit on top of each other: the reader
(`src/data/readAloud.ts`) decides what is read and where it has got to, the engine
(`src/data/neuralSpeech.ts`) cuts the text into pieces and keeps them playing end to
end, and this directory holds the two leaves — making the samples, and playing them.

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
  │  onnxruntime-web (webgpu, or wasm): input_ids int64 [1,T], style f32 [1,256], speed f32 [1]
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
  tells the UI once per model. On the machine this was written on,
  single-threaded wasm made 4.2 s of speech in 3.3 s (0.8× real time).
- **Phonemes.** eSpeak runs on the worker where it can. The worker's `ready` reply says
  whether it loaded; if not, `Synthesiser` phonemizes on the main thread and sends the
  phonemes with each request (`speak.phonemes`). In Chromium it loads on the worker.
- **Speed.** The model's metadata gives each speaker a speed prior, which sherpa-onnx (the
  runtime these model files were packaged for) multiplies into the speed it is asked for.
  The engine passes `rate / speaker.prior` and `modelSpeed` multiplies the prior back in
  before the tensor is made, so the prior cancels and 1× is the pace the voice was trained
  at.

## Which backend (`backendChoice.ts`)

The worker is told what to try, in order — `['webgpu', 'wasm']` unless something has been
learnt — and answers with what it ended up on and what it refused, and why.

- **WebGPU** is `onnxruntime-web/webgpu` (the `asyncify` binary under `/ort/`). It is
  passed over where `navigator.gpu` gives no adapter, or one drawn in software.
- **Proving it.** A graphics driver that gets an operation wrong returns silence or
  noise, not an error. The first time on a device the worker synthesises a word on the
  GPU and checks that it is sound (`notSpeech`); every piece after is checked for
  numbers that are not numbers. A failure mid-chapter (`backendFailed`) reloads the
  voice on wasm and goes on from the piece it had reached.
- **A page that dies.** A phone short of memory does not fail the load: iOS ends the
  page. A mark is written to localStorage before a load and wiped when it returns (or
  when the page is left on purpose, `pagehide`); found standing twice, the backend it
  was trying is passed over for a fortnight. With both passed over the voice is not
  offered and the device's own voices read instead.
- **Pace.** Each backend's measured pace is kept; a GPU that falls behind gives way to
  the processor unless the processor has been found slower.

What is learnt is kept per browser version (the user agent), so an update starts afresh.

## Worker protocol (`ttsWorker.ts`)

| In | Out |
|---|---|
| `{type:'load', files:{model: ArrayBuffer, voices: ArrayBuffer, tokens: string}, wasmPaths?, backends?, prove?}` | `{type:'ready', phonemizer: boolean, backend, refused}` or `{type:'error', message}` |
| `{type:'speak', id, text, sid, speed, phonemes?}` | `{type:'audio', id, samples: Float32Array, sampleRate: 24000, ms}`, `{type:'error', id, message, backendFailed?}` or `{type:'cancelled', id}` |
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
`OPENWORD_TTS_HARNESS=1` is set; the dev server serves it regardless. `--webgpu` runs the
model on the graphics processor instead — drawn in software (SwiftShader) on a machine
without one, so many times slower than real time, but through the same shaders — and
`--wasm` on the processor; `--preview` runs any of them against a build.

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
- **iOS Safari.** Safari gives a page no threads here (it does not know
  `credentialless`), so on the processor an iPhone falls behind; WebGPU, which it has
  from iOS 26, is what keeps up, and is tried first. None of this has been run on an
  iPhone by the people who wrote it: it is built to fail safe (see "Which backend")
  rather than known to succeed. The model (57 MB) plus the runtime's arena is a lot for
  a Safari tab; the worker releases the session on `close`, and the files are never held
  on the main thread. eSpeak is given twelve seconds to answer on the worker and fifteen
  on the page, having been reported to hang there. Web Audio needs a user gesture before
  any sound: `src/speech/audio.ts` makes and resumes the shared AudioContext on the first
  tap anywhere on the page, sets `navigator.audioSession.type = 'playback'` while reading
  (so the ring switch does not silence it and the lock screen does not stop it), and
  resumes a context a phone call left "interrupted".
- **Media session.** Lock-screen and headset controls (`src/data/readAloudSession.ts`)
  are active only while the page plays audio; a silent loop at near-zero gain keeps the
  context running between pieces. A web page cannot be an Android Auto or CarPlay app,
  so there is no browsable list on a car's screen; a car's media buttons work like a
  headset's, through the same session.
- **Device voices.** `src/data/webSpeechEngine.ts` wraps `speechSynthesis` for browsers
  that cannot run the model, or when a device voice is chosen. It cannot pause reliably
  (`canPause` is false, so the reader resumes from the word reached), and Chrome's
  15-second cutoff is dodged by speaking one sentence at a time.
