#!/usr/bin/env bash
# Install and enable the declared apps only after an App Store compatibility preflight.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
APP_LIST=${APP_LIST_FILE:-$PROJECT_DIR/config/nextcloud-apps.txt}
REPORT_DIR=${APP_REPORT_DIR:-$PROJECT_DIR/reports}
EXPECTED_NEXTCLOUD_MAJOR=${EXPECTED_NEXTCLOUD_MAJOR:-34}
MODE=apply
UPDATE_APPS=false
WORK_DIR=

die() {
  printf 'reconcile-apps: %s\n' "$*" >&2
  exit 1
}

occ() {
  docker compose exec -T -u www-data app php occ "$@"
}

cleanup() {
  local status=$?
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/nextcloud-apps.* ]]; then
    rm -rf -- "$WORK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

case "${1:-}" in
  '') ;;
  --check) MODE=check ;;
  --update) UPDATE_APPS=true ;;
  *) die 'usage: reconcile-apps.sh [--check|--update]' ;;
esac

for command in curl docker jq mktemp; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$PROJECT_DIR/.env" ] || die 'missing .env; run bootstrap.sh first'
[ -f "$APP_LIST" ] || die "missing app declaration: $APP_LIST"
cd "$PROJECT_DIR"
docker compose config -q
docker compose ps --status running --services | grep -Fxq app || die 'app service is not running'

status=$(occ status --output=json)
installed=$(printf '%s\n' "$status" | jq -r '.installed')
maintenance=$(printf '%s\n' "$status" | jq -r '.maintenance')
needs_upgrade=$(printf '%s\n' "$status" | jq -r '.needsDbUpgrade')
nextcloud_version=$(printf '%s\n' "$status" | jq -r '.versionstring')
nextcloud_major=${nextcloud_version%%.*}
[ "$installed" = true ] || die 'Nextcloud is not installed'
[ "$maintenance" = false ] || die 'Nextcloud is in maintenance mode'
[ "$needs_upgrade" = false ] || die 'Nextcloud requires a database upgrade'
[ "$nextcloud_major" = "$EXPECTED_NEXTCLOUD_MAJOR" ] || \
  die "Nextcloud $nextcloud_version does not match allowed major $EXPECTED_NEXTCLOUD_MAJOR"

mapfile -t apps < <(sed -E '/^[[:space:]]*(#|$)/d; s/[[:space:]]+$//' "$APP_LIST")
[ "${#apps[@]}" -gt 0 ] || die 'the app declaration is empty'
if [ "$(printf '%s\n' "${apps[@]}" | sort -u | wc -l)" -ne "${#apps[@]}" ]; then
  die 'the app declaration contains duplicate IDs'
fi

WORK_DIR=$(mktemp -d /tmp/nextcloud-apps.XXXXXX)
compatibility_json="$WORK_DIR/compatible-apps.json"
curl --fail --silent --show-error --location \
  --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 120 \
  "https://apps.nextcloud.com/api/v1/platform/${nextcloud_version}/apps.json" \
  --output "$compatibility_json"
jq -e 'type == "array"' "$compatibility_json" >/dev/null || die 'App Store returned invalid JSON'

printf 'reconcile-apps: compatibility preflight for Nextcloud %s\n' "$nextcloud_version"
for app in "${apps[@]}"; do
  candidate=$(jq -r --arg app "$app" \
    '[.[] | select(.id == $app) | .releases[0].version][0] // empty' \
    "$compatibility_json")
  [ -n "$candidate" ] || die "no App Store release of $app is compatible with Nextcloud $nextcloud_version"
  printf '  %-16s compatible release %s\n' "$app" "$candidate"
done

app_state=$(occ app:list --output=json)
changes_required=false
for app in "${apps[@]}"; do
  if ! printf '%s\n' "$app_state" | jq -e --arg app "$app" \
    '(.enabled[$app] // .disabled[$app] // null) != null' >/dev/null; then
    changes_required=true
  elif ! printf '%s\n' "$app_state" | jq -e --arg app "$app" \
    '.enabled[$app] != null' >/dev/null; then
    changes_required=true
  fi
done
if [ "$UPDATE_APPS" = true ]; then
  changes_required=true
fi

if [ "$MODE" = check ]; then
  [ "$changes_required" = false ] || die 'declared app state differs from the running instance'
else
  if [ "$changes_required" = true ]; then
    "$SCRIPT_DIR/backup.sh"
  fi
  for app in "${apps[@]}"; do
    app_state=$(occ app:list --output=json)
    if printf '%s\n' "$app_state" | jq -e --arg app "$app" '.enabled[$app] != null' >/dev/null; then
      printf 'reconcile-apps: %s is already enabled\n' "$app"
    elif printf '%s\n' "$app_state" | jq -e --arg app "$app" '.disabled[$app] != null' >/dev/null; then
      occ app:enable "$app"
    else
      # Never use --force: OCC must enforce the compatibility metadata.
      occ app:install "$app"
    fi
    if [ "$UPDATE_APPS" = true ]; then
      occ app:update "$app"
    fi
  done
fi

final_state=$(occ app:list --output=json)
report_lines="$WORK_DIR/report.jsonl"
for app in "${apps[@]}"; do
  installed_version=$(printf '%s\n' "$final_state" | jq -r --arg app "$app" \
    '.enabled[$app] // .disabled[$app] // empty')
  enabled=$(printf '%s\n' "$final_state" | jq -r --arg app "$app" '.enabled[$app] != null')
  [ -n "$installed_version" ] || die "$app is missing after reconciliation"
  compatible_version=$(jq -r --arg app "$app" \
    '[.[] | select(.id == $app) | .releases[0].version][0]' "$compatibility_json")
  jq -n --arg id "$app" --arg installedVersion "$installed_version" \
    --arg compatibleVersion "$compatible_version" --argjson enabled "$enabled" \
    '{id: $id, installedVersion: $installedVersion, enabled: $enabled, latestCompatibleVersion: $compatibleVersion}' \
    >>"$report_lines"
done

mkdir -p "$REPORT_DIR"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
report="$REPORT_DIR/nextcloud-apps-$stamp.json"
jq -s --arg generatedAt "$stamp" --arg nextcloudVersion "$nextcloud_version" \
  '{generatedAt: $generatedAt, nextcloudVersion: $nextcloudVersion, apps: .}' \
  "$report_lines" >"$report"
cp -- "$report" "$REPORT_DIR/nextcloud-apps-latest.json"
printf 'reconcile-apps: declared state verified; version report written to %s\n' "$report"
