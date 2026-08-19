#!/usr/bin/env bash
# Verify immutable GitHub Action and container references used by CI and tests.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"

die() {
  printf 'check-supply-chain: %s\n' "$*" >&2
  exit 1
}

for command in awk find rg sort; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
cd "$PROJECT_DIR"

while IFS= read -r reference; do
  revision=${reference##*@}
  revision=${revision%%[[:space:]]*}
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || die "GitHub Action is not pinned to a full commit SHA: $reference"
done < <(awk '/^[[:space:]]*uses:[[:space:]]*/ {sub(/^[[:space:]]*uses:[[:space:]]*/, ""); print}' .github/workflows/*.yaml)

mapfile -d '' compose_files < <(find . -path './.git' -prune -o -type f \
  \( -name 'compose.yaml' -o -name 'compose.*.yaml' -o -name 'docker-compose.yaml' -o -name 'docker-compose.yml' \) \
  -print0 | sort -z)
[ "${#compose_files[@]}" -gt 0 ] || die 'no Compose files found'
for compose_file in "${compose_files[@]}"; do
  while IFS= read -r image; do
    [[ "$image" =~ @sha256:[0-9a-f]{64}$ ]] || die "mutable Compose image in $compose_file: $image"
  done < <(awk '/^[[:space:]]*image:[[:space:]]*/ {sub(/^[[:space:]]*image:[[:space:]]*/, ""); gsub(/["'\'']/, ""); print}' "$compose_file")
done

runtime_images=(
  nextcloud postgres redis python vaultwarden/server collabora/code coturn/coturn
  caddy curlimages/curl keinos/sqlite3 koalaman/shellcheck-alpine
  rhysd/actionlint ghcr.io/gitleaks/gitleaks anchore/syft
)
for image_name in "${runtime_images[@]}"; do
  while IFS= read -r reference; do
    [[ "$reference" == *@sha256:* ]] ||
      die "mutable runtime/test image reference remains: $reference"
  done < <(rg -n --pcre2 --glob '!check-supply-chain.sh' "\\Q${image_name}\\E:[v0-9]" \
    .github scripts tests compose.yaml compose.*.yaml || true)
done

rg -q 'fetch-depth:[[:space:]]*0' .github/workflows/ci.yaml || die 'full-history checkout for secret scanning is missing'
rg -q 'gitleaks.*@sha256:[0-9a-f]{64}' .github/workflows/ci.yaml || die 'digest-pinned Gitleaks scan is missing'
rg -q 'anchore/syft:.*@sha256:[0-9a-f]{64}' .github/workflows/ci.yaml || die 'digest-pinned SBOM generation is missing'

printf 'check-supply-chain: Action SHAs, Compose/test digests, full-history secret scan, and SBOM pin passed\n'
