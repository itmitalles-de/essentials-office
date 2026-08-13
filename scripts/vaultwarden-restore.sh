#!/usr/bin/env bash
# Restore a Vaultwarden backup only into a new, empty target directory.
set -Eeuo pipefail

SQLITE_IMAGE=keinos/sqlite3:3.51.3@sha256:520cfebb116119cc642b72d72c3ff948cc120a891dc4d83824c664f1ca65a354

die() {
  printf 'vaultwarden-restore: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' 'Usage: ./scripts/vaultwarden-restore.sh BACKUP_DIR EMPTY_TARGET_DIR'
}

[ "$#" -eq 2 ] || { usage >&2; exit 2; }
BACKUP_DIR=$1
TARGET_DIR=$2

for command in docker find install sha256sum stat tar; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -d "$BACKUP_DIR" ] || die "backup directory does not exist: $BACKUP_DIR"
for required_file in db.sqlite3 vaultwarden-files.tar.gz SHA256SUMS README.txt; do
  [ -f "$BACKUP_DIR/$required_file" ] || die "backup is incomplete: missing $required_file"
done

if [ -e "$TARGET_DIR" ]; then
  [ -d "$TARGET_DIR" ] || die "restore target exists but is not a directory: $TARGET_DIR"
  [ -z "$(find "$TARGET_DIR" -mindepth 1 -print -quit)" ] ||
    die "restore target must be empty: $TARGET_DIR"
else
  install -d -m 0700 "$TARGET_DIR"
fi
target_uid=$(stat -c '%u' "$TARGET_DIR")
target_gid=$(stat -c '%g' "$TARGET_DIR")

(cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS)
tar --extract --gzip --file "$BACKUP_DIR/vaultwarden-files.tar.gz" \
  --numeric-owner --acls --xattrs -C "$TARGET_DIR"
cp "$BACKUP_DIR/db.sqlite3" "$TARGET_DIR/db.sqlite3"
docker run --rm --network none --user "$target_uid:$target_gid" --entrypoint sqlite3 \
  -v "$TARGET_DIR:/restore" \
  "$SQLITE_IMAGE" /restore/db.sqlite3 'PRAGMA integrity_check;' | grep -qx ok ||
  die 'restored SQLite database failed integrity_check'

printf 'vaultwarden-restore: restored and verified %s\n' "$TARGET_DIR"
