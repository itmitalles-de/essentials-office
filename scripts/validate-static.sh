#!/usr/bin/env bash
# Run repository-only checks. This script deliberately performs no host checks.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"

die() {
  printf 'validate-static: %s\n' "$*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || die 'Docker is required'
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required'

cd "$PROJECT_DIR"

# Values exist only in this process and are intentionally non-secret CI fixtures.
export POSTGRES_PASSWORD=compose-validation-placeholder
export POSTGRES_DB=nextcloud
export POSTGRES_USER=nextcloud
export NEXTCLOUD_ADMIN_PASSWORD=compose-validation-placeholder
export NEXTCLOUD_ADMIN_USER=ncadmin
export REDIS_PASSWORD=compose-validation-placeholder
export NEXTCLOUD_TRUSTED_DOMAINS=cloud.itmitalles.de
export TRUSTED_PROXIES=172.18.0.0/16
export PROXY_NETWORK=proxy_net
export COLLABORA_WOPI_HOST=cloud\.itmitalles\.de
export TURN_REALM=turn.invalid
export TURN_EXTERNAL_IP=192.0.2.10
export TURN_SECRET_FILE="$PROJECT_DIR/secrets/example-not-present"
export RESTORE_ROOT=/tmp/nextcloud-restore-validation

docker compose -f compose.yaml config -q
docker compose -f compose.yaml -f compose.collabora.yaml --profile office config -q
docker compose -f compose.yaml -f compose.talk-turn.yaml --profile talk-turn config -q
docker compose -f tests/restore/compose.yaml config -q

while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find scripts tests -type f -name '*.sh' -print0)

if command -v shellcheck >/dev/null 2>&1; then
  mapfile -d '' shell_scripts < <(find scripts tests -type f -name '*.sh' -print0)
  shellcheck "${shell_scripts[@]}"
else
  printf 'validate-static: shellcheck not installed; syntax checks still ran\n' >&2
fi

printf 'validate-static: Compose and shell checks passed (host checks intentionally skipped)\n'
