#!/usr/bin/env bash
# Create a consistent local backup and upload it to an encrypted restic repository.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE=${OFFSITE_BACKUP_CONFIG:-/etc/nextcloud/offsite-backup.env}
EVIDENCE_FILE=${OFFSITE_EVIDENCE_FILE:-/var/lib/essentials-office/evidence/last-offsite-snapshot.json}
BACKUP_ROOT=
BACKUP_JSON=
EVIDENCE_TMP=

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

cleanup() {
  local status=$?
  if [ -n "$BACKUP_JSON" ] && [[ "$BACKUP_JSON" == /tmp/essentials-office-restic-backup.* ]]; then
    rm -f -- "$BACKUP_JSON"
  fi
  if [ -n "$EVIDENCE_TMP" ] && [ -f "$EVIDENCE_TMP" ]; then
    rm -f -- "$EVIDENCE_TMP"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

for command in awk cat chmod cmp date dirname find flock head hostname install jq mktemp mv restic rm sort stat tail tr; do
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
case "$BACKUP_ROOT" in /*) ;; *) die 'backup root must be absolute' ;; esac
[ "$BACKUP_ROOT" != / ] || die 'backup root must not be the filesystem root'
install -d -o root -g root -m 0700 "$BACKUP_ROOT"

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

BACKUP_JSON=$(mktemp /tmp/essentials-office-restic-backup.XXXXXX)
chmod 0600 "$BACKUP_JSON"
restic backup --json --tag nextcloud --tag "$latest_backup" \
  "$BACKUP_ROOT/$latest_backup" "$PROJECT_DIR/.env" >"$BACKUP_JSON"
snapshot_id=$(jq -r 'select(.message_type == "summary") | .snapshot_id // empty' "$BACKUP_JSON" | tail -n 1)
[[ "$snapshot_id" =~ ^[0-9a-f]{64}$ ]] || die 'restic did not return a full snapshot ID'
snapshot_time=$(restic snapshots --json "$snapshot_id" \
  | jq -r --arg id "$snapshot_id" '.[] | select(.id == $id) | .time // empty')
[ -n "$snapshot_time" ] || die 'restic did not return the snapshot time'
check_scope=${RESTIC_READ_DATA_SUBSET:-5%}
restic check --read-data-subset="$check_scope"

repository_commit=$(cat "$BACKUP_ROOT/$latest_backup/repository-commit.txt" 2>/dev/null || printf unknown)
repository_dirty=$(jq -r '.repository.dirty' "$BACKUP_ROOT/$latest_backup/versions.json")
case "$repository_dirty" in true|false) ;; *) die 'local backup has no reliable repository dirty state' ;; esac
evidence_dir=$(dirname -- "$EVIDENCE_FILE")
install -d -o root -g root -m 0700 "$evidence_dir"
EVIDENCE_TMP=$(mktemp "$evidence_dir/.last-offsite-snapshot.XXXXXX")
chmod 0600 "$EVIDENCE_TMP"
jq -n \
  --arg snapshotId "$snapshot_id" --arg snapshotTimeUtc "$snapshot_time" \
  --arg sourceHost "$(hostname)" --arg repositoryCommit "$repository_commit" \
  --argjson repositoryDirty "$repository_dirty" \
  --arg backupTimestamp "$latest_backup" --arg checkScope "$check_scope" \
  '{schemaVersion: "1.0.0", snapshotId: $snapshotId, snapshotTimeUtc: $snapshotTimeUtc,
    sourceHost: $sourceHost, repositoryCommit: $repositoryCommit, repositoryDirty: $repositoryDirty,
    backupTimestamp: $backupTimestamp, checkScope: $checkScope,
    repositoryCheckPassed: true}' >"$EVIDENCE_TMP"
snapshot_receipt="$evidence_dir/offsite-snapshot-$snapshot_id.json"
if [ -e "$snapshot_receipt" ]; then
  cmp -s "$EVIDENCE_TMP" "$snapshot_receipt" ||
    die "immutable snapshot receipt conflicts with existing evidence: $snapshot_receipt"
else
  install -o root -g root -m 0600 "$EVIDENCE_TMP" "$snapshot_receipt"
fi
mv -- "$EVIDENCE_TMP" "$EVIDENCE_FILE"
EVIDENCE_TMP=
chmod 0600 "$EVIDENCE_FILE"

printf 'offsite-backup: encrypted snapshot %s at %s and repository check passed for %s\n' \
  "$snapshot_id" "$snapshot_time" "$latest_backup"
printf 'offsite-backup: secret-redacted latest and immutable receipts written to %s\n' "$evidence_dir"
