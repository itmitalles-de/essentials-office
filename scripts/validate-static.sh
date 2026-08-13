#!/usr/bin/env bash
# Run repository-only checks without touching a deployed host.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
CADDY_IMAGE='caddy:2.10.2-alpine@sha256:d8c17a862962def15cde69863a3a463f25a2664942eafd7bdbf050e9c3116b83'
SHELLCHECK_IMAGE='koalaman/shellcheck-alpine:v0.11.0@sha256:9955be09ea7f0dbf7ae942ac1f2094355bb30d96fffba0ec09f5432207544002'

die() {
  printf 'validate-static: %s\n' "$*" >&2
  exit 1
}

for command in bash docker find jq node python3 rg; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required'
python3 -c 'import jsonschema' >/dev/null 2>&1 || die 'Python jsonschema is required'

cd "$PROJECT_DIR"

# Values exist only in this process and are intentionally non-secret fixtures.
export POSTGRES_PASSWORD=compose-validation-placeholder
export POSTGRES_DB=nextcloud
export POSTGRES_USER=nextcloud
export NEXTCLOUD_ADMIN_PASSWORD=compose-validation-placeholder
export NEXTCLOUD_ADMIN_USER=ncadmin
export REDIS_PASSWORD=compose-validation-placeholder
export NEXTCLOUD_TRUSTED_DOMAINS=cloud.itmitalles.de
export TRUSTED_PROXIES=172.18.0.0/16
export PROXY_NETWORK=proxy_net
export COLLABORA_WOPI_HOST=cloud\.itmitalles\.de
export TURN_REALM=turn.invalid
export TURN_EXTERNAL_IP=192.0.2.10
export TURN_SECRET_FILE="$PROJECT_DIR/secrets/example-not-present"
export TURN_RUNTIME_GID=65534
export TURN_TEST_CONFIG="$PROJECT_DIR/config/turnserver.conf.example"
export RESTORE_ROOT=/tmp/nextcloud-restore-validation
export VAULTWARDEN_ENV_FILE="$PROJECT_DIR/vaultwarden.env.example"
export VAULTWARDEN_DATA_DIR=/tmp/vaultwarden-validation-data
export VAULTWARDEN_BROWSER_PORT=18080
export VAULTWARDEN_TEST_CADDYFILE="$PROJECT_DIR/tests/vaultwarden/Caddyfile"

docker compose -f compose.yaml config -q
docker compose -f compose.yaml -f compose.collabora.yaml --profile office config -q
docker compose -f compose.yaml -f compose.talk-turn.yaml --profile talk-turn config -q
docker compose -f compose.yaml -f compose.vaultwarden.yaml --profile vaultwarden config -q
docker compose -f compose.yaml -f compose.vaultwarden.yaml -f tests/vaultwarden/compose.browser.yaml --profile vaultwarden config -q
docker compose -f compose.yaml -f tests/deploy/compose.browser.yaml config -q
docker compose -f tests/restore/compose.yaml config -q
docker compose -f tests/talk/compose.yaml config -q

mapfile -d '' shell_scripts < <(find scripts tests -type f -name '*.sh' -print0 | sort -z)
[ "${#shell_scripts[@]}" -gt 0 ] || die 'no shell scripts found'
for script in "${shell_scripts[@]}"; do bash -n "$script"; done
docker run --rm --network none --entrypoint sh -v "$PROJECT_DIR:/repo:ro" \
  "$SHELLCHECK_IMAGE" \
  -ec 'find /repo/scripts /repo/tests -type f -name "*.sh" -print0 | xargs -0 shellcheck -x'

python3 - <<'PY'
import pathlib
for source in pathlib.Path("tests").rglob("*.py"):
    compile(source.read_text(encoding="utf-8"), str(source), "exec")
PY
mapfile -d '' javascript_files < <(find nextcloud-apps tests -type f -name '*.js' -print0 | sort -z)
for javascript_file in "${javascript_files[@]}"; do node --check "$javascript_file"; done

while IFS= read -r -d '' json_file; do jq empty "$json_file"; done < <(find . -path './.git' -prune -o -type f -name '*.json' -print0)
python3 - <<'PY'
import pathlib
import xml.etree.ElementTree as ET
for source in pathlib.Path("nextcloud-apps").rglob("*.xml"):
    ET.parse(source)
PY
docker run --rm --network none -v "$PROJECT_DIR/nextcloud-apps/essentialsplus:/app:ro" nextcloud:34-apache \
  sh -ec 'find /app -type f -name "*.php" -print0 | xargs -0 -n1 php -l >/dev/null'

for caddy_file in Caddyfile.example Caddyfile.vaultwarden.example caddy/office.Caddyfile.example tests/vaultwarden/Caddyfile; do
  docker run --rm --network none --read-only --tmpfs /tmp:size=16m --tmpfs /data:size=16m --tmpfs /config:size=4m \
    -v "$PROJECT_DIR/$caddy_file:/etc/caddy/Caddyfile:ro" "$CADDY_IMAGE" \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1
done

if rg -n '(^|[;&|[:space:]])eval[[:space:]]' scripts tests; then
  die 'eval is forbidden in repository automation'
fi
if rg -n -- '--(password|secret|token)="?\$|redis-cli[^\n]*[[:space:]]-a[[:space:]]|compose exec[^\n]*-e[[:space:]]+[^[:space:]]+=(\$|"\$)' scripts tests; then
  die 'a secret-like value may be exposed through process arguments'
fi

"$PROJECT_DIR/tests/office-modules-contract.sh"
"$PROJECT_DIR/tests/update-policy.sh"
printf 'validate-static: Compose, schema, Caddy, PHP, Python, JS, ShellCheck, and security checks passed\n'
