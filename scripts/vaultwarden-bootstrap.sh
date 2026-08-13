#!/usr/bin/env bash
# Prepare the optional Vaultwarden module without touching the Nextcloud core.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE=${VAULTWARDEN_ENV_FILE:-"$PROJECT_DIR/.vaultwarden.env"}
DATA_DIR=${VAULTWARDEN_DATA_DIR:-/srv/vaultwarden/data}
BACKUP_DIR=${VAULTWARDEN_BACKUP_DIR:-/srv/vaultwarden/backups}
VAULTWARDEN_UID=${VAULTWARDEN_UID:-1000}
VAULTWARDEN_GID=${VAULTWARDEN_GID:-1000}
DOMAIN=
ENABLE_ADMIN=false

die() {
  printf 'vaultwarden-bootstrap: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/vaultwarden-bootstrap.sh --domain https://vault.internal.example [--enable-admin]

Creates the private Vaultwarden environment file and empty persistent paths.
The optional global /admin page is protected with an interactively entered token
stored only as an Argon2 hash. It is disabled when --enable-admin is omitted.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain)
      [ "$#" -ge 2 ] || die '--domain requires an HTTPS URL'
      DOMAIN=$2
      shift 2
      ;;
    --enable-admin)
      ENABLE_ADMIN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "$DOMAIN" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] ||
  die 'DOMAIN must be an HTTPS hostname without a path, query, or credentials'
[[ "$VAULTWARDEN_UID" =~ ^[0-9]+$ ]] || die 'VAULTWARDEN_UID must be numeric'
[[ "$VAULTWARDEN_GID" =~ ^[0-9]+$ ]] || die 'VAULTWARDEN_GID must be numeric'

for command in docker find install sed stat; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$PROJECT_DIR/.env" ] || die 'missing Nextcloud .env; bootstrap the core before an optional module'

create_or_preserve_directory() {
  local path=$1 owner=$2 group=$3
  if [ ! -e "$path" ]; then
    install -d -m 0700 -o "$owner" -g "$group" "$path"
    return
  fi
  [ -d "$path" ] || die "$path exists but is not a directory"
  if [ -z "$(find "$path" -mindepth 1 -print -quit)" ]; then
    chmod 0700 "$path"
    chown "$owner:$group" "$path"
  else
    printf 'vaultwarden-bootstrap: preserving non-empty directory: %s\n' "$path"
  fi
}

if [ -e "$ENV_FILE" ]; then
  [ -f "$ENV_FILE" ] || die "$ENV_FILE exists but is not a regular file"
  [ "$(stat -c '%a' "$ENV_FILE")" = 600 ] || die "$ENV_FILE must have mode 0600"
  printf 'vaultwarden-bootstrap: preserving existing %s\n' "$ENV_FILE"
else
  umask 077
  cp "$PROJECT_DIR/vaultwarden.env.example" "$ENV_FILE"
  sed -i "s|^DOMAIN=.*|DOMAIN=$DOMAIN|" "$ENV_FILE"
  chmod 0600 "$ENV_FILE"
fi

if [ "$ENABLE_ADMIN" = true ]; then
  [ -t 0 ] || die '--enable-admin requires an interactive terminal'
  printf 'New Vaultwarden admin token (not stored in plaintext): ' >&2
  IFS= read -r -s admin_token
  printf '\nRepeat Vaultwarden admin token: ' >&2
  IFS= read -r -s admin_token_repeat
  printf '\n' >&2
  [ -n "$admin_token" ] || die 'admin token must not be empty'
  [ "$admin_token" = "$admin_token_repeat" ] || die 'admin token confirmation does not match'

  admin_hash=$(printf '%s' "$admin_token" | docker run --rm -i \
    --entrypoint /vaultwarden vaultwarden/server:1.37.1 hash)
  unset admin_token admin_token_repeat
  [[ "$admin_hash" == \$argon2* ]] || die 'Vaultwarden did not return an Argon2 admin-token hash'
  sed -i "s|^# ADMIN_TOKEN=.*|ADMIN_TOKEN='$admin_hash'|" "$ENV_FILE"
  unset admin_hash
fi

create_or_preserve_directory "$DATA_DIR" "$VAULTWARDEN_UID" "$VAULTWARDEN_GID"
create_or_preserve_directory "$BACKUP_DIR" "$(id -u)" "$(id -g)"

proxy_network=$(awk -F= '$1 == "PROXY_NETWORK" { print $2; exit }' "$PROJECT_DIR/.env")
proxy_network=${proxy_network:-proxy_net}
docker network inspect "$proxy_network" >/dev/null 2>&1 ||
  die "required shared Docker network $proxy_network does not exist"

VAULTWARDEN_ENV_FILE="$ENV_FILE" \
VAULTWARDEN_DATA_DIR="$DATA_DIR" \
VAULTWARDEN_BACKUP_DIR="$BACKUP_DIR" \
docker compose -f "$PROJECT_DIR/compose.yaml" -f "$PROJECT_DIR/compose.vaultwarden.yaml" \
  --profile vaultwarden config -q

printf 'vaultwarden-bootstrap: optional module is configured but not started\n'
