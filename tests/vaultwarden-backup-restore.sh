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
TEST_CADDYFILE="$TEST_ROOT/Caddyfile"
CREATED_NETWORK=false
CHROMEDRIVER_PID=

die() {
  printf 'vaultwarden-backup-restore-test: %s\n' "$*" >&2
  exit 1
}

compose_product() {
  docker compose --project-name "$PROJECT_NAME" --env-file "$CORE_ENV" \
    -f "$PROJECT_DIR/compose.yaml" -f "$PROJECT_DIR/compose.vaultwarden.yaml" \
    --profile vaultwarden "$@"
}

compose_browser() {
  docker compose --project-name "$PROJECT_NAME" --env-file "$CORE_ENV" \
    -f "$PROJECT_DIR/compose.yaml" -f "$PROJECT_DIR/compose.vaultwarden.yaml" \
    -f "$PROJECT_DIR/tests/vaultwarden/compose.browser.yaml" --profile vaultwarden "$@"
}

cleanup() {
  local status=$?
  if [ -n "$CHROMEDRIVER_PID" ]; then
    kill "$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
    wait "$CHROMEDRIVER_PID" 2>/dev/null || true
  fi
  compose_browser down --remove-orphans >/dev/null 2>&1 || true
  if [ "$CREATED_NETWORK" = true ]; then
    docker network rm "$PROXY_NETWORK" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TEST_ROOT"
  exit "$status"
}
trap cleanup EXIT INT TERM

for command in chmod cmp curl docker find grep install jq openssl python3 restic sed touch tr; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
chromedriver_bin=${CHROMEDRIVER_BIN:-}
if [ -n "$chromedriver_bin" ]; then
  [ -x "$chromedriver_bin" ] || die 'CHROMEDRIVER_BIN is not executable'
else
  chromedriver_bin=$(command -v chromedriver || true)
  [ -n "$chromedriver_bin" ] || die 'chromedriver is required'
fi
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
cp "$PROJECT_DIR/tests/vaultwarden/Caddyfile" "$TEST_CADDYFILE"
sed -i 's|^DOMAIN=.*|DOMAIN=https://vault.test.invalid|' "$VAULT_ENV"
chmod 600 "$VAULT_ENV"
install -d -m 0700 "$DATA_DIR" "$BACKUP_DIR"
chown 1000:1000 "$DATA_DIR"

docker network create "$PROXY_NETWORK" >/dev/null
CREATED_NETWORK=true
export PROXY_NETWORK VAULTWARDEN_ENV_FILE="$VAULT_ENV" VAULTWARDEN_DATA_DIR="$DATA_DIR" VAULTWARDEN_BACKUP_DIR="$BACKUP_DIR"
export VAULTWARDEN_TEST_CADDYFILE="$TEST_CADDYFILE"
export VAULTWARDEN_CONTAINER_NAME="$PROJECT_NAME-vaultwarden"

compose_product config -q
signups=$(compose_product config --format json | jq -r '.services.vaultwarden.environment.SIGNUPS_ALLOWED')
[ "$signups" = false ] || die 'product Vaultwarden profile does not keep registration closed'
compose_product up -d --wait vaultwarden >/dev/null
NEXTCLOUD_ENV_FILE="$CORE_ENV" VAULTWARDEN_COMPOSE_PROJECT_NAME="$PROJECT_NAME" \
  "$PROJECT_DIR/scripts/vaultwarden-healthcheck.sh"
compose_product down --remove-orphans >/dev/null

VAULTWARDEN_BROWSER_PORT=$(python3 - <<'PY'
import socket
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
    listener.bind(("127.0.0.1", 0))
    print(listener.getsockname()[1])
PY
)
[[ "$VAULTWARDEN_BROWSER_PORT" =~ ^[0-9]+$ ]] || die 'could not allocate a loopback browser port'
export VAULTWARDEN_BROWSER_PORT
sed -i "s|^DOMAIN=.*|DOMAIN=https://localhost:$VAULTWARDEN_BROWSER_PORT|" "$VAULT_ENV"
compose_browser config -q
compose_browser up -d --wait vaultwarden vaultwarden-browser-proxy >/dev/null
port_mapping=$(compose_browser port vaultwarden-browser-proxy 8443)
[[ "$port_mapping" =~ ^127\.0\.0\.1:[0-9]+$ ]] || die "browser port is not loopback-only: $port_mapping"
[ "${port_mapping##*:}" = "$VAULTWARDEN_BROWSER_PORT" ] || die 'browser port differs from the protected Vaultwarden DOMAIN'
if compose_browser port vaultwarden 8080 >/dev/null 2>&1; then
  die 'browser fixture exposed Vaultwarden directly instead of through TLS'
fi
curl --fail --silent --show-error --insecure "https://localhost:$VAULTWARDEN_BROWSER_PORT/alive" >/dev/null
browser_secrets="$TEST_ROOT/browser.env"
umask 077
{
  printf 'OWNER_EMAIL=owner-%s@example.com\n' "$RANDOM"
  printf 'OWNER_PASSWORD=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
  printf 'MEMBER_EMAIL=member-%s@example.com\n' "$RANDOM"
  printf 'MEMBER_PASSWORD=%s\n' "$(openssl rand -base64 36 | tr -d '\n')"
} >"$browser_secrets"
"$chromedriver_bin" --port=9516 --allowed-ips=127.0.0.1 >/dev/null 2>&1 &
CHROMEDRIVER_PID=$!
sleep 1
chromium_bin=${CHROMIUM_BIN:-}
if [ -z "$chromium_bin" ]; then
  chromium_bin=$(command -v chrome || command -v google-chrome || command -v chromium || command -v chromium-browser || true)
fi
[ -n "$chromium_bin" ] || die 'Chromium or Chrome executable is missing'
VAULTWARDEN_BASE_URL="https://localhost:$VAULTWARDEN_BROWSER_PORT" \
VAULTWARDEN_BROWSER_SECRETS_FILE="$browser_secrets" \
CHROMIUM_BIN="$chromium_bin" \
  python3 "$PROJECT_DIR/tests/e2e/vaultwarden.py"
kill "$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
wait "$CHROMEDRIVER_PID" 2>/dev/null || true
CHROMEDRIVER_PID=

# The marker is synthetic test data. The initialized Vaultwarden SQLite database
# and generated RSA material exercise the real backup and restore path.
touch "$DATA_DIR/synthetic-restore-marker"
"$PROJECT_DIR/scripts/vaultwarden-backup.sh"
backup=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)
[ -n "$backup" ] || die 'backup directory was not created'
python3 "$PROJECT_DIR/tests/verify-vaultwarden-db.py" "$backup/db.sqlite3"
"$PROJECT_DIR/scripts/vaultwarden-restore.sh" "$backup" "$RESTORE_DIR"
[ -f "$RESTORE_DIR/synthetic-restore-marker" ] || die 'synthetic marker is absent after restore'
[ -f "$RESTORE_DIR/db.sqlite3" ] || die 'SQLite database is absent after restore'
python3 "$PROJECT_DIR/tests/verify-vaultwarden-db.py" "$RESTORE_DIR/db.sqlite3"

export RESTIC_REPOSITORY="$TEST_ROOT/restic-repository"
export RESTIC_PASSWORD_FILE="$TEST_ROOT/restic-password"
openssl rand -base64 48 >"$RESTIC_PASSWORD_FILE"
chmod 0600 "$RESTIC_PASSWORD_FILE"
restic init >/dev/null
restic backup --quiet --tag essentialsplus-office-vaultwarden "$backup" "$VAULT_ENV"
restic check --read-data >/dev/null
restic_stage="$TEST_ROOT/restic-stage"
restic restore latest --target "$restic_stage" >/dev/null
restic_db=$(find "$restic_stage" -type f -path '*/backups/*/db.sqlite3' -print -quit)
[ -n "$restic_db" ] || die 'encrypted restic restore did not reproduce the Vaultwarden database'
cmp -- "$backup/db.sqlite3" "$restic_db" || die 'restic-restored Vaultwarden database differs byte-for-byte'
printf 'vaultwarden-backup-restore-test: closed product profile, Web Vault browser flow, encrypted backup, and empty-target restore passed\n'
