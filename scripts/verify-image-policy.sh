#!/usr/bin/env bash
# Refuse unexpected images and every unreviewed major-version change.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE=${1:-"$PROJECT_DIR/compose.yaml"}

die() {
  printf 'verify-image-policy: %s\n' "$*" >&2
  exit 1
}

for command in docker grep sort; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$COMPOSE_FILE" ] || die "missing Compose file: $COMPOSE_FILE"
mapfile -t images < <(docker compose -f "$COMPOSE_FILE" config --images | sort -u)
[ "${#images[@]}" -eq 3 ] || die 'base Compose contains an unexpected image count'
patterns=(
  '^nextcloud:34\.[0-9]+\.[0-9]+-apache@sha256:[0-9a-f]{64}$'
  '^postgres:17\.[0-9]+-alpine@sha256:[0-9a-f]{64}$'
  '^redis:7\.[0-9]+\.[0-9]+-alpine@sha256:[0-9a-f]{64}$'
)
labels=('Nextcloud 34 patch' 'PostgreSQL 17 minor' 'Redis 7 patch')
for index in "${!patterns[@]}"; do
  matches=$(printf '%s\n' "${images[@]}" | grep -Ec "${patterns[$index]}" || true)
  [ "$matches" -eq 1 ] || die "required reviewed ${labels[$index]} tag plus digest is missing"
done
printf 'verify-image-policy: exact digests and approved Nextcloud 34, PostgreSQL 17, and Redis 7 boundaries passed\n'
