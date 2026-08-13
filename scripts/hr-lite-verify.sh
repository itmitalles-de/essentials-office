#!/usr/bin/env bash
# Verify the reproducible, non-sensitive HR Lite target state.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
NEXTCLOUD_ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
HR_LITE_SECRETS_FILE=${HR_LITE_SECRETS_FILE:-"$PROJECT_DIR/.hr-lite-demo.env"}
BASE_URL=
ALLOW_TEST_HTTP=false

die() {
  printf 'hr-lite-verify: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --url)
      [ "$#" -ge 2 ] || die '--url requires an HTTPS URL'
      BASE_URL=${2%/}
      shift 2
      ;;
    --allow-test-http) ALLOW_TEST_HTTP=true; shift ;;
    -h|--help)
      printf '%s\n' 'Usage: ./scripts/hr-lite-verify.sh [--url https://cloud.example.internal] [--allow-test-http]'
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

secret_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$HR_LITE_SECRETS_FILE"
}

for command in awk curl docker jq stat; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
compose config -q
apps=$(occ app:list --output=json)
for app in calendar deck forms tables collectives; do
  jq -e --arg app "$app" '.enabled | has($app)' <<<"$apps" >/dev/null ||
    die "required HR Lite app is not enabled: $app"
done
for group in hr-admin manager employee; do
  occ group:info "$group" >/dev/null || die "missing group: $group"
done
for pair in 'hr-demo-admin:hr-admin' 'manager-demo:manager' 'employee-demo:employee'; do
  user=${pair%%:*}
  group=${pair#*:}
  info=$(occ user:info --output=json "$user") || die "missing fictional user: $user"
  jq -e --arg group "$group" '.groups | index($group) != null' <<<"$info" >/dev/null ||
    die "$user is not in $group"
done

if [ -n "$BASE_URL" ]; then
  if [ "$ALLOW_TEST_HTTP" = true ]; then
    [[ "$BASE_URL" =~ ^http://127\.0\.0\.1:[0-9]+$ ]] || die 'test HTTP mode accepts loopback with an explicit port only'
  else
    [[ "$BASE_URL" =~ ^https:// ]] || die 'verification URL must use HTTPS outside explicit test mode'
  fi
  [ -f "$HR_LITE_SECRETS_FILE" ] || die 'missing HR Lite demo secret file for WebDAV permission test'
  [ "$(stat -c '%a' "$HR_LITE_SECRETS_FILE")" = 600 ] || die 'HR Lite demo secret file must have mode 0600'
  admin_password=$(secret_value HR_LITE_ADMIN_PASSWORD)
  manager_password=$(secret_value HR_LITE_MANAGER_PASSWORD)
  url_host=${BASE_URL#*://}
  url_host=${url_host%%:*}
  admin_netrc=$(mktemp)
  manager_netrc=$(mktemp)
  employee_netrc=
  trap 'rm -f -- "$admin_netrc" "$manager_netrc" "$employee_netrc"' EXIT INT TERM
  chmod 600 "$admin_netrc" "$manager_netrc"
  printf 'machine %s login hr-demo-admin password %s\n' "$url_host" "$admin_password" >"$admin_netrc"
  printf 'machine %s login manager-demo password %s\n' "$url_host" "$manager_password" >"$manager_netrc"
  folder_url="$BASE_URL/remote.php/dav/files/hr-demo-admin/HR%20Lite%20-%20Confidential"
  admin_status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --netrc-file "$admin_netrc" --request PROPFIND -H 'Depth: 0' "$folder_url")
  [ "$admin_status" = 207 ] || die "HR admin cannot read protected folder (HTTP $admin_status)"
  manager_url="$BASE_URL/remote.php/dav/files/manager-demo/HR%20Lite%20-%20Confidential"
  manager_status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --netrc-file "$manager_netrc" --request PROPFIND -H 'Depth: 0' "$manager_url")
  case "$manager_status" in 403|404) ;; *) die "manager unexpectedly reached protected folder (HTTP $manager_status)" ;; esac
  employee_password=$(secret_value HR_LITE_EMPLOYEE_PASSWORD)
  employee_netrc=$(mktemp)
  chmod 600 "$employee_netrc"
  printf 'machine %s login employee-demo password %s\n' "$url_host" "$employee_password" >"$employee_netrc"
  employee_url="$BASE_URL/remote.php/dav/files/employee-demo/HR%20Lite%20-%20Confidential"
  employee_status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --netrc-file "$employee_netrc" --request PROPFIND -H 'Depth: 0' "$employee_url")
  case "$employee_status" in 403|404) ;; *) die "employee unexpectedly reached protected folder (HTTP $employee_status)" ;; esac
  for fixture in employee-directory.csv absence-requests.csv responsibilities.csv workflow-target.json; do
    status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
      --netrc-file "$admin_netrc" --head "$folder_url/$fixture")
    [ "$status" = 200 ] || die "synthetic HR workflow fixture is missing: $fixture (HTTP $status)"
  done
fi

printf 'hr-lite-verify: group, app, and fictional-account target state passed\n'
