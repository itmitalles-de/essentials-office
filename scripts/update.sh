#!/usr/bin/env bash
# Update only the floating minor/patch tags inside the declared major versions.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"

die() {
  printf 'update: %s\n' "$*" >&2
  exit 1
}

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

command -v docker >/dev/null 2>&1 || die 'Docker is required'
[ -f "$PROJECT_DIR/.env" ] || die 'missing .env; run bootstrap.sh first'
cd "$PROJECT_DIR"
docker compose config -q
"$SCRIPT_DIR/verify-image-policy.sh" "$PROJECT_DIR/compose.yaml"

"$SCRIPT_DIR/backup.sh"
before_images=$(docker compose images --format json 2>/dev/null || true)
docker compose pull
docker compose up -d
docker compose exec -T -u www-data app php occ status --output=json
"$SCRIPT_DIR/healthcheck.sh"
mkdir -p "$PROJECT_DIR/reports"
printf '%s\n' "$before_images" >"$PROJECT_DIR/reports/update-rollback-images-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
printf 'update: completed without a major-version change\n'
