#!/usr/bin/env bash
# Prepare a new Nextcloud host without overwriting data or existing secrets.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
DATA_ROOT=
CREATED_ENV=false

die() {
  printf 'bootstrap: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

env_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE"
}

set_env_value() {
  local key=$1 value=$2
  sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
}

directory_is_empty() {
  [ -z "$(sudo find "$1" -mindepth 1 -print -quit 2>/dev/null)" ]
}

prepare_directory() {
  local path=$1 mode=$2 owner=$3 group=$4

  if [ ! -e "$path" ]; then
    sudo install -d -m "$mode" "$path"
    sudo chown "$owner:$group" "$path"
    return
  fi

  [ -d "$path" ] || die "$path exists but is not a directory"
  if directory_is_empty "$path"; then
    sudo chown "$owner:$group" "$path"
    sudo chmod "$mode" "$path"
  else
    printf 'bootstrap: preserving existing non-empty directory: %s\n' "$path"
  fi
}

image_identity() {
  local image=$1 account=$2
  docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image" >/dev/null
  docker run --rm --entrypoint sh "$image" -ec "id -u '$account'; id -g '$account'"
}

cd "$PROJECT_DIR"

for command in awk docker openssl sed sudo; do
  require_command "$command"
done
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required'
sudo -n true 2>/dev/null || die 'passwordless sudo is required to create and secure /srv/nextcloud'

if [ -e "$ENV_FILE" ]; then
  [ -f "$ENV_FILE" ] || die "$ENV_FILE exists but is not a regular file"
  printf 'bootstrap: preserving existing %s\n' "$ENV_FILE"
else
  umask 077
  cp .env.example "$ENV_FILE"
  set_env_value POSTGRES_PASSWORD "$(openssl rand -hex 32)"
  set_env_value NEXTCLOUD_ADMIN_PASSWORD "$(openssl rand -hex 32)"
  set_env_value REDIS_PASSWORD "$(openssl rand -hex 32)"
  chmod 600 "$ENV_FILE"
  CREATED_ENV=true
  printf 'bootstrap: generated secrets in %s\n' "$ENV_FILE"
fi

for key in POSTGRES_PASSWORD NEXTCLOUD_ADMIN_PASSWORD REDIS_PASSWORD; do
  [ -n "$(env_value "$key")" ] || die "$key is empty in $ENV_FILE; refusing to replace an existing file"
done

DATA_ROOT=$(env_value NEXTCLOUD_DATA_ROOT)
[ -n "$DATA_ROOT" ] || die 'NEXTCLOUD_DATA_ROOT is empty in .env'
case "$DATA_ROOT" in
  /*) ;;
  *) die 'NEXTCLOUD_DATA_ROOT must be an absolute path' ;;
esac
[ "$DATA_ROOT" != / ] || die 'NEXTCLOUD_DATA_ROOT must not be the filesystem root'

proxy_network=$(env_value PROXY_NETWORK)
[ -n "$proxy_network" ] || die 'PROXY_NETWORK is empty in .env'
if ! docker network inspect "$proxy_network" >/dev/null 2>&1; then
  docker network create "$proxy_network" >/dev/null
  printf 'bootstrap: created Docker network %s\n' "$proxy_network"
fi

proxy_cidr=$(docker network inspect "$proxy_network" --format '{{range .IPAM.Config}}{{.Subnet}}{{" "}}{{end}}' | awk '{print $1}')
[ -n "$proxy_cidr" ] || die "could not determine an IPv4 CIDR for Docker network $proxy_network"
configured_proxies=$(env_value TRUSTED_PROXIES)
if [ "$configured_proxies" != "$proxy_cidr" ]; then
  if [ "$CREATED_ENV" = true ]; then
    set_env_value TRUSTED_PROXIES "$proxy_cidr"
  else
    die "TRUSTED_PROXIES ($configured_proxies) does not match $proxy_network ($proxy_cidr); change it deliberately"
  fi
fi

readarray -t nc_identity < <(image_identity \
  nextcloud:34.0.2-apache@sha256:3323e178371b1b0d03f9b3fdbe1831ff78335f07f25116d0d598048ce459e329 www-data)
readarray -t pg_identity < <(image_identity \
  postgres:17.10-alpine@sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193 postgres)
readarray -t redis_identity < <(image_identity \
  redis:7.4.10-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2 redis)
[ "${#nc_identity[@]}" -eq 2 ] || die 'could not determine Nextcloud image ownership'
[ "${#pg_identity[@]}" -eq 2 ] || die 'could not determine PostgreSQL image ownership'
[ "${#redis_identity[@]}" -eq 2 ] || die 'could not determine Redis image ownership'

prepare_directory "$DATA_ROOT" 0750 root root
prepare_directory "$DATA_ROOT/html" 0750 "${nc_identity[0]}" "${nc_identity[1]}"
prepare_directory "$DATA_ROOT/data" 0750 "${nc_identity[0]}" "${nc_identity[1]}"
prepare_directory "$DATA_ROOT/postgres" 0700 "${pg_identity[0]}" "${pg_identity[1]}"
prepare_directory "$DATA_ROOT/redis" 0700 "${redis_identity[0]}" "${redis_identity[1]}"
prepare_directory "$DATA_ROOT/backups" 0700 root root

docker compose config -q
printf 'bootstrap: configuration is valid; secrets are in %s and data root is %s\n' "$ENV_FILE" "$DATA_ROOT"
