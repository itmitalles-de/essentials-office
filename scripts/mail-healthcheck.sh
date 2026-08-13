#!/usr/bin/env bash
# Check configured IMAPS and TLS SMTP endpoints without authenticating or sending mail.
set -Eeuo pipefail

HOST=
IMAP_PORT=993
SMTP_PORT=465
CA_FILE=
TEST_MODE=false

die() {
  printf 'mail-healthcheck: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) [ "$#" -ge 2 ] || die '--host requires a value'; HOST=$2; shift 2 ;;
    --imap-port) [ "$#" -ge 2 ] || die '--imap-port requires a value'; IMAP_PORT=$2; shift 2 ;;
    --smtp-port) [ "$#" -ge 2 ] || die '--smtp-port requires a value'; SMTP_PORT=$2; shift 2 ;;
    --ca-file) [ "$#" -ge 2 ] || die '--ca-file requires a value'; CA_FILE=$2; shift 2 ;;
    --test-mode) TEST_MODE=true; shift ;;
    *) die 'usage: mail-healthcheck.sh --host HOST [--imap-port PORT] [--smtp-port PORT] [--ca-file FILE] [--test-mode]' ;;
  esac
done
for command in head openssl timeout; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -n "$HOST" ] || die '--host is required'
[[ "$IMAP_PORT" =~ ^[0-9]+$ ]] && [[ "$SMTP_PORT" =~ ^[0-9]+$ ]] || die 'ports must be numeric'
if [ "$TEST_MODE" = true ]; then
  case "$HOST" in 127.0.0.1|::1) ;; *) die 'test mode accepts loopback only' ;; esac
  [ -f "$CA_FILE" ] || die 'test mode requires an explicit CA file'
fi

openssl_args=(-quiet -verify_return_error -verify_hostname "$HOST")
if [ -n "$CA_FILE" ]; then
  [ -f "$CA_FILE" ] || die "CA file does not exist: $CA_FILE"
  openssl_args+=(-CAfile "$CA_FILE")
fi
imap_greeting=$(timeout 10 openssl s_client "${openssl_args[@]}" -connect "$HOST:$IMAP_PORT" </dev/null 2>/dev/null | head -n 1 || true)
smtp_greeting=$(timeout 10 openssl s_client "${openssl_args[@]}" -connect "$HOST:$SMTP_PORT" </dev/null 2>/dev/null | head -n 1 || true)
[[ "$imap_greeting" == \*\ OK* ]] || die 'IMAPS TLS/greeting check failed'
[[ "$smtp_greeting" == 220* ]] || die 'SMTP TLS/greeting check failed'
printf 'mail-healthcheck: IMAPS and SMTP TLS endpoints passed without credentials or mail delivery\n'
