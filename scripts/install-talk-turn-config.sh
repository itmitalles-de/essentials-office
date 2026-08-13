#!/usr/bin/env bash
# Render a root-only coturn configuration without exposing its shared secret.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR=${TURN_CONFIG_DIR:-/etc/nextcloud}
TURN_RUNTIME_GID=${TURN_RUNTIME_GID:-65534}
CONFIG_FILE="$TARGET_DIR/turnserver.conf"
SECRET_FILE="$TARGET_DIR/talk-turn.secret"
TEMPLATE="$PROJECT_DIR/config/turnserver.conf.example"

die() {
  printf 'install-talk-turn-config: %s\n' "$*" >&2
  exit 1
}

[ "${EUID}" -eq 0 ] || die 'run this installer as root'
[ "$#" -eq 2 ] || die 'usage: install-talk-turn-config.sh TURN_REALM PUBLIC_IPV4'
realm=$1
external_ip=$2
[[ "$realm" =~ ^[A-Za-z0-9.-]+$ ]] || die 'TURN_REALM must be a DNS hostname'
[[ "$external_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die 'PUBLIC_IPV4 must be an IPv4 address'
[[ "$TURN_RUNTIME_GID" =~ ^[0-9]+$ ]] || die 'TURN_RUNTIME_GID must be numeric'
[ -f "$TEMPLATE" ] || die "missing template: $TEMPLATE"

install -d -o root -g root -m 0700 "$TARGET_DIR"
if [ ! -e "$SECRET_FILE" ]; then
  umask 077
  openssl rand -hex 32 >"$SECRET_FILE"
fi
chown root:root "$SECRET_FILE"
chmod 0600 "$SECRET_FILE"
secret=$(<"$SECRET_FILE")
[[ "$secret" =~ ^[[:xdigit:]]{64}$ ]] || die "$SECRET_FILE has an unexpected format"

rendered=$(mktemp "$TARGET_DIR/.turnserver.conf.XXXXXX")
cleanup() {
  local status=$?
  unset secret
  rm -f -- "$rendered"
  exit "$status"
}
trap cleanup EXIT INT TERM
while IFS= read -r line || [ -n "$line" ]; do
  line=${line//@TURN_REALM@/$realm}
  line=${line//@TURN_EXTERNAL_IP@/$external_ip}
  line=${line//@TURN_SECRET@/$secret}
  printf '%s\n' "$line"
done <"$TEMPLATE" >"$rendered"
chown "root:$TURN_RUNTIME_GID" "$rendered"
chmod 0640 "$rendered"
if [ ! -f "$CONFIG_FILE" ] || ! cmp --silent "$rendered" "$CONFIG_FILE"; then
  install -o root -g "$TURN_RUNTIME_GID" -m 0640 "$rendered" "$CONFIG_FILE"
fi

printf 'install-talk-turn-config: protected coturn configuration is ready in %s\n' "$TARGET_DIR"
