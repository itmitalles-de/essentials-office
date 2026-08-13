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
expected=(nextcloud:34-apache postgres:17-alpine redis:7-alpine)
[ "${#images[@]}" -eq "${#expected[@]}" ] || die 'base Compose contains an unexpected image count'
for image in "${expected[@]}"; do
  printf '%s\n' "${images[@]}" | grep -Fxq "$image" || die "required approved major image is missing: $image"
done
printf 'verify-image-policy: approved Nextcloud 34, PostgreSQL 17, and Redis 7 major boundaries passed\n'
