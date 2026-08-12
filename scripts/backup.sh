#!/usr/bin/env bash
# Create a consistent, local Nextcloud backup. Run as root or through sudo.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
BACKUP_ROOT=${BACKUP_DIR:-/srv/nextcloud/backups}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
FINAL_DIR="$BACKUP_ROOT/$STAMP"
WORK_DIR=
MAINTENANCE_ENABLED=false
CRON_STOPPED=false

die() {
  printf 'backup: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local status=$?
  if [ "$MAINTENANCE_ENABLED" = true ]; then
    if ! docker compose -f "$PROJECT_DIR/compose.yaml" exec -T -u www-data app php occ maintenance:mode --off >/dev/null; then
      printf 'backup: WARNING: could not disable maintenance mode automatically\n' >&2
      status=1
    fi
  fi
  if [ "$CRON_STOPPED" = true ]; then
    if ! docker compose -f "$PROJECT_DIR/compose.yaml" up -d cron >/dev/null; then
      printf 'backup: WARNING: could not restart the cron container automatically\n' >&2
      status=1
    fi
  fi
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && [ "$status" -ne 0 ]; then
    rm -rf -- "$WORK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

command -v docker >/dev/null 2>&1 || die 'Docker is required'
command -v tar >/dev/null 2>&1 || die 'tar is required'
command -v flock >/dev/null 2>&1 || die 'flock is required'
[ -f "$PROJECT_DIR/.env" ] || die "missing $PROJECT_DIR/.env; run bootstrap.sh first"

cd "$PROJECT_DIR"
docker compose config -q
mkdir -p -m 0700 "$BACKUP_ROOT"
exec 9>"$BACKUP_ROOT/.backup.lock"
flock -n 9 || die 'another backup is already running'

WORK_DIR=$(mktemp -d "$BACKUP_ROOT/.${STAMP}.incomplete.XXXXXX")
chmod 0700 "$WORK_DIR"

docker compose exec -T -u www-data app php occ status --output=json >/dev/null
docker compose exec -T -u www-data app php occ maintenance:mode --on >/dev/null
MAINTENANCE_ENABLED=true
docker compose stop --timeout 10 cron >/dev/null
CRON_STOPPED=true

docker compose exec -T db sh -ec 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-privileges' >"$WORK_DIR/nextcloud.pg.dump"

# PostgreSQL is backed up through pg_dump above. Do not copy its live data
# directory: a raw copy while PostgreSQL is running is not a consistent backup.
tar --create --gzip --file "$WORK_DIR/nextcloud-files.tar.gz" \
  --numeric-owner --acls --xattrs \
  -C /srv/nextcloud html data redis

docker compose config >"$WORK_DIR/compose.resolved.yaml"
sed -Ei \
  -e 's/^([[:space:]]*(POSTGRES_PASSWORD|NEXTCLOUD_ADMIN_PASSWORD|REDIS_PASSWORD|REDIS_HOST_PASSWORD):).*/\1 "[REDACTED]"/' \
  "$WORK_DIR/compose.resolved.yaml"
cp compose.yaml "$WORK_DIR/compose.yaml"
cp .env.example "$WORK_DIR/env.example"
cp Caddyfile.example "$WORK_DIR/Caddyfile.example"
printf '%s\n' \
  'Database restore source: nextcloud.pg.dump (custom pg_dump format).' \
  'Filesystem archive includes html, data, and redis; PostgreSQL is intentionally excluded because the logical dump is consistent.' \
  'The live .env file is intentionally not included. Restore it from protected secret storage.' \
  >"$WORK_DIR/README.txt"

docker compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null
MAINTENANCE_ENABLED=false
docker compose up -d cron >/dev/null
CRON_STOPPED=false

mv -- "$WORK_DIR" "$FINAL_DIR"
WORK_DIR=
printf 'backup: created %s\n' "$FINAL_DIR"
