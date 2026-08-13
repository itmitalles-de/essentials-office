#!/usr/bin/env bash
# Create a consistent, local Nextcloud backup. Run as root or through sudo.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
BACKUP_ROOT=
DATA_ROOT=
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
FINAL_DIR=
WORK_DIR=
MAINTENANCE_ENABLED=false
CRON_STOPPED=false

die() {
  printf 'backup: %s\n' "$*" >&2
  exit 1
}

env_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROJECT_DIR/.env"
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
command -v sha256sum >/dev/null 2>&1 || die 'sha256sum is required'
[ -f "$PROJECT_DIR/.env" ] || die "missing $PROJECT_DIR/.env; run bootstrap.sh first"

DATA_ROOT=$(env_value NEXTCLOUD_DATA_ROOT)
[ -n "$DATA_ROOT" ] || die 'NEXTCLOUD_DATA_ROOT is empty in .env'
BACKUP_ROOT=${BACKUP_DIR:-$DATA_ROOT/backups}
case "$BACKUP_ROOT" in
  /*) ;;
  *) die 'backup root must be an absolute path' ;;
esac
[ "$BACKUP_ROOT" != / ] || die 'backup root must not be the filesystem root'
FINAL_DIR="$BACKUP_ROOT/$STAMP"

cd "$PROJECT_DIR"
docker compose config -q
mkdir -p "$BACKUP_ROOT"
chmod 0700 "$BACKUP_ROOT"
exec 9>"$BACKUP_ROOT/.backup.lock"
flock -n 9 || die 'another backup is already running'

WORK_DIR=$(mktemp -d "$BACKUP_ROOT/.${STAMP}.incomplete.XXXXXX")
chmod 0700 "$WORK_DIR"

docker compose exec -T -u www-data app php occ status --output=json >/dev/null
docker compose exec -T -u www-data app php occ maintenance:mode --on >/dev/null
MAINTENANCE_ENABLED=true
docker compose stop --timeout 10 cron >/dev/null
CRON_STOPPED=true

# Preserve object ownership and ACL metadata. Nextcloud 34 can use a dedicated
# application database role even when POSTGRES_USER is the administrative role.
docker compose exec -T db sh -ec 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' >"$WORK_DIR/nextcloud.pg.dump"

# PostgreSQL is backed up through pg_dump above. Do not copy its live data
# directory: a raw copy while PostgreSQL is running is not a consistent backup.
tar --create --gzip --file "$WORK_DIR/nextcloud-files.tar.gz" \
  --numeric-owner --acls --xattrs \
  -C "$DATA_ROOT" html data

docker compose config >"$WORK_DIR/compose.resolved.yaml"
sed -Ei \
  -e 's/^([[:space:]]*(POSTGRES_PASSWORD|NEXTCLOUD_ADMIN_PASSWORD|REDIS_PASSWORD|REDIS_HOST_PASSWORD):).*/\1 "[REDACTED]"/' \
  "$WORK_DIR/compose.resolved.yaml"
cp compose.yaml "$WORK_DIR/compose.yaml"
cp .env.example "$WORK_DIR/env.example"
cp Caddyfile.example "$WORK_DIR/Caddyfile.example"
if git -C "$PROJECT_DIR" rev-parse HEAD >"$WORK_DIR/repository-commit.txt" 2>/dev/null; then
  chmod 0600 "$WORK_DIR/repository-commit.txt"
else
  printf 'unknown\n' >"$WORK_DIR/repository-commit.txt"
fi
printf '%s\n' \
  'Database restore source: nextcloud.pg.dump (custom pg_dump format).' \
  'Filesystem archive includes html and data; PostgreSQL is represented by the logical dump and Redis is intentionally rebuilt empty.' \
  'The live .env file is intentionally not included. Restore it from protected secret storage.' \
  >"$WORK_DIR/README.txt"
(
  cd "$WORK_DIR"
  mapfile -d '' checksum_files < <(find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z)
  sha256sum -- "${checksum_files[@]}" | sed 's|  \./|  |' >SHA256SUMS
)

docker compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null
MAINTENANCE_ENABLED=false
docker compose up -d cron >/dev/null
CRON_STOPPED=false

mv -- "$WORK_DIR" "$FINAL_DIR"
WORK_DIR=
printf 'backup: created %s\n' "$FINAL_DIR"
