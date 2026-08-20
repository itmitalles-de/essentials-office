#!/usr/bin/env bash
# Run dependency-free Appointments domain tests in the pinned Nextcloud PHP image.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"

command -v docker >/dev/null 2>&1 || {
  printf 'appointments-unit: docker is required\n' >&2
  exit 1
}

docker run --rm --network none \
  -v "$PROJECT_DIR:/repo:ro" \
  --workdir /repo \
  --entrypoint php \
  nextcloud:34-apache \
  tests/appointments/unit.php
