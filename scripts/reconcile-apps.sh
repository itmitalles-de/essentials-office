#!/usr/bin/env bash
# Reconcile manifest-declared app packages without activating optional modules.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
MANIFEST=${OFFICE_MODULE_CONTRACT:-"$PROJECT_DIR/office-modules.json"}
REPORT_DIR=${APP_REPORT_DIR:-"$PROJECT_DIR/reports"}
CATALOG_FILE=${NEXTCLOUD_APP_CATALOG_FILE:-}
EXPECTED_NEXTCLOUD_MAJOR=${EXPECTED_NEXTCLOUD_MAJOR:-34}
MODE=apply
UPDATE_APPS=false
SCOPE=nextcloud-core
WORK_DIR=

die() {
  printf 'reconcile-apps: %s\n' "$*" >&2
  exit 1
}

occ() {
  docker compose exec -T -u www-data app php occ "$@"
}

installed_app_version() {
  occ config:app:get "$1" installed_version --default-value=''
}

cleanup() {
  local status=$?
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/essentialsplus-apps.* ]] && [ -d "$WORK_DIR" ]; then
    find "$WORK_DIR" -xdev -depth -delete
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

usage() {
  printf '%s\n' 'Usage: reconcile-apps.sh [--check|--update] [--module MODULE_ID|--all]'
}

scope_set=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      [ "$MODE" = apply ] && [ "$UPDATE_APPS" = false ] || die '--check and --update are mutually exclusive'
      MODE=check
      shift
      ;;
    --update)
      [ "$MODE" = apply ] || die '--check and --update are mutually exclusive'
      UPDATE_APPS=true
      shift
      ;;
    --module)
      [ "$#" -ge 2 ] || die '--module requires a module ID'
      [ "$scope_set" = false ] || die 'select only one --module or --all scope'
      SCOPE=$2
      scope_set=true
      shift 2
      ;;
    --all)
      [ "$scope_set" = false ] || die 'select only one --module or --all scope'
      SCOPE=all
      scope_set=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

for command in awk cmp cp curl date diff docker find head install jq mktemp sed sort stat; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$PROJECT_DIR/.env" ] || die 'missing .env; run bootstrap.sh first'
[ -f "$MANIFEST" ] || die "missing module contract: $MANIFEST"
jq -e '.product.displayName == "Essentials+ Office" and .schemaVersion == "1.0.0"' "$MANIFEST" >/dev/null ||
  die 'module contract is invalid or incompatible'
if [ "$SCOPE" != all ]; then
  jq -e --arg id "$SCOPE" '.modules[] | select(.id == $id)' "$MANIFEST" >/dev/null || die "unknown module: $SCOPE"
fi

cd "$PROJECT_DIR"
docker compose config -q
docker compose ps --status running --services | grep -Fxq app || die 'app service is not running'

status=$(occ status --output=json)
installed=$(jq -r '.installed' <<<"$status")
maintenance=$(jq -r '.maintenance' <<<"$status")
needs_upgrade=$(jq -r '.needsDbUpgrade' <<<"$status")
nextcloud_version=$(jq -r '.versionstring' <<<"$status")
nextcloud_major=${nextcloud_version%%.*}
[ "$installed" = true ] || die 'Nextcloud is not installed'
[ "$maintenance" = false ] || die 'Nextcloud is in maintenance mode'
[ "$needs_upgrade" = false ] || die 'Nextcloud requires a database upgrade'
[ "$nextcloud_major" = "$EXPECTED_NEXTCLOUD_MAJOR" ] ||
  die "Nextcloud $nextcloud_version does not match allowed major $EXPECTED_NEXTCLOUD_MAJOR"

mapfile -t apps < <(jq -c --arg scope "$SCOPE" --argjson all "$([ "$SCOPE" = all ] && printf true || printf false)" '
  [.modules[] | select($all or .id == $scope) as $module |
    $module.nextcloudApps[] + {activateOnReconcile: $module.required, moduleId: $module.id}]
  | group_by(.id)
  | map(.[0] + {activateOnReconcile: any(.activateOnReconcile)})
  | .[]
' "$MANIFEST")
[ "${#apps[@]}" -gt 0 ] || die "module scope $SCOPE declares no Nextcloud apps"

WORK_DIR=$(mktemp -d /tmp/essentialsplus-apps.XXXXXX)
compatibility_json="$WORK_DIR/compatible-apps.json"
if printf '%s\n' "${apps[@]}" | jq -e -s 'any(.source == "app-store")' >/dev/null; then
  mkdir -p "$REPORT_DIR"
  cache="$REPORT_DIR/app-store-catalog-$nextcloud_version.json"
  if [ -n "$CATALOG_FILE" ]; then
    [ -f "$CATALOG_FILE" ] && [ ! -L "$CATALOG_FILE" ] || die 'NEXTCLOUD_APP_CATALOG_FILE must be a regular non-symlink file'
    cp -- "$CATALOG_FILE" "$compatibility_json"
  elif [ -f "$cache" ] && [ ! -L "$cache" ] &&
    [ $(( $(date +%s) - $(stat -c '%Y' "$cache") )) -lt 86400 ]; then
    cp -- "$cache" "$compatibility_json"
  else
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
      --connect-timeout 10 --max-time 120 --retry 3 --retry-all-errors \
      "https://apps.nextcloud.com/api/v1/platform/${nextcloud_version}/apps.json" \
      --output "$compatibility_json"
    install -m 0644 "$compatibility_json" "$cache"
  fi
  jq -e 'type == "array"' "$compatibility_json" >/dev/null || die 'App Store returned invalid JSON'
else
  printf '[]\n' >"$compatibility_json"
fi

printf 'reconcile-apps: compatibility preflight for Nextcloud %s (scope=%s)\n' "$nextcloud_version" "$SCOPE"
for app_json in "${apps[@]}"; do
  app=$(jq -r '.id' <<<"$app_json")
  source=$(jq -r '.source' <<<"$app_json")
  minimum=$(jq -r '.minVersion' <<<"$app_json")
  maximum=$(jq -r '.maxExclusive' <<<"$app_json")
  case "$source" in
    app-store)
      candidate=$(jq -r --arg app "$app" '[.[] | select(.id == $app) | .releases[0].version][0] // empty' "$compatibility_json")
      [ -n "$candidate" ] || die "no App Store release of $app is compatible with Nextcloud $nextcloud_version"
      if ! printf '%s\n%s\n' "$minimum" "$candidate" | sort -V -C \
        || ! printf '%s\n%s\n' "$candidate" "$maximum" | sort -V -C \
        || [ "$candidate" = "$maximum" ]; then
        die "compatible App Store release $candidate is outside manifest range for $app"
      fi
      printf '  %-20s app-store %s\n' "$app" "$candidate"
      ;;
    shipped)
      printf '  %-20s shipped package\n' "$app"
      ;;
    repository)
      case "$app" in
        appointments|essentialsplus) ;;
        *) die "unsupported repository-owned app: $app" ;;
      esac
      source_version=$(sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "nextcloud-apps/$app/appinfo/info.xml" | head -n 1)
      [ -n "$source_version" ] || die 'could not read repository app version'
      printf '  %-20s repository %s\n' "$app" "$source_version"
      ;;
    *) die "unsupported app source for $app: $source" ;;
  esac
done

app_state=$(occ app:list --output=json)
changes_required=false
for app_json in "${apps[@]}"; do
  app=$(jq -r '.id' <<<"$app_json")
  source=$(jq -r '.source' <<<"$app_json")
  activate=$(jq -r '.activateOnReconcile' <<<"$app_json")
  installed_version=$(installed_app_version "$app")
  if [ -z "$installed_version" ]; then
    changes_required=true
  elif [ "$activate" = true ] && ! jq -e --arg app "$app" '.enabled | has($app)' <<<"$app_state" >/dev/null; then
    changes_required=true
  fi
  if [ "$source" = repository ]; then
    target=$(awk -F= '$1 == "NEXTCLOUD_DATA_ROOT" {print $2; exit}' .env)/html/custom_apps/"$app"
    repository_tree_matches=false
    if [ -d "$target" ]; then
      if [ "$app" = essentialsplus ]; then
        diff -qr --no-dereference --exclude=office-modules.json \
          "nextcloud-apps/$app" "$target" >/dev/null 2>&1 && repository_tree_matches=true
      else
        diff -qr --no-dereference "nextcloud-apps/$app" "$target" >/dev/null 2>&1 && repository_tree_matches=true
      fi
    fi
    if [ "$repository_tree_matches" = false ]; then
      changes_required=true
    fi
    if [ "$app" = essentialsplus ] && { [ ! -f "$target/resources/office-modules.json" ] ||
      ! cmp --silent office-modules.json "$target/resources/office-modules.json"; }; then
      changes_required=true
    fi
  fi
done
[ "$UPDATE_APPS" = false ] || changes_required=true

if [ "$MODE" = check ]; then
  [ "$changes_required" = false ] || die 'declared app package/activation state differs from the selected manifest scope'
else
  if [ "$changes_required" = true ]; then
    "$SCRIPT_DIR/backup.sh"
  fi
  for app_json in "${apps[@]}"; do
    app=$(jq -r '.id' <<<"$app_json")
    source=$(jq -r '.source' <<<"$app_json")
    activate=$(jq -r '.activateOnReconcile' <<<"$app_json")
    app_state=$(occ app:list --output=json)
    installed_version=$(installed_app_version "$app")
    if [ "$source" = repository ]; then
      case "$app" in
        essentialsplus)
          ESSENTIALSPLUS_BACKUP_DONE=true "$SCRIPT_DIR/install-essentialsplus-app.sh"
          ;;
        appointments)
          APPOINTMENTS_BACKUP_DONE=true "$SCRIPT_DIR/install-appointments-app.sh"
          ;;
        *) die "unsupported repository-owned app: $app" ;;
      esac
      app_state=$(occ app:list --output=json)
    fi
    if [ -z "$installed_version" ]; then
      if [ "$source" = repository ]; then
        occ app:enable "$app" >/dev/null
        # Enabling is required once so Nextcloud registers the local package and
        # runs its migration. Optional modules must nevertheless stay private
        # until their health-gated module activation is requested explicitly.
        if [ "$activate" != true ]; then
          occ app:disable "$app" >/dev/null
        fi
      elif [ "$activate" = true ]; then
        occ app:install "$app" >/dev/null
      else
        occ app:install --keep-disabled "$app" >/dev/null
      fi
    elif [ "$activate" = true ] && ! jq -e --arg app "$app" '.enabled | has($app)' <<<"$app_state" >/dev/null; then
      occ app:enable "$app" >/dev/null
    fi
    if [ "$UPDATE_APPS" = true ] && [ "$source" = app-store ]; then
      occ app:update "$app" >/dev/null
    fi
  done
fi

final_state=$(occ app:list --output=json)
report_lines="$WORK_DIR/report.jsonl"
for app_json in "${apps[@]}"; do
  app=$(jq -r '.id' <<<"$app_json")
  source=$(jq -r '.source' <<<"$app_json")
  installed_version=$(installed_app_version "$app")
  enabled=$(jq -r --arg app "$app" '.enabled | has($app)' <<<"$final_state")
  [ -n "$installed_version" ] || die "$app is missing after reconciliation"
  compatible_version=$installed_version
  if [ "$source" = app-store ]; then
    compatible_version=$(jq -r --arg app "$app" '[.[] | select(.id == $app) | .releases[0].version][0]' "$compatibility_json")
  fi
  jq -n --arg id "$app" --arg source "$source" --arg installedVersion "$installed_version" \
    --arg compatibleVersion "$compatible_version" --argjson enabled "$enabled" \
    '{id: $id, source: $source, installedVersion: $installedVersion, enabled: $enabled, latestCompatibleVersion: $compatibleVersion}' \
    >>"$report_lines"
done

mkdir -p "$REPORT_DIR"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
report="$REPORT_DIR/nextcloud-apps-$stamp.json"
jq -s --arg generatedAt "$stamp" --arg nextcloudVersion "$nextcloud_version" --arg scope "$SCOPE" \
  '{generatedAt: $generatedAt, nextcloudVersion: $nextcloudVersion, scope: $scope, apps: .}' \
  "$report_lines" >"$report"
cp -- "$report" "$REPORT_DIR/nextcloud-apps-latest.json"
printf 'reconcile-apps: selected package state verified; optional module activation remains Admin-Center controlled (%s)\n' "$report"
