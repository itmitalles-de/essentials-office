#!/usr/bin/env bash
# Update the intentionally pinned Vaultwarden image after a separate version change.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
NEXTCLOUD_ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
VAULTWARDEN_COMPOSE_PROJECT_NAME=${VAULTWARDEN_COMPOSE_PROJECT_NAME:-}

die() {
  printf 'vaultwarden-update: %s\n' "$*" >&2
  exit 1
}

compose() {
  local -a project_args=()
  if [ -n "$VAULTWARDEN_COMPOSE_PROJECT_NAME" ]; then
    project_args=(--project-name "$VAULTWARDEN_COMPOSE_PROJECT_NAME")
  fi
  docker compose "${project_args[@]}" --env-file "$NEXTCLOUD_ENV_FILE" \
    -f "$PROJECT_DIR/compose.yaml" -f "$PROJECT_DIR/compose.vaultwarden.yaml" \
    --profile vaultwarden "$@"
}

command -v docker >/dev/null 2>&1 || die 'Docker is required'
[ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
[ -f "${VAULTWARDEN_ENV_FILE:-$PROJECT_DIR/.vaultwarden.env}" ] ||
  die 'missing private Vaultwarden environment file'
compose config -q
compose config --images | grep -Fxq 'vaultwarden/server:1.37.1@sha256:ebdfe70701c60ac0c28c697e787cea767d7972940b786037b29fe0d507f821e8' ||
  die 'the expected pinned Vaultwarden image is missing from the overlay'

"$SCRIPT_DIR/vaultwarden-backup.sh"
compose pull vaultwarden
compose up -d --no-deps vaultwarden

for _ in $(seq 1 24); do
  if NEXTCLOUD_ENV_FILE="$NEXTCLOUD_ENV_FILE" \
    VAULTWARDEN_COMPOSE_PROJECT_NAME="$VAULTWARDEN_COMPOSE_PROJECT_NAME" \
    VAULTWARDEN_ENV_FILE="${VAULTWARDEN_ENV_FILE:-$PROJECT_DIR/.vaultwarden.env}" \
    "$SCRIPT_DIR/vaultwarden-healthcheck.sh" >/dev/null; then
    printf 'vaultwarden-update: completed successfully\n'
    exit 0
  fi
  sleep 5
done
die 'health check did not pass; use the documented rollback procedure'
