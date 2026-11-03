#!/usr/bin/env bash
# OpenWord web, self-hosted behind a Cloudflare Tunnel, in one line:
#
#   curl -fsSL https://raw.githubusercontent.com/tahuffman1s/OpenWord/main/deploy/install.sh | bash
#
# With no token it serves the app on a random https://<words>.trycloudflare.com
# address, which needs no Cloudflare account. For your own domain, pass the
# token of a tunnel made in the Cloudflare dashboard:
#
#   curl -fsSL https://raw.githubusercontent.com/tahuffman1s/OpenWord/main/deploy/install.sh | bash -s -- --token <TOKEN>
#
# Either way nothing listens on the machine: cloudflared only dials out, so no
# port is forwarded and no firewall is opened. Run it again to update to the
# newest release; the token it was given before is kept.
#
# Options (each has an environment-variable twin):
#   --token TOKEN   named tunnel on your own domain          TUNNEL_TOKEN
#   --quick         trycloudflare.com address, even if a
#                   token was saved by an earlier run        OPENWORD_QUICK=1
#   --dir DIR       where to install (default ~/openword)    OPENWORD_DIR
#   --version TAG   release to serve (default: the latest)   OPENWORD_VERSION
#   --ref REF       git ref the deploy files come from       OPENWORD_REF
#   --uninstall     stop and remove everything it installed
#
# The whole script is a function called on its last line, so a download cut
# short part-way through runs nothing at all.

set -euo pipefail

REPO="tahuffman1s/OpenWord"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  sed -n '2,/^# The whole script/p' "$0" 2>/dev/null | sed '$d; s/^# \{0,1\}//' \
    || echo "See https://github.com/$REPO#self-hosting-the-web-build"
}

# Root needs no sudo; anyone else needs it for installing or reaching Docker.
SUDO=""
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif have sudo; then sudo "$@"
  else die "this step needs root and sudo is not installed: $*"
  fi
}

ensure_docker() {
  if ! have docker; then
    [ "$(uname -s)" = "Linux" ] \
      || die "Docker is not installed. Install Docker Desktop, start it, and run this again."
    say "Docker is not installed; installing it with get.docker.com"
    curl -fsSL https://get.docker.com | as_root sh
  fi

  # Reach the daemon directly if we can, through sudo if we must, and start
  # it if it is merely stopped.
  if ! docker info >/dev/null 2>&1; then
    if [ "$(id -u)" -ne 0 ] && have sudo && sudo docker info >/dev/null 2>&1; then
      SUDO="sudo"
    else
      if have systemctl; then as_root systemctl enable --now docker >/dev/null 2>&1 || true; fi
      if docker info >/dev/null 2>&1; then :
      elif [ "$(id -u)" -ne 0 ] && have sudo && sudo docker info >/dev/null 2>&1; then SUDO="sudo"
      else die "cannot reach the Docker daemon. Is it running?"
      fi
    fi
  fi

  # $SUDO is either empty or "sudo", so letting it split is the point.
  # shellcheck disable=SC2206
  if $SUDO docker compose version >/dev/null 2>&1; then
    COMPOSE=($SUDO docker compose)
  elif have docker-compose; then
    COMPOSE=($SUDO docker-compose)
  else
    die "Docker Compose is missing. Install the docker-compose-plugin package and run this again."
  fi
}

compose() { (cd "$DIR" && "${COMPOSE[@]}" "$@"); }

latest_version() {
  # The /releases/latest page redirects to /releases/tag/<tag>. Following
  # that redirect needs no API call, so it is not rate-limited.
  local url
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/$REPO/releases/latest") || return 1
  case "$url" in
    */releases/tag/*) printf '%s\n' "${url##*/}" ;;
    *) return 1 ;;
  esac
}

# Read KEY's value from an existing .env, if there is one.
env_get() {
  [ -f "$DIR/.env" ] || return 0
  sed -n "s/^$1=//p" "$DIR/.env" | tail -n 1
}

quick_url() {
  compose logs --no-color cloudflared-quick 2>/dev/null \
    | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -n 1
}

uninstall() {
  [ -f "$DIR/docker-compose.yml" ] || die "nothing installed in $DIR"
  ensure_docker
  say "Stopping OpenWord and removing its containers and images"
  compose --profile tunnel --profile quick down --rmi local --remove-orphans || true
  rm -rf "$DIR"
  say "Removed $DIR"
}

main() {
  local token="${TUNNEL_TOKEN:-}" quick="${OPENWORD_QUICK:-}" version="${OPENWORD_VERSION:-}"
  local ref="${OPENWORD_REF:-main}" do_uninstall=""
  DIR="${OPENWORD_DIR:-$HOME/openword}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --token)     [ $# -ge 2 ] || die "--token needs a value"; token="$2"; shift 2 ;;
      --token=*)   token="${1#*=}"; shift ;;
      --quick)     quick=1; shift ;;
      --dir)       [ $# -ge 2 ] || die "--dir needs a value"; DIR="$2"; shift 2 ;;
      --dir=*)     DIR="${1#*=}"; shift ;;
      --version)   [ $# -ge 2 ] || die "--version needs a value"; version="$2"; shift 2 ;;
      --version=*) version="${1#*=}"; shift ;;
      --ref)       [ $# -ge 2 ] || die "--ref needs a value"; ref="$2"; shift 2 ;;
      --ref=*)     ref="${1#*=}"; shift ;;
      --uninstall) do_uninstall=1; shift ;;
      -h|--help)   usage; exit 0 ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
  done

  have curl || die "curl is required"

  if [ -n "$do_uninstall" ]; then uninstall; return; fi

  ensure_docker

  mkdir -p "$DIR"

  # Which tunnel. An explicit choice wins; then a token saved by an earlier
  # run, so updating keeps the domain; then, on a terminal, ask; otherwise
  # fall back to a quick tunnel, which needs nothing.
  if [ -z "$token" ] && [ -z "$quick" ]; then
    token="$(env_get TUNNEL_TOKEN)"
    if [ -z "$token" ] && [ "$(env_get COMPOSE_PROFILES)" != "quick" ] \
        && [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then
      printf '\nPaste a Cloudflare tunnel token to serve OpenWord on your own domain,\n'
      printf 'or press Enter for a free https://<words>.trycloudflare.com address: '
      IFS= read -r token </dev/tty || token=""
      # People paste the whole `cloudflared ... --token XYZ` line; keep XYZ.
      token="${token%"${token##*[![:space:]]}"}"
      token="${token##*[[:space:]]}"
    fi
  fi
  [ -n "$quick" ] && token=""

  local profile service other_profile other_service
  if [ -n "$token" ]; then
    profile=tunnel; service=cloudflared
    other_profile=quick; other_service=cloudflared-quick
  else
    profile=quick; service=cloudflared-quick
    other_profile=tunnel; other_service=cloudflared
  fi

  if [ -z "$version" ]; then
    say "Looking up the latest OpenWord release"
    version="$(latest_version)" || die "could not find the latest release; pass --version vX.Y.Z"
  fi
  case "$version" in v*) ;; *) version="v$version" ;; esac

  say "Fetching the deploy files ($ref) into $DIR"
  local base="https://raw.githubusercontent.com/$REPO/$ref/deploy" f
  for f in Dockerfile nginx.conf docker-compose.yml; do
    curl -fsSL "$base/$f" -o "$DIR/$f.tmp" || die "could not download $base/$f"
    mv "$DIR/$f.tmp" "$DIR/$f"
  done

  # The token is a password: keep the file it lives in private.
  ( umask 077
    cat >"$DIR/.env.tmp" <<EOF
# Written by install.sh. Run the installer again to update; edit this and run
# \`docker compose up -d\` here to change it by hand.
COMPOSE_PROFILES=$profile
TUNNEL_TOKEN=$token
OPENWORD_VERSION=$version
EOF
  )
  mv "$DIR/.env.tmp" "$DIR/.env"

  # Switching between a quick tunnel and a named one: stop the one not wanted.
  compose --profile "$other_profile" rm -sf "$other_service" >/dev/null 2>&1 || true

  say "Building OpenWord $version and starting it (the first build takes a minute)"
  compose pull --quiet "$service" || warn "could not pull the cloudflared image; using what is here"
  compose up -d --build --remove-orphans

  echo
  if [ "$profile" = "tunnel" ]; then
    say "OpenWord $version is up behind your Cloudflare Tunnel."
    echo "    In the Cloudflare dashboard, give the tunnel a public hostname"
    echo "    pointing at the service  http://web:80"
  else
    say "Waiting for the trycloudflare.com address"
    local url=""
    for _ in $(seq 1 60); do
      url="$(quick_url || true)"
      [ -n "$url" ] && break
      sleep 2
    done
    if [ -n "$url" ]; then
      say "OpenWord $version is live at:"
      echo
      echo "    $url"
      echo
      echo "    This address changes whenever the tunnel restarts. For a fixed one on"
      echo "    your own domain, run the installer again with --token <TOKEN>."
    else
      warn "the tunnel has not printed its address yet. Look for it with:"
      echo "    cd $DIR && ${COMPOSE[*]} logs cloudflared-quick | grep trycloudflare.com"
    fi
  fi
  local dir_arg=""
  [ "$DIR" = "$HOME/openword" ] || dir_arg=" --dir $DIR"
  echo
  echo "    Installed in   $DIR"
  echo "    Logs           cd $DIR && ${COMPOSE[*]} logs -f"
  echo "    Update         run the same curl line again"
  echo "    Remove         curl -fsSL https://raw.githubusercontent.com/$REPO/main/deploy/install.sh | bash -s -- --uninstall$dir_arg"
}

main "$@"
