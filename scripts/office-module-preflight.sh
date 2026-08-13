#!/usr/bin/env bash
# Validate an Office module before an administrator makes it visible to users.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
CONTRACT=${OFFICE_MODULE_CONTRACT:-"$PROJECT_DIR/office-modules.json"}
CONFIG=${OFFICE_MODULE_CONFIG:-"$PROJECT_DIR/config/office-modules.env"}
NEXTCLOUD_ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
MODULE=

die() {
  printf 'office-module-preflight: %s\n' "$*" >&2
  exit 1
}

config_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$CONFIG"
}

usage() {
  printf '%s\n' 'Usage: ./scripts/office-module-preflight.sh --module MODULE_ID'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --module)
      [ "$#" -ge 2 ] || die '--module requires a module id'
      MODULE=$2
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

for command in awk curl docker jq; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -n "$MODULE" ] || { usage >&2; exit 2; }
[ -f "$CONTRACT" ] || die "missing contract: $CONTRACT"
[ -f "$CONFIG" ] || die "missing module configuration: $CONFIG"
jq -e --arg id "$MODULE" '.modules[] | select(.id == $id)' "$CONTRACT" >/dev/null ||
  die "unknown module: $MODULE"

config_key=$(jq -r --arg id "$MODULE" '.modules[] | select(.id == $id) | .configKey' "$CONTRACT")
health_type=$(jq -r --arg id "$MODULE" '.modules[] | select(.id == $id) | .health' "$CONTRACT")
[ "$(config_value "$config_key")" = true ] ||
  die "$MODULE is disabled in $CONFIG; keep it hidden until its preflight is ready"

case "$health_type" in
  nextcloud-core)
    [ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
    NEXTCLOUD_ENV_FILE="$NEXTCLOUD_ENV_FILE" "$SCRIPT_DIR/healthcheck.sh" >/dev/null
    ;;
  intranet-lite-script)
    [ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
    NEXTCLOUD_ENV_FILE="$NEXTCLOUD_ENV_FILE" \
      OFFICE_MODULE_CONFIG="$CONFIG" "$SCRIPT_DIR/intranet-lite-reconcile.sh" --verify
    ;;
  hr-lite-script)
    [ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
    NEXTCLOUD_ENV_FILE="$NEXTCLOUD_ENV_FILE" "$SCRIPT_DIR/hr-lite-verify.sh"
    ;;
  vaultwarden-script)
    [ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
    NEXTCLOUD_ENV_FILE="$NEXTCLOUD_ENV_FILE" "$SCRIPT_DIR/vaultwarden-healthcheck.sh" >/dev/null
    ;;
  https)
    health_key="${config_key%_ENABLED}_HEALTH_URL"
    health_url=$(config_value "$health_key")
    [[ "$health_url" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]([/:][^@?]*)?$ ]] ||
      die "$health_key must be a credential-free HTTPS URL without a query string"
    curl --fail --silent --show-error --max-time 10 --output /dev/null "$health_url" ||
      die "$MODULE health endpoint did not pass"
    if [ "$MODULE" = visual-pbx ]; then
      NEXTCLOUD_ENV_FILE="$NEXTCLOUD_ENV_FILE" \
        "$SCRIPT_DIR/visual-pbx-contract-check.sh" --check-health
    fi
    ;;
  *) die "unsupported health type in contract: $health_type" ;;
esac

printf 'office-module-preflight: %s is configured and healthy; an admin may now publish its restricted link\n' "$MODULE"
