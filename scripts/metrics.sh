#!/usr/bin/env bash
# Export a secret-free Prometheus text snapshot for Essentials+ Office.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}

die() {
  printf 'metrics: %s\n' "$*" >&2
  exit 1
}

for command in awk date docker find jq sort; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$ENV_FILE" ] || die "missing environment file: $ENV_FILE"
cd "$PROJECT_DIR"
compose=(docker compose --env-file "$ENV_FILE" -f compose.yaml)
"${compose[@]}" config -q

printf '%s\n' \
  '# HELP essentialsplus_service_up Whether a required core service is running and healthy where applicable.' \
  '# TYPE essentialsplus_service_up gauge'
for service in db redis app cron; do
  container_id=$("${compose[@]}" ps -q "$service")
  up=0
  if [ -n "$container_id" ]; then
    state=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id")
    case "$state" in
      'running healthy'|'running none') up=1 ;;
    esac
  fi
  printf 'essentialsplus_service_up{service="%s"} %d\n' "$service" "$up"
done

data_root=$(awk -F= '$1 == "NEXTCLOUD_DATA_ROOT" {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE")
latest_backup=$(find "$data_root/backups" -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%T@\n' 2>/dev/null | sort -n | tail -n 1)
printf '%s\n' \
  '# HELP essentialsplus_backup_timestamp_seconds Modification timestamp of the latest local backup directory.' \
  '# TYPE essentialsplus_backup_timestamp_seconds gauge'
printf 'essentialsplus_backup_timestamp_seconds %.0f\n' "${latest_backup:-0}"

if "${compose[@]}" ps --status running --services | grep -Fxq app; then
  "${compose[@]}" exec -T -u www-data app php occ essentialsplus:metrics 2>/dev/null || true
  apps=$("${compose[@]}" exec -T -u www-data app php occ app:list --output=json)
  printf '%s\n' '# HELP essentialsplus_nextcloud_app_enabled Whether a manifest-declared Nextcloud app is enabled.' '# TYPE essentialsplus_nextcloud_app_enabled gauge'
  while IFS= read -r app; do
    enabled=$(jq -r --arg app "$app" 'if .enabled | has($app) then 1 else 0 end' <<<"$apps")
    printf 'essentialsplus_nextcloud_app_enabled{app="%s"} %s\n' "$app" "$enabled"
  done < <(jq -r '[.modules[].nextcloudApps[].id] | unique[]' office-modules.json)
  cron_mode=$("${compose[@]}" exec -T -u www-data app php occ config:app:get core backgroundjobs_mode 2>/dev/null || true)
  [ "$cron_mode" = cron ] && cron_configured=1 || cron_configured=0
  printf '%s\n' '# HELP essentialsplus_cron_configured Whether Nextcloud background mode is cron.' '# TYPE essentialsplus_cron_configured gauge'
  printf 'essentialsplus_cron_configured %d\n' "$cron_configured"
fi
