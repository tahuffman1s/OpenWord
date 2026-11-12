#!/usr/bin/env bash
# Checks a running OpenWord stack from the outside, the way a browser would
# meet it: the app's shell, the files it keeps for offline use, the voice,
# the headers the voice's threads depend on, and the API through nginx with
# the database behind it.
#
#   deploy/smoke.sh                        http://localhost:8080
#   deploy/smoke.sh https://openword.example
#
# CI runs this against the two images it has just built, before it
# publishes them. It is as happy against a Pi: nothing here changes
# anything but one throwaway account, which it deletes again.
set -euo pipefail

BASE=${1:-http://localhost:8080}
BASE=${BASE%/}
jar=$(mktemp)
body=$(mktemp)
trap 'rm -f "$jar" "$body"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

# status PATH -> the HTTP status of a GET
status() { curl -s -o /dev/null -w '%{http_code}' "$BASE$1"; }
# header PATH NAME -> one response header's value, lower-cased name
header() {
  curl -sI "$BASE$1" | tr -d '\r' | awk -v n="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" \
    'BEGIN{FS=": "} tolower($1)==n {sub(/^[^:]*: /,""); print; exit}'
}
expect_status() { # PATH WANT WHAT
  local got; got=$(status "$1")
  if [ "$got" = "$2" ]; then ok "$3"; else bad "$3 (wanted $2, got $got from $1)"; fi
}
expect_header() { # PATH NAME PATTERN WHAT
  local got; got=$(header "$1" "$2")
  if printf '%s' "$got" | grep -Eq "$3"; then ok "$4"; else bad "$4 ($2 was '${got:-absent}' on $1)"; fi
}

echo "Smoke test of $BASE"

echo "The app"
expect_status /healthz 200 "the web server answers its health check"
expect_status / 200 "the app's shell is served"
expect_header / content-type 'text/html' "the shell is HTML"
expect_status /sw.js 200 "the service worker is there"
expect_header /sw.js cache-control 'no-cache|no-store' "the service worker is never cached stale"
expect_status /manifest.webmanifest 200 "the manifest is there"
expect_header /manifest.webmanifest content-type 'manifest\+json' "the manifest has its own type"
expect_status /manifest-dark.webmanifest 200 "so is the dark one"
expect_status /version.json 200 "the build says which version it is"
expect_status /icons/Icon-512.png 200 "the app's icon is there"
expect_status /some/deep/link 200 "a link into the app gets the shell"

echo "What it keeps for offline"
for f in bible/eng-web.bib bible/eng-bsb.bib bible/eng-gb-webbe.bib maps/atlas.json.gz \
         notes/book-intros-eng.json.gz refs/xrefs.owx.gz strongs/originals.ows.gz fonts/Literata-Regular.ttf; do
  expect_status "/assets/$f" 200 "assets/$f"
done
# The app unpacks these itself; a server that unpacked them first would
# hand it plain bytes it then fails to gunzip.
enc=$(curl -sI -H 'Accept-Encoding: gzip' "$BASE/assets/bible/eng-web.bib" | tr -d '\r' | grep -i '^content-encoding' || true)
if [ -z "$enc" ]; then ok "a .bib goes out as it is, not re-encoded"; else bad "a .bib was sent with $enc"; fi
expect_status /assets/bible/no-such.bib 404 "a missing file is a 404, not the shell"

echo "The voice"
voice=/voice/kitten-nano-en-v0_8-fp32
expect_status "$voice/model.fp32.onnx" 200 "the model"
expect_status "$voice/model.fp32.onnx.bin" 200 "the model under the name Cloudflare caches"
size=$(header "$voice/model.fp32.onnx.bin" content-length)
if [ "${size:-0}" -gt 50000000 ]; then ok "the model is whole (${size} bytes)"; else bad "the model is ${size:-0} bytes"; fi
expect_status "$voice/voices.bin" 200 "the speakers"
expect_status "$voice/tokens.txt" 200 "the tokens"
expect_status /ort/ort-wasm-simd-threaded.wasm 200 "the runtime's WebAssembly"
expect_status /ort/ort-wasm-simd-threaded.mjs 200 "the runtime's loader"
expect_header /ort/ort-wasm-simd-threaded.wasm content-type 'application/wasm' "WebAssembly has its type"
part=$(curl -s -o /dev/null -w '%{http_code}' -H 'Range: bytes=0-1023' "$BASE$voice/model.fp32.onnx")
if [ "$part" = 206 ]; then ok "the model answers a range request"; else bad "a range request got $part"; fi
expect_header / cross-origin-opener-policy 'same-origin' "the page is isolated (opener)"
expect_header / cross-origin-embedder-policy 'credentialless|require-corp' "the page is isolated (embedder), so the voice has threads"

echo "The API, through nginx, with the database behind it"
expect_status /api/push/vapid 200 "the API answers"
expect_status /api/me 401 "and knows a stranger"
expect_status /api/no-such-thing 404 "an unknown route is a 404 from the API, not the shell"
user="smoke$(date +%s)$RANDOM"
pw="smoke-test-$RANDOM-$RANDOM"
code=$(curl -s -o "$body" -w '%{http_code}' -c "$jar" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$user\",\"password\":\"$pw\",\"displayName\":\"Smoke Test\"}" "$BASE/api/auth/register")
case "$code" in
  201)
    ok "an account can be made (the database is there and migrated)"
    code=$(curl -s -o "$body" -w '%{http_code}' -b "$jar" "$BASE/api/me")
    if [ "$code" = 200 ] && grep -q "\"$user\"" "$body"; then ok "its session is kept"; else bad "the session was not kept ($code)"; fi
    code=$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" -H 'Content-Type: application/json' \
      -X PUT -d '{"current":1,"best":1,"freezes":0,"lastDay":"2026-01-01"}' "$BASE/api/streak")
    if [ "$code" = 200 ]; then ok "it can write"; else bad "a write got $code"; fi
    code=$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" -H 'Content-Type: application/json' \
      -X DELETE -d "{\"password\":\"$pw\"}" "$BASE/api/me")
    if [ "$code" = 204 ]; then ok "and is deleted again"; else bad "the test account $user was not deleted ($code)"; fi
    ;;
  403)
    # An instance that asks for an invite code: the API and its database
    # answered, which is what this is here to find out.
    ok "registration is invite-only here; the API refused politely"
    ;;
  *) bad "making an account got $code: $(head -c 200 "$body")" ;;
esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
