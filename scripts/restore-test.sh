#!/usr/bin/env bash
# Restore one backup into an isolated, disposable Compose project.
# shellcheck disable=SC2016 # Variables in single quotes expand inside the target containers.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/tests/restore/compose.yaml"
ENV_FILE=${RESTORE_ENV_FILE:-$PROJECT_DIR/.env}
DEFAULT_BACKUP_ROOT=${BACKUP_DIR:-/srv/nextcloud/backups}
WORK_DIR=
RESTORE_ROOT=
RESTORE_PROJECT=

die() {
  printf 'restore-test: %s\n' "$*" >&2
  exit 1
}

compose() {
  RESTORE_ROOT="$RESTORE_ROOT" docker compose \
    --project-name "$RESTORE_PROJECT" \
    --env-file "$ENV_FILE" \
    --file "$COMPOSE_FILE" "$@"
}

cleanup() {
  local status=$?
  if [ -n "$RESTORE_PROJECT" ] && [ -n "$RESTORE_ROOT" ]; then
    compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/nextcloud-restore-test.* ]]; then
    rm -rf --one-file-system -- "$WORK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

for command in docker grep mktemp tar; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required'
[ -f "$ENV_FILE" ] || die "missing environment file: $ENV_FILE"

if [ "$#" -gt 1 ]; then
  die 'usage: restore-test.sh [BACKUP_DIRECTORY]'
fi
backup_dir=${1:-}
if [ -z "$backup_dir" ]; then
  latest=$(find "$DEFAULT_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    ! -name '.*' -printf '%f\n' | sort | tail -n 1)
  [ -n "$latest" ] || die "no backup found below $DEFAULT_BACKUP_ROOT"
  backup_dir="$DEFAULT_BACKUP_ROOT/$latest"
fi

[ -d "$backup_dir" ] || die "backup directory not found: $backup_dir"
for file in nextcloud.pg.dump nextcloud-files.tar.gz; do
  [ -s "$backup_dir/$file" ] || die "backup artifact missing or empty: $file"
done
if [ -f "$backup_dir/SHA256SUMS" ]; then
  (cd "$backup_dir" && sha256sum --check SHA256SUMS)
fi

# Reject archive paths that could escape the disposable restore root.
while IFS= read -r entry; do
  case "$entry" in
    html|html/*|data|data/*) ;;
    *) die "unexpected or unsafe archive entry: $entry" ;;
  esac
done < <(tar --list --gzip --file "$backup_dir/nextcloud-files.tar.gz")

WORK_DIR=$(mktemp -d /tmp/nextcloud-restore-test.XXXXXX)
RESTORE_ROOT="$WORK_DIR/root"
RESTORE_PROJECT="nc-restore-${RANDOM}-$$"
install -d -m 0700 "$RESTORE_ROOT/postgres" "$RESTORE_ROOT/redis"
tar --extract --gzip --file "$backup_dir/nextcloud-files.tar.gz" \
  --directory "$RESTORE_ROOT" --numeric-owner --acls --xattrs

docker run --rm --entrypoint sh \
  --volume "$RESTORE_ROOT/postgres:/target" postgres:17-alpine \
  -ec 'chown "$(id -u postgres):$(id -g postgres)" /target; chmod 0700 /target'
docker run --rm --entrypoint sh \
  --volume "$RESTORE_ROOT/redis:/target" redis:7-alpine \
  -ec 'chown "$(id -u redis):$(id -g redis)" /target; chmod 0700 /target'

compose config -q
compose up --detach --wait db redis

# Nextcloud 34 may store a dedicated application role (for example oc_admin*)
# in config.php. Recreate that login before pg_restore applies object owners.
# The password is passed directly from config.php to PostgreSQL and is never
# emitted to stdout, the process list, or a temporary file.
compose run --rm --no-deps --entrypoint php app -r '
$CONFIG = [];
require "/var/www/html/config/config.php";
$role = $CONFIG["dbuser"] ?? "";
$password = $CONFIG["dbpassword"] ?? "";
if (!preg_match("/^[A-Za-z_][A-Za-z0-9_]*$/D", $role) || $password === "") {
    fwrite(STDERR, "restore-test: invalid database role in config.php\n");
    exit(2);
}
$pdo = new PDO(
    "pgsql:host=" . getenv("POSTGRES_HOST") . ";dbname=" . getenv("POSTGRES_DB"),
    getenv("POSTGRES_USER"),
    getenv("POSTGRES_PASSWORD"),
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
$identifier = "\"" . str_replace("\"", "\"\"", $role) . "\"";
$quotedPassword = $pdo->quote($password);
$query = $pdo->prepare("SELECT 1 FROM pg_roles WHERE rolname = :role");
$query->execute([":role" => $role]);
if ($query->fetchColumn() === false) {
    $pdo->exec("CREATE ROLE " . $identifier . " LOGIN PASSWORD " . $quotedPassword);
} else {
    $pdo->exec("ALTER ROLE " . $identifier . " LOGIN PASSWORD " . $quotedPassword);
}
' >/dev/null
compose exec -T db sh -ec \
  'exec pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
  <"$backup_dir/nextcloud.pg.dump"
compose up --detach --wait app

# The filesystem snapshot is intentionally taken while maintenance mode is on.
compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null
status=$(compose exec -T -u www-data app php occ status --output=json)
printf '%s\n' "$status" | grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' || die 'restored Nextcloud is not installed'
printf '%s\n' "$status" | grep -Eq '"maintenance"[[:space:]]*:[[:space:]]*false' || die 'restored Nextcloud remained in maintenance mode'
compose exec -T db sh -ec 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null
compose exec -T redis sh -ec 'redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping | grep -qx PONG'

printf 'restore-test: disposable restore passed for %s\n' "$(basename -- "$backup_dir")"
