#!/usr/bin/env bash
# Install the pinned restic and rclone binaries after verifying release hashes.
set -Eeuo pipefail

RESTIC_VERSION=0.19.1
RESTIC_SHA256=f415415624dcc452f2a02b8c33641791a8c6d6d3b65bbb3543fcf9a25151585c
RCLONE_VERSION=1.75.0
RCLONE_SHA256=aa2804e08f48250e71009c727124b6341cd0288465804a9a09d14663cabafbaa
WORK_DIR=

die() {
  printf 'install-backup-tools: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local status=$?
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/nextcloud-backup-tools.* ]]; then
    rm -rf -- "$WORK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

[ "$(uname -m)" = x86_64 ] || die 'only Linux x86_64 is supported by this pinned installer'
for command in awk bunzip2 curl grep head install sha256sum unzip; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

WORK_DIR=$(mktemp -d /tmp/nextcloud-backup-tools.XXXXXX)
restic_archive=restic_"$RESTIC_VERSION"_linux_amd64.bz2
rclone_archive=rclone-v"$RCLONE_VERSION"-linux-amd64.zip

curl --fail --location --proto '=https' --tlsv1.2 \
  --output "$WORK_DIR/$restic_archive" \
  "https://github.com/restic/restic/releases/download/v$RESTIC_VERSION/$restic_archive"
curl --fail --location --proto '=https' --tlsv1.2 \
  --output "$WORK_DIR/$rclone_archive" \
  "https://github.com/rclone/rclone/releases/download/v$RCLONE_VERSION/$rclone_archive"

printf '%s  %s\n' "$RESTIC_SHA256" "$WORK_DIR/$restic_archive" | sha256sum --check --status - \
  || die 'restic release hash mismatch'
printf '%s  %s\n' "$RCLONE_SHA256" "$WORK_DIR/$rclone_archive" | sha256sum --check --status - \
  || die 'rclone release hash mismatch'

bunzip2 --stdout "$WORK_DIR/$restic_archive" >"$WORK_DIR/restic"
unzip -q "$WORK_DIR/$rclone_archive" -d "$WORK_DIR"
install -o root -g root -m 0755 "$WORK_DIR/restic" /usr/local/bin/restic
install -o root -g root -m 0755 \
  "$WORK_DIR/rclone-v$RCLONE_VERSION-linux-amd64/rclone" /usr/local/bin/rclone

[ "$(restic version | awk '{print $2}')" = "$RESTIC_VERSION" ] \
  || die 'installed restic version does not match the pin'
rclone version | head -n 1 | grep -Fx "rclone v$RCLONE_VERSION" >/dev/null \
  || die 'installed rclone version does not match the pin'

printf 'install-backup-tools: installed restic %s and rclone %s\n' \
  "$RESTIC_VERSION" "$RCLONE_VERSION"
