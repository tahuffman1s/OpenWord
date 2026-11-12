# OpenWord API contract

Base path: `/api`. Everything is JSON (`Content-Type: application/json`)
with camelCase field names. Timestamps are RFC 3339 in UTC (fractional
seconds may be present). "Days" are the client's local calendar date as a
`YYYY-MM-DD` string chosen by the client; the server stores and compares
them as strings and never converts them.

All endpoints require authentication unless marked **public**.

## Conventions

### Errors

Every error is

```json
{"error": "code", "message": "Human-readable text."}
```

| Status | `error`             | When |
|--------|---------------------|------|
| 400    | `validation`        | Malformed JSON or a field that fails validation; `message` names the field |
| 401    | `unauthorized`      | Missing, expired or unknown session |
| 401    | `bad_credentials`   | Wrong username/password (login, password change, account deletion) |
| 403    | `invite_required`   | Registration needs a valid `inviteCode` |
| 404    | `not_found`         | No such user/request/achievement, or it is not visible to you |
| 409    | `username_taken`, `email_taken`, `already_friends`, `already_requested` | Conflicts |
| 413    | `too_large`         | Body over the limit (1 MB; 4 MB for avatar and backup) |
| 429    | `rate_limited`      | `/api/auth/*` exceeded 10 requests/minute (burst 20) per IP; `Retry-After: 60` |
| 500    | `internal`          | Server bug or database failure |

Unknown JSON fields are ignored.

### Authentication

`POST /api/auth/register` and `POST /api/auth/login` set the cookie
`ow_session` (HttpOnly, SameSite=Lax, Path=/, 90 days, `Secure` when the
request arrived over HTTPS or with `X-Forwarded-Proto: https`) and also
return the same token in the body. Either the cookie or
`Authorization: Bearer <token>` authenticates later requests. The expiry
slides: a request more than a day after the last extension re-issues the
cookie with a fresh 90-day expiry.

### Types

**User** (your own account; `email` may be `null`)

```json
{
  "id": "302d4c1d-1054-428f-9113-70dc2bc26e88",
  "username": "alice",
  "displayName": "Alice",
  "bio": "",
  "email": "alice@example.com",
  "avatarVersion": 2,
  "avatarUrl": "/api/users/302d4c1d-1054-428f-9113-70dc2bc26e88/avatar?v=2",
  "createdAt": "2026-03-01T10:00:00Z"
}
```

`avatarUrl` is `null` when `avatarVersion` is 0.

**PublicUser** — the same without `email`.

**StreakSnapshot** — the client's own streak model (it has freeze days),
mirrored so friends can see it:

```json
{"current": 12, "best": 40, "freezes": 1, "lastDay": "2026-03-10", "updatedAt": "2026-03-10T07:12:00Z"}
```

**Settings**

```json
{"reminderTime": "07:30", "reminderTz": "Europe/London", "reminderDays": 127, "reminderOnlyIfUndone": true, "friendReminders": true}
```

`reminderTime` is `HH:MM` local time or `null` (off). `reminderTz` is an
IANA zone or `null`. `reminderDays` is a bitmask: Mon=1, Tue=2, Wed=4,
Thu=8, Fri=16, Sat=32, Sun=64 (127 = every day).

**FriendStreak**

```json
{"current": 5, "best": 9, "lastDay": "2026-03-10", "atRisk": false}
```

See [Friend streak definition](#friend-streak-definition).

**Achievement**

```json
{"id": "a3778bcb-…", "kind": "badge", "key": "first_lesson", "title": "First lesson", "detail": "", "earnedAt": "2026-03-01T10:00:00Z"}
```

**Activity kinds**: `learn`, `read`, `plan`, `quiz`, `listen`.
**Achievement kinds**: `badge`, `level`, `streak`, `plan`, `quiz`, `memory`, `friend`.

### Validation rules

| Field | Rule |
|-------|------|
| `username` | 3–24 chars of `a-z 0-9 _`; lowercased on input; unique |
| `password` | ≥ 8 characters (≤ 256 bytes) |
| `displayName` | 1–40 characters after trimming; defaults to the username |
| `bio` | ≤ 160 characters |
| `email` | valid address; lowercased; unique; optional |
| `day` | `YYYY-MM-DD`, a real date |
| `reminderTime` | `HH:MM`, 24-hour |
| `reminderTz` | loadable IANA zone name |
| `reminderDays` | integer 0–127 |

---

## Health

### `GET /healthz` — public

Pings the database (2 s timeout). `200 ok` (text/plain) or `503`.

---

## Auth

### `POST /api/auth/register` — public

```json
{"username": "alice", "password": "correct horse", "displayName": "Alice", "email": "alice@example.com", "inviteCode": "friends-only"}
```

`displayName`, `email` and `inviteCode` are optional (`inviteCode` is
required only when the server has `OPENWORD_INVITE_CODE` set).

`201` + session cookie:

```json
{"user": User, "token": "vn4XY6dCi4UseAC6WvK8fnOBKJ1qn90Irj4Vs0TYI-I"}
```

Errors: `409 username_taken`, `409 email_taken`, `403 invite_required`, `400 validation`.

### `POST /api/auth/login` — public

```json
{"username": "alice", "password": "correct horse"}
```

`username` may be the username or the email address. `200` with the same
body as register. Errors: `401 bad_credentials` (same response and timing
whether the user exists or not).

### `POST /api/auth/logout`

Deletes the session and clears the cookie. `204`. Succeeds even without a
valid session.

---

## Me

### `GET /api/me`

```json
{
  "user": User,
  "settings": Settings,
  "streak": StreakSnapshot | null,
  "counts": {"friends": 3, "pendingRequests": 1}
}
```

`pendingRequests` counts incoming requests.

### `PATCH /api/me`

Any subset of:

```json
{
  "displayName": "Alice W",
  "bio": "Reading through Mark",
  "email": null,
  "reminderTime": "07:30",
  "reminderTz": "Europe/London",
  "reminderDays": 31,
  "reminderOnlyIfUndone": true,
  "friendReminders": false
}
```

Absent fields are left alone. `email` and `reminderTime` accept `null` (or
`""`) to clear; `reminderTz` likewise. `200`:

```json
{"user": User, "settings": Settings}
```

Errors: `400 validation`, `409 email_taken`.

### `POST /api/me/password`

```json
{"current": "old password", "next": "new password"}
```

`204`. Errors: `401 bad_credentials`, `400 validation`. Existing sessions
stay valid.

### `PUT /api/me/avatar`

Body: the raw image bytes with `Content-Type: image/png`, `image/jpeg`,
`image/gif` or `image/webp` (any `image/*`; the bytes are sniffed). Max
4 MB and 24 megapixels. The image is centre-cropped to a square, resized
to 256×256 and stored as JPEG.

`200`:

```json
{"avatarVersion": 3, "avatarUrl": "/api/users/{id}/avatar?v=3"}
```

Errors: `400 validation` (not an image / too many pixels), `413 too_large`.

### `DELETE /api/me/avatar`

`204`. `avatarVersion` returns to 0 and `avatarUrl` to `null`.

### `DELETE /api/me`

```json
{"password": "correct horse"}
```

Deletes the account and everything that references it (sessions,
friendships, requests, activity, streak, achievements, cheers, push
subscriptions, backup, reminder log). `204`. Errors: `401 bad_credentials`.

### Backup

An opaque JSON document the client stores for restore on a new device.

#### `PUT /api/me/backup`

Body: any JSON value, ≤ 4 MB. `200`:

```json
{"updatedAt": "2026-03-10T07:12:00Z", "sizeBytes": 18234}
```

Errors: `400 validation` (not JSON), `413 too_large`.

#### `GET /api/me/backup`

`200` with the stored document as the body (whitespace may be normalised;
JSON semantics are preserved) and the header `X-Backup-Updated-At`.
`404 not_found` when nothing is stored.

#### `DELETE /api/me/backup`

`204`.

---

## Users

### `GET /api/users/{id}/avatar?v=N` — public

The stored JPEG, or `404`. Responds with `ETag: "N"` and, when `v` matches
the current version, `Cache-Control: public, max-age=31536000, immutable`
(otherwise `max-age=60`). Supports `If-None-Match` → `304`. Always use the
`avatarUrl` from a User object so the version is right.

### `GET /api/users/search?q=text`

Prefix match on username, case-insensitive substring match on display
name. Excludes yourself. Up to 20 results, username-prefix matches first.

```json
{"users": [{ ...PublicUser, "relation": "none" | "friend" | "requested" | "incoming"}]}
```

`requested` = you sent them a request; `incoming` = they sent you one.
`400 validation` when `q` is empty or longer than 64 characters.

### `GET /api/users/{username}`

```json
{
  "user": PublicUser,
  "streak": StreakSnapshot | null,
  "friendStreak": FriendStreak | null,
  "achievements": [Achievement, ...],
  "relation": "none" | "friend" | "requested" | "incoming" | "self"
}
```

`friendStreak` is present only when you are friends. `achievements` is
their 20 most recent, newest first; each one also carries `cheers` (a
count) and `cheered` (whether you have cheered it), as a feed item does. `404 not_found` for unknown usernames.

---

## Friends

### `GET /api/friends`

Sorted by display name (then username).

```json
{
  "friends": [
    {
      "user": PublicUser,
      "since": "2026-02-01T18:00:00Z",
      "streak": StreakSnapshot | null,
      "friendStreak": {"current": 5, "best": 9, "lastDay": "2026-03-10", "atRisk": false} | null,
      "lastActiveDay": "2026-03-10" | null
    }
  ]
}
```

`friendStreak` is `null` when the two of you have never shared a learn
day; `lastActiveDay` is their most recent activity day of any kind.

### `GET /api/friends/requests`

```json
{
  "incoming": [{"id": "…", "from": PublicUser, "message": "hey!", "createdAt": "…"}],
  "outgoing": [{"id": "…", "to": PublicUser, "message": "", "createdAt": "…"}]
}
```

Newest first.

### `POST /api/friends/requests`

```json
{"username": "bob", "message": "It's Alice from church"}
```

`message` is optional (≤ 200 characters).

- `201 {"request": {"id", "to": PublicUser, "message", "createdAt"}}` normally.
- `200 {"friend": <friend entry as in GET /api/friends>}` if `bob` had
  already requested you: the two requests cancel out and you become
  friends immediately.
- `404 not_found` unknown username; `400 validation` for yourself;
  `409 already_friends`; `409 already_requested`.

### `POST /api/friends/requests/{id}/accept`

Only the recipient may accept. `200 {"friend": <friend entry>}`.
`404 not_found` otherwise.

### `POST /api/friends/requests/{id}/decline`

Only the recipient. `204`.

### `DELETE /api/friends/requests/{id}`

Cancel your own outgoing request. `204`. `404 not_found` if it is not
yours or no longer exists.

### `DELETE /api/friends/{userId}`

Unfriend. `204`; `404 not_found` if you were not friends.

---

## Activity & streaks

### `POST /api/activity`

```json
{"day": "2026-03-10", "kind": "learn", "count": 1}
```

Upsert, idempotent: `count` (default 1, 0–10000) is kept at the maximum
ever posted for that day/kind. `day` must be within 3 days ahead or 400
days behind "today" in your `reminderTz` (UTC if unset).

`200 {"day": "2026-03-10", "kind": "learn", "count": 1}`

### `GET /api/activity?from=YYYY-MM-DD&to=YYYY-MM-DD`

`to` defaults to today, `from` to 90 days before `to`.

```json
{
  "from": "2026-03-01",
  "to": "2026-03-10",
  "days": [
    {"day": "2026-03-08", "kinds": {"learn": 1, "read": 3}},
    {"day": "2026-03-10", "kinds": {"learn": 1}}
  ]
}
```

Only days with activity appear, ascending.

### `PUT /api/streak`

```json
{"current": 12, "best": 40, "freezes": 1, "lastDay": "2026-03-10"}
```

Replaces your snapshot (`best` is raised to `current` if lower).
`200 {"streak": StreakSnapshot}`.

### `GET /api/streaks`

```json
{
  "streak": StreakSnapshot | null,
  "friendStreaks": [
    {"user": PublicUser, "current": 5, "best": 9, "lastDay": "2026-03-10", "atRisk": false}
  ]
}
```

One entry per friend, in friend-list order.

### Friend streak definition

Let *today* be the current calendar day in your `reminderTz` (UTC if
unset). A **shared day** is a day on which both you and the friend have a
`learn` activity (any count).

- **current**: the number of consecutive shared days counted backwards
  starting from *today* if that is shared, else from *yesterday* if that
  is shared, else 0.
- **lastDay**: the day the current run starts from (today or yesterday),
  or `""` when current is 0.
- **atRisk**: `true` when the run is alive as of yesterday but today is
  not yet shared, i.e. at least one of you has not learned today.
- **best**: the longest run of consecutive shared days within the last
  400 days.

Only the last 400 days are examined.

---

## Achievements feed

### `POST /api/achievements`

```json
{"key": "first_lesson", "kind": "badge", "title": "First lesson", "detail": "Finished Mark 1", "earnedAt": "2026-03-01T10:00:00Z"}
```

`detail` (≤ 400) and `earnedAt` (default now; must not be more than a day
in the future) are optional. `key` (≤ 80) is unique per user:
`201 {"achievement": Achievement}` when created, `200` with the existing
one when the key already exists (fields are not updated).

### `POST /api/achievements/batch`

```json
{"achievements": [ {...}, {...} ]}
```

Up to 500 per call, validated up front (a bad entry rejects the whole
batch with `400`). `200 {"created": 2}` — existing keys are skipped.

### `GET /api/feed?before=<RFC3339>&limit=30`

Achievements of you and all your friends, newest `earnedAt` first.
`limit` 1–100 (default 30). `before` is exclusive; omit it for the first
page.

```json
{
  "items": [
    {
      "id": "a3778bcb-…",
      "user": PublicUser,
      "kind": "badge",
      "key": "first_lesson",
      "title": "First lesson",
      "detail": "",
      "earnedAt": "2026-03-09T10:00:00Z",
      "cheers": 2,
      "cheered": false,
      "mine": true
    }
  ],
  "nextBefore": "2026-03-09T10:00:00Z" | null
}
```

Pass `nextBefore` as `before` for the next page; `null` means the end.
(Items sharing the exact same `earnedAt` across a page boundary may be
skipped; clients that post with distinct timestamps are unaffected.)

### `POST /api/feed/{id}/cheer`

Only for items by you or a friend. Idempotent. `200 {"cheers": 3, "cheered": true}`.
`404 not_found` otherwise.

### `DELETE /api/feed/{id}/cheer`

`200 {"cheers": 2, "cheered": false}`.

---

## Push & reminders

### `GET /api/push/vapid` — public

```json
{"publicKey": "BNQWuzcweRYwVRYm1udMRg3Z3_0BN8YwxgJsrEQJaOY3uSZ9…"}
```

Use as `applicationServerKey` (base64url) in `pushManager.subscribe`.

### `POST /api/push/subscriptions`

The `PushSubscription.toJSON()` shape:

```json
{"endpoint": "https://fcm.googleapis.com/fcm/send/…", "keys": {"p256dh": "BNcRd…", "auth": "tjVn…"}}
```

`201 {"id": "…", "createdAt": "…"}`. Re-posting an endpoint (even from
another account) re-assigns it to the caller and resets its failure count.

### `DELETE /api/push/subscriptions`

```json
{"endpoint": "https://fcm.googleapis.com/fcm/send/…"}
```

`204` (also when the endpoint was not registered).

### `POST /api/push/test`

Sends `{"title":"OpenWord","body":"Push notifications are working.","url":"/","tag":"test"}`
to all of your subscriptions. `200 {"sent": 2}` — the number the push
service accepted.

### Notification payload

Every push carries a JSON body the service worker should display:

```json
{"title": "OpenWord", "body": "Today's lesson is waiting — keep your streak going.", "url": "/learn", "tag": "daily"}
```

`url` is absolute when the server knows its public URL. Tags: `daily`,
`friend`, `test`.

### Reminder schedule

- **Daily**: on each weekday enabled in `reminderDays`, at `reminderTime`
  in `reminderTz` (within a 5-minute window), unless `reminderOnlyIfUndone`
  is on and a `learn` activity exists for that local day. At most once per
  local day.
- **Friend**: at 19:30 local (same zone; UTC if unset) for users with
  `friendReminders` on who have no `learn` today and at least one friend
  streak that is `atRisk`: *"Your streak with {displayName} is at risk"*
  (with "and N more" when several). At most once per local day.

Subscriptions that the push service answers with 404/410 are removed
automatically; after 20 consecutive other failures a subscription is also
dropped.
