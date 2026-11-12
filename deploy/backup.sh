#!/usr/bin/env bash
# Dump the OpenWord database to deploy/backups/openword-<timestamp>.sql.gz.
#
#   ./backup.sh                 (or: openword backup)
#   OPENWORD_BACKUP_KEEP=30 ./backup.sh
#
# The dump is plain SQL made by pg_dump inside the db container, so it needs
# nothing installed on the host and restores into any Postgres 16. It holds
# everything the server knows: accounts (password hashes, not passwords),
# friends, streaks, the feed, push subscriptions and the users' encrypted
# backups. It does NOT hold deploy/.env; keep a copy of that too.
#
# The newest OPENWORD_BACKUP_KEEP dumps are kept (default 14) and older ones
# deleted, so a nightly cron job cannot fill the SD card (0 keeps them all):
#
#   15 3 * * * /usr/local/bin/openword backup >/dev/null
#
# Copy the files somewhere that is not this Pi. An SD card is not a backup.

set -euo pipefail
cd "$(dirname "$0")"

KEEP=${OPENWORD_BACKUP_KEEP:-14}
DIR=${OPENWORD_BACKUP_DIR:-backups}

case "$KEEP" in ''|*[!0-9]*) echo "backup: OPENWORD_BACKUP_KEEP must be a number" >&2; exit 1 ;; esac

if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
compose() { "${DOCKER[@]}" compose -f docker-compose.yml "$@"; }

if [ -z "$(compose ps -q db 2>/dev/null)" ]; then
  echo "backup: the db container is not running (openword start)" >&2
  exit 1
fi

mkdir -p "$DIR"
chmod 700 "$DIR" 2>/dev/null || true
out="$DIR/openword-$(date +%Y%m%d-%H%M%S).sql.gz"
tmp="$out.part"
trap 'rm -f "$tmp"' EXIT

# --clean --if-exists makes the dump replace what is there when restored,
# rather than colliding with it. pipefail makes a failed pg_dump fail the
# script even though gzip was happy to compress an empty stream.
compose exec -T db pg_dump -U openword -d openword --clean --if-exists --no-owner \
  | gzip -9 > "$tmp"

# A dump that did not finish has no trailer; refuse to call it a backup.
# (Read into a variable rather than piped to grep -q: under pipefail a grep
# that stops early can make a good dump look like a failed one.)
ending=$(gzip -dc "$tmp" | tail -n 12)
case "$ending" in
  *'PostgreSQL database dump complete'*) ;;
  *) echo "backup: the dump is incomplete; nothing was kept" >&2; exit 1 ;;
esac
mv "$tmp" "$out"
trap - EXIT

if [ "$KEEP" -gt 0 ]; then
  # Names sort by time, so everything before the newest $KEEP goes.
  find "$DIR" -maxdepth 1 -type f -name 'openword-*.sql.gz' | sort -r | tail -n +"$((KEEP + 1))" \
    | while IFS= read -r old; do rm -f -- "$old"; done
fi

echo "$out ($(du -h "$out" | cut -f1))"
