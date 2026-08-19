#!/usr/bin/env bash
# Remove exactly one decrypted restic staging directory after explicit invocation.
set -Eeuo pipefail

STAGE_ROOT=${OFFSITE_RESTORE_STAGE_ROOT:-/srv/nextcloud/restore-output}
EVIDENCE_FILE=${RESTORE_EVIDENCE_FILE:-}

die() {
  printf 'cleanup-restore-stage: %s\n' "$*" >&2
  exit 1
}

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi
for command in chmod date dirname find jq mktemp mv realpath; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ "$#" -eq 1 ] || die 'usage: cleanup-restore-stage.sh STAGE_DIRECTORY'
case "$STAGE_ROOT" in /*) ;; *) die 'OFFSITE_RESTORE_STAGE_ROOT must be absolute' ;; esac
[ "$STAGE_ROOT" != / ] || die 'OFFSITE_RESTORE_STAGE_ROOT must not be the filesystem root'
target=$1
[ -d "$target" ] || die "not a directory: $target"
[ ! -L "$target" ] || die 'refusing to follow a staging-directory symlink'
canonical_target=$(realpath -e -- "$target")
case "$canonical_target" in
  "$STAGE_ROOT"/restic-restore.*) ;;
  *) die "target is not a generated restore stage below $STAGE_ROOT" ;;
esac
[ "$(dirname -- "$canonical_target")" = "$STAGE_ROOT" ] || die 'nested targets are not allowed'
if [ -n "$EVIDENCE_FILE" ]; then
  case "$EVIDENCE_FILE" in /*) ;; *) die 'RESTORE_EVIDENCE_FILE must be absolute' ;; esac
  [ -f "$EVIDENCE_FILE" ] || die "restore evidence file not found: $EVIDENCE_FILE"
  jq -e '.schemaVersion == "1.0.0" and .cleanupRecorded == false and
    (.stageDirectory | type == "string")' "$EVIDENCE_FILE" >/dev/null ||
    die 'restore evidence is invalid or cleanup was already recorded'
  receipt_stage=$(jq -r '.stageDirectory' "$EVIDENCE_FILE")
  [ "$(realpath -e -- "$receipt_stage")" = "$canonical_target" ] ||
    die 'restore evidence does not belong to the requested staging directory'
fi

find "$canonical_target" -xdev -depth -delete
if [ -n "$EVIDENCE_FILE" ]; then
  evidence_tmp=$(mktemp "$(dirname -- "$EVIDENCE_FILE")/.restore-cleanup.XXXXXX")
  jq --arg cleanupAtUtc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.cleanupRecorded = true | .cleanupAtUtc = $cleanupAtUtc' "$EVIDENCE_FILE" >"$evidence_tmp"
  chmod 0600 "$evidence_tmp"
  mv -- "$evidence_tmp" "$EVIDENCE_FILE"
fi
printf 'cleanup-restore-stage: removed %s; it is not recoverable locally\n' "$canonical_target"
