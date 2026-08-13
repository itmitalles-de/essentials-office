#!/usr/bin/env bash
# Start only pinned Collabora in a random, disposable proxy network.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT=$(mktemp -d /tmp/essentialsplus-collabora-test.XXXXXX)
suffix=${TEST_ROOT##*.}
PROJECT_NAME="essentialsplus-collabora-${suffix,,}"
PROXY_NETWORK="essentialsplus-collabora-proxy-${suffix,,}"
ENV_FILE="$TEST_ROOT/core.env"
CREATED_NETWORK=false
CURL_IMAGE='curlimages/curl:8.16.0@sha256:3af101f2b2c560bb7ca1be412a8087c9d382f01915625431b7d84cf166536a3a'

die() {
  printf 'collabora-health-test: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" \
    -f "$PROJECT_DIR/compose.yaml" -f "$PROJECT_DIR/compose.collabora.yaml" --profile office "$@"
}

cleanup() {
  local status=$?
  compose down --remove-orphans >/dev/null 2>&1 || true
  if [ "$CREATED_NETWORK" = true ]; then docker network rm "$PROXY_NETWORK" >/dev/null 2>&1 || true; fi
  rm -rf -- "$TEST_ROOT"
  exit "$status"
}
trap cleanup EXIT INT TERM

for command in curl docker grep jq mktemp sed seq sleep; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
cp "$PROJECT_DIR/.env.example" "$ENV_FILE"
sed -i \
  -e 's/^POSTGRES_PASSWORD=$/POSTGRES_PASSWORD=synthetic-postgres/' \
  -e 's/^NEXTCLOUD_ADMIN_PASSWORD=$/NEXTCLOUD_ADMIN_PASSWORD=synthetic-nextcloud/' \
  -e 's/^REDIS_PASSWORD=$/REDIS_PASSWORD=synthetic-redis/' \
  "$ENV_FILE"
chmod 600 "$ENV_FILE"
docker network create "$PROXY_NETWORK" >/dev/null
CREATED_NETWORK=true
export PROXY_NETWORK COLLABORA_CONTAINER_NAME="$PROJECT_NAME-service"
export COLLABORA_WOPI_HOST='deploy-test\.invalid'
export COLLABORA_PUBLIC_HOST=office.test.invalid

compose config -q
compose config --format json | jq -e '
  .services.collabora.environment.aliasgroup1 == "https://deploy-test\\.invalid:443"
  and (.services.collabora.networks | keys) == ["proxy_net"]
  and (.services.collabora.ports // []) == []
' >/dev/null || die 'Collabora WOPI host or network boundary is invalid'
compose up -d --wait collabora >/dev/null
container_id=$(compose ps -q collabora)
[ -n "$container_id" ] || die 'Collabora container is unavailable'
[ "$(docker inspect --format '{{.Config.Image}}' "$container_id")" = 'collabora/code:26.04.3.1.1@sha256:6b70f91f0b6e9c76f75f162f58ef0a12cf9415d78e14713d33c0318ddc4a2cc0' ] ||
  die 'Collabora runtime image differs from the exact contract pin'
[ "$(docker inspect --format '{{.State.Health.Status}}' "$container_id")" = healthy ] || die 'Collabora is not healthy'
[ -z "$(docker port "$container_id")" ] || die 'Collabora unexpectedly publishes a host port'
discovery=$(docker run --rm --network "$PROXY_NETWORK" "$CURL_IMAGE" \
  --fail --silent --show-error http://collabora:9980/hosting/discovery)
grep -q 'wopi-discovery' <<<"$discovery" || die 'Collabora discovery response is invalid'
compose restart collabora >/dev/null
for _ in $(seq 1 90); do
  [ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id")" = healthy ] && break
  sleep 2
done
[ "$(docker inspect --format '{{.State.Health.Status}}' "$container_id")" = healthy ] || die 'Collabora did not recover after restart'
docker run --rm --network "$PROXY_NETWORK" "$CURL_IMAGE" \
  --fail --silent --show-error http://collabora:9980/hosting/discovery >/dev/null
printf 'collabora-health-test: pinned isolated service, discovery, no host port, and restart recovery passed\n'
