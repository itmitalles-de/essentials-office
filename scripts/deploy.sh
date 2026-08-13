#!/usr/bin/env bash
# Idempotently bootstrap, start, and validate the repository-declared stack.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
DEPLOY_APPS=false
TIMEOUT_SECONDS=${DEPLOY_TIMEOUT_SECONDS:-600}

die() {
  printf 'deploy: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'usage: deploy.sh [--apps]\n' >&2
  exit 2
}

case "${1:-}" in
  '') ;;
  --apps) DEPLOY_APPS=true ;;
  *) usage ;;
esac
[ "$#" -le 1 ] || usage

for command in date docker grep sleep; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
case "$TIMEOUT_SECONDS" in
  ''|*[!0-9]*) die 'DEPLOY_TIMEOUT_SECONDS must be a positive integer' ;;
esac
[ "$TIMEOUT_SECONDS" -gt 0 ] || die 'DEPLOY_TIMEOUT_SECONDS must be greater than zero'

cd "$PROJECT_DIR"
"$SCRIPT_DIR/bootstrap.sh"
docker compose config -q
docker compose up -d

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while :; do
  all_ready=true
  for service in db redis app; do
    container_id=$(docker compose ps -q "$service")
    if [ -z "$container_id" ]; then
      all_ready=false
      continue
    fi
    state=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id")
    case "$state" in
      'running healthy') ;;
      'exited '*|'dead '*)
        docker compose ps >&2
        die "$service stopped before becoming healthy"
        ;;
      *) all_ready=false ;;
    esac
  done
  docker compose ps --status running --services | grep -Fxq cron || all_ready=false
  [ "$all_ready" = false ] || break
  [ "$(date +%s)" -lt "$deadline" ] || {
    docker compose ps >&2
    die "core did not become healthy within $TIMEOUT_SECONDS seconds"
  }
  sleep 5
done

docker compose exec -T -u www-data app php occ background:cron >/dev/null
"$SCRIPT_DIR/healthcheck.sh" --core-only

if [ "$DEPLOY_APPS" = true ]; then
  "$SCRIPT_DIR/reconcile-apps.sh"
  "$SCRIPT_DIR/healthcheck.sh" --core-only
fi

printf 'deploy: repository state applied and core health verified (apps=%s)\n' "$DEPLOY_APPS"
