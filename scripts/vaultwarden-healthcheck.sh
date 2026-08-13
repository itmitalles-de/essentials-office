#!/usr/bin/env bash
# Check the isolated Vaultwarden container without requiring a public route.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
NEXTCLOUD_ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
VAULTWARDEN_COMPOSE_PROJECT_NAME=${VAULTWARDEN_COMPOSE_PROJECT_NAME:-}
VAULTWARDEN_CONTAINER_NAME=${VAULTWARDEN_CONTAINER_NAME:-essentialsplus-office-vaultwarden}

die() {
  printf 'vaultwarden-healthcheck: %s\n' "$*" >&2
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

for command in docker grep; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
[ -f "${VAULTWARDEN_ENV_FILE:-$PROJECT_DIR/.vaultwarden.env}" ] ||
  die 'missing private Vaultwarden environment file'

compose config -q
compose ps --status running --services | grep -Fxq vaultwarden || die 'vaultwarden is not running'
container_id=$(compose ps -q vaultwarden)
[ -n "$container_id" ] || die 'Vaultwarden container ID is unavailable'
health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id")
[ "$health" = healthy ] || die "Vaultwarden container health is $health"
if docker port "$container_id" 8080 2>/dev/null | grep -q .; then
  die 'Vaultwarden must not publish a host port'
fi
compose exec -T vaultwarden /healthcheck.sh >/dev/null || die 'Vaultwarden internal health check failed'
printf 'vaultwarden-healthcheck: isolated container is healthy and has no host port\n'
