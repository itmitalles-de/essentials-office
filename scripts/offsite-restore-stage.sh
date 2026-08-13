#!/usr/bin/env bash
# Decrypt one restic snapshot into a unique staging directory for restore tests.
set -Eeuo pipefail

CONFIG_FILE=${OFFSITE_BACKUP_CONFIG:-/etc/nextcloud/offsite-backup.env}
STAGE_ROOT=/srv/nextcloud/restore-output
SNAPSHOT=${1:-latest}
STAGE_DIR=

die() {
  printf 'offsite-restore-stage: %s\n' "$*" >&2
  exit 1
}

require_protected_file() {
  local path=$1 mode owner
  [ -f "$path" ] || die "missing protected file: $path"
  owner=$(stat -c '%u' "$path")
  mode=$(stat -c '%a' "$path")
  [ "$owner" = 0 ] || die "$path must be owned by root"
  case "$mode" in
    400|600) ;;
    *) die "$path must have mode 0400 or 0600" ;;
  esac
}

cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ -n "$STAGE_DIR" ] && [[ "$STAGE_DIR" == "$STAGE_ROOT"/restic-restore.* ]]; then
    rm -rf --one-file-system -- "$STAGE_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi
[ "$#" -le 1 ] || die 'usage: offsite-restore-stage.sh [SNAPSHOT_ID]'
for command in awk head restic sort stat; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
required_restic_version=0.19.1
restic_version=$(restic version | awk '{print $2}')
if [ "$(printf '%s\n' "$required_restic_version" "$restic_version" | sort -V | head -n 1)" != "$required_restic_version" ]; then
  die "restic $required_restic_version or newer is required (found $restic_version)"
fi
require_protected_file "$CONFIG_FILE"
set -a
# shellcheck disable=SC1090 # The path is deliberately supplied by root.
. "$CONFIG_FILE"
set +a
: "${RESTIC_REPOSITORY_FILE:?RESTIC_REPOSITORY_FILE must be set}"
: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE must be set}"
require_protected_file "$RESTIC_REPOSITORY_FILE"
require_protected_file "$RESTIC_PASSWORD_FILE"

install -d -o root -g root -m 0700 "$STAGE_ROOT"
STAGE_DIR=$(mktemp -d "$STAGE_ROOT/restic-restore.XXXXXX")
chmod 0700 "$STAGE_DIR"
restic restore "$SNAPSHOT" --target "$STAGE_DIR"
printf 'offsite-restore-stage: decrypted snapshot is staged at %s\n' "$STAGE_DIR"
printf 'offsite-restore-stage: remove it with cleanup-restore-stage.sh immediately after the test\n'
