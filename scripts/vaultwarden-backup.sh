#!/usr/bin/env bash
# Make a consistent SQLite backup of the optional Vaultwarden data directory.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
DATA_DIR=${VAULTWARDEN_DATA_DIR:-/srv/vaultwarden/data}
BACKUP_ROOT=${VAULTWARDEN_BACKUP_DIR:-/srv/vaultwarden/backups}
SQLITE_IMAGE=keinos/sqlite3:3.51.3
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
WORK_DIR=

die() {
  printf 'vaultwarden-backup: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local status=$?
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf -- "$WORK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

for command in docker flock install sha256sum stat tar; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$DATA_DIR/db.sqlite3" ] || die "missing $DATA_DIR/db.sqlite3; Vaultwarden has not initialized"
data_uid=$(stat -c '%u' "$DATA_DIR")
data_gid=$(stat -c '%g' "$DATA_DIR")

install -d -m 0700 "$BACKUP_ROOT"
exec 9>"$BACKUP_ROOT/.backup.lock"
flock -n 9 || die 'another Vaultwarden backup is already running'
WORK_DIR=$(mktemp -d "$BACKUP_ROOT/.${STAMP}.incomplete.XXXXXX")
chmod 0700 "$WORK_DIR"
chown "$data_uid:$data_gid" "$WORK_DIR"

# SQLite's backup API provides a transactionally consistent database snapshot
# while Vaultwarden continues to run. The live WAL files are intentionally not
# copied into the archive.
docker run --rm --network none --user "$data_uid:$data_gid" --entrypoint sqlite3 \
  -v "$DATA_DIR:/data:ro" \
  -v "$WORK_DIR:/backup" \
  "$SQLITE_IMAGE" 'file:/data/db.sqlite3?mode=ro' '.backup /backup/db.sqlite3'
docker run --rm --network none --user "$data_uid:$data_gid" --entrypoint sqlite3 \
  -v "$WORK_DIR:/backup" \
  "$SQLITE_IMAGE" /backup/db.sqlite3 'PRAGMA integrity_check;' | grep -qx ok ||
  die 'SQLite backup integrity check failed'

tar --create --gzip --file "$WORK_DIR/vaultwarden-files.tar.gz" \
  --numeric-owner --acls --xattrs \
  --exclude='./db.sqlite3' --exclude='./db.sqlite3-*' \
  -C "$DATA_DIR" .
cp "$PROJECT_DIR/compose.vaultwarden.yaml" "$WORK_DIR/compose.vaultwarden.yaml"
cp "$PROJECT_DIR/vaultwarden.env.example" "$WORK_DIR/vaultwarden.env.example"
(cd "$WORK_DIR" && sha256sum db.sqlite3 vaultwarden-files.tar.gz >SHA256SUMS)
printf '%s\n' \
  'SQLite database is a consistent .backup snapshot; live WAL files are not copied.' \
  'The private Vaultwarden environment file is intentionally excluded. Restore it from protected secret storage.' \
  'Restore only into an empty disposable target first, using scripts/vaultwarden-restore.sh.' \
  >"$WORK_DIR/README.txt"

FINAL_DIR="$BACKUP_ROOT/$STAMP"
mv -- "$WORK_DIR" "$FINAL_DIR"
WORK_DIR=
printf 'vaultwarden-backup: created %s\n' "$FINAL_DIR"
