#!/usr/bin/env bash
# Reconcile fictional, Nextcloud-native Intranet Lite prerequisites and content.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
NEXTCLOUD_ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
OFFICE_MODULE_CONFIG=${OFFICE_MODULE_CONFIG:-"$PROJECT_DIR/config/office-modules.env"}
INTRANET_SECRETS_FILE=${INTRANET_SECRETS_FILE:-"$PROJECT_DIR/.intranet-lite-demo.env"}
BASE_URL=
ALLOW_TEST_HTTP=false
MODE=

die() {
  printf 'intranet-lite-reconcile: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/intranet-lite-reconcile.sh --reconcile|--verify [--url https://cloud.example.internal] [--allow-test-http]

The script uses only supported OCC, WebDAV, and OCS APIs. It creates fictional
demonstration accounts and content; disabling the module never invokes it and
never removes apps, content, users, shares, or volumes.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reconcile|--verify) MODE=${1#--}; shift ;;
    --url) [ "$#" -ge 2 ] || die '--url requires a URL'; BASE_URL=${2%/}; shift 2 ;;
    --allow-test-http) ALLOW_TEST_HTTP=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$MODE" ] || die 'use --reconcile or --verify'

config_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$OFFICE_MODULE_CONFIG"
}

secret_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$INTRANET_SECRETS_FILE"
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

ensure_group() {
  local group=$1
  occ group:info "$group" >/dev/null 2>&1 || occ group:add "$group" >/dev/null
}

ensure_app_package() {
  local app=$1
  if app_state "$app" enabled || app_state "$app" disabled; then return; fi
  occ app:install "$app" >/dev/null
  occ app:disable "$app" >/dev/null
}

ensure_user() {
  local user=$1 display_name=$2 password=$3
  if ! occ user:info "$user" >/dev/null 2>&1; then
    OC_PASS="$password" compose exec -T -u www-data -e OC_PASS app php occ user:add \
      --password-from-env --display-name "$display_name" "$user" >/dev/null
  fi
}

ensure_membership() {
  local user=$1 group=$2 info
  info=$(occ user:info --output=json "$user")
  jq -e --arg group "$group" '.groups | index($group) != null' <<<"$info" >/dev/null ||
    occ group:adduser "$group" "$user" >/dev/null
}

make_secrets_file() {
  if [ -e "$INTRANET_SECRETS_FILE" ]; then
    [ -f "$INTRANET_SECRETS_FILE" ] || die "$INTRANET_SECRETS_FILE is not a regular file"
    [ "$(stat -c '%a' "$INTRANET_SECRETS_FILE")" = 600 ] || die "$INTRANET_SECRETS_FILE must have mode 0600"
    return
  fi
  umask 077
  {
    printf 'INTRANET_EDITOR_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    printf 'INTRANET_READER_PASSWORD=%s\n' "$(openssl rand -hex 32)"
    printf 'INTRANET_OUTSIDER_PASSWORD=%s\n' "$(openssl rand -hex 32)"
  } >"$INTRANET_SECRETS_FILE"
  chmod 0600 "$INTRANET_SECRETS_FILE"
}

http_status() {
  local method=$1 url=$2 netrc=$3
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --netrc-file "$netrc" --request "$method" "$url"
}

ensure_group_share() {
  local netrc=$1 path=$2 group=$3 permissions=$4 shares
  shares=$(curl --fail --silent --show-error --netrc-file "$netrc" \
    -H 'OCS-APIRequest: true' -H 'Accept: application/json' \
    "$BASE_URL/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json&path=$(jq -rn --arg v "$path" '$v|@uri')")
  if ! jq -e --arg group "$group" --argjson permissions "$permissions" \
    '[.ocs.data[]? | select(.share_type == 1 and .share_with == $group and .permissions == $permissions)] | length > 0' \
    <<<"$shares" >/dev/null; then
    curl --fail --silent --show-error --netrc-file "$netrc" \
      -H 'OCS-APIRequest: true' -H 'Accept: application/json' --request POST \
      --data-urlencode "path=$path" --data 'shareType=1' --data-urlencode "shareWith=$group" \
      --data-urlencode "permissions=$permissions" \
      "$BASE_URL/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json" >/dev/null
  fi
}

for command in awk curl docker jq openssl stat; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
[ -f "$OFFICE_MODULE_CONFIG" ] || die "missing $OFFICE_MODULE_CONFIG; initialize it from config/office-modules.env.example"
[ "$(config_value OFFICE_MODULE_INTRANET_LITE_ENABLED)" = true ] ||
  die 'Intranet Lite is disabled in the Essentials+ Office module configuration'
if [ -z "$BASE_URL" ]; then
  BASE_URL=$(awk -F= '$1 == "OVERWRITECLIURL" { print $2; exit }' "$NEXTCLOUD_ENV_FILE")
fi
if [ "$ALLOW_TEST_HTTP" = true ]; then
  [[ "$BASE_URL" =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || die 'test HTTP mode accepts loopback with an explicit port only'
else
  [[ "$BASE_URL" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || die 'a configured HTTPS URL is required'
fi
compose config -q

for group in intranet-editor employee manager; do
  if [ "$MODE" = reconcile ]; then ensure_group "$group"; else occ group:info "$group" >/dev/null || die "missing group: $group"; fi
done
for app in dashboard circles collectives announcementcenter forms tables deck; do
  if [ "$MODE" = reconcile ]; then ensure_app_package "$app"; else app_state "$app" enabled || die "required Intranet Lite app is not enabled: $app"; fi
done

if [ "$MODE" = reconcile ]; then
  make_secrets_file
  editor_password=$(secret_value INTRANET_EDITOR_PASSWORD)
  reader_password=$(secret_value INTRANET_READER_PASSWORD)
  outsider_password=$(secret_value INTRANET_OUTSIDER_PASSWORD)
  for password in "$editor_password" "$reader_password" "$outsider_password"; do
    [[ "$password" =~ ^[0-9a-f]{64}$ ]] || die 'invalid Intranet Lite demonstration secret'
  done
  ensure_user intranet-editor-demo 'Intranet Editor Demo' "$editor_password"
  ensure_user intranet-reader-demo 'Intranet Reader Demo' "$reader_password"
  ensure_user intranet-outsider-demo 'Intranet Outsider Demo' "$outsider_password"
  ensure_membership intranet-editor-demo intranet-editor
  ensure_membership intranet-reader-demo employee

  editor_netrc=$(mktemp)
  trap 'rm -f -- "$editor_netrc"' EXIT INT TERM
  chmod 600 "$editor_netrc"
  printf 'machine %s login intranet-editor-demo password %s\n' "${BASE_URL#*://}" "$editor_password" >"$editor_netrc"
  unset editor_password reader_password outsider_password
  public_url="$BASE_URL/remote.php/dav/files/intranet-editor-demo/Intranet%20Lite"
  confidential_url="$BASE_URL/remote.php/dav/files/intranet-editor-demo/Intranet%20Lite%20-%20Confidential"
  for folder_url in "$public_url" "$confidential_url"; do
    status=$(http_status MKCOL "$folder_url" "$editor_netrc")
    case "$status" in 201|405) ;; *) die "could not create Intranet Lite area (HTTP $status)" ;; esac
  done
  for content in "$PROJECT_DIR"/intranet-lite/content/*.md; do
    curl --fail --silent --show-error --netrc-file "$editor_netrc" --upload-file "$content" \
      "$public_url/$(basename "$content")" >/dev/null
  done
  curl --fail --silent --show-error --netrc-file "$editor_netrc" \
    --upload-file "$PROJECT_DIR/intranet-lite/confidential/editorial-draft.md" \
    "$confidential_url/editorial-draft.md" >/dev/null
  ensure_group_share "$editor_netrc" '/Intranet Lite' employee 1
  ensure_group_share "$editor_netrc" '/Intranet Lite' manager 1
  ensure_group_share "$editor_netrc" '/Intranet Lite' intranet-editor 15
  rm -f -- "$editor_netrc"
fi

[ -f "$INTRANET_SECRETS_FILE" ] || die 'missing Intranet Lite demonstration secret file'
[ "$(stat -c '%a' "$INTRANET_SECRETS_FILE")" = 600 ] || die 'Intranet Lite demonstration secret file must have mode 0600'
editor_password=$(secret_value INTRANET_EDITOR_PASSWORD)
reader_password=$(secret_value INTRANET_READER_PASSWORD)
outsider_password=$(secret_value INTRANET_OUTSIDER_PASSWORD)
editor_netrc=$(mktemp)
reader_netrc=$(mktemp)
outsider_netrc=$(mktemp)
trap 'rm -f -- "$editor_netrc" "$reader_netrc" "$outsider_netrc"' EXIT INT TERM
chmod 600 "$editor_netrc" "$reader_netrc" "$outsider_netrc"
url_host=${BASE_URL#*://}
printf 'machine %s login intranet-editor-demo password %s\n' "$url_host" "$editor_password" >"$editor_netrc"
printf 'machine %s login intranet-reader-demo password %s\n' "$url_host" "$reader_password" >"$reader_netrc"
printf 'machine %s login intranet-outsider-demo password %s\n' "$url_host" "$outsider_password" >"$outsider_netrc"
unset editor_password reader_password outsider_password

editor_public="$BASE_URL/remote.php/dav/files/intranet-editor-demo/Intranet%20Lite"
reader_public="$BASE_URL/remote.php/dav/files/intranet-reader-demo/Intranet%20Lite"
outsider_public="$BASE_URL/remote.php/dav/files/intranet-outsider-demo/Intranet%20Lite"
editor_confidential="$BASE_URL/remote.php/dav/files/intranet-editor-demo/Intranet%20Lite%20-%20Confidential"
[ "$(http_status PROPFIND "$editor_public" "$editor_netrc")" = 207 ] || die 'editor cannot read public intranet area'
[ "$(http_status PROPFIND "$reader_public" "$reader_netrc")" = 207 ] || die 'reader cannot read shared intranet area'
case "$(http_status PROPFIND "$outsider_public" "$outsider_netrc")" in 403|404) ;; *) die 'outsider unexpectedly reached intranet area' ;; esac
[ "$(http_status PROPFIND "$editor_confidential" "$editor_netrc")" = 207 ] || die 'editor cannot read confidential test area'
case "$(http_status PROPFIND "$BASE_URL/remote.php/dav/files/intranet-reader-demo/Intranet%20Lite%20-%20Confidential" "$reader_netrc")" in
  403|404) ;; *) die 'reader unexpectedly reached confidential test area' ;;
esac
for page in current-news handbook processes contacts faq templates-and-links; do
  [ "$(http_status HEAD "$editor_public/$page.md" "$editor_netrc")" = 200 ] || die "missing fictional intranet page: $page.md"
done
providers=$(curl --fail --silent --show-error --netrc-file "$reader_netrc" \
  -H 'OCS-APIRequest: true' -H 'Accept: application/json' "$BASE_URL/ocs/v2.php/search/providers?format=json")
jq -e '.ocs.meta.statuscode == 100 and (.ocs.data | type == "array")' <<<"$providers" >/dev/null ||
  die 'Nextcloud unified-search provider API is unavailable'

printf 'intranet-lite-reconcile: apps, roles, fictional content, search API, and confidential-area permissions passed\n'
