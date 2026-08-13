#!/usr/bin/env bash
# Remove exactly one decrypted restic staging directory after explicit invocation.
set -Eeuo pipefail

STAGE_ROOT=/srv/nextcloud/restore-output

die() {
  printf 'cleanup-restore-stage: %s\n' "$*" >&2
  exit 1
}

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi
for command in dirname find realpath; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ "$#" -eq 1 ] || die 'usage: cleanup-restore-stage.sh STAGE_DIRECTORY'
target=$1
[ -d "$target" ] || die "not a directory: $target"
[ ! -L "$target" ] || die 'refusing to follow a staging-directory symlink'
canonical_target=$(realpath -e -- "$target")
case "$canonical_target" in
  "$STAGE_ROOT"/restic-restore.*) ;;
  *) die "target is not a generated restore stage below $STAGE_ROOT" ;;
esac
[ "$(dirname -- "$canonical_target")" = "$STAGE_ROOT" ] || die 'nested targets are not allowed'

find "$canonical_target" -xdev -depth -delete
printf 'cleanup-restore-stage: removed %s; it is not recoverable locally\n' "$canonical_target"
