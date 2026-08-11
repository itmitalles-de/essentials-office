#!/usr/bin/env bash
# Update only the floating minor/patch tags inside the declared major versions.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

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

mapfile -t images < <(docker compose config --images | sort -u)
expected_images=(nextcloud:34-apache postgres:17-alpine redis:7-alpine)
for image in "${expected_images[@]}"; do
  printf '%s\n' "${images[@]}" | grep -Fxq "$image" || die "required pinned image is missing: $image"
done
if [ "${#images[@]}" -ne "${#expected_images[@]}" ]; then
  die 'compose.yaml contains an unexpected image; inspect the change before updating'
fi

"$SCRIPT_DIR/backup.sh"
docker compose pull
docker compose up -d
docker compose exec -T -u www-data app php occ status --output=json
"$SCRIPT_DIR/healthcheck.sh"
printf 'update: completed without a major-version change\n'
