#!/usr/bin/env bash
# Create a consistent local backup and upload it to an encrypted restic repository.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE=${OFFSITE_BACKUP_CONFIG:-/etc/nextcloud/offsite-backup.env}
BACKUP_ROOT=

die() {
  printf 'offsite-backup: %s\n' "$*" >&2
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

env_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROJECT_DIR/.env"
}

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

for command in awk find flock head restic sort stat tail tr; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

required_restic_version=0.19.1
restic_version=$(restic version | awk '{print $2}')
if [ "$(printf '%s\n' "$required_restic_version" "$restic_version" | sort -V | head -n 1)" != "$required_restic_version" ]; then
  die "restic $required_restic_version or newer is required (found $restic_version)"
fi

require_protected_file "$CONFIG_FILE"
# The path is deliberately supplied by root.
set -a
# shellcheck disable=SC1090
. "$CONFIG_FILE"
set +a

: "${RESTIC_REPOSITORY_FILE:?RESTIC_REPOSITORY_FILE must be set}"
: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE must be set}"
require_protected_file "$RESTIC_REPOSITORY_FILE"
require_protected_file "$RESTIC_PASSWORD_FILE"
[ -f "$PROJECT_DIR/.env" ] || die "missing $PROJECT_DIR/.env"
data_root=$(env_value NEXTCLOUD_DATA_ROOT)
[ -n "$data_root" ] || die 'NEXTCLOUD_DATA_ROOT is empty in .env'
BACKUP_ROOT=${BACKUP_DIR:-$data_root/backups}

repository=$(tr -d '\r\n' <"$RESTIC_REPOSITORY_FILE")
case "$repository" in
  rclone:*)
    command -v rclone >/dev/null 2>&1 || die 'rclone repository configured but rclone is missing'
    : "${RCLONE_CONFIG:?RCLONE_CONFIG must be set for an rclone repository}"
    require_protected_file "$RCLONE_CONFIG"
    ;;
esac

exec 9>"$BACKUP_ROOT/.offsite-backup.lock"
flock -n 9 || die 'another offsite backup is already running'

if [ "${1:-}" = --init ]; then
  restic init
elif [ "$#" -ne 0 ]; then
  die 'usage: offsite-backup.sh [--init]'
else
  restic cat config >/dev/null
fi

"$SCRIPT_DIR/backup.sh"
latest_backup=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
  ! -name '.*' -printf '%f\n' | sort | tail -n 1)
[ -n "$latest_backup" ] || die 'local backup completed but no backup directory was found'

restic backup --quiet --tag nextcloud --tag "$latest_backup" \
  "$BACKUP_ROOT/$latest_backup" "$PROJECT_DIR/.env"
restic check --read-data-subset="${RESTIC_READ_DATA_SUBSET:-5%}"

printf 'offsite-backup: encrypted snapshot created and repository check passed for %s\n' "$latest_backup"
