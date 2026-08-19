#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
WORK_DIR=$(mktemp -d /tmp/essentialsplus-update-policy.XXXXXX)
trap 'find "$WORK_DIR" -xdev -depth -delete' EXIT INT TERM

cp "$PROJECT_DIR/compose.yaml" "$WORK_DIR/compose.yaml"
cp "$PROJECT_DIR/compose.yaml" "$WORK_DIR/compose-allowed.yaml"
sed -i \
  's#nextcloud:34\.0\.2-apache@sha256:[0-9a-f]\{64\}#nextcloud:34.0.3-apache@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb#g' \
  "$WORK_DIR/compose-allowed.yaml"
sed -i \
  's#nextcloud:34\.0\.2-apache@sha256:[0-9a-f]\{64\}#nextcloud:35.0.0-apache@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa#g' \
  "$WORK_DIR/compose.yaml"
export POSTGRES_PASSWORD=placeholder NEXTCLOUD_ADMIN_PASSWORD=placeholder REDIS_PASSWORD=placeholder
export POSTGRES_DB=nextcloud POSTGRES_USER=nextcloud NEXTCLOUD_ADMIN_USER=admin
export NEXTCLOUD_TRUSTED_DOMAINS=cloud.itmitalles.de TRUSTED_PROXIES=172.18.0.0/16
"$PROJECT_DIR/scripts/verify-image-policy.sh" "$WORK_DIR/compose-allowed.yaml" >/dev/null
if "$PROJECT_DIR/scripts/verify-image-policy.sh" "$WORK_DIR/compose.yaml" >/dev/null 2>&1; then
  printf 'update-policy-test: unexpected Nextcloud major was accepted\n' >&2
  exit 1
fi
"$PROJECT_DIR/scripts/verify-image-policy.sh" "$PROJECT_DIR/compose.yaml" >/dev/null
printf 'update-policy-test: reviewed patch pins pass and simulated Nextcloud major upgrade fails closed\n'
