#!/usr/bin/env bash
# Point Nextcloud Office at the dedicated Collabora service after reachability checks.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
PUBLIC_HOST=${COLLABORA_PUBLIC_HOST:-office.itmitalles.de}
WOPI_ALLOWLIST=${COLLABORA_WOPI_ALLOWLIST:-}

die() {
  printf 'configure-office: %s\n' "$*" >&2
  exit 1
}

occ() {
  docker compose exec -T -u www-data app php occ "$@"
}

for command in curl docker grep; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$PROJECT_DIR/.env" ] || die 'missing .env; run bootstrap.sh first'
[ -n "$WOPI_ALLOWLIST" ] || die 'COLLABORA_WOPI_ALLOWLIST must explicitly name the Collabora source IP or CIDR'
[[ "$WOPI_ALLOWLIST" =~ ^[0-9A-Fa-f:.,/\ |]+$ ]] || die 'COLLABORA_WOPI_ALLOWLIST has an invalid format'

cd "$PROJECT_DIR"
compose=(docker compose -f compose.yaml -f compose.collabora.yaml --profile office)
"${compose[@]}" config -q
"${compose[@]}" ps --status running --services | grep -Fxq collabora || die 'Collabora is not running'
curl --fail --silent --show-error --max-time 20 \
  "https://$PUBLIC_HOST/hosting/discovery" >/dev/null || die 'public Collabora discovery endpoint is unavailable'
docker compose exec -T app php -r \
  '$body = @file_get_contents("http://collabora:9980/hosting/discovery"); exit($body === false ? 1 : 0);' || \
  die 'Nextcloud cannot reach Collabora over proxy_net'
occ app:list --output=json | grep -q '"richdocuments"' || die 'Nextcloud Office is not installed'

"$SCRIPT_DIR/backup.sh"
occ config:app:set richdocuments wopi_url --value="https://$PUBLIC_HOST"
occ config:app:set richdocuments wopi_allowlist --value="$WOPI_ALLOWLIST"
occ richdocuments:activate-config

configured_url=$(occ config:app:get richdocuments wopi_url)
configured_allowlist=$(occ config:app:get richdocuments wopi_allowlist)
[ "$configured_url" = "https://$PUBLIC_HOST" ] || die 'stored Collabora URL differs from the requested URL'
[ "$configured_allowlist" = "$WOPI_ALLOWLIST" ] || die 'stored WOPI allowlist differs from the requested value'
printf 'configure-office: dedicated Collabora URL and WOPI allowlist configured\n'
