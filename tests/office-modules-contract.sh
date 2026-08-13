#!/usr/bin/env bash
# Validate the non-secret Essentials Plus Office module contract and its defaults.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
CONTRACT=${OFFICE_MODULE_CONTRACT:-"$PROJECT_DIR/office-modules.json"}
CONFIG_EXAMPLE=${OFFICE_MODULE_CONFIG_EXAMPLE:-"$PROJECT_DIR/config/office-modules.env.example"}

die() {
  printf 'office-modules-contract-test: %s\n' "$*" >&2
  exit 1
}

for command in awk jq sort uniq; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$CONTRACT" ] || die "missing contract: $CONTRACT"
[ -f "$CONFIG_EXAMPLE" ] || die "missing config example: $CONFIG_EXAMPLE"
jq empty "$CONTRACT"
jq -e '
  .contractVersion == 1 and
  .product.name == "Office" and
  .product.brand == "Essentials Plus" and
  .adminCenter.ownerGroup == "admin" and
  ([.modules[].id] | length == (unique | length)) and
  ([.modules[] | select(.id != "nextcloud-core") | .defaultEnabled] | all(. == false)) and
  ([.modules[] | select(.id == "nextcloud-core" and .defaultEnabled == true)] | length == 1) and
  ([.themes[].modules[]] - [.modules[].id] | length == 0)
' "$CONTRACT" >/dev/null || die 'contract structure, module defaults, or themes are invalid'

while IFS= read -r key; do
  grep -Eq "^${key}=(true|false)$" "$CONFIG_EXAMPLE" ||
    die "config example lacks a boolean value for $key"
done < <(jq -r '.modules[].configKey' "$CONTRACT")

printf 'office-modules-contract-test: Office contract and inactive optional defaults passed\n'
