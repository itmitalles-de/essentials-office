#!/usr/bin/env bash
# Install the base packages required to deploy Essentials+ Office on Ubuntu.
set -Eeuo pipefail

MODE=apply

die() {
  printf 'provision-host: %s\n' "$*" >&2
  exit 1
}

case "${1:-}" in
  '') ;;
  --check) MODE=check ;;
  *) die 'usage: provision-host.sh [--check]' ;;
esac
[ "$#" -le 1 ] || die 'usage: provision-host.sh [--check]'

# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = ubuntu ] || die 'only Ubuntu is supported by this host provisioner'
[ -n "${VERSION_CODENAME:-}" ] || die 'Ubuntu VERSION_CODENAME is unavailable'

check_runtime() {
  local command
  for command in curl docker git jq openssl rsync sudo; do
    command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
  done
  docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required'
  docker info >/dev/null 2>&1 || die 'Docker Engine is not reachable for the current user'
  printf 'provision-host: Ubuntu %s, Docker Engine, Compose v2, and host tools are ready\n' \
    "$VERSION_CODENAME"
}

if [ "$MODE" = check ]; then
  check_runtime
  exit 0
fi
if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes ca-certificates curl git jq openssl rsync sudo
install -d -m 0755 /etc/apt/keyrings
curl --fail --location --proto '=https' --tlsv1.2 \
  https://download.docker.com/linux/ubuntu/gpg \
  --output /etc/apt/keyrings/docker.asc
chmod 0644 /etc/apt/keyrings/docker.asc
architecture=$(dpkg --print-architecture)
printf '%s\n' \
  "deb [arch=$architecture signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
  >/etc/apt/sources.list.d/docker.list
apt-get update
apt-get install --yes docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker.service
check_runtime
