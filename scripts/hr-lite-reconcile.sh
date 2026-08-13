#!/usr/bin/env bash
# Create only fictional HR Lite groups, users, templates, and a protected share.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
NEXTCLOUD_ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
HR_LITE_SECRETS_FILE=${HR_LITE_SECRETS_FILE:-"$PROJECT_DIR/.hr-lite-demo.env"}
BASE_URL=

die() {
  printf 'hr-lite-reconcile: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/hr-lite-reconcile.sh [--url https://cloud.example.internal]

This script creates fictional accounts only. It installs compatible Nextcloud
apps through OCC, creates the HR groups, and publishes the committed templates
through supported WebDAV and OCS sharing APIs. It never writes Nextcloud SQL.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      [ "$#" -ge 2 ] || die '--url requires an HTTPS URL'
      BASE_URL=${2%/}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

compose() {
  docker compose --env-file "$NEXTCLOUD_ENV_FILE" -f "$PROJECT_DIR/compose.yaml" "$@"
}

occ() {
  compose exec -T -u www-data app php occ "$@"
}

env_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$HR_LITE_SECRETS_FILE"
}

ensure_group() {
  local group=$1
  occ group:info "$group" >/dev/null 2>&1 || occ group:add "$group" >/dev/null
}

app_state() {
  local app=$1 state=$2 apps
  apps=$(occ app:list --output=json)
  jq -e --arg app "$app" --arg state "$state" '.[$state] | has($app)' <<<"$apps" >/dev/null
}

ensure_app() {
  local app=$1
  if app_state "$app" enabled; then
    return
  fi
  if app_state "$app" disabled; then
    occ app:enable "$app" >/dev/null
  else
    # OCC selects an app-store release compatible with this Nextcloud version.
    occ app:install "$app" >/dev/null
    occ app:enable "$app" >/dev/null
  fi
}

ensure_user() {
  local user=$1 display_name=$2 password=$3
  if ! occ user:info "$user" >/dev/null 2>&1; then
    compose exec -T -u www-data -e "OC_PASS=$password" app php occ user:add \
      --password-from-env --display-name "$display_name" "$user" >/dev/null
  fi
}

ensure_membership() {
  local user=$1 group=$2 info
  info=$(occ user:info --output=json "$user")
  if ! jq -e --arg group "$group" '.groups | index($group) != null' <<<"$info" >/dev/null; then
    occ group:adduser "$group" "$user" >/dev/null
  fi
}

make_secrets_file() {
  if [ -e "$HR_LITE_SECRETS_FILE" ]; then
    [ -f "$HR_LITE_SECRETS_FILE" ] || die "$HR_LITE_SECRETS_FILE exists but is not a regular file"
    [ "$(stat -c '%a' "$HR_LITE_SECRETS_FILE")" = 600 ] || die "$HR_LITE_SECRETS_FILE must have mode 0600"
    return
  fi
  umask 077
  {
    printf 'HR_LITE_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    printf 'HR_LITE_MANAGER_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    printf 'HR_LITE_EMPLOYEE_PASSWORD=%s\n' "$(openssl rand -hex 32)"
  } >"$HR_LITE_SECRETS_FILE"
  chmod 0600 "$HR_LITE_SECRETS_FILE"
}

webdav_status() {
  local method=$1 url=$2 netrc=$3
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --netrc-file "$netrc" --request "$method" "$url"
}

for command in awk curl docker jq openssl stat; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
if [ -z "$BASE_URL" ]; then
  BASE_URL=$(awk -F= '$1 == "OVERWRITECLIURL" { print $2; exit }' "$NEXTCLOUD_ENV_FILE")
fi
[[ "$BASE_URL" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] ||
  die 'provide a configured HTTPS Nextcloud URL with --url or OVERWRITECLIURL'
compose config -q

for app in calendar deck forms tables collectives; do
  ensure_app "$app"
done
for group in hr-admin manager employee; do
  ensure_group "$group"
done
make_secrets_file

hr_admin_password=$(env_value HR_LITE_ADMIN_PASSWORD)
manager_password=$(env_value HR_LITE_MANAGER_PASSWORD)
employee_password=$(env_value HR_LITE_EMPLOYEE_PASSWORD)
for password in "$hr_admin_password" "$manager_password" "$employee_password"; do
  [[ "$password" =~ ^[0-9a-f]{64}$ ]] || die 'HR Lite demo secret file has an invalid value'
done

ensure_user hr-demo-admin 'HR Demo Administrator' "$hr_admin_password"
ensure_user manager-demo 'Manager Demo' "$manager_password"
ensure_user employee-demo 'Employee Demo' "$employee_password"
ensure_membership hr-demo-admin hr-admin
ensure_membership manager-demo manager
ensure_membership employee-demo employee

netrc=$(mktemp)
trap 'rm -f -- "$netrc"' EXIT INT TERM
chmod 600 "$netrc"
url_host=${BASE_URL#https://}
printf 'machine %s login %s password %s\n' "$url_host" hr-demo-admin "$hr_admin_password" >"$netrc"
unset hr_admin_password manager_password employee_password

folder_path='HR%20Lite%20-%20Confidential'
folder_url="$BASE_URL/remote.php/dav/files/hr-demo-admin/$folder_path"
status=$(webdav_status MKCOL "$folder_url" "$netrc")
case "$status" in
  201|405) ;;
  *) die "could not create protected HR Lite folder (HTTP $status)" ;;
esac

for template in "$PROJECT_DIR"/hr-lite/templates/*.md; do
  template_name=$(basename "$template")
  curl --fail --silent --show-error --netrc-file "$netrc" --upload-file "$template" \
    "$folder_url/$template_name" >/dev/null
done

shares=$(curl --fail --silent --show-error --netrc-file "$netrc" \
  -H 'OCS-APIRequest: true' -H 'Accept: application/json' \
  "$BASE_URL/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json&path=%2FHR%20Lite%20-%20Confidential")
if ! jq -e --arg group hr-admin \
  '[.ocs.data[]? | select(.share_type == 1 and .share_with == $group)] | length > 0' \
  <<<"$shares" >/dev/null; then
  curl --fail --silent --show-error --netrc-file "$netrc" \
    -H 'OCS-APIRequest: true' -H 'Accept: application/json' \
    --request POST \
    --data-urlencode 'path=/HR Lite - Confidential' \
    --data 'shareType=1' --data-urlencode 'shareWith=hr-admin' --data 'permissions=31' \
    "$BASE_URL/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json" >/dev/null
fi

printf '%s\n' \
  'hr-lite-reconcile: fictional users, app prerequisites, templates, and protected share are ready' \
  'hr-lite-reconcile: complete the documented Forms, Tables, Deck, Calendar, and Collectives setup manually'
