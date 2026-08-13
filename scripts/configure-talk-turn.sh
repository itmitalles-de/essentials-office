#!/usr/bin/env bash
# Configure Talk with the protected coturn shared secret.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
SECRET_FILE=${TURN_SECRET_FILE:-/etc/nextcloud/talk-turn.secret}
TURN_SERVER=${TURN_SERVER:-}

die() {
  printf 'configure-talk-turn: %s\n' "$*" >&2
  exit 1
}

occ() {
  docker compose exec -T -u www-data app php occ "$@"
}

if [ "${EUID}" -ne 0 ]; then
  exec sudo --preserve-env=TURN_SERVER,TURN_SECRET_FILE -- "$0" "$@"
fi
[ "$#" -eq 0 ] || die 'usage: configure-talk-turn.sh (set TURN_SERVER=host:port)'
[ -n "$TURN_SERVER" ] || die 'TURN_SERVER must be set to a bare host:port value'
[[ "$TURN_SERVER" =~ ^[A-Za-z0-9.-]+:[0-9]{1,5}$ ]] || die 'TURN_SERVER must be a bare host:port value'
[ -f "$SECRET_FILE" ] || die "missing TURN secret file: $SECRET_FILE"
[ "$(stat -c '%u:%a' "$SECRET_FILE")" = 0:600 ] || die "$SECRET_FILE must be root-owned with mode 0600"
IFS= read -r secret_format_check <"$SECRET_FILE"
[[ "$secret_format_check" =~ ^[[:xdigit:]]{64}$ ]] || die "$SECRET_FILE has an unexpected format"
unset secret_format_check

cd "$PROJECT_DIR"
compose=(docker compose -f compose.yaml -f compose.talk-turn.yaml --profile talk-turn)
"${compose[@]}" config -q
"${compose[@]}" ps --status running --services | grep -Fxq turn || die 'TURN service is not running'
occ app:list --output=json | grep -q '"spreed"' || die 'Talk is not installed'

"$SCRIPT_DIR/backup.sh"
TURN_SERVER="$TURN_SERVER" "${compose[@]}" exec -T -u root -e TURN_SERVER app php \
  <"$SCRIPT_DIR/configure-talk-turn.php"
printf 'configure-talk-turn: Talk now uses %s over UDP and TCP\n' "$TURN_SERVER"
