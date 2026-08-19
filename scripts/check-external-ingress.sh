#!/usr/bin/env bash
# Check public DNS, TCP, TLS, HTTP, and DAV from the network that runs this script.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
HOSTNAME_TO_CHECK=${1:-}
IP_STRATEGY=${2:-}
CERTIFICATE_NAME=${3:-}
OUTPUT_DIR=${4:-"$PROJECT_DIR/reports/external-ingress-$STAMP"}
SOURCE_NETWORK=${INGRESS_SOURCE_NETWORK:-unknown}
WORK_DIR=

die() {
  printf 'check-external-ingress: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local status=$?
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/essentials-office-ingress.* ]]; then
    find "$WORK_DIR" -xdev -depth -delete
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

usage='usage: check-external-ingress.sh HOSTNAME (ipv4-only|ipv6-only|dual-stack|either|offline) CERTIFICATE_NAME [EMPTY_OUTPUT_DIRECTORY]'
[ "$#" -ge 3 ] && [ "$#" -le 4 ] || die "$usage"
for value in "$HOSTNAME_TO_CHECK" "$CERTIFICATE_NAME"; do
  [[ "$value" =~ ^[A-Za-z0-9.-]+$ ]] || die 'hostnames may contain only letters, digits, dots, and hyphens'
done
case "$IP_STRATEGY" in
  ipv4-only|ipv6-only|dual-stack|either|offline) ;;
  *) die "$usage" ;;
esac
for command in awk curl date dig find git head install jq mktemp mv openssl python3 sed sha256sum sort timeout; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

tool_commit=unknown
tool_dirty=null
if git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" \
  rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tool_commit=$(git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" rev-parse HEAD)
  if [ -z "$(git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" status --porcelain)" ]; then
    tool_dirty=false
  else
    tool_dirty=true
  fi
fi

case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$PWD/$OUTPUT_DIR" ;;
esac
[ "$OUTPUT_DIR" != / ] || die 'output directory must not be the filesystem root'
if [ -e "$OUTPUT_DIR" ]; then
  [ -d "$OUTPUT_DIR" ] || die "output path is not a directory: $OUTPUT_DIR"
  [ -z "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit)" ] || die "output directory must be empty: $OUTPUT_DIR"
else
  install -d -m 0700 "$OUTPUT_DIR"
fi
WORK_DIR=$(mktemp -d /tmp/essentials-office-ingress.XXXXXX)
chmod 0700 "$WORK_DIR"
head -c 1024 /dev/zero >"$WORK_DIR/request-body.bin"

filter_ip_family() {
  local version=$1
  python3 -c '
import ipaddress
import sys

version = int(sys.argv[1])
for raw in sys.stdin:
    candidate = raw.strip()
    try:
        address = ipaddress.ip_address(candidate)
    except ValueError:
        continue
    if address.version == version:
        print(address.compressed)
' "$version"
}

mapfile -t a_records < <(dig +time=5 +tries=1 +short A "$HOSTNAME_TO_CHECK" \
  | filter_ip_family 4 | sort -u)
mapfile -t aaaa_records < <(dig +time=5 +tries=1 +short AAAA "$HOSTNAME_TO_CHECK" \
  | filter_ip_family 6 | sort -u)
printf '%s\n' "${a_records[@]}" | jq -R -s 'split("\n") | map(select(length > 0))' >"$WORK_DIR/a.json"
printf '%s\n' "${aaaa_records[@]}" | jq -R -s 'split("\n") | map(select(length > 0))' >"$WORK_DIR/aaaa.json"

check_family() {
  local family=$1 curl_family=$2 address=$3 connect_address tls_ok=false tls_expiry='' tls_days=null
  local resolve_address=$address resolve_http resolve_https
  local http_code=000 https_code=000 redirect_code=000 redirect_target='' status_code=000 status_installed=false
  local webdav_code=000 carddav_code=000 carddav_target='' caldav_code=000 caldav_target='' body_code=000
  local tcp80=false tcp443=false http_redirect=false webdav_ok=false carddav_ok=false caldav_ok=false body_safe=false
  if [ "$family" = ipv6 ]; then
    connect_address="[$address]:443"
    resolve_address="[$address]"
  else
    connect_address="$address:443"
  fi
  resolve_http="$HOSTNAME_TO_CHECK:80:$resolve_address"
  resolve_https="$HOSTNAME_TO_CHECK:443:$resolve_address"

  http_code=$(curl "$curl_family" --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --resolve "$resolve_http" --connect-timeout 5 --max-time 12 \
    "http://$HOSTNAME_TO_CHECK/" 2>/dev/null || true)
  [ "$http_code" != 000 ] && tcp80=true
  https_code=$(curl "$curl_family" --insecure --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --resolve "$resolve_https" --connect-timeout 5 --max-time 12 \
    "https://$HOSTNAME_TO_CHECK/" 2>/dev/null || true)
  [ "$https_code" != 000 ] && tcp443=true

  redirect_code=$(curl "$curl_family" --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --resolve "$resolve_http" --connect-timeout 5 --max-time 12 \
    "http://$HOSTNAME_TO_CHECK/" 2>/dev/null || true)
  redirect_target=$(curl "$curl_family" --silent --show-error --head --resolve "$resolve_http" \
    --connect-timeout 5 --max-time 12 \
    "http://$HOSTNAME_TO_CHECK/" 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /^location:/ {sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' || true)
  case "$redirect_code" in
    301|302|307|308)
      { [ "$redirect_target" = "https://$HOSTNAME_TO_CHECK" ] \
        || [[ "$redirect_target" == https://"$HOSTNAME_TO_CHECK"/* ]]; } && http_redirect=true
      ;;
  esac

  if timeout 15 openssl s_client -connect "$connect_address" -servername "$CERTIFICATE_NAME" \
    -verify_hostname "$CERTIFICATE_NAME" -verify_return_error </dev/null \
    >"$WORK_DIR/tls-$family.pem" 2>"$WORK_DIR/tls-$family.error"; then
    if openssl x509 -in "$WORK_DIR/tls-$family.pem" -noout -checkhost "$CERTIFICATE_NAME" >/dev/null 2>&1; then
      tls_ok=true
      tls_expiry=$(openssl x509 -in "$WORK_DIR/tls-$family.pem" -noout -enddate | sed 's/^notAfter=//')
      if expiry_epoch=$(date -u -d "$tls_expiry" +%s 2>/dev/null); then
        now_epoch=$(date -u +%s)
        tls_days=$(( (expiry_epoch - now_epoch) / 86400 ))
      fi
    fi
  fi

  status_code=$(curl "$curl_family" --silent --show-error --output "$WORK_DIR/status-$family.json" \
    --write-out '%{http_code}' --resolve "$resolve_https" --connect-timeout 5 --max-time 12 \
    "https://$HOSTNAME_TO_CHECK/status.php" 2>/dev/null || true)
  if [ "$status_code" = 200 ] && jq -e '.installed == true' "$WORK_DIR/status-$family.json" >/dev/null 2>&1; then
    status_installed=true
  fi

  webdav_code=$(curl "$curl_family" --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --request OPTIONS --resolve "$resolve_https" --connect-timeout 5 --max-time 12 \
    "https://$HOSTNAME_TO_CHECK/remote.php/dav/" 2>/dev/null || true)
  case "$webdav_code" in 200|207|401|405) webdav_ok=true ;; esac

  carddav_code=$(curl "$curl_family" --silent --show-error --head --output "$WORK_DIR/carddav-$family.headers" \
    --write-out '%{http_code}' --resolve "$resolve_https" --connect-timeout 5 --max-time 12 \
    "https://$HOSTNAME_TO_CHECK/.well-known/carddav" 2>/dev/null || true)
  carddav_target=$(awk 'BEGIN{IGNORECASE=1} /^location:/ {sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' \
    "$WORK_DIR/carddav-$family.headers" 2>/dev/null || true)
  [ "$carddav_code" = 301 ] && [[ "$carddav_target" == */remote.php/dav/ ]] && carddav_ok=true

  caldav_code=$(curl "$curl_family" --silent --show-error --head --output "$WORK_DIR/caldav-$family.headers" \
    --write-out '%{http_code}' --resolve "$resolve_https" --connect-timeout 5 --max-time 12 \
    "https://$HOSTNAME_TO_CHECK/.well-known/caldav" 2>/dev/null || true)
  caldav_target=$(awk 'BEGIN{IGNORECASE=1} /^location:/ {sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' \
    "$WORK_DIR/caldav-$family.headers" 2>/dev/null || true)
  [ "$caldav_code" = 301 ] && [[ "$caldav_target" == */remote.php/dav/ ]] && caldav_ok=true

  # This sends 1 KiB to an unauthenticated collection endpoint. A rejection
  # proves that the ingress accepts and safely rejects the body without creating
  # a user object. It does not prove the configured maximum authenticated upload.
  body_code=$(curl "$curl_family" --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --request POST --header 'Content-Type: application/octet-stream' \
    --data-binary "@$WORK_DIR/request-body.bin" --resolve "$resolve_https" \
    --connect-timeout 5 --max-time 12 \
    "https://$HOSTNAME_TO_CHECK/remote.php/dav/" 2>/dev/null || true)
  case "$body_code" in 401|403|404|405) body_safe=true ;; esac

  jq -n \
    --arg family "$family" --arg address "$address" \
    --argjson tcp80 "$tcp80" --argjson tcp443 "$tcp443" \
    --arg httpCode "$http_code" --arg httpsCode "$https_code" \
    --argjson tlsOk "$tls_ok" --arg tlsExpiry "$tls_expiry" --argjson tlsDays "$tls_days" \
    --arg redirectCode "$redirect_code" --arg redirectTarget "$redirect_target" --argjson redirectOk "$http_redirect" \
    --arg statusCode "$status_code" --argjson statusInstalled "$status_installed" \
    --arg webdavCode "$webdav_code" --argjson webdavOk "$webdav_ok" \
    --arg carddavCode "$carddav_code" --arg carddavTarget "$carddav_target" --argjson carddavOk "$carddav_ok" \
    --arg caldavCode "$caldav_code" --arg caldavTarget "$caldav_target" --argjson caldavOk "$caldav_ok" \
    --arg bodyCode "$body_code" --argjson bodySafe "$body_safe" \
    '{family: $family, address: $address,
      tcp: {port80: $tcp80, port443: $tcp443, httpCode: $httpCode, httpsCode: $httpsCode},
      tls: {chainAndNameValid: $tlsOk, expiresAt: (if $tlsExpiry == "" then null else $tlsExpiry end), daysRemaining: $tlsDays},
      httpRedirect: {ok: $redirectOk, code: $redirectCode, target: (if $redirectTarget == "" then null else $redirectTarget end)},
      nextcloudStatus: {ok: $statusInstalled, code: $statusCode},
      webdav: {ok: $webdavOk, code: $webdavCode},
      carddavRedirect: {ok: $carddavOk, code: $carddavCode, target: (if $carddavTarget == "" then null else $carddavTarget end)},
      caldavRedirect: {ok: $caldavOk, code: $caldavCode, target: (if $caldavTarget == "" then null else $caldavTarget end)},
      smallUnauthenticatedBody: {ok: $bodySafe, bytes: 1024, code: $bodyCode,
        boundary: "Does not prove authenticated maximum upload size."}}'
}

printf '[]\n' >"$WORK_DIR/families.json"
for address in "${a_records[@]}"; do
  [ -n "$address" ] || continue
  check_family ipv4 -4 "$address" >"$WORK_DIR/family.json"
  jq --slurpfile item "$WORK_DIR/family.json" '. + $item' "$WORK_DIR/families.json" >"$WORK_DIR/families.next.json"
  mv "$WORK_DIR/families.next.json" "$WORK_DIR/families.json"
done
for address in "${aaaa_records[@]}"; do
  [ -n "$address" ] || continue
  check_family ipv6 -6 "$address" >"$WORK_DIR/family.json"
  jq --slurpfile item "$WORK_DIR/family.json" '. + $item' "$WORK_DIR/families.json" >"$WORK_DIR/families.next.json"
  mv "$WORK_DIR/families.next.json" "$WORK_DIR/families.json"
done

has_v4=false
has_v6=false
[ "${#a_records[@]}" -gt 0 ] && has_v4=true
[ "${#aaaa_records[@]}" -gt 0 ] && has_v6=true
network_expectation=false
case "$IP_STRATEGY" in
  ipv4-only) [ "$has_v4" = true ] && [ "$has_v6" = false ] && network_expectation=true ;;
  ipv6-only) [ "$has_v4" = false ] && [ "$has_v6" = true ] && network_expectation=true ;;
  dual-stack) [ "$has_v4" = true ] && [ "$has_v6" = true ] && network_expectation=true ;;
  either) { [ "$has_v4" = true ] || [ "$has_v6" = true ]; } && network_expectation=true ;;
  offline) [ "$has_v4" = false ] && [ "$has_v6" = false ] && network_expectation=true ;;
esac

family_checks=false
if [ "$IP_STRATEGY" = offline ]; then
  family_checks=true
elif jq -e 'length > 0 and all(.[];
  .tcp.port80 and .tcp.port443 and .tls.chainAndNameValid and .httpRedirect.ok and
  .nextcloudStatus.ok and .webdav.ok and .carddavRedirect.ok and .caldavRedirect.ok and
  .smallUnauthenticatedBody.ok)' "$WORK_DIR/families.json" >/dev/null; then
  family_checks=true
fi

result=fail
if [ "$network_expectation" = true ] && [ "$family_checks" = true ]; then
  if [ "$IP_STRATEGY" = offline ]; then
    result=intentionally-not-live
  else
    result=pass
  fi
fi

jq -n \
  --arg schemaVersion 1.0.0 --arg observedAtUtc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sourceNetwork "$SOURCE_NETWORK" --arg hostname "$HOSTNAME_TO_CHECK" \
  --arg strategy "$IP_STRATEGY" --arg certificateName "$CERTIFICATE_NAME" \
  --arg result "$result" --arg toolCommit "$tool_commit" --argjson toolDirty "$tool_dirty" \
  --argjson strategyMatched "$network_expectation" \
  --slurpfile a "$WORK_DIR/a.json" --slurpfile aaaa "$WORK_DIR/aaaa.json" \
  --slurpfile families "$WORK_DIR/families.json" \
  '{schemaVersion: $schemaVersion, observedAtUtc: $observedAtUtc,
    observedFrom: $sourceNetwork, hostname: $hostname, expectedIpStrategy: $strategy,
    expectedCertificateName: $certificateName, result: $result,
    toolRepository: {commit: $toolCommit, dirty: $toolDirty},
    dns: {a: $a[0], aaaa: $aaaa[0], strategyMatched: $strategyMatched},
    families: $families[0],
    uploadAcceptance: {authenticatedMaximum: null,
      reason: "No approved test credentials were supplied; only a non-persisting 1 KiB unauthenticated rejection was tested."}}' \
  >"$OUTPUT_DIR/external-ingress.json"

python3 - "$OUTPUT_DIR/external-ingress.json" "$OUTPUT_DIR/external-ingress.md" <<'PY'
import json
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
report = json.loads(source.read_text(encoding="utf-8"))
lines = [
    "# Essentials+ Office external ingress",
    "",
    f"- Observed (UTC): `{report['observedAtUtc']}`",
    f"- Observed from: `{report['observedFrom']}`",
    f"- Hostname: `{report['hostname']}`",
    f"- Expected strategy: `{report['expectedIpStrategy']}`",
    f"- Tool repository: `{report['toolRepository']['commit']}`, dirty=`{str(report['toolRepository']['dirty']).lower()}`",
    f"- Result: **{report['result']}**",
    f"- A records: `{len(report['dns']['a'])}`; AAAA records: `{len(report['dns']['aaaa'])}`",
    "",
    "| Family | TCP 80 | TCP 443 | TLS/name | Redirect | status.php | WebDAV | CardDAV | CalDAV | 1 KiB safe rejection |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
]
for family in report["families"]:
    lines.append(
        f"| {family['family']} | {family['tcp']['port80']} | {family['tcp']['port443']} | "
        f"{family['tls']['chainAndNameValid']} | {family['httpRedirect']['ok']} | "
        f"{family['nextcloudStatus']['ok']} | {family['webdav']['ok']} | "
        f"{family['carddavRedirect']['ok']} | {family['caldavRedirect']['ok']} | "
        f"{family['smallUnauthenticatedBody']['ok']} |"
    )
lines.extend([
    "",
    "Authenticated maximum upload size remains unknown because this read-only public check receives no credentials.",
    "The source-network label must be reviewed; a LAN or NAT-hairpin run is not external evidence.",
    "",
])
target.write_text("\n".join(lines), encoding="utf-8")
PY

(
  cd "$OUTPUT_DIR"
  sha256sum external-ingress.json external-ingress.md >external-ingress.sha256
)
chmod 0600 "$OUTPUT_DIR"/external-ingress.json "$OUTPUT_DIR"/external-ingress.md "$OUTPUT_DIR"/external-ingress.sha256
printf 'check-external-ingress: wrote %s (result=%s)\n' "$OUTPUT_DIR" "$result"
[ "$result" != fail ]
