#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
WORK_DIR=$(mktemp -d /tmp/essentialsplus-external-contracts.XXXXXX)
SERVER_PID=

cleanup() {
  local status=$?
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  find "$WORK_DIR" -xdev -depth -delete
  exit "$status"
}
trap cleanup EXIT INT TERM

for command in jq openssl python3; do command -v "$command" >/dev/null 2>&1 || exit 1; done
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=127.0.0.1' \
  -addext 'subjectAltName=IP:127.0.0.1' -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" >/dev/null 2>&1
chmod 0600 "$WORK_DIR/key.pem"
FAKE_TLS_CERT="$WORK_DIR/cert.pem" FAKE_TLS_KEY="$WORK_DIR/key.pem" FAKE_TLS_PORT_FILE="$WORK_DIR/ports.json" \
  python3 "$PROJECT_DIR/tests/fakes/tls_services.py" &
SERVER_PID=$!
for _ in $(seq 1 50); do [ -f "$WORK_DIR/ports.json" ] && break; sleep 0.1; done
[ -f "$WORK_DIR/ports.json" ] || { printf 'external-contracts-test: fake TLS service did not start\n' >&2; exit 1; }
imap_port=$(jq -r .imap "$WORK_DIR/ports.json")
smtp_port=$(jq -r .smtp "$WORK_DIR/ports.json")
health_port=$(jq -r .health "$WORK_DIR/ports.json")
"$PROJECT_DIR/scripts/mail-healthcheck.sh" --host 127.0.0.1 --imap-port "$imap_port" --smtp-port "$smtp_port" \
  --ca-file "$WORK_DIR/cert.pem" --test-mode

cp "$PROJECT_DIR/integrations/visual-pbx.env.example" "$WORK_DIR/calls.env"
sed -i \
  -e 's/^VISUAL_PBX_ENABLED=.*/VISUAL_PBX_ENABLED=true/' \
  -e "s|^VISUAL_PBX_PORTAL_URL=.*|VISUAL_PBX_PORTAL_URL=https://127.0.0.1:$health_port/|" \
  -e "s|^VISUAL_PBX_HEALTH_URL=.*|VISUAL_PBX_HEALTH_URL=https://127.0.0.1:$health_port/health|" \
  -e "s|^VISUAL_PBX_CA_FILE=.*|VISUAL_PBX_CA_FILE=$WORK_DIR/cert.pem|" \
  "$WORK_DIR/calls.env"
cp "$PROJECT_DIR/.env.example" "$WORK_DIR/core.env"
sed -i -e 's/^POSTGRES_PASSWORD=$/POSTGRES_PASSWORD=placeholder/' \
  -e 's/^NEXTCLOUD_ADMIN_PASSWORD=$/NEXTCLOUD_ADMIN_PASSWORD=placeholder/' \
  -e 's/^REDIS_PASSWORD=$/REDIS_PASSWORD=placeholder/' "$WORK_DIR/core.env"
VISUAL_PBX_CONFIG="$WORK_DIR/calls.env" NEXTCLOUD_ENV_FILE="$WORK_DIR/core.env" VISUAL_PBX_TEST_MODE=true \
  "$PROJECT_DIR/scripts/visual-pbx-contract-check.sh" --check-health

cp "$PROJECT_DIR/integrations/visual-pbx.env.example" "$WORK_DIR/calls-disabled.env"
VISUAL_PBX_CONFIG="$WORK_DIR/calls-disabled.env" NEXTCLOUD_ENV_FILE="$WORK_DIR/core.env" \
  "$PROJECT_DIR/scripts/visual-pbx-contract-check.sh"
printf 'external-contracts-test: synthetic IMAP/SMTP and Essentials+ Calls health contracts passed; Calls remains disabled by default\n'
