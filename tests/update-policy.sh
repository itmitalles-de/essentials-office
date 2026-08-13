#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
WORK_DIR=$(mktemp -d /tmp/essentialsplus-update-policy.XXXXXX)
trap 'find "$WORK_DIR" -xdev -depth -delete' EXIT INT TERM

cp "$PROJECT_DIR/compose.yaml" "$WORK_DIR/compose.yaml"
sed -i 's/nextcloud:34-apache/nextcloud:35-apache/g' "$WORK_DIR/compose.yaml"
export POSTGRES_PASSWORD=placeholder NEXTCLOUD_ADMIN_PASSWORD=placeholder REDIS_PASSWORD=placeholder
export POSTGRES_DB=nextcloud POSTGRES_USER=nextcloud NEXTCLOUD_ADMIN_USER=admin
export NEXTCLOUD_TRUSTED_DOMAINS=cloud.itmitalles.de TRUSTED_PROXIES=172.18.0.0/16
if "$PROJECT_DIR/scripts/verify-image-policy.sh" "$WORK_DIR/compose.yaml" >/dev/null 2>&1; then
  printf 'update-policy-test: unexpected Nextcloud major was accepted\n' >&2
  exit 1
fi
"$PROJECT_DIR/scripts/verify-image-policy.sh" "$PROJECT_DIR/compose.yaml" >/dev/null
printf 'update-policy-test: approved majors pass and simulated Nextcloud major upgrade fails closed\n'
