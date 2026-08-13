#!/usr/bin/env bash
# Prove a clean, idempotent repository deployment without touching production.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"
WITH_APPS=false
WITH_BROWSER=false
WITH_RECOVERY=false
WITH_HR=false
WITH_INTRANET=false
WITH_TALK=false
WORK_DIR=
DATA_ROOT=
PROJECT_NAME=
PROXY_NETWORK=
CHROMEDRIVER_PID=
ORIGINAL_ARGS=("$@")
HR_TEST_BASE=
INTRANET_TEST_BASE=
TALK_TEST_BASE=
TALK_SECRETS_FILE=
BROWSER_EXPECTED_MODULES=nextcloud-core

die() {
  printf 'deploy-test: %s\n' "$*" >&2
  exit 1
}

set_env_value() {
  local key=$1 value=$2
  sed -i "s|^${key}=.*|${key}=${value}|" "$WORK_DIR/.env"
}

netrc_machine() {
  local endpoint=$1 host
  host=${endpoint#*://}
  printf '%s\n' "${host%%:*}"
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
    --recovery) WITH_RECOVERY=true; WITH_APPS=true ;;
    --hr) WITH_HR=true; WITH_APPS=true ;;
    --intranet) WITH_INTRANET=true; WITH_APPS=true ;;
    --talk) WITH_TALK=true; WITH_APPS=true ;;
    *) die 'usage: tests/deploy/run.sh [--apps] [--browser] [--recovery] [--hr] [--intranet] [--talk]' ;;
  esac
  shift
done

if [ "${EUID}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -- "$0" "${ORIGINAL_ARGS[@]}"
  fi
  die 'run as root or install sudo for disposable bind-mount ownership setup'
fi
for command in awk chmod cmp cp curl docker find jq mktemp openssl rg rsync sed sha256sum sort xargs; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
if [ "$WITH_BROWSER" = true ]; then
  for command in chromedriver python3; do
    command -v "$command" >/dev/null 2>&1 || die "browser test requires: $command"
  done
fi
if [ "$WITH_RECOVERY" = true ]; then
  command -v restic >/dev/null 2>&1 || die 'recovery test requires restic'
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
if [ "$WITH_BROWSER" = true ] || [ "$WITH_HR" = true ] || [ "$WITH_INTRANET" = true ] || [ "$WITH_TALK" = true ]; then
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
  OC_PASS="$browser_password" compose exec -T -u www-data -e OC_PASS app php occ user:add \
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

  chromium_bin=${CHROMIUM_BIN:-}
  if [ -z "$chromium_bin" ]; then
    chromium_bin=$(command -v chrome || command -v google-chrome || command -v chromium || command -v chromium-browser || true)
  fi
  [ -n "$chromium_bin" ] || die 'Chromium executable is missing'
  chromedriver --port=9515 --allowed-ips=127.0.0.1 >/dev/null 2>&1 &
  CHROMEDRIVER_PID=$!
  sleep 1
  BROWSER_BASE_URL="$browser_base" \
  BROWSER_CORE_ENV_FILE="$WORK_DIR/.env" \
  BROWSER_USER_ENV_FILE="$browser_secret_file" \
  BROWSER_EXPECTED_MODULES="$BROWSER_EXPECTED_MODULES" \
  CHROMIUM_BIN="$chromium_bin" \
    python3 "$WORK_DIR/tests/e2e/admin_center.py"
  kill "$CHROMEDRIVER_PID" >/dev/null 2>&1 || true
  wait "$CHROMEDRIVER_PID" 2>/dev/null || true
  CHROMEDRIVER_PID=
}

run_recovery_e2e() {
  local recovery_user recovery_password admin admin_password netrc source_file shares backup_dir restic_stage staged_backup staged_env
  recovery_user=recovery-demo
  recovery_password=$(openssl rand -hex 32)
  admin=$(awk -F= '$1 == "NEXTCLOUD_ADMIN_USER" {sub(/^[^=]*=/, ""); print; exit}' "$WORK_DIR/.env")
  admin_password=$(awk -F= '$1 == "NEXTCLOUD_ADMIN_PASSWORD" {sub(/^[^=]*=/, ""); print; exit}' "$WORK_DIR/.env")
  umask 077
  {
    printf 'RECOVERY_TEST_USER=%s\n' "$recovery_user"
    printf 'RECOVERY_TEST_PASSWORD=%s\n' "$recovery_password"
  } >>"$WORK_DIR/.env"
  OC_PASS="$recovery_password" compose exec -T -u www-data -e OC_PASS app php occ user:add \
    --password-from-env --display-name 'Recovery Demo User' "$recovery_user" >/dev/null
  netrc="$WORK_DIR/.recovery-admin.netrc"
  source_file="$WORK_DIR/essentialsplus-recovery.txt"
  printf 'machine 127.0.0.1 login %s password %s\n' "$admin" "$admin_password" >"$netrc"
  printf 'Essentials+ Office synthetic backup and share fixture\n' >"$source_file"
  compose cp "$netrc" app:/tmp/recovery-admin.netrc >/dev/null
  compose cp "$source_file" app:/tmp/essentialsplus-recovery.txt >/dev/null
  compose exec -T app chmod 0600 /tmp/recovery-admin.netrc
  compose exec -T app curl --fail --silent --show-error \
    --header 'Host: deploy-test.invalid' --netrc-file /tmp/recovery-admin.netrc \
    --upload-file /tmp/essentialsplus-recovery.txt \
    "http://127.0.0.1/remote.php/dav/files/$admin/essentialsplus-recovery.txt" >/dev/null
  shares=$(compose exec -T app curl --fail --silent --show-error \
    --header 'Host: deploy-test.invalid' --header 'OCS-APIRequest: true' --header 'Accept: application/json' \
    --netrc-file /tmp/recovery-admin.netrc --request POST \
    --data-urlencode 'path=/essentialsplus-recovery.txt' --data 'shareType=0' \
    --data-urlencode "shareWith=$recovery_user" --data 'permissions=1' \
    'http://127.0.0.1/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json')
  jq -e '.ocs.meta.status == "ok"
    and (.ocs.meta.statuscode == 100 or .ocs.meta.statuscode == 200)
    and (.ocs.data.id | tostring | length > 0)' <<<"$shares" >/dev/null ||
    die 'could not create synthetic recovery share'
  unset recovery_password admin_password

  BACKUP_DIR="$DATA_ROOT/backups" "$WORK_DIR/scripts/backup.sh"
  backup_dir=$(find "$DATA_ROOT/backups" -mindepth 1 -maxdepth 1 -type d -name '20*' -print | sort | tail -n 1)
  [ -n "$backup_dir" ] || die 'recovery test backup is missing'
  export RESTIC_REPOSITORY="$WORK_DIR/restic-repository"
  export RESTIC_PASSWORD_FILE="$WORK_DIR/.restic-password"
  openssl rand -base64 48 >"$RESTIC_PASSWORD_FILE"
  chmod 0600 "$RESTIC_PASSWORD_FILE"
  restic init >/dev/null
  restic backup --quiet --tag essentialsplus-office-recovery "$backup_dir" "$WORK_DIR/.env"
  restic check --read-data >/dev/null
  restic_stage="$WORK_DIR/restic-stage"
  restic restore latest --target "$restic_stage" >/dev/null
  staged_backup=$(find "$restic_stage" -type d -name "$(basename -- "$backup_dir")" -path '*/backups/*' -print -quit)
  staged_env=$(find "$restic_stage" -type f -name .env -print -quit)
  [ -n "$staged_backup" ] && [ -n "$staged_env" ] || die 'restic restore did not reproduce backup and environment files'
  RESTORE_ENV_FILE="$staged_env" "$WORK_DIR/scripts/restore-test.sh" "$staged_backup"
  printf 'deploy-test: encrypted temporary restic backup and full empty-target restore passed\n'
}

run_hr_e2e() {
  local port_mapping hr_port hr_base target_hash_before target_hash_after secrets_hash_before secrets_hash_after
  port_mapping=$(compose port app 80)
  [[ "$port_mapping" =~ ^127\.0\.0\.1:[0-9]+$ ]] || die "HR test port is not loopback-only: $port_mapping"
  hr_port=${port_mapping##*:}
  hr_base="http://127.0.0.1:$hr_port"
  HR_TEST_BASE=$hr_base
  export HR_LITE_SECRETS_FILE="$WORK_DIR/.hr-lite-demo.env"
  NEXTCLOUD_ENV_FILE="$WORK_DIR/.env" HR_LITE_SECRETS_FILE="$HR_LITE_SECRETS_FILE" \
    "$WORK_DIR/scripts/hr-lite-reconcile.sh" --url "$hr_base" --allow-test-http
  target_hash_before=$(find "$WORK_DIR/hr-lite" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
  secrets_hash_before=$(sha256sum "$HR_LITE_SECRETS_FILE" | awk '{print $1}')
  NEXTCLOUD_ENV_FILE="$WORK_DIR/.env" HR_LITE_SECRETS_FILE="$HR_LITE_SECRETS_FILE" \
    "$WORK_DIR/scripts/hr-lite-reconcile.sh" --url "$hr_base" --allow-test-http
  target_hash_after=$(find "$WORK_DIR/hr-lite" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
  secrets_hash_after=$(sha256sum "$HR_LITE_SECRETS_FILE" | awk '{print $1}')
  [ "$target_hash_before" = "$target_hash_after" ] || die 'HR Lite target fixtures changed during reconciliation'
  [ "$secrets_hash_before" = "$secrets_hash_after" ] || die 'HR Lite demo secrets changed during reconciliation'
  printf 'deploy-test: idempotent HR Lite content reconciliation passed\n'
}

run_intranet_e2e() {
  local port_mapping intranet_port intranet_base content_hash_before content_hash_after secrets_hash_before secrets_hash_after module_config
  port_mapping=$(compose port app 80)
  [[ "$port_mapping" =~ ^127\.0\.0\.1:[0-9]+$ ]] || die "Intranet test port is not loopback-only: $port_mapping"
  intranet_port=${port_mapping##*:}
  intranet_base="http://127.0.0.1:$intranet_port"
  INTRANET_TEST_BASE=$intranet_base
  module_config="$WORK_DIR/config/office-modules.env"
  cp "$WORK_DIR/config/office-modules.env.example" "$module_config"
  chmod 0600 "$module_config"
  sed -i 's/^OFFICE_MODULE_INTRANET_LITE_ENABLED=.*/OFFICE_MODULE_INTRANET_LITE_ENABLED=true/' "$module_config"
  export INTRANET_SECRETS_FILE="$WORK_DIR/.intranet-lite-demo.env"
  NEXTCLOUD_ENV_FILE="$WORK_DIR/.env" OFFICE_MODULE_CONFIG="$module_config" INTRANET_SECRETS_FILE="$INTRANET_SECRETS_FILE" \
    "$WORK_DIR/scripts/intranet-lite-reconcile.sh" --reconcile --url "$intranet_base" --allow-test-http
  content_hash_before=$(find "$WORK_DIR/intranet-lite" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
  secrets_hash_before=$(sha256sum "$INTRANET_SECRETS_FILE" | awk '{print $1}')
  NEXTCLOUD_ENV_FILE="$WORK_DIR/.env" OFFICE_MODULE_CONFIG="$module_config" INTRANET_SECRETS_FILE="$INTRANET_SECRETS_FILE" \
    "$WORK_DIR/scripts/intranet-lite-reconcile.sh" --reconcile --url "$intranet_base" --allow-test-http
  content_hash_after=$(find "$WORK_DIR/intranet-lite" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
  secrets_hash_after=$(sha256sum "$INTRANET_SECRETS_FILE" | awk '{print $1}')
  [ "$content_hash_before" = "$content_hash_after" ] || die 'Intranet Lite target content changed during reconciliation'
  [ "$secrets_hash_before" = "$secrets_hash_after" ] || die 'Intranet Lite demo secrets changed during reconciliation'
  printf 'deploy-test: idempotent Intranet Lite content reconciliation, search API, and least-privilege checks passed\n'
}

prepare_talk_e2e() {
  local port_mapping talk_port alice_password bob_password outsider_password
  NEXTCLOUD_APP_CATALOG_FILE="$NEXTCLOUD_APP_CATALOG_FILE" "$WORK_DIR/scripts/reconcile-apps.sh" --module talk
  port_mapping=$(compose port app 80)
  [[ "$port_mapping" =~ ^127\.0\.0\.1:[0-9]+$ ]] || die "Talk test port is not loopback-only: $port_mapping"
  talk_port=${port_mapping##*:}
  TALK_TEST_BASE="http://127.0.0.1:$talk_port"
  TALK_SECRETS_FILE="$WORK_DIR/.talk-demo.env"
  alice_password=$(openssl rand -hex 32)
  bob_password=$(openssl rand -hex 32)
  outsider_password=$(openssl rand -hex 32)
  umask 077
  {
    printf 'TALK_ALICE_PASSWORD=%s\n' "$alice_password"
    printf 'TALK_BOB_PASSWORD=%s\n' "$bob_password"
    printf 'TALK_OUTSIDER_PASSWORD=%s\n' "$outsider_password"
  } >"$TALK_SECRETS_FILE"
  occ group:add employee >/dev/null 2>&1 || true
  for tuple in \
    "talk-alice-demo|Talk Alice Demo|$alice_password" \
    "talk-bob-demo|Talk Bob Demo|$bob_password" \
    "talk-outsider-demo|Talk Outsider Demo|$outsider_password"; do
    user=${tuple%%|*}
    remainder=${tuple#*|}
    display=${remainder%%|*}
    password=${remainder#*|}
    if ! occ user:info "$user" >/dev/null 2>&1; then
      OC_PASS="$password" compose exec -T -u www-data -e OC_PASS app php occ user:add \
        --password-from-env --display-name "$display" "$user" >/dev/null
    fi
  done
  occ group:adduser employee talk-alice-demo >/dev/null
  occ group:adduser employee talk-bob-demo >/dev/null
  unset alice_password bob_password outsider_password password
}

run_talk_e2e() {
  local alice_password bob_password outsider_password alice_netrc bob_netrc outsider_netrc talk_host room token participant message messages outsider_status state
  alice_password=$(awk -F= '$1 == "TALK_ALICE_PASSWORD" {sub(/^[^=]*=/, ""); print; exit}' "$TALK_SECRETS_FILE")
  bob_password=$(awk -F= '$1 == "TALK_BOB_PASSWORD" {sub(/^[^=]*=/, ""); print; exit}' "$TALK_SECRETS_FILE")
  outsider_password=$(awk -F= '$1 == "TALK_OUTSIDER_PASSWORD" {sub(/^[^=]*=/, ""); print; exit}' "$TALK_SECRETS_FILE")
  alice_netrc=$(mktemp)
  bob_netrc=$(mktemp)
  outsider_netrc=$(mktemp)
  trap 'rm -f -- "$alice_netrc" "$bob_netrc" "$outsider_netrc"' RETURN
  chmod 600 "$alice_netrc" "$bob_netrc" "$outsider_netrc"
  talk_host=$(netrc_machine "$TALK_TEST_BASE")
  printf 'machine %s login talk-alice-demo password %s\n' "$talk_host" "$alice_password" >"$alice_netrc"
  printf 'machine %s login talk-bob-demo password %s\n' "$talk_host" "$bob_password" >"$bob_netrc"
  printf 'machine %s login talk-outsider-demo password %s\n' "$talk_host" "$outsider_password" >"$outsider_netrc"
  unset alice_password bob_password outsider_password

  room=$(curl --fail --silent --show-error --netrc-file "$alice_netrc" \
    -H 'OCS-APIRequest: true' -H 'Accept: application/json' --request POST \
    --data 'roomType=2' --data-urlencode 'roomName=Essentials+ Office synthetic room' \
    "$TALK_TEST_BASE/ocs/v2.php/apps/spreed/api/v4/room?format=json")
  token=$(jq -r '.ocs.data.token // empty' <<<"$room")
  [[ "$token" =~ ^[a-z0-9]{4,64}$ ]] || die 'Talk room API did not return a valid token'
  participant=$(curl --fail --silent --show-error --netrc-file "$alice_netrc" \
    -H 'OCS-APIRequest: true' -H 'Accept: application/json' --request POST \
    --data 'source=users' --data 'newParticipant=talk-bob-demo' \
    "$TALK_TEST_BASE/ocs/v2.php/apps/spreed/api/v4/room/$token/participants?format=json")
  jq -e '.ocs.meta.status == "ok"
    and (.ocs.meta.statuscode == 100 or .ocs.meta.statuscode == 200)' <<<"$participant" >/dev/null ||
    die 'Talk participant invitation failed'
  message=$(curl --fail --silent --show-error --netrc-file "$alice_netrc" \
    -H 'OCS-APIRequest: true' -H 'Accept: application/json' --request POST \
    --data-urlencode 'message=Essentials+ Office synthetic Talk message' \
    "$TALK_TEST_BASE/ocs/v2.php/apps/spreed/api/v1/chat/$token?format=json")
  jq -e '.ocs.meta.status == "ok"
    and .ocs.meta.statuscode == 201
    and (.ocs.data.id | tonumber) > 0' <<<"$message" >/dev/null || die 'Talk message send failed'
  messages=$(curl --fail --silent --show-error --netrc-file "$bob_netrc" \
    -H 'OCS-APIRequest: true' -H 'Accept: application/json' \
    "$TALK_TEST_BASE/ocs/v2.php/apps/spreed/api/v1/chat/$token?format=json&lookIntoFuture=0&limit=100")
  jq -e '[.ocs.data[]? | select(.message == "Essentials+ Office synthetic Talk message")] | length == 1' <<<"$messages" >/dev/null ||
    die 'invited Talk participant did not receive the synthetic message'
  outsider_status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --netrc-file "$outsider_netrc" \
    -H 'OCS-APIRequest: true' "$TALK_TEST_BASE/ocs/v2.php/apps/spreed/api/v1/chat/$token?format=json")
  case "$outsider_status" in 403|404) ;; *) die "Talk outsider unexpectedly reached the room (HTTP $outsider_status)" ;; esac

  occ essentialsplus:module:disable talk >/dev/null
  state=$(occ essentialsplus:module:status talk)
  jq -e '.state == "disabled" and .active == false' <<<"$state" >/dev/null || die 'Talk logical disable failed'
  state=$(occ essentialsplus:module:enable talk)
  jq -e '.state == "enabled" and .active == true' <<<"$state" >/dev/null || die 'Talk reactivation failed'
  messages=$(curl --fail --silent --show-error --netrc-file "$bob_netrc" \
    -H 'OCS-APIRequest: true' -H 'Accept: application/json' \
    "$TALK_TEST_BASE/ocs/v2.php/apps/spreed/api/v1/chat/$token?format=json&lookIntoFuture=0&limit=100")
  jq -e '[.ocs.data[]? | select(.message == "Essentials+ Office synthetic Talk message")] | length == 1' <<<"$messages" >/dev/null ||
    die 'Talk room data was not preserved across logical disable'
  rm -f -- "$alice_netrc" "$bob_netrc" "$outsider_netrc"
  trap - RETURN
  printf 'deploy-test: Talk room, participant, message, permission, state, and data-preservation flow passed\n'
}

assert_hr_data_present() {
  local password netrc status hr_host
  password=$(awk -F= '$1 == "HR_LITE_ADMIN_PASSWORD" {sub(/^[^=]*=/, ""); print; exit}' "$HR_LITE_SECRETS_FILE")
  netrc=$(mktemp)
  chmod 600 "$netrc"
  hr_host=$(netrc_machine "$HR_TEST_BASE")
  printf 'machine %s login hr-demo-admin password %s\n' "$hr_host" "$password" >"$netrc"
  unset password
  status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --netrc-file "$netrc" --head \
    "$HR_TEST_BASE/remote.php/dav/files/hr-demo-admin/HR%20Lite%20-%20Confidential/workflow-target.json")
  rm -f -- "$netrc"
  [ "$status" = 200 ] || die "HR Lite data was not preserved during logical disable (HTTP $status)"
}

assert_intranet_data_present() {
  local password netrc status intranet_host
  password=$(awk -F= '$1 == "INTRANET_EDITOR_PASSWORD" {sub(/^[^=]*=/, ""); print; exit}' "$INTRANET_SECRETS_FILE")
  netrc=$(mktemp)
  chmod 600 "$netrc"
  intranet_host=$(netrc_machine "$INTRANET_TEST_BASE")
  printf 'machine %s login intranet-editor-demo password %s\n' "$intranet_host" "$password" >"$netrc"
  unset password
  status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --netrc-file "$netrc" --head \
    "$INTRANET_TEST_BASE/remote.php/dav/files/intranet-editor-demo/Intranet%20Lite/handbook.md")
  rm -f -- "$netrc"
  [ "$status" = 200 ] || die "Intranet Lite data was not preserved during logical disable (HTTP $status)"
}

run_module_control_tests() {
  local state enabled_groups failure_output metrics
  printf 'deploy-test: starting OCC module control and health-gate checks\n'
  state=$(occ essentialsplus:module:status nextcloud-core) || die 'core module status command failed'
  jq -e '.id == "nextcloud-core" and .state == "enabled" and .active == true' <<<"$state" >/dev/null ||
    die 'required core module is not healthy and enabled'

  failure_output="$WORK_DIR/external-enable.failure"
  if occ essentialsplus:module:enable vaultwarden >"$failure_output" 2>&1; then
    die 'unconfigured Vaultwarden was unexpectedly enabled'
  fi
  state=$(occ essentialsplus:module:status vaultwarden) || die 'Vaultwarden module status command failed'
  jq -e '.state == "not_installed" and .active == false' <<<"$state" >/dev/null ||
    die 'uninstalled Vaultwarden did not remain inactive'
  if occ essentialsplus:module:configure vaultwarden password synthetic-secret >"$failure_output" 2>&1; then
    die 'Admin Center accepted a secret-like configuration key'
  fi
  ! rg -q 'synthetic-secret' "$failure_output" || die 'rejected secret value appeared in command output'
  occ essentialsplus:module:disable vaultwarden >/dev/null || die 'Vaultwarden logical disable command failed'

  for pair in \
    'installed:true' \
    'serviceUrl:https://calls-unreachable.internal' \
    'healthUrl:https://calls-unreachable.internal/health' \
    'authenticationReady:true' \
    'rolesReady:true' \
    'sipCredentialStorageReady:true' \
    'rightsReady:true'; do
    occ essentialsplus:module:configure essentials-calls "${pair%%:*}" "${pair#*:}" >/dev/null ||
      die "Essentials+ Calls configuration failed for ${pair%%:*}"
  done
  if occ essentialsplus:module:enable essentials-calls >"$failure_output" 2>&1; then
    die 'unhealthy Essentials+ Calls service was unexpectedly enabled'
  fi
  state=$(occ essentialsplus:module:status essentials-calls) || die 'Essentials+ Calls status command failed'
  jq -e '.state == "degraded" and .desired == true and .active == false and .serviceUrl == null' <<<"$state" >/dev/null ||
    die 'failed external healthcheck did not produce hidden degraded state'
  occ essentialsplus:module:disable essentials-calls >/dev/null || die 'Essentials+ Calls logical disable command failed'

  if [ "$WITH_INTRANET" = true ]; then
    if ! state=$(occ essentialsplus:module:enable intranet-lite); then
      printf '%s\n' "$state" >&2
      die 'Intranet Lite enable command failed'
    fi
    jq -e '.state == "enabled" and .active == true' <<<"$state" >/dev/null || die 'Intranet Lite activation failed'
    BROWSER_EXPECTED_MODULES="$BROWSER_EXPECTED_MODULES,intranet-lite"
  fi
  if [ "$WITH_HR" = true ]; then
    occ essentialsplus:module:configure hr-lite workflowReady true >/dev/null || die 'HR Lite readiness configuration failed'
    state=$(occ essentialsplus:module:enable hr-lite) || die 'HR Lite enable command failed'
    jq -e '.state == "enabled" and .active == true' <<<"$state" >/dev/null || die 'HR Lite activation failed'
    BROWSER_EXPECTED_MODULES="$BROWSER_EXPECTED_MODULES,hr-lite"
  fi
  if [ "$WITH_TALK" = true ]; then
    if ! state=$(occ essentialsplus:module:enable talk); then
      printf '%s\n' "$state" >&2
      die 'Talk enable command failed'
    fi
    jq -e '.state == "enabled" and .active == true' <<<"$state" >/dev/null || die 'Talk activation failed'
    BROWSER_EXPECTED_MODULES="$BROWSER_EXPECTED_MODULES,talk"
  fi

  if [ "$WITH_HR" = true ] && [ "$WITH_INTRANET" = true ]; then
    enabled_groups=$(occ config:app:get tables enabled) || die 'shared Tables visibility query failed'
    jq -e 'sort == ["employee", "hr-admin", "intranet-editor", "manager"]' <<<"$enabled_groups" >/dev/null ||
      die 'shared app group visibility is not the union of active modules'
  fi

  if [ "$WITH_HR" = true ]; then
    occ essentialsplus:module:disable hr-lite >/dev/null || die 'HR Lite disable command failed'
    assert_hr_data_present
    state=$(occ essentialsplus:module:status hr-lite) || die 'HR Lite disabled status command failed'
    jq -e '.state == "disabled" and .active == false' <<<"$state" >/dev/null || die 'HR Lite logical disable failed'
    state=$(occ essentialsplus:module:enable hr-lite) || die 'HR Lite re-enable command failed'
    jq -e '.state == "enabled" and .active == true' <<<"$state" >/dev/null || die 'HR Lite reactivation failed'
    NEXTCLOUD_ENV_FILE="$WORK_DIR/.env" HR_LITE_SECRETS_FILE="$HR_LITE_SECRETS_FILE" \
      "$WORK_DIR/scripts/hr-lite-verify.sh" --url "$HR_TEST_BASE" --allow-test-http
  fi
  if [ "$WITH_INTRANET" = true ]; then
    occ essentialsplus:module:disable intranet-lite >/dev/null || die 'Intranet Lite disable command failed'
    assert_intranet_data_present
    state=$(occ essentialsplus:module:status intranet-lite) || die 'Intranet Lite disabled status command failed'
    jq -e '.state == "disabled" and .active == false' <<<"$state" >/dev/null || die 'Intranet Lite logical disable failed'
    state=$(occ essentialsplus:module:enable intranet-lite) || die 'Intranet Lite re-enable command failed'
    jq -e '.state == "enabled" and .active == true' <<<"$state" >/dev/null || die 'Intranet Lite reactivation failed'
    NEXTCLOUD_ENV_FILE="$WORK_DIR/.env" OFFICE_MODULE_CONFIG="$WORK_DIR/config/office-modules.env" \
      INTRANET_SECRETS_FILE="$INTRANET_SECRETS_FILE" "$WORK_DIR/scripts/intranet-lite-reconcile.sh" \
      --verify --url "$INTRANET_TEST_BASE" --allow-test-http
  fi
  metrics=$(occ essentialsplus:metrics) || die 'Prometheus module metrics command failed'
  rg -q '^essentialsplus_module_state\{module="nextcloud-core",state="enabled"\} 1$' <<<"$metrics" ||
    die 'Prometheus module metrics are missing the healthy core state'
  printf 'deploy-test: OCC/API control, health gates, shared visibility, disable preservation, and metrics passed\n'
}

run_app_failure_mode_tests() {
  local incompatible_catalog missing_catalog failure_log
  incompatible_catalog="$WORK_DIR/app-catalog-incompatible.json"
  missing_catalog="$WORK_DIR/app-catalog-missing.json"
  failure_log="$WORK_DIR/app-preflight.failure"
  jq 'map(if .id == "notes" then .releases[0].version = "99.0.0" else . end)' \
    "$NEXTCLOUD_APP_CATALOG_FILE" >"$incompatible_catalog"
  if NEXTCLOUD_APP_CATALOG_FILE="$incompatible_catalog" "$WORK_DIR/scripts/reconcile-apps.sh" --check >"$failure_log" 2>&1; then
    die 'incompatible app release was unexpectedly accepted'
  fi
  rg -q 'outside manifest range for notes' "$failure_log" || die 'incompatible app failure was not explicit'
  jq 'map(select(.id != "notes"))' "$NEXTCLOUD_APP_CATALOG_FILE" >"$missing_catalog"
  if NEXTCLOUD_APP_CATALOG_FILE="$missing_catalog" "$WORK_DIR/scripts/reconcile-apps.sh" --check >"$failure_log" 2>&1; then
    die 'missing App Store package was unexpectedly accepted'
  fi
  rg -q 'no App Store release of notes is compatible' "$failure_log" || die 'missing app failure was not explicit'
  printf 'deploy-test: incompatible and missing app preflights failed closed\n'
}

deploy_args=()
if [ "$WITH_APPS" = true ]; then
  deploy_args+=(--apps)
fi
"$WORK_DIR/scripts/deploy.sh" "${deploy_args[@]}"

webdav_prepare
run_app_failure_mode_tests
if [ "$WITH_HR" = true ]; then
  run_hr_e2e
fi
if [ "$WITH_INTRANET" = true ]; then
  run_intranet_e2e
fi
if [ "$WITH_TALK" = true ]; then
  prepare_talk_e2e
fi
run_module_control_tests
if [ "$WITH_TALK" = true ]; then
  run_talk_e2e
fi
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
if [ "$WITH_RECOVERY" = true ]; then
  run_recovery_e2e
fi

printf 'deploy-test: clean deploy, WebDAV restart persistence, semantic idempotence, and browser=%s passed (apps=%s)\n' \
  "$WITH_BROWSER" "$WITH_APPS"
