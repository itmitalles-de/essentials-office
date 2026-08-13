#!/usr/bin/env bash
# Reconcile the local, optional Intranet Lite prerequisites without data deletion.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
NEXTCLOUD_ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
OFFICE_MODULE_CONFIG=${OFFICE_MODULE_CONFIG:-"$PROJECT_DIR/config/office-modules.env"}

die() {
  printf 'intranet-lite-reconcile: %s\n' "$*" >&2
  exit 1
}

config_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$OFFICE_MODULE_CONFIG"
}

compose() {
  docker compose --env-file "$NEXTCLOUD_ENV_FILE" -f "$PROJECT_DIR/compose.yaml" "$@"
}

occ() {
  compose exec -T -u www-data app php occ "$@"
}

app_state() {
  local app=$1 state=$2 apps
  apps=$(occ app:list --output=json)
  jq -e --arg app "$app" --arg state "$state" '.[$state] | has($app)' <<<"$apps" >/dev/null
}

ensure_app_for_groups() {
  local app=$1
  if ! app_state "$app" enabled && ! app_state "$app" disabled; then
    occ app:install "$app" >/dev/null
  fi
  occ app:enable --groups admin --groups office-user "$app" >/dev/null
}

MODE=
case "${1:-}" in
  --reconcile) MODE=reconcile ;;
  --verify) MODE=verify ;;
  -h|--help)
    printf '%s\n' 'Usage: ./scripts/intranet-lite-reconcile.sh --reconcile|--verify'
    exit 0
    ;;
  *) die 'use --reconcile; disabling is a configuration change and never removes app data' ;;
esac

for command in awk docker jq; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
[ -f "$OFFICE_MODULE_CONFIG" ] || die "missing $OFFICE_MODULE_CONFIG; initialize it from config/office-modules.env.example"
[ "$(config_value OFFICE_MODULE_INTRANET_LITE_ENABLED)" = true ] ||
  die 'Intranet Lite is disabled in the Office module configuration'
compose config -q
if [ "$MODE" = reconcile ]; then
  occ group:info office-user >/dev/null 2>&1 || occ group:add office-user >/dev/null
else
  occ group:info office-user >/dev/null || die 'missing group: office-user'
fi

# circles is Teams' historical app id. dashboard ships with Nextcloud 34 but is
# still checked through OCC, so an incompatible or missing app stops safely.
for app in dashboard circles collectives announcementcenter; do
  if [ "$MODE" = reconcile ]; then
    ensure_app_for_groups "$app"
  else
    app_state "$app" enabled || die "required Intranet Lite app is not enabled: $app"
  fi
done

if [ "$MODE" = reconcile ]; then
  printf '%s\n' \
    'intranet-lite-reconcile: prerequisites are enabled only for admin and office-user' \
    'intranet-lite-reconcile: finish the documented Collectives, Teams, Dashboard, and Announcement Center setup manually'
else
  printf '%s\n' \
    'intranet-lite-reconcile: prerequisite app and group target state passed' \
    'intranet-lite-reconcile: verify the documented Collective, Team, Dashboard, and announcement UI state manually'
fi
