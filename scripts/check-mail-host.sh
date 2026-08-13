#!/usr/bin/env bash
# Run on the proposed mailcow VM/VPS before cloning or starting mailcow.
set -Eeuo pipefail

die() {
  printf 'check-mail-host: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 3 ] || die 'usage: check-mail-host.sh MAIL_HOSTNAME MAIL_DOMAIN EXPECTED_PUBLIC_IPV4'
mail_hostname=${1%.}
mail_domain=${2%.}
expected_ip=$3
[[ "$mail_hostname" =~ ^[A-Za-z0-9.-]+$ ]] || die 'MAIL_HOSTNAME is invalid'
[[ "$mail_domain" =~ ^[A-Za-z0-9.-]+$ ]] || die 'MAIL_DOMAIN is invalid'
[[ "$expected_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die 'EXPECTED_PUBLIC_IPV4 is invalid'

for command in dig docker free nc ss systemd-detect-virt timeout; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required'

memory_bytes=$(free -b | awk '/^Mem:/ {print $2}')
swap_bytes=$(free -b | awk '/^Swap:/ {print $2}')
[ "$memory_bytes" -ge 6442450944 ] || die 'mailcow requires at least 6 GiB RAM'
[ "$swap_bytes" -ge 1073741824 ] || die 'mailcow requires at least 1 GiB swap'

case "$(uname -m)" in
  x86_64|aarch64) ;;
  *) die 'mailcow requires x86_64 or ARM64' ;;
esac
case "$(systemd-detect-virt 2>/dev/null || true)" in
  lxc|openvz) die 'mailcow is not supported in LXC or OpenVZ' ;;
esac

docker_major=$(docker version --format '{{.Server.Version}}' | cut -d. -f1)
[ "$docker_major" -ge 24 ] || die 'Docker Engine 24 or newer is required'

for port in 25 80 110 143 443 465 587 993 995 4190; do
  if ss -H -ltn "sport = :$port" | grep -q .; then
    die "TCP port $port is already in use"
  fi
done

mapfile -t a_records < <(dig +short A "$mail_hostname" | sort -u)
[ "${#a_records[@]}" -eq 1 ] || die "$mail_hostname must have exactly one public A record"
[ "${a_records[0]}" = "$expected_ip" ] || die "$mail_hostname does not resolve to the expected static IPv4"
ptr=$(dig +short -x "$expected_ip" | head -n 1)
[ "${ptr%.}" = "$mail_hostname" ] || die 'PTR/rDNS does not resolve to MAIL_HOSTNAME'

# This opens only a TCP connection and sends no mail.
timeout 12 nc -z -w 10 gmail-smtp-in.l.google.com 25 || die 'outbound TCP 25 is blocked'

printf 'check-mail-host: resource, virtualization, port, A/PTR and outbound TCP 25 gates passed\n'
printf 'check-mail-host: the provider must still confirm that the IPv4 assignment and PTR are durable\n'
