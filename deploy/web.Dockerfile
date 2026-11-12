# OpenWord's web image: the PWA, the bundled Scripture, the voice and nginx.
#
# Build context is the repository root (docker-compose.yml does this for you):
#
#   docker build -f deploy/web.Dockerfile -t openword-web .
#
# Three stages do the work, and all three run on the *build* machine's own
# architecture (--platform=$BUILDPLATFORM): a Vite build and a voice download
# produce the same bytes whatever CPU runs them, so there is no reason to
# emulate arm64 for them in CI, and on a Pi they are simply native. Only the
# final nginx stage is per-architecture, and it does nothing but copy files.
#
#   build   node:22-alpine  npm ci, copy ../assets in, vite build, precompress
#   voice   alpine          fetch the Kitten voice, verify its SHA-256, unpack
#   final   nginx:1.27      deploy/nginx.conf + the two trees above
#
# On a Pi 4 with 2 GB, budget 10-15 minutes for the first build and about
# 1.5 GB of memory for the node stage: NODE_OPTIONS below caps V8's heap at
# 1536 MB so it fails cleanly rather than taking the machine down. Have
# swap on first if `free -m` shows none (install.sh offers to set it up).

ARG NODE_IMAGE=node:22-alpine
ARG NGINX_IMAGE=nginx:1.27-alpine
ARG ALPINE_IMAGE=alpine:3.20

# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM ${NODE_IMAGE} AS build

ENV NODE_OPTIONS=--max-old-space-size=1536 \
    CI=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false

WORKDIR /src/pwa

# Dependencies first, so a change to src/ does not reinstall them. npm's
# postinstall hook runs scripts/copy-ort.mjs (the ONNX Runtime wasm the
# voice runs on, into public/ort/), so the scripts come along with the
# lockfile.
COPY pwa/package.json pwa/package-lock.json ./
COPY pwa/scripts ./scripts
RUN npm ci --no-audit --no-fund

# The build reads the bundled Scripture, atlas, notes, references, originals,
# fonts and licences from ../assets (scripts/sync-assets.mjs copies them into
# public/assets), so the repository's assets/ sits beside pwa/ as it does in
# the working tree.
COPY assets /src/assets
COPY pwa ./

RUN set -eux; \
    node scripts/sync-assets.mjs; \
    # The icon table is generated from icons.txt and git-ignored, so a fresh
    # clone has none until this runs. Harmless when it already exists.
    if [ -f scripts/gen-icons.mjs ]; then node scripts/gen-icons.mjs; fi; \
    npm run build; \
    # What nginx.conf and the app both rely on. Fail here, not on first visit.
    test -f dist/index.html; \
    test -f dist/sw.js; \
    test -f dist/manifest.webmanifest; \
    test -d dist/assets/bible; \
    test -f dist/ort/ort-wasm-simd-threaded.wasm; \
    test -f dist/version.json; \
    # The voice comes from the stage below, never from a working tree.
    rm -rf dist/voice; \
    # nginx's workers are not root. Files copied from a checkout made under
    # a strict umask would otherwise arrive unreadable and serve as 403s.
    chmod -R a+rX dist

# Pre-compress what compresses, so the Pi spends no CPU on it per request and
# the tunnel carries a third of the bytes (gzip_static in nginx.conf serves
# the .gz sibling when the browser accepts it). Files that are *already*
# compressed, or that the app must receive byte-for-byte, are deliberately
# left alone: the .bib translations, the .gz originals and cross-references
# (the app gunzips those itself), and the voice's .onnx and .bin. If nginx
# ever set Content-Encoding on one of those the browser would unpack it
# early and the app's own gunzip would fail on what was left.
RUN find dist -type f \( \
        -name '*.js'   -o -name '*.mjs'  -o -name '*.css'  -o -name '*.html' -o \
        -name '*.json' -o -name '*.wasm' -o -name '*.ttf'  -o -name '*.otf'  -o \
        -name '*.svg'  -o -name '*.webmanifest' -o -name '*.txt' -o -name '*.xml' \) \
        -exec sh -c 'for f; do gzip -9 -c "$f" > "$f.gz"; done' sh {} + \
    && ! find dist -name '*.gz.gz' -o -name '*.bib.gz' -o -name '*.onnx.gz' -o -name '*.bin.gz' | grep -q .

# ---------------------------------------------------------------------------
# The voice is 63 MB and lives in a GitHub release, not in git. It is fetched
# once per image build, checked against a pinned digest, and only the three
# files the app loads are kept (the archive also carries espeak-ng data the
# PWA does not use: its phonemizer is JavaScript). The directory name is the
# version, which is why nginx.conf may cache /voice/ for a year.
FROM --platform=$BUILDPLATFORM ${ALPINE_IMAGE} AS voice

ARG VOICE_NAME=kitten-nano-en-v0_8-fp32
ARG VOICE_URL=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kitten-nano-en-v0_8-fp32.tar.bz2
ARG VOICE_SHA256=16092117bfe591ddcd58d078e1454603b8e1caea46f85653b2c2efae76bd883e

RUN apk add --no-cache curl tar bzip2
WORKDIR /tmp/voice
RUN set -eux; \
    curl -fsSL --retry 5 --retry-delay 5 -o voice.tar.bz2 "${VOICE_URL}"; \
    echo "${VOICE_SHA256}  voice.tar.bz2" | sha256sum -c -; \
    mkdir -p "/voice/${VOICE_NAME}"; \
    tar -xjf voice.tar.bz2 -C "/voice/${VOICE_NAME}" --strip-components=1 --no-same-owner \
        "${VOICE_NAME}/model.fp32.onnx" \
        "${VOICE_NAME}/voices.bin" \
        "${VOICE_NAME}/tokens.txt" \
        "${VOICE_NAME}/LICENSE"; \
    rm voice.tar.bz2; \
    chmod -R a+rX /voice; \
    test -s "/voice/${VOICE_NAME}/model.fp32.onnx"; \
    test -s "/voice/${VOICE_NAME}/voices.bin"; \
    test -s "/voice/${VOICE_NAME}/tokens.txt"; \
    ls -l "/voice/${VOICE_NAME}"

# ---------------------------------------------------------------------------
FROM ${NGINX_IMAGE}

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/pwa/dist /usr/share/nginx/html
COPY --from=voice /voice /usr/share/nginx/html/voice

# A broken server config should fail the build, not the first `up`.
RUN nginx -t

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1/healthz >/dev/null 2>&1 || exit 1
