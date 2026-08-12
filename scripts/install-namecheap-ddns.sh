#!/usr/bin/env bash
set -Eeuo pipefail

readonly env_file="/etc/namecheap-ddns.env"
readonly updater_target="/usr/local/sbin/namecheap-ddns"
readonly service_target="/etc/systemd/system/namecheap-ddns.service"
readonly timer_target="/etc/systemd/system/namecheap-ddns.timer"
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/.." && pwd -P)"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/install-namecheap-ddns.sh [--stage-only]

Without options, securely prompts for the Namecheap per-domain Dynamic DNS
password when it is not already configured, performs one update, and enables
the timer. --stage-only installs code and unit files without creating a secret
or changing the timer state.
EOF
}

stage_only=false
case "${1:-}" in
    "") ;;
    --stage-only) stage_only=true ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

[[ "$EUID" -eq 0 ]] || fail "run this installer as root"

for required_command in curl install systemctl; do
    command -v "$required_command" >/dev/null 2>&1 ||
        fail "$required_command is required"
done

install -D -o root -g root -m 0755 \
    "$repo_root/scripts/namecheap-ddns.sh" "$updater_target"
install -D -o root -g root -m 0644 \
    "$repo_root/systemd/namecheap-ddns.service" "$service_target"
install -D -o root -g root -m 0644 \
    "$repo_root/systemd/namecheap-ddns.timer" "$timer_target"
systemctl daemon-reload

if [[ "$stage_only" == true ]]; then
    printf 'Staged Namecheap DDNS files; timer state and secrets are unchanged.\n'
    exit 0
fi

if [[ ! -e "$env_file" ]]; then
    [[ -t 0 ]] || fail "an interactive terminal is required to enter the DDNS password"

    printf 'Namecheap per-domain Dynamic DNS password: ' >&2
    IFS= read -r -s ddns_password
    printf '\n' >&2

    [[ "$ddns_password" =~ ^[[:alnum:]]{8,128}$ ]] ||
        fail "the DDNS password must be 8-128 alphanumeric characters"

    umask 077
    if ! (set -o noclobber; printf 'NAMECHEAP_DDNS_PASSWORD=%s\n' "$ddns_password" >"$env_file"); then
        fail "$env_file appeared while creating it; it was not overwritten"
    fi
    unset ddns_password
fi

chown root:root "$env_file"
chmod 0600 "$env_file"

if ! systemctl start namecheap-ddns.service; then
    fail "the first DNS update failed; the timer was not enabled"
fi

systemctl enable --now namecheap-ddns.timer
printf 'Namecheap DDNS is active for cloud.itmitalles.de.\n'
