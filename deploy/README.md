# OpenWord on a Raspberry Pi

This directory puts OpenWord on a machine of your own: the app, its
accounts and friends, and the voice, all served from a Raspberry Pi 4 with
2 GB of memory. It works the same on any 64-bit Linux box with Docker.

```sh
curl -fsSL https://raw.githubusercontent.com/tahuffman1s/OpenWord/main/deploy/install.sh | bash
```

Run it as your normal user, not root. It asks a few questions, builds for a
while, and prints the address the app is at.

- [What you need](#what-you-need)
- [What the one-liner does](#what-the-one-liner-does)
- [Putting it on your domain with Cloudflare Tunnel](#putting-it-on-your-domain-with-cloudflare-tunnel)
- [LAN-only, without Cloudflare](#lan-only-without-cloudflare)
- [Installer options](#installer-options)
- [Day to day: the `openword` command](#day-to-day-the-openword-command)
- [Updating](#updating)
- [Backups and restoring](#backups-and-restoring)
- [Logs](#logs)
- [What it costs](#what-it-costs)
- [Settings](#settings)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Doing it by hand](#doing-it-by-hand)
- [How the files are served](#how-the-files-are-served)
- [Uninstalling](#uninstalling)

## What you need

- A **Raspberry Pi 4 Model B (2 GB or more)**, a Pi 5, or any x86-64
  machine.
- **64-bit Raspberry Pi OS** (or Debian, Ubuntu). The images are built for
  `linux/arm64` and `linux/amd64` only. If `uname -m` prints `armv7l` you
  have the 32-bit OS: re-flash with the 64-bit one from Raspberry Pi Imager.
  The installer checks and stops with this explanation.
- About **4 GB of free disk**. An SSD over USB is kinder than an SD card to
  a database, but either works.
- For a public address: a **domain whose DNS is on Cloudflare** (the free
  plan is enough). Without one, see [LAN-only](#lan-only-without-cloudflare).

You do not need to forward a port on your router or have a static address.

## What the one-liner does

In order, and it is safe to run again at any time (a second run updates):

1. Refuses to run as root, checks the OS is 64-bit.
2. Installs `git` and Docker if they are missing (Docker through
   `get.docker.com`) and adds you to the `docker` group. If it had to add
   you, it uses `sudo docker` for this run and tells you to log out and in.
3. Clones this repository into `~/openword` (or updates it).
4. Creates `deploy/.env`: generates a database password, then asks for a
   Cloudflare tunnel token, the public address, and an optional invite
   code.
5. On a machine with about 2 GB of memory and little swap, offers to create
   a 1 GB swapfile, because building the web image wants about 1.5 GB.
6. Builds the two images, one after the other, and starts everything.
   **Allow 10 to 15 minutes the first time on a Pi 4.** Later builds reuse
   most of the work.
7. Waits until the database, the API and the web server report healthy, and
   until `cloudflared` has connected.
8. Installs `/usr/local/bin/openword`, a small command for the things you
   will do afterwards.

What ends up running:

```
                        Cloudflare  (HTTPS, your domain)
                             ^
                             |  outbound connection only
  +--------------------------|---------------------------------------+
  |  Raspberry Pi            |                 docker network        |
  |                    cloudflared                                   |
  |                          |                                       |
  |                          v                                       |
  |   web  (nginx)  ---- the app, Scripture, the voice: static files |
  |     |                                                            |
  |     |  /api/                                                     |
  |     v                                                            |
  |   api  (Go)  ---- accounts, friends, streaks, push, backups      |
  |     |                                                            |
  |     v                                                            |
  |   db   (Postgres 16)  ---- volume: openword-db                   |
  +------------------------------------------------------------------+
```

No container publishes a port in this arrangement. The only way in is the
tunnel, and the tunnel is a connection the Pi makes outwards.

| File | What it is |
| --- | --- |
| `install.sh` | the one-liner |
| `docker-compose.yml` | the four services |
| `docker-compose.lan.yml` | overlay: publish `web` on a port instead of using the tunnel |
| `docker-compose.prebuilt.yml` | overlay: pull images from ghcr.io instead of building |
| `web.Dockerfile` | builds the app, fetches and checks the voice, bakes both into nginx |
| `nginx.conf` | how the files are served and `/api/` is proxied |
| `.env.example` | every setting, commented |
| `backup.sh`, `restore.sh` | database dump and reload |

The API's own image is `../server/Dockerfile`.

## Putting it on your domain with Cloudflare Tunnel

You do this once, in a browser, before or during the install. Cloudflare
moves its menus around from time to time; the names below are the ones to
look for, and where two names are given the second is the newer one.

**1. Have a domain on Cloudflare.** In the Cloudflare dashboard your domain
should be listed and "Active". If your domain is registered elsewhere, add
it to Cloudflare first (Add a site / Onboard a domain) and point its
nameservers where Cloudflare tells you.

**2. Open Zero Trust.** From the dashboard's left-hand menu choose **Zero
Trust**. The first time, it asks you to pick a team name (any name) and a
plan: the **Free** plan is the one you want. It may ask for a payment
method even for Free.

**3. Create the tunnel.** In Zero Trust go to **Networks -> Tunnels** (on
newer dashboards: **Networks -> Connectors -> Cloudflare Tunnels**) and
press **Create a tunnel**.

- Connector type: **Cloudflared**.
- Name: anything, for example `openword-pi`. Save.

**4. Copy the token.** The next page, "Install and run a connector", shows
commands for different systems. You do not run any of them: the installer
runs `cloudflared` for you in a container. What you need is the long string
after `--token` in any of those commands. It starts with `eyJ` and is
around 180 characters. Copy just that string.

Treat it as a password. Anyone holding it can run your tunnel.

**5. Give the tunnel a public hostname.** Press Next to reach **Public
Hostnames** (newer dashboards: **Published application routes**), then add
one:

| Field | Value |
| --- | --- |
| Subdomain | what you like, e.g. `bible` (or leave empty for the bare domain) |
| Domain | your domain, from the list |
| Path | leave empty |
| Service type | `HTTP` |
| URL | `web:80` |

That last line is the one people get wrong. `web` is the name of the nginx
container on the Pi's Docker network, which is where `cloudflared` runs, so
it is reachable under that name. It is **not** `localhost`, and it is
`HTTP`, not HTTPS: the connection from Cloudflare to your Pi is already
inside the encrypted tunnel, and HTTPS for your visitors is handled by
Cloudflare. Save.

Cloudflare creates the DNS record for the hostname itself.

**6. Run the installer** (or `openword configure` if it is already
installed) and paste:

- the token, when asked for it (it is not shown as you paste);
- the public address: `https://` + the hostname from step 5, for example
  `https://bible.example.org`.

When it finishes, the tunnel's status in the dashboard turns to
**Healthy**, and the address opens the app.

If you would rather not paste a secret into a prompt, put it in
`deploy/.env` yourself (`TUNNEL_TOKEN=...`, `OPENWORD_PUBLIC_URL=...`) and
run `openword restart`.

## LAN-only, without Cloudflare

Press Enter at the token question (or pass `--lan`) and the installer
publishes the web server on port 8080 of the Pi instead:

```
http://<the Pi's address>:8080
```

This is useful for trying it out, and it has real limits, all of them
because browsers only trust `https://` (and `localhost`):

- **No install-to-home-screen and no offline mode.** The service worker
  that provides both will not register over plain `http://` from another
  device.
- **No push notifications**, for the same reason.
- **Sign-in cookies are not marked `Secure`**, and travel in the clear on
  your network.

Reading and search work. Anything else that needs a secure context may
not. To move to a tunnel later run `openword configure`.

To change the port, set `OPENWORD_PORT` in `deploy/.env` and run
`openword restart`, or re-run the installer with `OPENWORD_PORT=9000`.

## Installer options

Environment variables go in front of `bash`, on the right-hand side of the
pipe:

```sh
curl -fsSL https://raw.githubusercontent.com/tahuffman1s/OpenWord/main/deploy/install.sh \
  | OPENWORD_PREBUILT=1 bash
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `OPENWORD_BRANCH` | `main` | branch to install |
| `OPENWORD_DIR` | `~/openword` | where the checkout lives |
| `OPENWORD_PREBUILT` | empty | `1` pulls ready-made images instead of building (below) |
| `OPENWORD_VERSION` | `latest` | which image tag to pull when prebuilt, e.g. `v2.0.0` |
| `OPENWORD_SKIP_SWAP` | empty | `1` never creates a swapfile |
| `OPENWORD_NONINTERACTIVE` | empty | `1` asks nothing; see below |

Flags go after `bash -s --`:

```sh
curl -fsSL .../install.sh | bash -s -- --lan
```

`--lan` (no tunnel; drops a stored token), `--reconfigure` (ask the
questions again), `--prebuilt`, `--branch NAME`, `--dir PATH`,
`--allow-root`, `--help`.

**Prebuilt images.** Every release tag, GitHub Actions builds both images
for arm64 and amd64 and pushes them to `ghcr.io/tahuffman1s/openword-web`
and `openword-api` (`.github/workflows/deploy-images.yml`). With
`OPENWORD_PREBUILT=1` the Pi pulls those instead of building: a few
minutes rather than fifteen, and no need for swap. This only works once a
release has been published and the two packages have been made public.

**Unattended.** With `OPENWORD_NONINTERACTIVE=1` (or with no terminal at
all) nothing is asked and settings come from the environment:

```sh
curl -fsSL .../install.sh | OPENWORD_NONINTERACTIVE=1 \
  TUNNEL_TOKEN=eyJ... OPENWORD_PUBLIC_URL=https://bible.example.org \
  OPENWORD_INVITE_CODE=grace-2026 OPENWORD_ADMIN_EMAIL=you@example.org bash
```

Leave `TUNNEL_TOKEN` out for a LAN install. In this mode a swapfile is
created without asking when the machine is short of memory.

**From a checkout.** `bash deploy/install.sh` run from a clone installs
that clone where it is, and leaves its git state alone.

## Day to day: the `openword` command

```
openword update              pull the latest version, rebuild, restart
openword status              what is running and how much memory it uses
openword logs [service]      follow the logs (web, api, db, cloudflared)
openword backup              dump the database to deploy/backups/
openword restore <file>      load a dump back in
openword restart | stop | start
openword psql                a psql shell on the database
openword configure           ask the setup questions again
openword url                 print the address
openword uninstall           stop everything; optionally delete data
```

It is a short shell script; it changes into `~/openword/deploy` and runs
`docker compose` with the right files for your install (tunnel or LAN,
built or prebuilt), which it works out from `deploy/.env`.

Everything is set to `restart: unless-stopped`, so it comes back by itself
after a power cut or a reboot.

## Updating

```sh
openword update
```

That is `git pull`, a rebuild of whatever changed, and a restart of the
containers whose image changed. The database is not touched; the API
applies any new migrations itself when it starts. People using the app see
"A new version is ready" the next time they open it.

Running the one-liner again does the same and also refreshes the `openword`
command itself.

If `git pull` refuses because you edited a tracked file, `git -C ~/openword
stash` puts your edit aside. `deploy/.env` and `deploy/backups/` are not
tracked and are never touched by an update.

To follow a release rather than `main` when using prebuilt images, set
`OPENWORD_VERSION=v2.0.0` in `deploy/.env`.

## Backups and restoring

Everything the server knows is in one Postgres database: accounts (password
hashes, never passwords), friends, streaks, the feed, push subscriptions,
and each user's backup of their own notes and highlights.

```sh
openword backup
# deploy/backups/openword-20261105-031500.sql.gz (48K)
```

The dump is plain SQL, gzipped. A dump that did not finish is detected and
discarded rather than kept. The newest 14 are kept and older ones deleted;
change that with `OPENWORD_BACKUP_KEEP` (0 keeps all).

**Every night**, with cron (`crontab -e`):

```
15 3 * * * /usr/local/bin/openword backup >/dev/null
```

**Somewhere else.** A backup on the same SD card as the database protects
against a mistake, not against the card dying. Copy `deploy/backups/` off
the Pi regularly, for example:

```sh
rsync -a pi@raspberrypi.local:openword/deploy/backups/ ~/openword-backups/
```

Keep a copy of `deploy/.env` with it. The dump does not contain it.

**Restoring:**

```sh
openword restore backups/openword-20261105-031500.sql.gz
```

It asks first, because it replaces the whole database with the file's
contents. Before loading it takes a backup of the current state, stops the
API so nothing is written half way, loads the dump in a single transaction
(all of it or none of it), and starts the API again.

**Moving to a new Pi:** install there, copy the dump and your old `.env`
values across, then `openword restore <file>`. If you keep the same tunnel
token the public address moves with you; stop the old Pi first, or
Cloudflare will share traffic between the two.

People's reading position, notes and highlights live in their own browser
and are not affected by any of this.

## Logs

```sh
openword logs              # everything, following
openword logs api          # one service: web, api, db or cloudflared
openword status            # is it all up, and memory per container
```

Logs are capped at 3 files of 10 MB per container, so they cannot fill the
card. The API logs one JSON line per event; Postgres logs any statement
slower than half a second.

## What it costs

These are **design figures and estimates**, not measurements from a Pi;
`openword status` shows what your install really uses.

| Container | Memory limit | Expect at rest | Notes |
| --- | --- | --- | --- |
| `web` | 64 MB | under 10 MB | nginx serving files that were compressed at build time |
| `api` | 256 MB | tens of MB | one Go binary, a small connection pool |
| `db` | 384 MB | 50-100 MB | Postgres with `shared_buffers=64MB`, 20 connections |
| `cloudflared` | 128 MB | 30-50 MB | absent on a LAN install |
| **Total** | **832 MB** | **well under 300 MB** | |

The limits are ceilings that stop one misbehaving process from taking the
whole machine; they are not reservations. A 2 GB Pi is left with more than
a gigabyte for the operating system and the file cache.

- **Disk:** the two images are a few hundred MB between them (the voice is
  60 MB of that and the bundled Scripture 13 MB); the build cache takes
  another 1-2 GB, which `docker builder prune` gives back. The database
  starts at a few tens of MB.
- **CPU:** close to idle. Serving is static files; the neural voice runs in
  each reader's own browser, not on the Pi.
- **Building:** the one heavy moment. Budget 10-15 minutes on a Pi 4 for
  the first build and about 1.5 GB of memory, which is why the installer
  wants swap on a 2 GB board. Prebuilt images avoid it entirely.
- **Network:** a first visit downloads about 15 MB (the app and the
  Scripture, compressed). The voice, about 60 MB, is fetched only when
  someone first presses Listen, and then kept by their browser.

The Postgres settings in `docker-compose.yml` are chosen for this size of
machine: small shared buffers (the OS cache does the rest), `work_mem=4MB`,
`random_page_cost=1.1` because flash has no seek penalty, and data
checksums on, so a failing SD card is noticed rather than silently
returning bad pages.

## Settings

Everything is in `deploy/.env` (see `.env.example` for the comments).
After editing it, `openword restart` is enough for most settings;
changing `TUNNEL_TOKEN` between empty and set changes which containers
run, so use `openword configure` or re-run the installer for that.

| Setting | Meaning |
| --- | --- |
| `TUNNEL_TOKEN` | Cloudflare tunnel token. Empty means LAN-only. |
| `OPENWORD_PUBLIC_URL` | the address people use; the API puts it in push notifications |
| `OPENWORD_PORT` | port on the Pi, LAN-only installs (default 8080) |
| `OPENWORD_INVITE_CODE` | if set, registering requires it |
| `OPENWORD_ADMIN_EMAIL` | contact address given to browser push services |
| `POSTGRES_PASSWORD` | generated at install. Changing it later does **not** change the database's stored password |
| `OPENWORD_VERSION` | image tag (which release to pull, when prebuilt) |
| `OPENWORD_PREBUILT` | `1` to pull images rather than build |
| `OPENWORD_LOG_LEVEL` | `debug`, `info`, `warn` or `error` |

Values are written without quotes. Keep them to letters, digits and
ordinary URL characters.

## Security

**Who can make an account.** With `OPENWORD_INVITE_CODE` empty,
registration is open: anyone who can reach the address can sign up. On a
public domain that means anyone on the internet. Set an invite code
(`openword configure`) and only people you give it to can register. Change
the code whenever you like; existing accounts are unaffected.

**HTTPS.** Through the tunnel, Cloudflare terminates HTTPS with a
certificate it manages, and the hop from Cloudflare to the Pi is inside the
tunnel's own encryption. There is no certificate to renew on the Pi.
Cloudflare can see the traffic, as any CDN in that position can.

**Cookies.** The API marks its session cookie `Secure` when the request
arrived over HTTPS, which it learns from the `X-Forwarded-Proto` header
Cloudflare sets and nginx passes on. On a LAN install over plain `http://`
the cookie is not `Secure` and can be read by anything on the network path.
Do not expose a LAN install to the internet by forwarding a port to it.

**Nothing is published.** In tunnel mode no container has a host port. The
database and the API are reachable only from the other containers, and the
API trusts the forwarding headers only because nginx is the only thing
that can reach it.

**Sign-in rate limiting.** The API limits sign-in attempts per visitor
address. nginx tells it that address, and builds the header itself rather
than passing on whatever the visitor sent: through the tunnel it uses the
address Cloudflare reports, and otherwise the address of the connection. A
visitor cannot pick their own.

**Secrets.** `deploy/.env` holds the tunnel token and the database
password. It is created readable by you alone (mode 600) and is ignored by
git. Do not paste it into an issue.

**Keeping current.** `openword update` picks up fixes to OpenWord. The base
images (nginx, Postgres, Alpine) are pinned to a release line and are
refreshed when you rebuild with `docker compose build --pull`. The
`cloudflared` image is pinned to an exact version in `docker-compose.yml`;
bump it there from time to time.

**Backups are sensitive.** A dump contains email addresses and password
hashes. Store copies with the same care as the database.

## Troubleshooting

**The build dies with "Killed", exit code 137, or the Pi freezes.** Out of
memory. Check `free -m`: if Swap is 0 or small, run the installer again and
say yes to the swapfile, or set it up by hand:

```sh
sudo dphys-swapfile swapoff
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile
sudo dphys-swapfile setup && sudo dphys-swapfile swapon
```

Close anything else running on the Pi while it builds. Or skip building
altogether: `OPENWORD_PREBUILT=1`.

**"port is already allocated" / "address already in use"** (LAN installs).
Something else is on port 8080. Find it with `sudo ss -ltnp | grep 8080`,
or choose another: set `OPENWORD_PORT=8090` in `deploy/.env` and
`openword restart`.

**The tunnel does not connect.** `openword logs cloudflared`.

- `Unauthorized: Invalid tunnel secret` or `failed to parse token`: the
  token is wrong or truncated. Copy it again from the dashboard (the whole
  string after `--token`, no spaces or line breaks) and run
  `openword configure`.
- `Registered tunnel connection` appears (normally four times) when all is
  well.
- Timeouts or `failed to dial` towards `argotunnel.com`: the Pi cannot make
  outbound connections on port 7844, which the tunnel uses (QUIC over UDP
  first, then HTTP/2 over TCP on the same port). Some guest and corporate
  networks block it; nothing on the Pi can fix that.
- Nothing at all in the log: is the container there? `openword status`. It
  only runs when `TUNNEL_TOKEN` is set in `deploy/.env`.

**The tunnel is Healthy but the browser shows a Cloudflare error.**

- **502 Bad Gateway**: Cloudflare reached your `cloudflared` but it could
  not reach the app. Almost always the public hostname's service is not
  `http://web:80`: `localhost`, an IP address, `https` or another port
  will all do this. Fix it in the dashboard under the tunnel's public
  hostname; nothing needs restarting on the Pi. If the service is right,
  `openword status` should show `web` as healthy.
- **Error 1033**: Cloudflare has no connected `cloudflared` for this
  tunnel. The Pi is off or offline, or the container is not running:
  `openword status`, `openword logs cloudflared`.
- **The address does not resolve at all**: the hostname has no DNS record.
  In the domain's DNS records there should be a CNAME for it pointing at
  `<tunnel id>.cfargotunnel.com`; removing and re-adding the public
  hostname recreates it.

**`openword status` shows a container restarting.** `openword logs api` (or
`db`) says why. The usual ones:

- api: `password authentication failed`. `POSTGRES_PASSWORD` in `.env` no
  longer matches the one the database was created with. Put the old value
  back. If it is lost and the data does not matter: `openword uninstall`
  (say yes to deleting the database) and install again.
- db: `No space left on device`. `df -h`, then `docker system prune` to
  clear old images and build cache.

**The app loads but everything to do with accounts fails.** The pages are
static files and work without the API; accounts need it. `openword status`
should show `api` and `db` as healthy, and `openword logs api` says what is
wrong if not.

**People still see the old version after an update.** The app updates
itself when it is next opened with a connection: it shows "A new version is
ready". Closing every tab of it and opening it again does the same.

**"permission denied while trying to connect to the Docker daemon".** You
were added to the `docker` group during this session. Log out and back in
(or `newgrp docker`). Until then the `openword` command uses `sudo`.

**Docker warns "Your kernel does not support memory limit capabilities".**
The containers run, without their memory ceilings. On Raspberry Pi OS add
`cgroup_enable=memory cgroup_memory=1` to the end of the single line in
`/boot/firmware/cmdline.txt` (older releases: `/boot/cmdline.txt`) and
reboot.

**The voice never loads.** Open the browser's developer tools, Network tab,
and press Listen. `/voice/.../model.fp32.onnx` should be a 200 of about
57 MB. A 404 means the image was built without the voice stage succeeding;
rebuild with `docker compose build --no-cache web` and read the output of
the `voice` stage. The download is checked against a pinned SHA-256, so a
corrupted or replaced file fails the build rather than being served.

**Start again from nothing.** `openword uninstall`, answer yes to all
three questions, and run the one-liner again.

## Doing it by hand

The installer is a convenience. The same result without it:

```sh
git clone https://github.com/tahuffman1s/OpenWord.git ~/openword
cd ~/openword/deploy
cp .env.example .env
# edit .env: set POSTGRES_PASSWORD (openssl rand -hex 24) and either
# TUNNEL_TOKEN + OPENWORD_PUBLIC_URL, or neither for a LAN install

# behind Cloudflare
docker compose --profile tunnel up -d --build

# or LAN only
docker compose -f docker-compose.yml -f docker-compose.lan.yml up -d --build

# or with prebuilt images (add --profile tunnel or the lan file as above)
docker compose -f docker-compose.yml -f docker-compose.prebuilt.yml \
  --profile tunnel up -d
```

On a 2 GB Pi build the two images one at a time, which is what the
installer does: `docker compose build api && docker compose build web`,
then `up -d`.

To build the web image alone, from the repository root (the build needs
`pwa/`, `assets/` and `deploy/nginx.conf`):

```sh
docker build -f deploy/web.Dockerfile -t openword-web .
```

To build both for a Pi on a faster machine and push them to your own
registry:

```sh
docker buildx build --platform linux/arm64 -f deploy/web.Dockerfile -t you/openword-web --push .
docker buildx build --platform linux/arm64 -t you/openword-api --push server
```

Both Dockerfiles run their build stage on the building machine's own
architecture and only assemble the final image for the target, so this
does not emulate arm64 for the slow parts.

## How the files are served

`nginx.conf` explains itself at length; in short:

| Path | Cache-Control | Why |
| --- | --- | --- |
| `/`, `/index.html`, `/sw.js`, `/manifest.webmanifest`, `/version.json`, `/icons/` | `no-cache` + ETag | these decide when a browser picks up a new build |
| `/assets/<name>-<hash>.<ext>` | one year, `immutable` | Vite names them by content; a new build has new names |
| `/assets/bible/`, `maps/`, `notes/`, `refs/`, `strongs/`, `fonts/`, `licences/` | one day + ETag | the app's data keeps its filenames between releases |
| `/voice/`, `/ort/` | one year | versioned by directory name; Range requests supported |
| `/api/` | whatever the API sends | proxied to `api:8080`, uploads up to 8 MB |
| `/healthz` | `no-store` | answers `ok` |

Text-like files (JavaScript, CSS, HTML, JSON, WebAssembly, fonts) are
gzipped once when the image is built and served from those copies, so the
Pi spends nothing compressing per request.

Four kinds of file are deliberately **not** compressed by the server and
never sent with `Content-Encoding`: the `.bib` translations and the `.gz`
originals and cross-references, which the app unpacks itself, and the
voice's `.onnx` and `.bin`. If a server compressed those in transit the
browser would unpack them before the app saw them and the app's own
decoding would fail.

Any path that is not a file gets `index.html`, so links into the app work;
but a missing file under `/assets/`, `/voice/`, `/ort/` or `/icons/` is an
honest 404, not the app's HTML with a 200.

The voice's neural network runs on one thread in the browser unless the
page is "cross-origin isolated". Two commented-out headers in `nginx.conf`
turn that on; read the note beside them before enabling them.

## Uninstalling

```sh
openword uninstall
```

It asks three separate questions: stop and remove the containers; also
delete the database volume; also delete the checkout (which includes
`deploy/backups/` and `.env`). Answer no to the last two and everything
needed to start again later is still there.

Docker itself, and the images, are left alone. `docker image prune -a`
reclaims the images. If the installer created a swapfile it stays; it is
harmless.

Then, in the Cloudflare dashboard, delete the tunnel if you no longer want
it.
