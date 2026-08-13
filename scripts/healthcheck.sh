#!/usr/bin/env bash
# Validate the local stack and its public Caddy endpoint without printing secrets.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
DOMAIN=
RUN_ROUNDTRIP=false
CORE_ONLY=false

die() {
  printf 'healthcheck: %s\n' "$*" >&2
  exit 1
}

env_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROJECT_DIR/.env"
}

require_running() {
  local service=$1
  docker compose ps --status running --services | grep -Fxq "$service" || die "$service is not running"
}

check_redirect() {
  local source=$1 expected=$2 headers
  headers=$(curl --silent --show-error --insecure --resolve "$DOMAIN:443:127.0.0.1" --head "https://$DOMAIN$source") || die "$source did not answer through Caddy"
  printf '%s\n' "$headers" | grep -Eiq '^HTTP/.* 301' || die "$source is not a 301 redirect"
  printf '%s\n' "$headers" | grep -Fqi "location: $expected" || die "$source redirects to the wrong DAV endpoint"
}

roundtrip_file() {
  local admin password netrc source download remote_id remote_path
  admin=$(env_value NEXTCLOUD_ADMIN_USER)
  password=$(env_value NEXTCLOUD_ADMIN_PASSWORD)
  if [ -z "$admin" ] || [ -z "$password" ]; then
    die 'admin credentials are missing from .env'
  fi

  netrc=$(mktemp)
  source=$(mktemp)
  download=$(mktemp)
  chmod 600 "$netrc"
  remote_id="healthcheck-${RANDOM}-$(date +%s)"
  remote_path="/remote.php/dav/files/$admin/$remote_id"
  printf 'machine %s login %s password %s\n' "$DOMAIN" "$admin" "$password" >"$netrc"
  printf 'Nextcloud healthcheck %s\n' "$remote_id" >"$source"

  cleanup_roundtrip() {
    curl --silent --show-error --insecure --netrc-file "$netrc" --request DELETE --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN$remote_path" >/dev/null 2>&1 || true
    rm -f -- "$netrc" "$source" "$download"
  }

  if ! curl --fail --silent --show-error --insecure --netrc-file "$netrc" --upload-file "$source" --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN$remote_path" >/dev/null; then
    cleanup_roundtrip
    die 'WebDAV test file upload failed'
  fi
  if ! curl --fail --silent --show-error --insecure --netrc-file "$netrc" --output "$download" --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN$remote_path"; then
    cleanup_roundtrip
    die 'WebDAV test file download failed'
  fi
  if ! cmp -- "$source" "$download" >/dev/null; then
    cleanup_roundtrip
    die 'uploaded WebDAV test file does not match its download'
  fi
  cleanup_roundtrip
  printf 'healthcheck: WebDAV upload/download round-trip passed\n'
}

case "${1:-}" in
  '') ;;
  --core-only) CORE_ONLY=true ;;
  --file-roundtrip) RUN_ROUNDTRIP=true ;;
  *) die 'usage: healthcheck.sh [--core-only|--file-roundtrip]' ;;
esac
[ "$#" -le 1 ] || die 'usage: healthcheck.sh [--core-only|--file-roundtrip]'

required_commands=(awk docker grep)
if [ "$CORE_ONLY" = false ]; then
  required_commands+=(curl openssl)
fi
if [ "$RUN_ROUNDTRIP" = true ]; then
  required_commands+=(cmp)
fi
for command in "${required_commands[@]}"; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$PROJECT_DIR/.env" ] || die 'missing .env; run bootstrap.sh first'
DOMAIN=$(env_value NEXTCLOUD_PUBLIC_HOST)
[ -n "$DOMAIN" ] || DOMAIN=$(env_value NEXTCLOUD_TRUSTED_DOMAINS | awk '{print $1}')
[ -n "$DOMAIN" ] || die 'could not determine the Nextcloud public hostname from .env'
cd "$PROJECT_DIR"
docker compose config -q

for service in db redis app cron; do
  require_running "$service"
done
docker compose ps

docker compose exec -T db sh -ec 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null || die 'PostgreSQL is not ready'
docker compose exec -T redis sh -ec 'redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping | grep -qx PONG' || die 'Redis did not answer PONG'

occ_status=$(docker compose exec -T -u www-data app php occ status --output=json)
printf '%s\n' "$occ_status" | grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' || die 'Nextcloud is not installed'
printf '%s\n' "$occ_status" | grep -Eq '"maintenance"[[:space:]]*:[[:space:]]*false' || die 'Nextcloud is in maintenance mode'
docker compose exec -T -u www-data app php occ config:app:get core backgroundjobs_mode | grep -Fxq cron || die 'Nextcloud background mode is not cron'

if [ "$CORE_ONLY" = true ]; then
  printf 'healthcheck: internal core checks passed\n'
  exit 0
fi

local_status=$(curl --fail --silent --show-error --insecure --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/status.php") || die 'Caddy does not reach Nextcloud status.php'
printf '%s\n' "$local_status" | grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' || die 'Caddy status response is not installed'

public_status=$(curl --fail --silent --show-error "https://$DOMAIN/status.php") || die 'public status.php is unreachable'
printf '%s\n' "$public_status" | grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' || die 'public status response is not installed'

openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -verify_return_error </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -enddate >/dev/null || die 'public HTTPS certificate is invalid'

webdav_status=$(curl --silent --show-error --insecure --output /dev/null --write-out '%{http_code}' --request OPTIONS --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/remote.php/dav/") || die 'WebDAV endpoint did not answer'
case "$webdav_status" in
  200|207|401|405) ;;
  *) die "unexpected WebDAV HTTP status: $webdav_status" ;;
esac
check_redirect '/.well-known/carddav' '/remote.php/dav/'
check_redirect '/.well-known/caldav' '/remote.php/dav/'

if [ "$RUN_ROUNDTRIP" = true ]; then
  roundtrip_file
fi

printf 'healthcheck: all checks passed\n'
