#!/usr/bin/env bash
# Verify that the Visual PBX boundary remains opt-in and credential-free.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG=${VISUAL_PBX_CONFIG:-"$PROJECT_DIR/integrations/visual-pbx.env"}
NEXTCLOUD_ENV_FILE=${NEXTCLOUD_ENV_FILE:-"$PROJECT_DIR/.env"}
CHECK_HEALTH=false
TEST_MODE=${VISUAL_PBX_TEST_MODE:-false}

die() {
  printf 'visual-pbx-contract-check: %s\n' "$*" >&2
  exit 1
}

config_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$CONFIG"
}

case "${1:-}" in
  '') ;;
  --check-health) CHECK_HEALTH=true ;;
  -h|--help)
    printf '%s\n' 'Usage: ./scripts/visual-pbx-contract-check.sh [--check-health]'
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
esac

for command in awk curl docker rg; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
[ -f "$CONFIG" ] || die "missing $CONFIG; copy integrations/visual-pbx.env.example locally"
[ -f "$NEXTCLOUD_ENV_FILE" ] || die "missing $NEXTCLOUD_ENV_FILE"
enabled=$(config_value VISUAL_PBX_ENABLED)
case "$enabled" in true|false) ;; *) die 'VISUAL_PBX_ENABLED must be true or false' ;; esac

# Office never defines a PBX container, port, or Caddy route.
docker compose --env-file "$NEXTCLOUD_ENV_FILE" -f "$PROJECT_DIR/compose.yaml" config --services | grep -Eiq '^visual-pbx$|^pbx$' &&
  die 'a PBX service must not be added to the Nextcloud core compose file'
if rg -n '^\s*reverse_proxy\s+.*(visual-pbx|\bpbx\b)' \
  "$PROJECT_DIR"/Caddyfile*.example >/dev/null 2>&1; then
  die 'a public PBX Caddy route must not be present in this repository'
fi

if [ "$enabled" = false ]; then
  printf 'visual-pbx-contract-check: integration is disabled; no PBX route or host port exists\n'
  exit 0
fi

portal_url=$(config_value VISUAL_PBX_PORTAL_URL)
health_url=$(config_value VISUAL_PBX_HEALTH_URL)
for url in "$portal_url" "$health_url"; do
  if [ "$TEST_MODE" = true ]; then
    [[ "$url" =~ ^https://127\.0\.0\.1:[0-9]+(/[A-Za-z0-9._/-]*)?$ ]] ||
      die 'Visual PBX test mode accepts loopback HTTPS URLs only'
  else
    [[ "$url" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]([/:][^@?]*)?$ ]] ||
      die 'enabled Visual PBX links must be credential-free HTTPS URLs without query strings'
  fi
done
[ "$CHECK_HEALTH" = true ] || die 'run with --check-health before publishing an enabled PBX link'
curl_args=(--fail --silent --show-error --max-time 10 --output /dev/null)
ca_file=$(config_value VISUAL_PBX_CA_FILE)
if [ -n "$ca_file" ]; then
  [ -f "$ca_file" ] || die 'configured Visual PBX CA file is missing'
  curl_args+=(--cacert "$ca_file")
fi
curl "${curl_args[@]}" "$health_url" ||
  die 'Visual PBX health endpoint did not pass'
printf 'visual-pbx-contract-check: enabled link is credential-free and its health endpoint passed\n'
