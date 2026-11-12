#!/usr/bin/env bash
# Load a dump made by backup.sh back into the OpenWord database.
#
#   ./restore.sh backups/openword-20261105-031500.sql.gz     (or: openword restore <file>)
#   ./restore.sh --yes <file>                                (no question asked)
#
# This REPLACES what is in the database with what is in the file: the dump
# drops each table before recreating it. The API is stopped while it runs,
# so nobody writes into a half-restored database, and started again after.
# A backup of the current state is taken first unless --no-safety-backup.
#
# To move to a new Pi: install there (deploy/install.sh), copy the dump and
# your old deploy/.env values across, then run this.

set -euo pipefail
# A relative path means relative to where the command was typed, which is
# not this directory; remember it before moving here.
start_dir=${OPENWORD_CALLER_PWD:-$PWD}
cd "$(dirname "$0")"

yes=0
safety=1
file=""
for arg in "$@"; do
  case "$arg" in
    -y|--yes) yes=1 ;;
    --no-safety-backup) safety=0 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "restore: unknown option $arg" >&2; exit 1 ;;
    *) file=$arg ;;
  esac
done

if [ -z "$file" ]; then
  echo "usage: restore.sh [--yes] [--no-safety-backup] <backups/openword-....sql.gz>" >&2
  if [ -d backups ]; then
    echo "available:" >&2
    find backups -maxdepth 1 -type f -name 'openword-*.sql.gz' | sort -r | head -n 10 | sed 's/^/  /' >&2
  fi
  exit 1
fi
case "$file" in
  /*) ;;
  *) if [ -f "$start_dir/$file" ]; then file="$start_dir/$file"; fi ;;
esac
[ -f "$file" ] || { echo "restore: no such file: $file" >&2; exit 1; }
gzip -t "$file" 2>/dev/null || { echo "restore: $file is not a complete gzip file" >&2; exit 1; }
ending=$(gzip -dc "$file" | tail -n 12)
case "$ending" in
  *'PostgreSQL database dump complete'*) ;;
  *) echo "restore: $file does not end like a finished pg_dump; refusing to load it" >&2; exit 1 ;;
esac

if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi
compose() { "${DOCKER[@]}" compose -f docker-compose.yml "$@"; }

if [ -z "$(compose ps -q db 2>/dev/null)" ]; then
  echo "restore: the db container is not running (openword start)" >&2
  exit 1
fi

if [ "$yes" != 1 ]; then
  echo "This replaces the whole OpenWord database with:"
  echo "  $file"
  read -r -p "Every account and everything since that dump will be gone. Continue? [y/N] " answer
  case "$answer" in y|Y|yes) ;; *) echo "Nothing was changed."; exit 0 ;; esac
fi

if [ "$safety" = 1 ]; then
  echo "Backing up the current database first..."
  # 0 = prune nothing, so this extra dump cannot push out the one being restored.
  OPENWORD_BACKUP_KEEP=0 ./backup.sh
fi

echo "Stopping the API..."
compose stop api >/dev/null
restart_api() { echo "Starting the API..."; compose start api >/dev/null || true; }
trap restart_api EXIT

echo "Restoring..."
# One transaction: either the whole dump goes in or the database is left
# exactly as it was.
gzip -dc "$file" | compose exec -T db psql -U openword -d openword \
  --quiet --set ON_ERROR_STOP=1 --single-transaction >/dev/null

echo "Restored from $file."
