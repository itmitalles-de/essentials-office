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
SOURCE_COMPOSE=
SOURCE_ENV_EXAMPLE=
SOURCE_CADDY=
REPOSITORY_COMMIT=unknown
REPOSITORY_DIRTY=null
SOURCE_MODE=working-tree

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
command -v jq >/dev/null 2>&1 || die 'jq is required'
command -v git >/dev/null 2>&1 || die 'git is required'
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
[ ! -e "$FINAL_DIR" ] || die "backup target already exists: $FINAL_DIR"

WORK_DIR=$(mktemp -d "$BACKUP_ROOT/.${STAMP}.incomplete.XXXXXX")
chmod 0700 "$WORK_DIR"

SOURCE_COMPOSE="$PROJECT_DIR/compose.yaml"
SOURCE_ENV_EXAMPLE="$PROJECT_DIR/.env.example"
SOURCE_CADDY="$PROJECT_DIR/Caddyfile.example"
if git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" \
  rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPOSITORY_COMMIT=$(git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" rev-parse HEAD)
  if [ -z "$(git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" status --porcelain)" ]; then
    REPOSITORY_DIRTY=false
  else
    REPOSITORY_DIRTY=true
  fi
fi

if [ -n "${BACKUP_REPOSITORY_COMMIT:-}" ]; then
  [[ "$BACKUP_REPOSITORY_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
    die 'BACKUP_REPOSITORY_COMMIT must be a full Git commit'
  REPOSITORY_COMMIT=$BACKUP_REPOSITORY_COMMIT
  case "${BACKUP_SOURCE_TREE_IS_COMMIT:-false}" in
    true)
      case "$PROJECT_DIR" in
        /tmp/essentials-office-deploy-test.*) ;;
        *) die 'BACKUP_SOURCE_TREE_IS_COMMIT is restricted to the disposable deployment test' ;;
      esac
      REPOSITORY_DIRTY=false
      SOURCE_MODE=disposable-commit-copy
      ;;
    false|'')
      git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" \
        cat-file -e "$REPOSITORY_COMMIT^{commit}" 2>/dev/null ||
        die 'BACKUP_REPOSITORY_COMMIT is not available in this checkout'
      SOURCE_COMPOSE="$WORK_DIR/source.compose.yaml"
      SOURCE_ENV_EXAMPLE="$WORK_DIR/source.env.example"
      SOURCE_CADDY="$WORK_DIR/source.Caddyfile.example"
      git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" show \
        "$REPOSITORY_COMMIT:compose.yaml" >"$SOURCE_COMPOSE"
      git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" show \
        "$REPOSITORY_COMMIT:.env.example" >"$SOURCE_ENV_EXAMPLE"
      git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" show \
        "$REPOSITORY_COMMIT:Caddyfile.example" >"$SOURCE_CADDY"
      REPOSITORY_DIRTY=false
      SOURCE_MODE=committed-tree
      ;;
    *) die 'BACKUP_SOURCE_TREE_IS_COMMIT must be true or false' ;;
  esac
fi

docker compose --project-directory "$PROJECT_DIR" --env-file "$PROJECT_DIR/.env" \
  -f "$SOURCE_COMPOSE" config -q

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
[ -s "$WORK_DIR/nextcloud.pg.dump" ] || die 'PostgreSQL dump is empty'
docker compose exec -T db sh -ec 'exec pg_restore --list' \
  <"$WORK_DIR/nextcloud.pg.dump" >/dev/null || die 'PostgreSQL dump catalog is invalid'
tar --list --gzip --file "$WORK_DIR/nextcloud-files.tar.gz" html/ data/ >/dev/null ||
  die 'Nextcloud archive is unreadable or lacks html/data roots'

docker compose --project-directory "$PROJECT_DIR" --env-file "$PROJECT_DIR/.env" \
  -f "$SOURCE_COMPOSE" config --format json | jq '
  def redact_sensitive:
    walk(
      if type == "object" then
        with_entries(
          if (.key | test("(?i)(password|secret|token|credential|private[_-]?key|api[_-]?key)"))
          then .value = "[REDACTED]"
          else .
          end
        )
      else . end
    );
  .services |= with_entries(
    .value |= (
      if has("environment") then .environment |= with_entries(.value = "[REDACTED]") else . end
      | if has("env_file") then .env_file = ["[REDACTED]"] else . end
    )
  )
  | redact_sensitive
' >"$WORK_DIR/compose.resolved.redacted.json"
cp "$SOURCE_COMPOSE" "$WORK_DIR/compose.yaml"
cp "$SOURCE_ENV_EXAMPLE" "$WORK_DIR/env.example"
cp "$SOURCE_CADDY" "$WORK_DIR/Caddyfile.example"
printf '%s\n' "$REPOSITORY_COMMIT" >"$WORK_DIR/repository-commit.txt"
chmod 0600 "$WORK_DIR/repository-commit.txt"
app_versions=$(docker compose exec -T -u www-data app php occ app:list --output=json)
image_metadata=$(docker compose --project-directory "$PROJECT_DIR" --env-file "$PROJECT_DIR/.env" \
  -f "$SOURCE_COMPOSE" config --images | sort -u | while IFS= read -r image; do
  docker image inspect "$image" --format '{{json .}}' \
    | jq -c --arg requested "$image" \
      '{requested: $requested, imageId: .Id, repoDigests: (.RepoDigests // [] | sort)}'
done | jq -s .)
running_image_metadata=$(for service in db redis app cron; do
  container_id=$(docker compose ps -q "$service")
  [ -n "$container_id" ] || die "running container is missing for backup evidence: $service"
  docker inspect "$container_id" --format '{{json .}}' |
    jq -c --arg service "$service" \
      '{service: $service, imageReference: .Config.Image, imageId: .Image}'
done | jq -s .)
if [ "$SOURCE_MODE" = committed-tree ]; then
  rm -f -- "$SOURCE_COMPOSE" "$SOURCE_ENV_EXAMPLE" "$SOURCE_CADDY"
fi
jq -n --arg createdAt "$STAMP" --arg repositoryCommit "$REPOSITORY_COMMIT" \
  --argjson repositoryDirty "$REPOSITORY_DIRTY" --arg sourceMode "$SOURCE_MODE" \
  --argjson apps "$app_versions" --argjson images "$image_metadata" \
  --argjson runningImages "$running_image_metadata" \
  '{createdAt: $createdAt,
    repository: {commit: $repositoryCommit, dirty: $repositoryDirty, sourceMode: $sourceMode},
    apps: $apps, images: $images, runningImages: $runningImages}' >"$WORK_DIR/versions.json"
printf '%s\n' \
  'Database restore source: nextcloud.pg.dump (custom pg_dump format).' \
  'Filesystem archive includes html and data; PostgreSQL is represented by the logical dump and Redis is intentionally rebuilt empty.' \
  'compose.yaml and its redacted render describe the repository source commit recorded by this backup; versions.json also records the running container images.' \
  'The live .env file is intentionally not included. Restore it from protected secret storage.' \
  >"$WORK_DIR/README.txt"
(
  cd "$WORK_DIR"
  mapfile -d '' checksum_files < <(find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z)
  sha256sum -- "${checksum_files[@]}" | sed 's|  \./|  |' >SHA256SUMS
  sha256sum --check SHA256SUMS >/dev/null
)

docker compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null
MAINTENANCE_ENABLED=false
docker compose up -d cron >/dev/null
CRON_STOPPED=false

mv -- "$WORK_DIR" "$FINAL_DIR"
WORK_DIR=
docker compose exec -T -u www-data app php occ config:app:set essentialsplus evidence.backup \
  --value="$(date +%s)" >/dev/null 2>&1 || true
printf 'backup: created %s\n' "$FINAL_DIR"
