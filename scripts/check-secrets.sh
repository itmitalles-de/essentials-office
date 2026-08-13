#!/usr/bin/env bash
# Dependency-free guard for obvious secrets in tracked files; not a secret manager.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"

die() {
  printf 'check-secrets: %s\n' "$*" >&2
  exit 1
}

case "${1:-}" in
  ''|--tracked) ;;
  -h|--help)
    printf '%s\n' 'Usage: ./scripts/check-secrets.sh [--tracked]'
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
esac

command -v git >/dev/null 2>&1 || die 'git is required'
cd "$PROJECT_DIR"
patterns=(
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  'AKIA[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9_]{20,}'
  '^(POSTGRES_PASSWORD|REDIS_PASSWORD|NEXTCLOUD_ADMIN_PASSWORD|ADMIN_TOKEN|SMTP_PASSWORD|API_KEY|SECRET_KEY)[[:space:]]*=[[:space:]]*[^#[:space:]][^[:space:]]{15,}'
)
for pattern in "${patterns[@]}"; do
  found=false
  while IFS= read -r -d '' file; do
    if grep -nI -E -e "$pattern" "$file"; then
      found=true
    fi
  done < <(git ls-files --cached --others --exclude-standard -z)
  [ "$found" = false ] || die 'possible secret found in a repository file'
done
printf 'check-secrets: no obvious secrets found in tracked implementation files\n'
