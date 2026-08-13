#!/usr/bin/env bash
# Prove a clean, idempotent repository deployment without touching production.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"
WITH_APPS=false
WORK_DIR=
DATA_ROOT=
PROJECT_NAME=
PROXY_NETWORK=

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

case "${1:-}" in
  '') ;;
  --apps) WITH_APPS=true ;;
  *) die 'usage: tests/deploy/run.sh [--apps]' ;;
esac
[ "$#" -le 1 ] || die 'usage: tests/deploy/run.sh [--apps]'

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi
for command in docker openssl rsync sed sha256sum; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

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

deploy_args=()
if [ "$WITH_APPS" = true ]; then
  deploy_args+=(--apps)
fi
"$WORK_DIR/scripts/deploy.sh" "${deploy_args[@]}"

env_hash_before=$(sha256sum "$WORK_DIR/.env" | awk '{print $1}')
docker compose --project-directory "$WORK_DIR" restart app >/dev/null
"$WORK_DIR/scripts/deploy.sh" "${deploy_args[@]}"
env_hash_after=$(sha256sum "$WORK_DIR/.env" | awk '{print $1}')
[ "$env_hash_before" = "$env_hash_after" ] || die '.env changed during idempotent redeployment'

printf 'deploy-test: clean deploy, restart persistence, and idempotent redeploy passed (apps=%s)\n' "$WITH_APPS"
