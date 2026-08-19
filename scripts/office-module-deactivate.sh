#!/usr/bin/env bash
# Make a module inactive in the local Essentials+ Office contract without deleting data.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
CONTRACT=${OFFICE_MODULE_CONTRACT:-"$PROJECT_DIR/office-modules.json"}
CONFIG=${OFFICE_MODULE_CONFIG:-"$PROJECT_DIR/config/office-modules.env"}
MODULE=

die() {
  printf 'office-module-deactivate: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --module)
      [ "$#" -ge 2 ] || die '--module requires a module id'
      MODULE=$2
      shift 2
      ;;
    -h|--help)
      printf '%s\n' 'Usage: ./scripts/office-module-deactivate.sh --module MODULE_ID'
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

for command in grep jq sed; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -n "$MODULE" ] || die 'a module id is required'
[ -f "$CONTRACT" ] || die "missing contract: $CONTRACT"
[ -f "$CONFIG" ] || die "missing local module configuration: $CONFIG"
config_key=$(jq -r --arg id "$MODULE" '.modules[] | select(.id == $id) | .configKey' "$CONTRACT")
[ -n "$config_key" ] && [ "$config_key" != null ] || die "unknown module: $MODULE"
[ "$MODULE" != nextcloud-core ] || die 'the Nextcloud core cannot be deactivated through this script'
grep -Eq "^${config_key}=(true|false)$" "$CONFIG" || die "invalid or missing $config_key in $CONFIG"
sed -i "s|^${config_key}=.*|${config_key}=false|" "$CONFIG"
printf '%s\n' \
  "office-module-deactivate: $MODULE is inactive in the contract" \
  'Remove its group-restricted External Sites link manually; no app, database, volume, backup, or content was deleted.'
