#!/usr/bin/env bash
# Validate the public mail DNS records after mailcow generated its DKIM key.
set -Eeuo pipefail

die() {
  printf 'check-mail-dns: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 3 ] || die 'usage: check-mail-dns.sh MAIL_HOSTNAME MAIL_DOMAIN DKIM_SELECTOR'
mail_hostname=${1%.}
mail_domain=${2%.}
selector=$3
for value in "$mail_hostname" "$mail_domain" "$selector"; do
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || die 'hostname, domain or selector has an invalid format'
done
command -v dig >/dev/null 2>&1 || die 'dig is required'

mx=$(dig +short MX "$mail_domain" | awk '{print $2}' | sed 's/\.$//' | sort -u)
printf '%s\n' "$mx" | grep -Fxq "$mail_hostname" || die 'MX does not point to MAIL_HOSTNAME'
spf=$(dig +short TXT "$mail_domain" | tr -d '"')
printf '%s\n' "$spf" | grep -Fq 'v=spf1' || die 'SPF record is missing'
dmarc=$(dig +short TXT "_dmarc.$mail_domain" | tr -d '"')
printf '%s\n' "$dmarc" | grep -Fq 'v=DMARC1' || die 'DMARC record is missing'
dkim=$(dig +short TXT "$selector._domainkey.$mail_domain" | tr -d '"')
printf '%s\n' "$dkim" | grep -Fq 'v=DKIM1' || die 'DKIM record is missing'

printf 'check-mail-dns: MX, SPF, DKIM and DMARC records are present\n'
