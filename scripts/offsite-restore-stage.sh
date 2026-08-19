#!/usr/bin/env bash
# Decrypt one restic snapshot into a unique staging directory for restore tests.
set -Eeuo pipefail

CONFIG_FILE=${OFFSITE_BACKUP_CONFIG:-/etc/nextcloud/offsite-backup.env}
STAGE_ROOT=${OFFSITE_RESTORE_STAGE_ROOT:-/srv/nextcloud/restore-output}
SNAPSHOT=${1:-latest}
STAGE_DIR=
SNAPSHOT_JSON=
STAGE_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STAGE_STARTED_EPOCH=$(date -u +%s)

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
for command in awk chmod date head install jq mktemp restic rm sort stat tr; do
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
repository=$(tr -d '\r\n' <"$RESTIC_REPOSITORY_FILE")
case "$repository" in
  rclone:*)
    command -v rclone >/dev/null 2>&1 || die 'rclone repository configured but rclone is missing'
    : "${RCLONE_CONFIG:?RCLONE_CONFIG must be set for an rclone repository}"
    require_protected_file "$RCLONE_CONFIG"
    ;;
esac
case "$SNAPSHOT" in
  latest) ;;
  *) [[ "$SNAPSHOT" =~ ^[0-9a-f]{8,64}$ ]] || die 'snapshot must be latest or a hexadecimal snapshot ID' ;;
esac

case "$STAGE_ROOT" in /*) ;; *) die 'OFFSITE_RESTORE_STAGE_ROOT must be absolute' ;; esac
[ "$STAGE_ROOT" != / ] || die 'OFFSITE_RESTORE_STAGE_ROOT must not be the filesystem root'

install -d -o root -g root -m 0700 "$STAGE_ROOT"
STAGE_DIR=$(mktemp -d "$STAGE_ROOT/restic-restore.XXXXXX")
chmod 0700 "$STAGE_DIR"
if [ "$SNAPSHOT" = latest ]; then
  SNAPSHOT_JSON=$(restic snapshots --latest 1 --json)
else
  SNAPSHOT_JSON=$(restic snapshots --json "$SNAPSHOT")
fi
jq -e 'type == "array" and length == 1 and
  (.[0].id | test("^[0-9a-f]{64}$")) and (.[0].time | type == "string" and length > 0)' \
  <<<"$SNAPSHOT_JSON" >/dev/null || die 'snapshot selector did not resolve to exactly one full snapshot'
resolved_snapshot=$(jq -r '.[0].id' <<<"$SNAPSHOT_JSON")
snapshot_time=$(jq -r '.[0].time' <<<"$SNAPSHOT_JSON")
restic restore "$resolved_snapshot" --target "$STAGE_DIR"
staged_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
stage_duration=$(( $(date -u +%s) - STAGE_STARTED_EPOCH ))
jq -n --arg snapshotId "$resolved_snapshot" --arg snapshotTimeUtc "$snapshot_time" \
  --arg startedAtUtc "$STAGE_STARTED_AT" --arg stagedAtUtc "$staged_at" \
  --argjson durationSeconds "$stage_duration" \
  '{schemaVersion: "1.0.0", snapshotId: $snapshotId, snapshotTimeUtc: $snapshotTimeUtc,
    startedAtUtc: $startedAtUtc, stagedAtUtc: $stagedAtUtc, durationSeconds: $durationSeconds}' \
  >"$STAGE_DIR/.essentials-office-restore-stage.json"
chmod 0600 "$STAGE_DIR/.essentials-office-restore-stage.json"
printf 'offsite-restore-stage: snapshot %s is staged at %s\n' "$resolved_snapshot" "$STAGE_DIR"
printf 'offsite-restore-stage: remove it with cleanup-restore-stage.sh immediately after the test\n'
