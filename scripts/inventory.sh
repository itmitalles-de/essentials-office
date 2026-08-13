#!/usr/bin/env bash
# Produce a secret-free, read-only deployment inventory in Markdown.
# shellcheck disable=SC2016 # Backticks and inner template strings are intentional.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
CADDY_PROJECT_DIR=${CADDY_PROJECT_DIR:-/opt/caddy}
OUTPUT_FILE=${1:-}
WORK_DIR=
CADDY_COMPOSE_FILE=

die() {
  printf 'inventory: %s\n' "$*" >&2
  exit 1
}

env_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROJECT_DIR/.env"
}

occ() {
  docker compose exec -T -u www-data app php occ "$@"
}

cleanup() {
  local status=$?
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/nextcloud-inventory.* ]]; then
    rm -rf -- "$WORK_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

for command in docker git jq; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$PROJECT_DIR/.env" ] || die 'missing .env; run this on the deployed host'
cd "$PROJECT_DIR"
docker compose config -q
WORK_DIR=$(mktemp -d /tmp/nextcloud-inventory.XXXXXX)
report="$WORK_DIR/report.md"

generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
commit=$(git rev-parse HEAD)
branch=$(git branch --show-current)
if [ -z "$(git status --porcelain)" ]; then
  worktree=clean
else
  worktree=dirty
fi
proxy_network=$(docker compose config --format json | jq -r '.networks.proxy_net.name')
proxy_cidr=$(docker network inspect "$proxy_network" --format '{{range .IPAM.Config}}{{.Subnet}}{{" "}}{{end}}' | awk '{print $1}')
occ_status=$(occ status --output=json)
data_root=$(env_value NEXTCLOUD_DATA_ROOT)
[ -n "$data_root" ] || die 'NEXTCLOUD_DATA_ROOT is empty in .env'

caddy_drift=not-checked
for candidate in compose.yaml docker-compose.yml docker-compose.yaml; do
  if [ -f "$CADDY_PROJECT_DIR/$candidate" ]; then
    CADDY_COMPOSE_FILE="$CADDY_PROJECT_DIR/$candidate"
    break
  fi
done
if [ -n "$CADDY_COMPOSE_FILE" ]; then
  if docker compose -f "$CADDY_COMPOSE_FILE" exec -T caddy \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
    caddy_drift=runtime-unavailable
    if docker compose -f "$CADDY_COMPOSE_FILE" exec -T caddy \
      caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile \
      >"$WORK_DIR/caddy-disk.json" 2>/dev/null \
      && docker compose -f "$CADDY_COMPOSE_FILE" exec -T caddy \
        wget -qO- http://127.0.0.1:2019/config/ >"$WORK_DIR/caddy-runtime.json" 2>/dev/null; then
      jq --sort-keys --compact-output . "$WORK_DIR/caddy-disk.json" >"$WORK_DIR/caddy-disk.canonical"
      jq --sort-keys --compact-output . "$WORK_DIR/caddy-runtime.json" >"$WORK_DIR/caddy-runtime.canonical"
      if cmp --silent "$WORK_DIR/caddy-disk.canonical" "$WORK_DIR/caddy-runtime.canonical"; then
        caddy_drift=match
      else
        caddy_drift=different
      fi
    fi
  else
    caddy_drift=invalid-on-disk
  fi
fi

{
  printf '# NUC deployment inventory\n\n'
  printf -- '- Generated (UTC): `%s`\n' "$generated_at"
  printf -- '- Host: `%s`\n' "$(hostname)"
  printf -- '- Kernel: `%s`\n' "$(uname -srmo)"
  printf -- '- Repository: branch `%s`, commit `%s`, worktree `%s`\n' "$branch" "$commit" "$worktree"
  printf -- '- Compose: valid\n'
  printf -- '- Proxy network: `%s` (`%s`)\n' "$proxy_network" "$proxy_cidr"
  printf -- '- Caddy disk/runtime comparison: `%s`\n\n' "$caddy_drift"
  printf '## Capacity\n\n```text\n'
  free -h
  df -h "$data_root"
  printf '```\n\n## Nextcloud status\n\n```json\n'
  printf '%s\n' "$occ_status" | jq .
  printf '```\n\n## Containers\n\n```text\n'
  docker compose ps
  docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \
    nextcloud-app nextcloud-cron nextcloud-db nextcloud-redis
  printf '```\n\n## Declared app versions\n\n```text\n'
  app_state=$(occ app:list --output=json)
  while IFS= read -r app; do
    version=$(printf '%s\n' "$app_state" | jq -r --arg app "$app" '.enabled[$app] // .disabled[$app] // "missing"')
    enabled=$(printf '%s\n' "$app_state" | jq -r --arg app "$app" '.enabled[$app] != null')
    printf '%s\t%s\tenabled=%s\n' "$app" "$version" "$enabled"
  done < <(sed -E '/^[[:space:]]*(#|$)/d; s/[[:space:]]+$//' config/nextcloud-apps.txt)
  printf '```\n\n## Backup state\n\n'
  backup_count=$(find "$data_root/backups" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | wc -l)
  latest_backup=$(find "$data_root/backups" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | sort | tail -n 1)
  printf -- '- Local backup directories: `%s`\n' "$backup_count"
  printf -- '- Latest local backup (UTC timestamp): `%s`\n' "${latest_backup:-none}"
  printf '\n## Exposure checks\n\n```text\n'
  printf 'db published ports: %s\n' "$(docker port "$(docker compose ps -q db)" 2>/dev/null || true)"
  printf 'redis published ports: %s\n' "$(docker port "$(docker compose ps -q redis)" 2>/dev/null || true)"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk 'NR == 1 || /:(25|80|443|3478|5349|9980)([[:space:]]|$)/'
  fi
  printf '```\n'
} >"$report"

if [ -n "$OUTPUT_FILE" ]; then
  install -D -m 0600 "$report" "$OUTPUT_FILE"
  printf 'inventory: wrote %s\n' "$OUTPUT_FILE"
else
  cat "$report"
fi
