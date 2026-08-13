#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
WORK_DIR=$(mktemp -d /tmp/essentialsplus-turn-test.XXXXXX)
PROJECT_NAME="essentialsplus-turn-test-${RANDOM}"
COMPOSE_FILE="$PROJECT_DIR/tests/talk/compose.yaml"

compose() {
  TURN_RUNTIME_GID="$(id -g)" TURN_TEST_CONFIG="$WORK_DIR/turnserver.conf" docker compose --project-name "$PROJECT_NAME" -f "$COMPOSE_FILE" "$@"
}

cleanup() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    compose logs --no-color turn >&2 || true
  fi
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  find "$WORK_DIR" -xdev -depth -delete
  exit "$status"
}
trap cleanup EXIT INT TERM

write_config() {
  local secret_file=$1 secret
  secret=$(<"$secret_file")
  umask 077
  {
    printf '%s\n' 'listening-port=3478' 'fingerprint' 'use-auth-secret'
    printf 'static-auth-secret=%s\n' "$secret"
    printf '%s\n' 'realm=turn.test.invalid' 'min-port=49160' 'max-port=49170' 'no-cli' 'no-tls' 'no-dtls' 'log-file=stdout'
  } >"$WORK_DIR/turnserver.conf"
  chmod 0640 "$WORK_DIR/turnserver.conf"
  unset secret
}

run_client() {
  local secret_file=$1
  docker run --rm --network "$PROJECT_NAME"_turn_test \
    --env TURN_HOST=turn --env TURN_SECRET_FILE=/run/secrets/turn \
    --volume "$secret_file:/run/secrets/turn:ro" \
    --volume "$PROJECT_DIR/tests/fakes/turn_client.py:/test.py:ro" \
    python:3.13-alpine python /test.py
}

for command in docker find openssl; do command -v "$command" >/dev/null 2>&1 || exit 1; done
openssl rand -hex 32 >"$WORK_DIR/secret.old"
openssl rand -hex 32 >"$WORK_DIR/secret.new"
chmod 0600 "$WORK_DIR"/secret.*
write_config "$WORK_DIR/secret.old"
compose up -d --wait
run_client "$WORK_DIR/secret.old"
write_config "$WORK_DIR/secret.new"
compose up -d --force-recreate --wait
if run_client "$WORK_DIR/secret.old" >/dev/null 2>&1; then
  printf 'talk-turn-test: rotated-out TURN credential still worked\n' >&2
  exit 1
fi
run_client "$WORK_DIR/secret.new"
printf 'talk-turn-test: isolated health, authenticated connectivity, and secret rotation passed without host ports\n'
