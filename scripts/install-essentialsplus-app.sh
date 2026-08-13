#!/usr/bin/env bash
# Install the repository-owned Nextcloud app and canonical manifest safely.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
SOURCE_DIR="$PROJECT_DIR/nextcloud-apps/essentialsplus"
MANIFEST="$PROJECT_DIR/office-modules.json"
STAGE_DIR=
MAINTENANCE_ENABLED=false

die() {
  printf 'install-essentialsplus-app: %s\n' "$*" >&2
  exit 1
}

env_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE"
}

compose() {
  docker compose --env-file "$ENV_FILE" -f "$PROJECT_DIR/compose.yaml" "$@"
}

occ() {
  compose exec -T -u www-data app php occ "$@"
}

cleanup() {
  local status=$?
  if [ "$MAINTENANCE_ENABLED" = true ]; then
    if ! occ maintenance:mode --off >/dev/null; then
      printf 'install-essentialsplus-app: WARNING: maintenance mode could not be disabled\n' >&2
      status=1
    fi
  fi
  if [ -n "$STAGE_DIR" ] && [[ "$STAGE_DIR" == */custom_apps/.essentialsplus.stage.* ]] && [ -d "$STAGE_DIR" ]; then
    find "$STAGE_DIR" -xdev -depth -delete
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ "${EUID}" -ne 0 ]; then
  exec sudo --preserve-env=NEXTCLOUD_ENV_FILE,ESSENTIALSPLUS_BACKUP_DONE -- "$0" "$@"
fi
[ "$#" -eq 0 ] || die 'usage: install-essentialsplus-app.sh'
for command in awk chown cmp diff docker find install jq mktemp mv rsync stat sudo tr; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$ENV_FILE" ] || die "missing environment file: $ENV_FILE"
[ -f "$SOURCE_DIR/appinfo/info.xml" ] || die 'repository-owned Nextcloud app source is incomplete'
[ -f "$MANIFEST" ] || die 'module manifest is missing'
jq -e '.product.displayName == "Essentials+ Office" and .schemaVersion == "1.0.0"' "$MANIFEST" >/dev/null ||
  die 'module manifest is invalid or incompatible'

data_root=$(env_value NEXTCLOUD_DATA_ROOT)
case "$data_root" in
  /*) ;;
  *) die 'NEXTCLOUD_DATA_ROOT must be an absolute path' ;;
esac
[ "$data_root" != / ] || die 'NEXTCLOUD_DATA_ROOT must not be the filesystem root'
custom_apps="$data_root/html/custom_apps"
target="$custom_apps/essentialsplus"
[ -d "$custom_apps" ] || die 'Nextcloud custom_apps directory is missing; start the core first'
[ ! -L "$custom_apps" ] || die 'custom_apps must not be a symlink'
[ ! -e "$target" ] || [ -d "$target" ] || die 'target exists but is not a directory'
[ ! -L "$target" ] || die 'refusing a symlinked Essentials+ app target'

STAGE_DIR=$(mktemp -d "$custom_apps/.essentialsplus.stage.XXXXXX")
rsync -a --delete --exclude='/resources/office-modules.json' "$SOURCE_DIR/" "$STAGE_DIR/"
install -m 0644 "$MANIFEST" "$STAGE_DIR/resources/office-modules.json"

www_uid=$(compose exec -T app id -u www-data | tr -d '\r')
www_gid=$(compose exec -T app id -g www-data | tr -d '\r')
[[ "$www_uid" =~ ^[0-9]+$ ]] || die 'could not determine Nextcloud app UID'
[[ "$www_gid" =~ ^[0-9]+$ ]] || die 'could not determine Nextcloud app GID'
chown -R "$www_uid:$www_gid" "$STAGE_DIR"

if [ -d "$target" ] && diff -qr --no-dereference "$STAGE_DIR" "$target" >/dev/null; then
  printf 'install-essentialsplus-app: app code and manifest already match\n'
  exit 0
fi

was_enabled=false
if occ app:list --output=json | jq -e '.enabled | has("essentialsplus")' >/dev/null 2>&1; then
  was_enabled=true
  if [ "${ESSENTIALSPLUS_BACKUP_DONE:-false}" != true ]; then
    "$SCRIPT_DIR/backup.sh"
  fi
  occ maintenance:mode --on >/dev/null
  MAINTENANCE_ENABLED=true
  occ app:disable essentialsplus >/dev/null
fi

if [ -d "$target" ]; then
  rsync -a --delete "$STAGE_DIR/" "$target/"
  chown -R "$www_uid:$www_gid" "$target"
  find "$STAGE_DIR" -xdev -depth -delete
  STAGE_DIR=
else
  mv -- "$STAGE_DIR" "$target"
  STAGE_DIR=
fi

if [ "$was_enabled" = true ]; then
  occ app:enable essentialsplus >/dev/null
  occ maintenance:mode --off >/dev/null
  MAINTENANCE_ENABLED=false
fi
printf 'install-essentialsplus-app: versioned app code and module manifest installed\n'
