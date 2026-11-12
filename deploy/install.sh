#!/usr/bin/env bash
# OpenWord on a Raspberry Pi (or any 64-bit Linux box with Docker) in one line:
#
#   curl -fsSL https://raw.githubusercontent.com/tahuffman1s/OpenWord/main/deploy/install.sh | bash
#
# What it does, in order, and all of it again safely on a second run:
#
#   1. refuses to run as root (use --allow-root), checks the OS is 64-bit
#   2. installs git and Docker if they are missing (get.docker.com), adds
#      you to the docker group
#   3. clones or updates the repository into $OPENWORD_DIR (~/openword)
#   4. writes deploy/.env: generates the database password, asks you for a
#      Cloudflare tunnel token (or none, for a LAN-only install), the public
#      address and an optional invite code
#   5. offers a swapfile on a 2 GB Pi, because the first build needs ~1.5 GB
#   6. builds and starts the containers, waits for them to be healthy
#   7. installs the `openword` helper (update, logs, status, backup, ...)
#
# Knobs, as environment variables in front of the command or the pipe:
#
#   OPENWORD_BRANCH=main        branch or tag to install
#   OPENWORD_DIR=~/openword     where the checkout lives
#   OPENWORD_PREBUILT=1         pull the images GitHub Actions built instead
#                               of building on this machine (no swap needed)
#   OPENWORD_VERSION=v2.0.0     which prebuilt tag to pull (default latest)
#   OPENWORD_SKIP_SWAP=1        never create a swapfile, whatever the memory
#   OPENWORD_NONINTERACTIVE=1   never prompt; take TUNNEL_TOKEN,
#                               OPENWORD_PUBLIC_URL, OPENWORD_INVITE_CODE,
#                               OPENWORD_ADMIN_EMAIL and OPENWORD_PORT from
#                               the environment and defaults for the rest
#
# Flags (after `bash -s --` when piping): --allow-root, --reconfigure (ask
# the questions again on an existing install), --lan (no tunnel; drops a
# stored token), --prebuilt, --branch NAME, --dir PATH, --help.

set -Eeuo pipefail

# Was the directory chosen by the caller, or is it the default?
OPENWORD_DIR_EXPLICIT=${OPENWORD_DIR:+1}
OPENWORD_REPO="${OPENWORD_REPO:-https://github.com/tahuffman1s/OpenWord.git}"
OPENWORD_BRANCH="${OPENWORD_BRANCH:-main}"
OPENWORD_DIR="${OPENWORD_DIR:-$HOME/openword}"
OPENWORD_NONINTERACTIVE="${OPENWORD_NONINTERACTIVE:-0}"
OPENWORD_PREBUILT="${OPENWORD_PREBUILT:-}"
OPENWORD_VERSION="${OPENWORD_VERSION:-}"
HELPER=${OPENWORD_HELPER_PATH:-/usr/local/bin/openword}

ALLOW_ROOT=0
RECONFIGURE=0
FORCE_LAN=0
LOCAL_CHECKOUT=0
GROUP_ADDED=0
SUDO=""
DOCKER=()
COMPOSE=()
TTY_IN=""
ME=$(id -un)

# --- output ----------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m' C_BOLD=$'\e[1m' C_OFF=$'\e[0m'
else
  C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_BOLD="" C_OFF=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '\n%sError:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

on_error() {
  local line=$1
  [ "$BASHPID" = "$$" ] || return 0
  printf '\n%sThe installer stopped%s (around line %s of install.sh).\n' "$C_RED" "$C_OFF" "$line" >&2
  cat >&2 <<EOF

  Things to check:
    - the message just above this one, which is usually the actual reason
    - free memory and swap:       free -m        (a build needs ~1.5 GB free)
    - free disk space:            df -h /        (images and build cache ~3 GB)
    - what the containers say:    cd $OPENWORD_DIR/deploy && docker compose logs --tail=100
    - the troubleshooting section of $OPENWORD_DIR/deploy/README.md

  Running the same command again picks up where it left off; nothing it
  already did needs undoing.
EOF
}
trap 'on_error $LINENO' ERR

# --- prompts ---------------------------------------------------------------
# Under `curl | bash` stdin is the script itself, so questions are read from
# the terminal device instead. No terminal (cron, ssh without -t, or
# OPENWORD_NONINTERACTIVE=1) means defaults and environment variables only.

setup_tty() {
  [ "$OPENWORD_NONINTERACTIVE" = 1 ] && return 0
  if [ -t 0 ]; then
    TTY_IN=/dev/stdin
  elif [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then
    TTY_IN=/dev/tty
  fi
}

interactive() { [ -n "$TTY_IN" ]; }

# ask "prompt" "default" [secret]  -> prints the answer
ask() {
  local prompt=$1 default=${2:-} secret=${3:-} answer=""
  if ! interactive; then printf '%s' "$default"; return 0; fi
  if [ -n "$default" ] && [ -n "$secret" ]; then
    printf '    %s [Enter keeps the current one]: ' "$prompt" >&2
  elif [ -n "$default" ]; then
    printf '    %s [%s]: ' "$prompt" "$default" >&2
  else
    printf '    %s: ' "$prompt" >&2
  fi
  if [ -n "$secret" ]; then
    IFS= read -rs answer <"$TTY_IN" || true
    printf '\n' >&2
  else
    IFS= read -r answer <"$TTY_IN" || true
  fi
  printf '%s' "${answer:-$default}"
}

# confirm "question" y|n  -> 0 for yes
confirm() {
  local prompt=$1 default=$2 answer
  if ! interactive; then [ "$default" = y ]; return; fi
  if [ "$default" = y ]; then prompt="$prompt [Y/n]"; else prompt="$prompt [y/N]"; fi
  printf '    %s ' "$prompt" >&2
  IFS= read -r answer <"$TTY_IN" || true
  answer=${answer:-$default}
  case "$answer" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

# --- .env handling -----------------------------------------------------------
# Values are written unquoted (docker compose reads them raw), so they are
# validated to the characters a URL, a token or a code can hold.

env_get() {
  local key=$1 val
  [ -f .env ] || { printf ''; return 0; }
  val=$(sed -n "s/^${key}=//p" .env | tail -n 1)
  val=${val#\"}; val=${val%\"}; val=${val#\'}; val=${val%\'}
  printf '%s' "$val"
}

env_set() {
  local key=$1 val=$2 tmp
  tmp=$(mktemp)
  KEY="$key" VAL="$val" awk '
    BEGIN { key = ENVIRON["KEY"]; val = ENVIRON["VAL"]; done = 0 }
    index($0, key "=") == 1 { if (!done) { print key "=" val; done = 1 }; next }
    { print }
    END { if (!done) print key "=" val }
  ' .env > "$tmp"
  cat "$tmp" > .env
  rm -f "$tmp"
}

gen_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 48
  fi
}

# --- helpers -----------------------------------------------------------------

usage() {
  cat <<'EOF'
OpenWord installer

  curl -fsSL https://raw.githubusercontent.com/tahuffman1s/OpenWord/main/deploy/install.sh | bash
  curl -fsSL .../install.sh | bash -s -- [options]
  bash deploy/install.sh [options]          (from a checkout: installs that checkout)

Options:
  --allow-root       run as root (files end up owned by root)
  --reconfigure      ask the setup questions again on an existing install
  --lan              LAN-only: no Cloudflare tunnel, drop any stored token
  --prebuilt         pull images from ghcr.io instead of building here
  --branch NAME      branch to install (default: main)
  --dir PATH         where the checkout lives (default: ~/openword)
  -h, --help         this text

Environment: OPENWORD_BRANCH, OPENWORD_DIR, OPENWORD_PREBUILT=1,
OPENWORD_VERSION, OPENWORD_NONINTERACTIVE=1 and, for a non-interactive
install, TUNNEL_TOKEN, OPENWORD_PUBLIC_URL, OPENWORD_INVITE_CODE,
OPENWORD_ADMIN_EMAIL, OPENWORD_PORT.
EOF
  exit 0
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --allow-root) ALLOW_ROOT=1 ;;
      --reconfigure) RECONFIGURE=1 ;;
      --lan) FORCE_LAN=1 ;;
      --prebuilt) OPENWORD_PREBUILT=1 ;;
      --branch) OPENWORD_BRANCH=$2; shift ;;
      --branch=*) OPENWORD_BRANCH=${1#*=} ;;
      --dir) OPENWORD_DIR=$2; OPENWORD_DIR_EXPLICIT=1; shift ;;
      --dir=*) OPENWORD_DIR=${1#*=}; OPENWORD_DIR_EXPLICIT=1 ;;
      -h|--help) usage ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done
}

have() { command -v "$1" >/dev/null 2>&1; }

pkg_install() {
  if have apt-get; then
    $SUDO apt-get update -qq </dev/null
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq "$@" </dev/null
  elif have dnf; then $SUDO dnf install -y "$@" </dev/null
  elif have yum; then $SUDO yum install -y "$@" </dev/null
  elif have apk; then $SUDO apk add "$@" </dev/null
  elif have pacman; then $SUDO pacman -Sy --noconfirm "$@" </dev/null
  elif have zypper; then $SUDO zypper install -y "$@" </dev/null
  else
    die "cannot install $*: no package manager I know. Install it and run this again."
  fi
}

is_pi() { grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null; }

lan_ip() {
  local ip=""
  if have ip; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')
  fi
  [ -n "$ip" ] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  printf '%s' "${ip:-127.0.0.1}"
}

compose() { "${DOCKER[@]}" compose "${COMPOSE[@]}" "$@"; }

# Which compose files and profile apply is decided by .env alone, so the
# installer, the helper and the backup scripts all agree.
pick_compose_files() {
  COMPOSE=(-f docker-compose.yml)
  if [ -n "$(env_get TUNNEL_TOKEN)" ]; then
    COMPOSE+=(--profile tunnel)
  else
    COMPOSE+=(-f docker-compose.lan.yml)
  fi
  if [ "$(env_get OPENWORD_PREBUILT)" = 1 ]; then
    COMPOSE+=(-f docker-compose.prebuilt.yml)
  fi
}

# --- steps -------------------------------------------------------------------

preflight() {
  step "Checking this machine"

  if [ "$(id -u)" -eq 0 ]; then
    if [ "$ALLOW_ROOT" != 1 ]; then
      die "running as root. Run it as the user who will manage the install (it uses sudo where needed), or pass --allow-root:
    curl -fsSL .../install.sh | bash -s -- --allow-root"
    fi
    SUDO=""
    warn "running as root; files will be owned by root"
  else
    have sudo || die "sudo is needed to install packages and Docker. Install it, or run as root with --allow-root."
    if sudo -n true 2>/dev/null; then
      SUDO="sudo"
    elif interactive; then
      info "sudo may ask for your password (to install packages and the openword command)"
      sudo -v || die "sudo failed"
      SUDO="sudo"
    else
      die "sudo needs a password and there is no terminal to ask on. Run interactively once, or allow passwordless sudo."
    fi
  fi

  case "$(uname -m)" in
    aarch64|arm64|x86_64|amd64) ok "64-bit $(uname -m)" ;;
    armv7l|armv6l)
      die "this is a 32-bit system ($(uname -m)). OpenWord's images are built for 64-bit only (linux/arm64 and linux/amd64).
    On a Raspberry Pi 3/4/5 or Zero 2 W install the 64-bit Raspberry Pi OS from Raspberry Pi Imager and run this again." ;;
    *) die "unsupported architecture $(uname -m); need aarch64 or x86_64" ;;
  esac
  [ "$(uname -s)" = Linux ] || die "this installer is for Linux (Raspberry Pi OS, Debian, Ubuntu, ...)"

  if is_pi; then
    ok "$(tr -d '\0' </proc/device-tree/model)"
    local mem
    mem=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
    info "${mem} MB of memory"
  fi

  local avail
  avail=$(df -Pm "${OPENWORD_DIR%/*}" 2>/dev/null | awk 'NR == 2 {print $4}' || echo 0)
  if [ -n "$avail" ] && [ "$avail" -lt 4096 ]; then
    warn "only ${avail} MB free under ${OPENWORD_DIR%/*}; the images and build cache take about 3 GB"
  fi
}

ensure_git() {
  if have git; then ok "git $(git --version | awk '{print $3}')"; return; fi
  step "Installing git"
  pkg_install git
  ok "git installed"
}

ensure_docker() {
  step "Checking Docker"
  if ! have docker; then
    info "Docker is not installed; installing it with the script from get.docker.com"
    info "(this takes a few minutes on a Pi)"
    local tmp
    tmp=$(mktemp -d)
    curl -fsSL https://get.docker.com -o "$tmp/get-docker.sh"
    $SUDO sh "$tmp/get-docker.sh" </dev/null
    rm -rf "$tmp"
    ok "Docker installed"
  fi

  if have systemctl && ! systemctl is-active --quiet docker 2>/dev/null; then
    $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
  fi

  local in_docker_group=0
  case " $(id -nG "$ME") " in *" docker "*) in_docker_group=1 ;; esac
  if [ "$(id -u)" -ne 0 ] && [ "$in_docker_group" = 0 ]; then
    $SUDO usermod -aG docker "$ME"
    GROUP_ADDED=1
    warn "added $ME to the docker group. That takes effect at your next login;"
    warn "this run uses sudo for docker commands instead."
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif [ -n "$SUDO" ] && "$SUDO" docker info >/dev/null 2>&1; then
    DOCKER=("$SUDO" docker)
  else
    die "Docker is installed but the daemon is not answering. Try: sudo systemctl start docker, then run this again."
  fi

  "${DOCKER[@]}" compose version >/dev/null 2>&1 \
    || die "the docker compose plugin is missing. On Debian/Raspberry Pi OS: sudo apt-get install docker-compose-plugin"
  ok "$("${DOCKER[@]}" --version | sed 's/,.*//'), $("${DOCKER[@]}" compose version --short | sed 's/^/compose /')"

  # The memory limits in docker-compose.yml need the kernel's memory cgroup.
  # Without it Docker warns and runs the containers unlimited, which works,
  # but the limits are the only thing keeping a runaway process from taking
  # the whole 2 GB.
  if ! grep -qw memory /sys/fs/cgroup/cgroup.controllers 2>/dev/null \
      && [ ! -d /sys/fs/cgroup/memory ]; then
    warn "the kernel's memory cgroup is off, so container memory limits will be ignored."
    local cmdline
    for cmdline in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
      if [ -f "$cmdline" ]; then
        warn "to turn it on, add 'cgroup_enable=memory cgroup_memory=1' to the end of the single line in $cmdline and reboot"
        break
      fi
    done
  fi
}

checkout() {
  step "Getting OpenWord ($OPENWORD_BRANCH) into $OPENWORD_DIR"
  if [ "$LOCAL_CHECKOUT" = 1 ]; then
    ok "running from an existing checkout; leaving its git state alone"
    return
  fi
  if [ ! -d "$OPENWORD_DIR/.git" ]; then
    if [ -e "$OPENWORD_DIR" ] && [ -n "$(ls -A "$OPENWORD_DIR" 2>/dev/null)" ]; then
      die "$OPENWORD_DIR exists and is not a git checkout. Move it aside, or point OPENWORD_DIR somewhere else."
    fi
    git clone --depth 1 --branch "$OPENWORD_BRANCH" "$OPENWORD_REPO" "$OPENWORD_DIR"
    ok "cloned"
    return
  fi

  cd "$OPENWORD_DIR"
  # The clone is shallow and tracks one branch. Name the branch wanted, then
  # fetch it without --depth: a plain fetch brings the commits between what
  # is here and the new tip, which is what lets --ff-only see them as one
  # line of history.
  git remote set-branches origin "$OPENWORD_BRANCH"
  git fetch origin "$OPENWORD_BRANCH" \
    || die "cannot fetch $OPENWORD_BRANCH from $OPENWORD_REPO (is that a branch, and is the network up?)"
  local current
  current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
  if [ "$current" = "$OPENWORD_BRANCH" ]; then
    if ! git merge --ff-only "origin/$OPENWORD_BRANCH" >/dev/null 2>&1; then
      die "cannot fast-forward $OPENWORD_DIR: it has local commits or edits to tracked files.
    Put them aside (git stash) or discard them (git reset --hard origin/$OPENWORD_BRANCH) and run this again.
    deploy/.env and deploy/backups/ are not tracked and will not be touched by either."
    fi
  else
    git checkout -B "$OPENWORD_BRANCH" "origin/$OPENWORD_BRANCH" >/dev/null 2>&1 \
      || die "cannot switch $OPENWORD_DIR to $OPENWORD_BRANCH over local edits; see git status there"
  fi
  git branch --set-upstream-to="origin/$OPENWORD_BRANCH" "$OPENWORD_BRANCH" >/dev/null 2>&1 || true
  ok "at $(git rev-parse --short HEAD) on $OPENWORD_BRANCH"
}

configure() {
  step "Configuring deploy/.env"
  cd "$OPENWORD_DIR/deploy"
  [ -f docker-compose.yml ] || die "no deploy/docker-compose.yml in $OPENWORD_DIR; is OPENWORD_BRANCH=$OPENWORD_BRANCH a branch with the new deployment?"

  local fresh=0
  if [ ! -f .env ]; then
    cp .env.example .env
    chmod 600 .env
    fresh=1
  fi
  if [ -z "$(env_get POSTGRES_PASSWORD)" ]; then
    env_set POSTGRES_PASSWORD "$(gen_password)"
    ok "generated a database password"
  fi

  # Settings given on the command line always win, so
  # OPENWORD_PREBUILT=1 curl ... | bash does what it says on a re-run too.
  [ -z "$OPENWORD_PREBUILT" ] || env_set OPENWORD_PREBUILT "$OPENWORD_PREBUILT"
  [ -z "$OPENWORD_VERSION" ] || env_set OPENWORD_VERSION "$OPENWORD_VERSION"

  # Ask when this is a new install, when asked to, when an earlier run was
  # interrupted before its answers were written (the address is the one
  # setting a finished run always fills in), or when the caller handed
  # settings in through the environment.
  local given="${TUNNEL_TOKEN:-}${OPENWORD_PUBLIC_URL:-}${OPENWORD_INVITE_CODE:-}${OPENWORD_ADMIN_EMAIL:-}${OPENWORD_PORT:-}"
  if [ "$fresh" = 1 ] || [ "$RECONFIGURE" = 1 ] || [ "$FORCE_LAN" = 1 ] \
      || [ -z "$(env_get OPENWORD_PUBLIC_URL)" ] || [ -n "$given" ]; then
    ask_settings
  else
    ok "keeping the existing deploy/.env (run with --reconfigure, or edit it, to change it)"
  fi

  pick_compose_files
}

ask_settings() {
  local token url invite email port
  token=${TUNNEL_TOKEN:-$(env_get TUNNEL_TOKEN)}
  url=${OPENWORD_PUBLIC_URL:-$(env_get OPENWORD_PUBLIC_URL)}
  invite=${OPENWORD_INVITE_CODE:-$(env_get OPENWORD_INVITE_CODE)}
  email=${OPENWORD_ADMIN_EMAIL:-$(env_get OPENWORD_ADMIN_EMAIL)}
  port=${OPENWORD_PORT:-$(env_get OPENWORD_PORT)}
  port=${port:-8080}
  local had_token old_port
  had_token=$(env_get TUNNEL_TOKEN)
  old_port=$(env_get OPENWORD_PORT)

  if [ "$FORCE_LAN" = 1 ]; then
    token=""
  elif interactive; then
    cat <<EOF

    ${C_BOLD}Cloudflare Tunnel${C_OFF} puts the app on your own domain over HTTPS with no port
    forwarded on your router. To get a token: Cloudflare dashboard -> Zero Trust ->
    Networks -> Tunnels -> Create a tunnel -> Cloudflared, then copy the long value
    after --token from the install command it shows. Give the tunnel a public
    hostname (your domain) whose service is  http://web:80  .
    Leave this empty for a LAN-only install (plain http on this machine's port).

EOF
    token=$(ask "Tunnel token (paste; hidden)" "$token" secret)
    token=${token//[[:space:]]/}
  fi

  if [ -n "$token" ]; then
    case "$token" in
      *[!A-Za-z0-9+/=_-]*) die "that does not look like a tunnel token (unexpected characters)" ;;
    esac
    [ ${#token} -ge 60 ] || warn "that token is shorter than Cloudflare's usually are; carrying on"
    while :; do
      url=$(ask "Public address (https://your.domain)" "$url")
      url=${url%/}
      case "$url" in
        https://*[!/]*) break ;;
        http://*) warn "through the tunnel the site is HTTPS; use https://"; url="" ;;
        *) warn "need a full address starting with https://"; url="" ;;
      esac
      interactive || die "OPENWORD_PUBLIC_URL must be set (https://...) for a tunnel install"
    done
  else
    while :; do
      port=$(ask "Port to serve on this machine" "$port")
      case "$port" in
        ''|*[!0-9]*) warn "port must be a number"; port=8080; interactive || break ;;
        *) [ "$port" -ge 1 ] && [ "$port" -le 65535 ] && break; warn "port out of range"; port=8080; interactive || break ;;
      esac
    done
    # A stored address is only still right if it was a LAN address for this
    # port; one left over from a tunnel, or from another port, is not.
    if [ -z "${OPENWORD_PUBLIC_URL:-}" ]; then
      case "$url" in
        http://*) { [ -z "$had_token" ] && [ "$port" = "${old_port:-$port}" ]; } || url="" ;;
        *) url="" ;;
      esac
    fi
    url=${url:-http://$(lan_ip):$port}
    info "LAN-only install: no tunnel, the app will be at $url"
    info "Browsers treat plain http (except localhost) as insecure: no install-to-home-screen,"
    info "no offline mode, no push. Fine for trying it out; add a tunnel later with --reconfigure."
  fi

  if interactive; then
    echo
    info "An invite code makes registration private: only people you give it to can"
    info "make an account. Letters, digits, . _ - only. Leave empty for open registration."
    invite=$(ask "Invite code (optional)" "$invite")
    email=$(ask "Admin email for push notification services (optional)" "$email")
  fi
  case "$invite" in
    *[!A-Za-z0-9._-]*) die "the invite code may only contain letters, digits, . _ -" ;;
  esac
  case "$email" in
    ''|*@*.*) ;;
    *) die "that does not look like an email address: $email" ;;
  esac

  env_set TUNNEL_TOKEN "$token"
  env_set OPENWORD_PUBLIC_URL "$url"
  env_set OPENWORD_PORT "$port"
  env_set OPENWORD_INVITE_CODE "$invite"
  env_set OPENWORD_ADMIN_EMAIL "$email"
  ok "wrote deploy/.env"
}

swap_check() {
  [ "$(env_get OPENWORD_PREBUILT)" = 1 ] && return 0
  [ "${OPENWORD_SKIP_SWAP:-0}" = 1 ] && return 0
  local total swap
  total=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
  swap=$(awk '/SwapTotal/ {print int($2 / 1024)}' /proc/meminfo)
  # A "2 GB" Pi 4 reports about 1850 MB once the firmware has taken its
  # share, so the line is drawn above that; a 4 GB board sails past it.
  [ "$total" -lt 2200 ] || return 0

  step "Memory"
  warn "this machine has ${total} MB of memory and ${swap} MB of swap."
  info "Building the web image runs a Node.js build that needs about 1.5 GB; without"
  info "swap the kernel is likely to kill it part way through. 1 GB of swap is enough,"
  info "and it is barely touched once the build is over."
  if [ "$swap" -ge 512 ]; then ok "existing swap will do"; return 0; fi

  if ! confirm "Create a 1 GB swapfile now?" y; then
    warn "carrying on without swap. If the build is killed, run the installer again and say yes,"
    warn "or set OPENWORD_PREBUILT=1 to pull ready-made images instead of building."
    return 0
  fi

  if have dphys-swapfile && [ -f /etc/dphys-swapfile ]; then
    $SUDO sed -i 's/^#\{0,1\}CONF_SWAPSIZE=.*/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile
    grep -q '^CONF_SWAPSIZE=1024' /etc/dphys-swapfile || echo 'CONF_SWAPSIZE=1024' | $SUDO tee -a /etc/dphys-swapfile >/dev/null
    $SUDO dphys-swapfile swapoff >/dev/null 2>&1 || true
    $SUDO dphys-swapfile setup >/dev/null
    $SUDO dphys-swapfile swapon
    ok "swap set to 1 GB through dphys-swapfile (persists across reboots)"
  else
    if [ ! -f /swapfile ]; then
      $SUDO fallocate -l 1G /swapfile 2>/dev/null || $SUDO dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
      $SUDO chmod 600 /swapfile
      $SUDO mkswap /swapfile >/dev/null
    fi
    $SUDO swapon /swapfile 2>/dev/null || true
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | $SUDO tee -a /etc/fstab >/dev/null
    ok "1 GB swapfile at /swapfile (in /etc/fstab, so it survives reboots)"
  fi
}

deploy() {
  cd "$OPENWORD_DIR/deploy"
  if [ "$(env_get OPENWORD_PREBUILT)" = 1 ]; then
    step "Pulling the images (ghcr.io/tahuffman1s/openword-*:$(env_get OPENWORD_VERSION))"
    compose pull
    step "Starting OpenWord"
    compose up -d --remove-orphans
  else
    step "Building the images"
    if is_pi; then
      info "On a Pi 4 the first build takes 10-15 minutes (npm install, the app build,"
      info "a 63 MB voice download and the Go API). Later builds reuse most of it."
    fi
    # One at a time. `up -d --build` builds both at once, and Node and the
    # Go compiler side by side are what runs a 2 GB Pi out of memory.
    compose build api
    compose build web
    step "Starting OpenWord"
    compose up -d --remove-orphans
    "${DOCKER[@]}" image prune -f >/dev/null 2>&1 || true
  fi
}

container_state() {
  local id
  id=$(compose ps -q "$1" 2>/dev/null || true)
  id=${id%%$'\n'*}
  [ -n "$id" ] || { echo missing; return; }
  "${DOCKER[@]}" inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || echo missing
}

wait_healthy() {
  step "Waiting for the containers to be healthy"
  local deadline=$((SECONDS + 240)) svc state pending
  while :; do
    pending=""
    for svc in db api web; do
      state=$(container_state "$svc")
      case "$state" in
        healthy|running) ;;
        exited|dead|missing)
          compose logs --tail=40 "$svc" >&2 || true
          die "the $svc container is $state. The lines above are its last words; 'openword logs $svc' shows more." ;;
        *) pending="$pending $svc($state)" ;;
      esac
    done
    [ -z "$pending" ] && break
    [ "$SECONDS" -lt "$deadline" ] || die "still waiting on:$pending. See 'openword logs'."
    sleep 3
  done
  ok "db, api and web are healthy"

  if [ -n "$(env_get TUNNEL_TOKEN)" ]; then
    deadline=$((SECONDS + 90))
    local tunnel_log
    while :; do
      # Into a variable, not a pipe to grep -q: under pipefail a grep that
      # stops at the first match makes the pipeline look like it failed.
      tunnel_log=$(compose logs --tail=200 cloudflared 2>&1 || true)
      case "$tunnel_log" in
        *'Registered tunnel connection'*)
          ok "cloudflared is connected to Cloudflare"
          return 0 ;;
      esac
      if [ "$SECONDS" -ge "$deadline" ]; then
        warn "cloudflared has not reported a connection yet. Check 'openword logs cloudflared':"
        warn "a bad token says 'Unauthorized'; no route to the hostname says 'error 1033' in the browser."
        return 0
      fi
      sleep 3
    done
  fi
}

install_helper() {
  step "Installing the openword command"
  local tmp
  tmp=$(mktemp)
  # Everything the helper needs to know about this install is the directory;
  # it reads deploy/.env itself for the rest.
  sed "s|__OPENWORD_DIR__|$OPENWORD_DIR|g" > "$tmp" <<'HELPER'
#!/usr/bin/env bash
# openword: manage the OpenWord install in __OPENWORD_DIR__.
# Written by deploy/install.sh; running the installer again rewrites it.
set -euo pipefail

OPENWORD_DIR="__OPENWORD_DIR__"
DEPLOY="$OPENWORD_DIR/deploy"
export OPENWORD_CALLER_PWD="$PWD"   # so `openword restore ./file` means what it says
cd "$DEPLOY" || { echo "openword: $DEPLOY is gone; re-run the installer" >&2; exit 1; }

if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi

env_get() {
  local v
  v=$(sed -n "s/^$1=//p" .env 2>/dev/null | tail -n 1)
  v=${v#\"}; v=${v%\"}; v=${v#\'}; v=${v%\'}
  printf '%s' "$v"
}

COMPOSE=(-f docker-compose.yml)
if [ -n "$(env_get TUNNEL_TOKEN)" ]; then COMPOSE+=(--profile tunnel); else COMPOSE+=(-f docker-compose.lan.yml); fi
if [ "$(env_get OPENWORD_PREBUILT)" = 1 ]; then COMPOSE+=(-f docker-compose.prebuilt.yml); fi
compose() { "${DOCKER[@]}" compose "${COMPOSE[@]}" "$@"; }

usage() {
  cat <<EOF
Usage: openword <command>

  update              pull the latest code (and images, if prebuilt), rebuild, restart
  status              what is running and how much memory it uses
  logs [service]      follow the logs (web, api, db, cloudflared)
  backup              dump the database to deploy/backups/<timestamp>.sql.gz
  restore <file>      load a dump back in (stops the API while it runs)
  restart | stop | start
  psql                a psql shell on the database
  configure           ask the setup questions again (tunnel token, URL, invite code)
  uninstall           stop everything; optionally delete the database and the checkout
  url                 print the address the app is served at

Install directory: $OPENWORD_DIR
EOF
}

app_url() {
  local url
  url=$(env_get OPENWORD_PUBLIC_URL)
  if [ -z "$url" ]; then
    url="http://$(hostname -I 2>/dev/null | awk '{print $1}'):$(env_get OPENWORD_PORT)"
  fi
  printf '%s\n' "$url"
}

cmd=${1:-help}
[ $# -gt 0 ] && shift
case "$cmd" in
  update)
    (cd "$OPENWORD_DIR" && git pull --ff-only) || {
      echo "git pull failed: local changes in $OPENWORD_DIR? Try 'git -C $OPENWORD_DIR stash'." >&2; exit 1; }
    if [ "$(env_get OPENWORD_PREBUILT)" = 1 ]; then
      compose pull
      compose up -d --remove-orphans
    else
      # One image at a time; see the note in install.sh.
      compose build api
      compose build web
      compose up -d --remove-orphans
    fi
    "${DOCKER[@]}" image prune -f >/dev/null 2>&1 || true
    echo "Updated. $(app_url)"
    ;;
  status)
    compose ps
    echo
    ids=$(compose ps -q 2>/dev/null | tr '\n' ' ')
    # shellcheck disable=SC2086
    [ -z "$ids" ] || "${DOCKER[@]}" stats --no-stream $ids
    ;;
  logs) compose logs -f --tail=200 "$@" ;;
  backup) exec "$DEPLOY/backup.sh" "$@" ;;
  restore) exec "$DEPLOY/restore.sh" "$@" ;;
  restart|stop|start) compose "$cmd" "$@" ;;
  psql) compose exec db psql -U openword openword ;;
  configure) exec bash "$DEPLOY/install.sh" --reconfigure ;;
  url) app_url ;;
  uninstall)
    read -r -p "Stop OpenWord and remove its containers? [y/N] " a; case "$a" in y|Y) ;; *) exit 0 ;; esac
    compose down --remove-orphans
    read -r -p "Also DELETE the database volume (all accounts, friends, streaks)? [y/N] " a
    case "$a" in y|Y) "${DOCKER[@]}" volume rm openword_openword-db ;; esac
    read -r -p "Also delete the checkout at $OPENWORD_DIR (keeps nothing, backups included)? [y/N] " a
    case "$a" in y|Y) rm -rf "$OPENWORD_DIR" ;; esac
    if [ "$(id -u)" -eq 0 ]; then rm -f /usr/local/bin/openword; else sudo rm -f /usr/local/bin/openword; fi
    echo "Removed. The Docker images stay until 'docker image prune -a'."
    ;;
  help|-h|--help) usage ;;
  *) echo "openword: unknown command '$cmd'" >&2; usage >&2; exit 1 ;;
esac
HELPER
  $SUDO install -m 0755 "$tmp" "$HELPER"
  rm -f "$tmp"
  chmod +x "$OPENWORD_DIR/deploy/backup.sh" "$OPENWORD_DIR/deploy/restore.sh" 2>/dev/null || true
  ok "$HELPER"
}

finish() {
  local url
  url=$(env_get OPENWORD_PUBLIC_URL)
  [ -n "$url" ] || url="http://$(lan_ip):$(env_get OPENWORD_PORT)"
  printf '\n%s%sOpenWord is running.%s\n\n' "$C_GREEN" "$C_BOLD" "$C_OFF"
  printf '    Open it at:   %s%s%s\n\n' "$C_BOLD" "$url" "$C_OFF"
  if [ -n "$(env_get TUNNEL_TOKEN)" ]; then
    info "If the browser shows a Cloudflare error page, the tunnel's public hostname is"
    info "not pointing at http://web:80 yet: Zero Trust -> Networks -> Tunnels -> your"
    info "tunnel -> Public hostname."
    echo
  fi
  if [ -n "$(env_get OPENWORD_INVITE_CODE)" ]; then
    info "Registration asks for the invite code in deploy/.env."
  else
    info "Registration is open to anyone who can reach the site. To change that:"
    info "openword configure, and set an invite code."
  fi
  cat <<EOF

    Day to day:
      openword update      pull the latest version and restart
      openword status      containers and memory
      openword logs        follow the logs (openword logs api, ...)
      openword backup      dump the database to deploy/backups/
      openword help        everything else

    Uninstall:   openword uninstall
    Settings:    $OPENWORD_DIR/deploy/.env   (then: openword restart)
    Guide:       $OPENWORD_DIR/deploy/README.md
EOF
  if [ "$GROUP_ADDED" = 1 ]; then
    echo
    warn "log out and back in (or run: newgrp docker) so docker works without sudo;"
    warn "until then the openword command will use sudo and may ask for your password."
  fi
  echo
}

main() {
  parse_args "$@"
  setup_tty

  # Run from a checkout (bash deploy/install.sh) rather than piped? Then
  # install *that* checkout and do not touch its git state.
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    local here
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    if [ -f "$here/docker-compose.yml" ] && [ -f "$here/web.Dockerfile" ] && [ -z "$OPENWORD_DIR_EXPLICIT" ]; then
      OPENWORD_DIR=$(dirname "$here")
      LOCAL_CHECKOUT=1
    fi
  fi

  printf '%s%sOpenWord installer%s\n' "$C_BLUE" "$C_BOLD" "$C_OFF"
  info "branch: $OPENWORD_BRANCH   directory: $OPENWORD_DIR"
  interactive || info "no terminal: running non-interactively with defaults and environment variables"

  preflight
  ensure_git
  ensure_docker
  checkout
  configure
  swap_check
  deploy
  wait_healthy
  install_helper
  finish
}

main "$@"
