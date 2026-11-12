# OpenWord API

The backend for the OpenWord PWA: accounts, friends, streaks, an
achievements feed, Web Push reminders and an opaque per-user backup blob.
It is one static Go binary in front of Postgres, sized for a Raspberry Pi 4
with 2 GB of RAM.

The HTTP contract lives in [`../docs/api.md`](../docs/api.md).

## Layout

```
cmd/openword-api/        main: config, DB, migrations, HTTP server, workers
internal/config/         environment variables
internal/db/             pgxpool + embedded SQL migrations (migrations/*.sql)
internal/store/          the Store interface
internal/store/pgstore/  Postgres implementation
internal/store/memstore/ in-memory implementation (tests)
internal/store/storetest/conformance suite both implementations pass
internal/handlers/       HTTP routing, middleware, sessions, endpoints
internal/auth/           argon2id password hashing, session tokens
internal/validate/       input rules
internal/streaks/        friend-streak computation
internal/push/           VAPID keys, Web Push sending, subscription pruning
internal/reminders/      the once-a-minute reminder scheduler
internal/images/         avatar decoding / cropping / JPEG encoding
internal/ratelimit/      per-IP token bucket for /api/auth/*
internal/httpx/          JSON helpers and the error envelope
```

## Running locally

You need Go 1.24+ and a Postgres 13+ (for `gen_random_uuid()`).

```sh
# 1. A throwaway Postgres.
docker run -d --name openword-pg -p 5432:5432 \
  -e POSTGRES_USER=openword -e POSTGRES_PASSWORD=openword -e POSTGRES_DB=openword \
  postgres:16-alpine

# 2. The API. Migrations run on start; VAPID keys are generated on first
#    start and kept in the server_keys table.
cd server
DATABASE_URL='postgres://openword:openword@localhost:5432/openword?sslmode=disable' \
LISTEN=:8080 \
go run ./cmd/openword-api

# 3. Poke it.
curl localhost:8080/healthz
curl -X POST localhost:8080/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"password123"}'
```

### Environment

| Variable               | Required | Default | Meaning |
|------------------------|----------|---------|---------|
| `DATABASE_URL`         | yes      |         | Postgres URL, e.g. `postgres://user:pass@host:5432/db?sslmode=disable` |
| `LISTEN`               | no       | `:8080` | Address to listen on |
| `OPENWORD_INVITE_CODE` | no       | (open)  | When set, `POST /api/auth/register` requires `inviteCode` to match |
| `OPENWORD_PUBLIC_URL`  | no       |         | Public origin, e.g. `https://openword.example`. Makes push payload links absolute; used as the VAPID subject if no admin email |
| `OPENWORD_ADMIN_EMAIL` | no       |         | VAPID subject `mailto:`; push services may use it to contact you |
| `TRUST_PROXY`          | no       | `1`     | Honour `X-Forwarded-For` (first hop) and `X-Forwarded-Proto` from nginx/cloudflared. Set `0` if the API is exposed directly |
| `LOG_LEVEL`            | no       | `info`  | `debug`, `info`, `warn` or `error`; JSON lines on stdout |

Everything the server generates (VAPID keys) is stored in Postgres, so a
container can be replaced freely; only the database is state.

### Tests

```sh
go vet ./... && go test ./...
```

The handler tests run against the in-memory store, so no database is
needed. To also run the store conformance suite against a real Postgres
(it truncates tables, so use a scratch database):

```sh
TEST_DATABASE_URL='postgres://openword:openword@localhost:5432/openword_test?sslmode=disable' \
go test ./internal/store/pgstore/
```

## Docker

```sh
# Native build
docker build -t openword-api server

# Multi-arch for a Pi (from an x86 machine)
docker buildx build --platform linux/arm64,linux/amd64 -t you/openword-api --push server

docker run -d --name openword-api -p 8080:8080 \
  -e DATABASE_URL='postgres://openword:openword@openword-pg:5432/openword?sslmode=disable' \
  -e OPENWORD_PUBLIC_URL='https://openword.example' \
  -e OPENWORD_INVITE_CODE='friends-only' \
  openword-api
```

The image is Alpine with `ca-certificates` (push endpoints are HTTPS),
`tzdata` (reminders are evaluated in each user's time zone) and `wget` for
`HEALTHCHECK`. It runs as a non-root user and listens on 8080. Put nginx or
cloudflared in front for TLS; the API marks its cookie `Secure` whenever
`X-Forwarded-Proto: https` arrives.

## How sessions work

Register/login return the user and set an `ow_session` cookie (HttpOnly,
SameSite=Lax, Path=/, 90 days, Secure behind HTTPS). The same token is also
returned in the body so non-browser clients can send
`Authorization: Bearer <token>`. Only the SHA-256 of the token is stored.
Expiry slides: any authenticated request made more than a day after the
last extension pushes the expiry out another 90 days and re-sets the
cookie. Expired rows are swept hourly.

## How reminders work

A goroutine ticks at the top of every minute. It loads every user who has
at least one push subscription and either a daily reminder configured or
friend reminders enabled, converts "now" to that user's `reminderTz`
(UTC if unset) and checks two things:

**Daily reminder.** Due when the local weekday's bit is set in
`reminderDays` (Mon=1, Tue=2, Wed=4, Thu=8, Fri=16, Sat=32, Sun=64) and the
local time is within five minutes after `reminderTime` (the window means a
slow tick or a short restart does not lose the day). If
`reminderOnlyIfUndone` is on and a `learn` activity already exists for the
local day, nothing is sent. Otherwise a `reminder_log (user, day, 'daily')`
row is claimed and the push goes out:

```json
{"title":"OpenWord","body":"Today's lesson is waiting — keep your streak going.","url":"/learn","tag":"daily"}
```

**Friend reminder.** At local 19:30 (same window), for users with
`friendReminders` on who have no `learn` activity today: every friend
streak is computed, and if any is *at risk* (alive as of yesterday but one
of the two has not learned today) one push is sent, logged as
`(user, day, 'friend')`:

```json
{"title":"OpenWord","body":"Your streak with Bob is at risk","url":"/learn","tag":"friend"}
```

Because the log is keyed by the user's local day, each kind is sent at
most once per day even if several API instances run. Subscriptions that the
push service answers with 404 or 410 are deleted; other failures increment
`failures`, and a subscription is dropped after 20 consecutive failures.
`url` is made absolute with `OPENWORD_PUBLIC_URL` when that is set.

"Days" everywhere are the client's local calendar date as `YYYY-MM-DD`; the
server never converts them. It only uses `reminderTz` to decide what
"today" is for reminders, friend streaks and for sanity-checking posted
activity days.

## Memory notes for the Pi

- argon2id uses 64 MB per hash, for ~150 ms. Logins are rate limited
  (10/min, burst 20 per IP) so a flood cannot pin memory.
- The pgx pool is capped at 8 connections.
- Avatars are decoded only after checking the header: anything over 24 MP
  or 4 MB is rejected before allocation. Stored avatars are 256×256 JPEGs
  (~15–30 KB).
- Backups are capped at 4 MB of JSON per user and stored as `jsonb`.
