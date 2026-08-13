#!/usr/bin/env bash
# Prove a clean, idempotent repository deployment without touching production.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"
WITH_APPS=false
WITH_BROWSER=false
WORK_DIR=
DATA_ROOT=
PROJECT_NAME=
PROXY_NETWORK=
CHROMEDRIVER_PID=

die() {
  printf 'deploy-test: %s\n' "$*" >&2
  exit 1
}

set_env_value() {
  local key=$1 value=$2
  sed -i "s|^${key}=.*|${key}=${value}|" "$WORK_DIR/.env"
}

cleanup() {
  local status=$?
  if [ -n "$CHROMEDRIVER_PID" ]; then
    kill "$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
    wait "$CHROMEDRIVER_PID" 2>/dev/null || true
  fi
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/workspace-suite-deploy-test.* ]]; then
    if [ -f "$WORK_DIR/.env" ]; then
      docker compose --project-directory "$WORK_DIR" down --volumes --remove-orphans >/dev/null 2>&1 || true
    fi
    rm -rf -- "$WORK_DIR"
  fi
  if [ -n "$PROXY_NETWORK" ] && [[ "$PROXY_NETWORK" == workspace-suite-test-proxy-* ]]; then
    docker network rm "$PROXY_NETWORK" >/dev/null 2>&1 || true
  fi
  if [ -n "$DATA_ROOT" ] && [[ "$DATA_ROOT" == /tmp/workspace-suite-deploy-data.* ]]; then
    rm -rf -- "$DATA_ROOT"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apps) WITH_APPS=true ;;
    --browser) WITH_BROWSER=true; WITH_APPS=true ;;
    *) die 'usage: tests/deploy/run.sh [--apps] [--browser]' ;;
  esac
  shift
done

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi
for command in awk cmp docker find jq openssl rsync sed sha256sum sort xargs; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
if [ "$WITH_BROWSER" = true ]; then
  for command in chromedriver python3; do
    command -v "$command" >/dev/null 2>&1 || die "browser test requires: $command"
  done
fi

WORK_DIR=$(mktemp -d /tmp/workspace-suite-deploy-test.XXXXXX)
DATA_ROOT=$(mktemp -d /tmp/workspace-suite-deploy-data.XXXXXX)
suffix=${WORK_DIR##*.}
PROJECT_NAME=workspace-suite-test-"${suffix,,}"
PROXY_NETWORK=workspace-suite-test-proxy-"${suffix,,}"

rsync -a \
  --exclude='.git/' \
  --exclude='.env' \
  --exclude='reports/' \
  --exclude='inventory-*.md' \
  "$SOURCE_DIR/" "$WORK_DIR/"
if [ "$WITH_BROWSER" = true ]; then
  export COMPOSE_FILE="$WORK_DIR/compose.yaml:$WORK_DIR/tests/deploy/compose.browser.yaml"
fi
cp "$WORK_DIR/.env.example" "$WORK_DIR/.env"
chmod 0600 "$WORK_DIR/.env"

docker network create "$PROXY_NETWORK" >/dev/null
proxy_cidr=$(docker network inspect "$PROXY_NETWORK" \
  --format '{{range .IPAM.Config}}{{.Subnet}}{{" "}}{{end}}' | awk '{print $1}')
[ -n "$proxy_cidr" ] || die 'could not determine disposable proxy CIDR'

set_env_value COMPOSE_PROJECT_NAME "$PROJECT_NAME"
set_env_value PROXY_NETWORK "$PROXY_NETWORK"
set_env_value NEXTCLOUD_DATA_ROOT "$DATA_ROOT"
set_env_value DB_CONTAINER_NAME "$PROJECT_NAME-db"
set_env_value REDIS_CONTAINER_NAME "$PROJECT_NAME-redis"
set_env_value APP_CONTAINER_NAME "$PROJECT_NAME-app"
set_env_value CRON_CONTAINER_NAME "$PROJECT_NAME-cron"
set_env_value NEXTCLOUD_TRUSTED_DOMAINS deploy-test.invalid
set_env_value NEXTCLOUD_PUBLIC_HOST deploy-test.invalid
set_env_value TRUSTED_PROXIES "$proxy_cidr"
set_env_value OVERWRITEPROTOCOL http
set_env_value OVERWRITECLIURL http://deploy-test.invalid
set_env_value POSTGRES_PASSWORD "$(openssl rand -hex 32)"
set_env_value NEXTCLOUD_ADMIN_USER demo-admin
set_env_value NEXTCLOUD_ADMIN_PASSWORD "$(openssl rand -hex 32)"
set_env_value REDIS_PASSWORD "$(openssl rand -hex 32)"

# The fixture is a dated snapshot of the official compatibility response. OCC
# still downloads and verifies the actual compatible app packages. Production
# reconciliation uses the live App Store unless this explicit test input is set.
export NEXTCLOUD_APP_CATALOG_FILE=${NEXTCLOUD_APP_CATALOG_FILE:-"$WORK_DIR/tests/fixtures/app-store-nextcloud-34.0.2.json"}

compose() {
  docker compose --project-directory "$WORK_DIR" "$@"
}

occ() {
  compose exec -T -u www-data app php occ "$@"
}

app_tree_hash() {
  find "$DATA_ROOT/html/custom_apps/essentialsplus" -type f -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | awk '{print $1}'
}

webdav_prepare() {
  local admin password netrc source_file
  admin=$(awk -F= '$1 == "NEXTCLOUD_ADMIN_USER" {sub(/^[^=]*=/, ""); print; exit}' "$WORK_DIR/.env")
  password=$(awk -F= '$1 == "NEXTCLOUD_ADMIN_PASSWORD" {sub(/^[^=]*=/, ""); print; exit}' "$WORK_DIR/.env")
  [ -n "$admin" ] && [ -n "$password" ] || die 'disposable WebDAV credentials are missing'
  netrc="$WORK_DIR/.webdav.netrc"
  source_file="$WORK_DIR/synthetic-persistence.txt"
  umask 077
  printf 'machine 127.0.0.1 login %s password %s\n' "$admin" "$password" >"$netrc"
  printf 'Essentials+ Office synthetic persistence fixture\n' >"$source_file"
  compose cp "$netrc" app:/tmp/essentialsplus-webdav.netrc >/dev/null
  compose cp "$source_file" app:/tmp/essentialsplus-source.txt >/dev/null
  compose exec -T app chmod 0600 /tmp/essentialsplus-webdav.netrc
  compose exec -T app curl --fail --silent --show-error \
    --netrc-file /tmp/essentialsplus-webdav.netrc \
    --header 'Host: deploy-test.invalid' \
    --upload-file /tmp/essentialsplus-source.txt \
    "http://127.0.0.1/remote.php/dav/files/$admin/essentialsplus-persistence.txt" >/dev/null
}

webdav_verify_and_remove() {
  local admin download_file
  admin=$(awk -F= '$1 == "NEXTCLOUD_ADMIN_USER" {sub(/^[^=]*=/, ""); print; exit}' "$WORK_DIR/.env")
  download_file="$WORK_DIR/synthetic-persistence.download"
  compose exec -T app curl --fail --silent --show-error \
    --netrc-file /tmp/essentialsplus-webdav.netrc \
    --header 'Host: deploy-test.invalid' \
    --output /tmp/essentialsplus-download.txt \
    "http://127.0.0.1/remote.php/dav/files/$admin/essentialsplus-persistence.txt"
  compose cp app:/tmp/essentialsplus-download.txt "$download_file" >/dev/null
  cmp -- "$WORK_DIR/synthetic-persistence.txt" "$download_file" || die 'WebDAV content changed across application restart'
  compose exec -T app curl --fail --silent --show-error \
    --netrc-file /tmp/essentialsplus-webdav.netrc \
    --header 'Host: deploy-test.invalid' \
    --request DELETE \
    "http://127.0.0.1/remote.php/dav/files/$admin/essentialsplus-persistence.txt" >/dev/null
  compose exec -T app rm -f -- /tmp/essentialsplus-webdav.netrc /tmp/essentialsplus-source.txt /tmp/essentialsplus-download.txt
}

run_browser_e2e() {
  local browser_user browser_password port_mapping browser_port browser_base chromium_bin browser_secret_file
  browser_user=ordinary-demo
  browser_password=$(openssl rand -hex 32)
  browser_secret_file="$WORK_DIR/.browser-test.env"
  umask 077
  {
    printf 'BROWSER_USER=%s\n' "$browser_user"
    printf 'BROWSER_PASSWORD=%s\n' "$browser_password"
  } >"$browser_secret_file"
  compose exec -T -u www-data -e "OC_PASS=$browser_password" app php occ user:add \
    --password-from-env --display-name 'Ordinary Demo User' "$browser_user" >/dev/null
  occ group:add employee >/dev/null 2>&1 || true
  occ group:adduser employee "$browser_user" >/dev/null
  unset browser_password

  port_mapping=$(compose port app 80)
  [[ "$port_mapping" =~ ^127\.0\.0\.1:[0-9]+$ ]] || die "browser test port is not loopback-only: $port_mapping"
  browser_port=${port_mapping##*:}
  browser_base="http://deploy-test.invalid:$browser_port"
  occ config:system:set overwrite.cli.url --value="$browser_base" >/dev/null
  occ config:system:set overwritehost --value="deploy-test.invalid:$browser_port" >/dev/null

  chromium_bin=$(command -v chromium-browser || command -v chromium || true)
  [ -n "$chromium_bin" ] || die 'Chromium executable is missing'
  chromedriver --port=9515 --allowed-ips=127.0.0.1 >/dev/null 2>&1 &
  CHROMEDRIVER_PID=$!
  sleep 1
  BROWSER_BASE_URL="$browser_base" \
  BROWSER_CORE_ENV_FILE="$WORK_DIR/.env" \
  BROWSER_USER_ENV_FILE="$browser_secret_file" \
  CHROMIUM_BIN="$chromium_bin" \
    python3 "$WORK_DIR/tests/e2e/admin_center.py"
  kill "$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
  wait "$CHROMEDRIVER_PID" 2>/dev/null || true
  CHROMEDRIVER_PID=
}

deploy_args=()
if [ "$WITH_APPS" = true ]; then
  deploy_args+=(--apps)
fi
"$WORK_DIR/scripts/deploy.sh" "${deploy_args[@]}"

webdav_prepare
if [ "$WITH_BROWSER" = true ]; then
  run_browser_e2e
fi

env_hash_before=$(sha256sum "$WORK_DIR/.env" | awk '{print $1}')
app_hash_before=$(app_tree_hash)
occ essentialsplus:module:list --output=json \
  | jq -S '[.modules[] | {id, state, desired, active, visibility}]' \
  >"$WORK_DIR/module-state.before.json"
app_ids=$(jq -c '[.modules[].nextcloudApps[].id] | unique' "$WORK_DIR/office-modules.json")
occ app:list --output=json \
  | jq -S --argjson ids "$app_ids" '{enabled: [.enabled | to_entries[] | select(.key as $id | $ids | index($id))], disabled: [.disabled | to_entries[] | select(.key as $id | $ids | index($id))]}' \
  >"$WORK_DIR/app-state.before.json"

compose restart app >/dev/null
"$WORK_DIR/scripts/deploy.sh" "${deploy_args[@]}"
env_hash_after=$(sha256sum "$WORK_DIR/.env" | awk '{print $1}')
[ "$env_hash_before" = "$env_hash_after" ] || die '.env changed during idempotent redeployment'
app_hash_after=$(app_tree_hash)
[ "$app_hash_before" = "$app_hash_after" ] || die 'repository-owned Nextcloud app changed during idempotent redeployment'
occ essentialsplus:module:list --output=json \
  | jq -S '[.modules[] | {id, state, desired, active, visibility}]' \
  >"$WORK_DIR/module-state.after.json"
occ app:list --output=json \
  | jq -S --argjson ids "$app_ids" '{enabled: [.enabled | to_entries[] | select(.key as $id | $ids | index($id))], disabled: [.disabled | to_entries[] | select(.key as $id | $ids | index($id))]}' \
  >"$WORK_DIR/app-state.after.json"
cmp -- "$WORK_DIR/module-state.before.json" "$WORK_DIR/module-state.after.json" || die 'module state is not semantically idempotent'
cmp -- "$WORK_DIR/app-state.before.json" "$WORK_DIR/app-state.after.json" || die 'declared app state is not semantically idempotent'
webdav_verify_and_remove

printf 'deploy-test: clean deploy, WebDAV restart persistence, semantic idempotence, and browser=%s passed (apps=%s)\n' \
  "$WITH_BROWSER" "$WITH_APPS"
