#!/usr/bin/env bash
# Start only the optional Vaultwarden profile and prove backup/restore in /tmp.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT=$(mktemp -d /tmp/office-vaultwarden-test.XXXXXX)
PROJECT_NAME="office-vaultwarden-test-$RANDOM"
PROXY_NETWORK="office-vaultwarden-test-proxy-$RANDOM"
CORE_ENV="$TEST_ROOT/nextcloud.env"
VAULT_ENV="$TEST_ROOT/vaultwarden.env"
DATA_DIR="$TEST_ROOT/data"
BACKUP_DIR="$TEST_ROOT/backups"
RESTORE_DIR="$TEST_ROOT/restore"
CREATED_NETWORK=false

die() {
  printf 'vaultwarden-backup-restore-test: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose --project-name "$PROJECT_NAME" --env-file "$CORE_ENV" \
    -f "$PROJECT_DIR/compose.yaml" -f "$PROJECT_DIR/compose.vaultwarden.yaml" \
    --profile vaultwarden "$@"
}

cleanup() {
  local status=$?
  compose down --remove-orphans >/dev/null 2>&1 || true
  if [ "$CREATED_NETWORK" = true ]; then
    docker network rm "$PROXY_NETWORK" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TEST_ROOT"
  exit "$status"
}
trap cleanup EXIT INT TERM

for command in docker grep install sed touch; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
docker info >/dev/null 2>&1 || die 'Docker daemon is not available'
if docker ps --format '{{.Names}}' | grep -Fxq essentialsplus-office-vaultwarden; then
  die 'the default Vaultwarden container already exists; refusing to interfere with an existing module'
fi

cp "$PROJECT_DIR/.env.example" "$CORE_ENV"
sed -i \
  -e 's/^POSTGRES_PASSWORD=$/POSTGRES_PASSWORD=test-postgres-password/' \
  -e 's/^NEXTCLOUD_ADMIN_PASSWORD=$/NEXTCLOUD_ADMIN_PASSWORD=test-nextcloud-password/' \
  -e 's/^REDIS_PASSWORD=$/REDIS_PASSWORD=test-redis-password/' \
  "$CORE_ENV"
cp "$PROJECT_DIR/vaultwarden.env.example" "$VAULT_ENV"
sed -i 's|^DOMAIN=.*|DOMAIN=https://vault.test.invalid|' "$VAULT_ENV"
chmod 600 "$VAULT_ENV"
install -d -m 0700 "$DATA_DIR" "$BACKUP_DIR"
chown 1000:1000 "$DATA_DIR"

docker network create "$PROXY_NETWORK" >/dev/null
CREATED_NETWORK=true
export PROXY_NETWORK VAULTWARDEN_ENV_FILE="$VAULT_ENV" VAULTWARDEN_DATA_DIR="$DATA_DIR" VAULTWARDEN_BACKUP_DIR="$BACKUP_DIR"
export VAULTWARDEN_CONTAINER_NAME="$PROJECT_NAME-vaultwarden"

compose config -q
compose up -d --wait vaultwarden >/dev/null
NEXTCLOUD_ENV_FILE="$CORE_ENV" VAULTWARDEN_COMPOSE_PROJECT_NAME="$PROJECT_NAME" \
  "$PROJECT_DIR/scripts/vaultwarden-healthcheck.sh"

# The marker is synthetic test data. The initialized Vaultwarden SQLite database
# and generated RSA material exercise the real backup and restore path.
touch "$DATA_DIR/synthetic-restore-marker"
"$PROJECT_DIR/scripts/vaultwarden-backup.sh"
backup=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)
[ -n "$backup" ] || die 'backup directory was not created'
"$PROJECT_DIR/scripts/vaultwarden-restore.sh" "$backup" "$RESTORE_DIR"
[ -f "$RESTORE_DIR/synthetic-restore-marker" ] || die 'synthetic marker is absent after restore'
[ -f "$RESTORE_DIR/db.sqlite3" ] || die 'SQLite database is absent after restore'
printf 'vaultwarden-backup-restore-test: isolated synthetic backup and empty-target restore passed\n'
