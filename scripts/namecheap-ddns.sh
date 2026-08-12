#!/usr/bin/env bash
set -Eeuo pipefail

readonly ddns_host="cloud"
readonly ddns_domain="itmitalles.de"
readonly ddns_endpoint="https://dynamicdns.park-your-domain.com/update"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required"

ddns_password="${NAMECHEAP_DDNS_PASSWORD:-}"
[[ -n "$ddns_password" ]] || fail "NAMECHEAP_DDNS_PASSWORD is not set"

# Namecheap currently issues an alphanumeric per-domain Dynamic DNS password.
# Reject other input so it cannot alter the curl configuration supplied on stdin.
[[ "$ddns_password" =~ ^[[:alnum:]]{8,128}$ ]] ||
    fail "NAMECHEAP_DDNS_PASSWORD has an unexpected format"

request_url="${ddns_endpoint}?host=${ddns_host}&domain=${ddns_domain}&password=${ddns_password}"

# Keep the password out of curl's command line and therefore out of process lists.
# Omitting the optional IP parameter makes Namecheap use the request's public IPv4.
response="$({ printf 'url = "%s"\n' "$request_url"; } | curl \
    --config - \
    --silent \
    --show-error \
    --fail \
    --proto '=https' \
    --tlsv1.2 \
    --noproxy '*' \
    --connect-timeout 10 \
    --max-time 30 \
    --retry 2 \
    --retry-all-errors)" || fail "Namecheap Dynamic DNS request failed"

unset ddns_password request_url

if [[ "${response,,}" != *'<errcount>0'* ]]; then
    fail "Namecheap rejected the Dynamic DNS update"
fi

unset response
printf 'Namecheap Dynamic DNS update succeeded for %s.%s.\n' "$ddns_host" "$ddns_domain"
