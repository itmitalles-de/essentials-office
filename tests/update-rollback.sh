#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
WORK_DIR=$(mktemp -d /tmp/essentials-office-update-test.XXXXXX)
GATE_DIR=

cleanup() {
  if [ -n "$GATE_DIR" ] && [[ "$GATE_DIR" == /tmp/essentials-office-update-gate-test.* ]]; then
    find "$GATE_DIR" -xdev -depth -delete
  fi
  find "$WORK_DIR" -xdev -depth -delete
}
trap cleanup EXIT INT TERM

for command in awk chmod cp date find git jq mkdir rg; do
  command -v "$command" >/dev/null 2>&1 || exit 1
done
mkdir -p "$WORK_DIR/scripts" "$WORK_DIR/bin" "$WORK_DIR/reports"
cp "$PROJECT_DIR/compose.yaml" "$WORK_DIR/compose.yaml"
cp "$PROJECT_DIR/.env.example" "$WORK_DIR/.env"
cp "$PROJECT_DIR/scripts/update.sh" "$PROJECT_DIR/scripts/verify-image-policy.sh" "$WORK_DIR/scripts/"
printf 'synthetic data must survive update and rollback\n' >"$WORK_DIR/data-marker"

cat >"$WORK_DIR/bin/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$FAKE_DOCKER_LOG"
if [ "${1:-}" = inspect ]; then
  case "${*: -1}" in
    cid-db) printf 'sha256:%064d\n' 1 ;;
    cid-redis) printf 'sha256:%064d\n' 2 ;;
    cid-app|cid-cron) printf 'sha256:%064d\n' 3 ;;
    *) exit 1 ;;
  esac
  exit 0
fi
[ "${1:-}" = compose ] || exit 1
shift
joined=" $* "
if [[ "$joined" == *" config --images "* ]]; then
  awk '/^[[:space:]]*image:/ {print $2}' "$FAKE_PROJECT_DIR/compose.yaml" | sort -u
  exit 0
fi
if [[ "$joined" == *" config -q "* ]]; then exit 0; fi
if [[ "$joined" == *" ps -q "* ]]; then
  printf 'cid-%s\n' "${*: -1}"
  exit 0
fi
if [[ "$joined" == *" pull "* ]]; then
  [ "${FAKE_FAIL_MODE:-}" != pull ]
  exit
fi
if [[ "$joined" == *" stop --timeout "* ]]; then exit 0; fi
if [[ "$joined" == *" up -d "* ]]; then
  if [ "${FAKE_FAIL_MODE:-}" = start ] && [[ "$joined" != *"update-rollback-compose.yaml"* ]] \
    && [ ! -e "$FAKE_SCENARIO_DIR/start-failed" ]; then
    : >"$FAKE_SCENARIO_DIR/start-failed"
    exit 1
  fi
  exit 0
fi
if [[ "$joined" == *" php occ status --output=json "* ]]; then
  printf '%s\n' '{"installed":true,"maintenance":true,"needsDbUpgrade":false}'
  exit 0
fi
if [[ "$joined" == *" php occ maintenance:mode --on "* ]] \
  || [[ "$joined" == *" php occ maintenance:mode --off "* ]]; then
  exit 0
fi
exit 0
FAKE_DOCKER

cat >"$WORK_DIR/scripts/backup.sh" <<'FAKE_BACKUP'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'backup %s\n' "${BACKUP_REPOSITORY_COMMIT:-unset}" >>"$FAKE_DOCKER_LOG"
FAKE_BACKUP

cat >"$WORK_DIR/scripts/healthcheck.sh" <<'FAKE_HEALTH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'health %s\n' "$*" >>"$FAKE_DOCKER_LOG"
if [ "${FAKE_FAIL_MODE:-}" = health ] && [ "${1:-}" != --core-only ] \
  && [ ! -e "$FAKE_SCENARIO_DIR/health-failed" ]; then
  : >"$FAKE_SCENARIO_DIR/health-failed"
  exit 1
fi
FAKE_HEALTH

chmod +x "$WORK_DIR/bin/docker" "$WORK_DIR/scripts/"*.sh

run_update() {
  local scenario=$1 mode=$2 health_mode=$3 scenario_dir
  scenario_dir="$WORK_DIR/$scenario"
  mkdir -p "$scenario_dir/reports"
  : >"$scenario_dir/docker.log"
  env \
    PATH="$WORK_DIR/bin:$PATH" \
    ESSENTIALS_OFFICE_UPDATE_TEST_MODE=true \
    FAKE_PROJECT_DIR="$WORK_DIR" \
    FAKE_DOCKER_LOG="$scenario_dir/docker.log" \
    FAKE_SCENARIO_DIR="$scenario_dir" \
    FAKE_FAIL_MODE="$mode" \
    UPDATE_HEALTHCHECK_MODE="$health_mode" \
    UPDATE_REPORT_ROOT="$scenario_dir/reports" \
    "$WORK_DIR/scripts/update.sh"
}

run_update success '' core-only >/dev/null
rg -q '^backup unset$' "$WORK_DIR/success/docker.log"
rg -q 'compose\.yaml pull$' "$WORK_DIR/success/docker.log"
rg -q 'maintenance:mode --off' "$WORK_DIR/success/docker.log"
backup_line=$(awk '/^backup / {print NR; exit}' "$WORK_DIR/success/docker.log")
pull_line=$(awk '/compose\.yaml pull$/ {print NR; exit}' "$WORK_DIR/success/docker.log")
[ -n "$backup_line" ] && [ -n "$pull_line" ] && [ "$backup_line" -lt "$pull_line" ] || {
  printf 'update-rollback-test: image pull occurred before the accepted backup\n' >&2
  exit 1
}

if run_update pull-failure pull core-only >/dev/null 2>&1; then
  printf 'update-rollback-test: failed pull unexpectedly passed\n' >&2
  exit 1
fi
! rg -q 'maintenance:mode --on' "$WORK_DIR/pull-failure/docker.log" || {
  printf 'update-rollback-test: failed pull entered maintenance mode\n' >&2
  exit 1
}

if run_update start-failure start core-only >/dev/null 2>&1; then
  printf 'update-rollback-test: failed start unexpectedly passed\n' >&2
  exit 1
fi
rg -q 'update-rollback-compose.yaml up -d' "$WORK_DIR/start-failure/docker.log"
rg -q 'maintenance:mode --off' "$WORK_DIR/start-failure/docker.log"
rg -q '^health --core-only$' "$WORK_DIR/start-failure/docker.log"
rollback_override=$(find "$WORK_DIR/start-failure/reports" -name update-rollback-compose.yaml -print -quit)
[ -n "$rollback_override" ] || {
  printf 'update-rollback-test: exact-image rollback override is missing\n' >&2
  exit 1
}
for image_id in \
  'sha256:0000000000000000000000000000000000000000000000000000000000000001' \
  'sha256:0000000000000000000000000000000000000000000000000000000000000002' \
  'sha256:0000000000000000000000000000000000000000000000000000000000000003'; do
  rg -Fq "image: $image_id" "$rollback_override" || {
    printf 'update-rollback-test: rollback override lacks accepted image ID %s\n' "$image_id" >&2
    exit 1
  }
done

if run_update health-failure health full >/dev/null 2>&1; then
  printf 'update-rollback-test: failed health check unexpectedly passed\n' >&2
  exit 1
fi
rg -q '^health $' "$WORK_DIR/health-failure/docker.log"
rg -q 'update-rollback-compose.yaml up -d' "$WORK_DIR/health-failure/docker.log"
rg -q '^health --core-only$' "$WORK_DIR/health-failure/docker.log"

before_hash=$(sha256sum "$WORK_DIR/data-marker" | awk '{print $1}')
run_update idempotent-first '' core-only >/dev/null
run_update idempotent-second '' core-only >/dev/null
after_hash=$(sha256sum "$WORK_DIR/data-marker" | awk '{print $1}')
[ "$before_hash" = "$after_hash" ] || {
  printf 'update-rollback-test: synthetic data marker changed\n' >&2
  exit 1
}

GATE_DIR=$(mktemp -d /tmp/essentials-office-update-gate-test.XXXXXX)
install -d "$GATE_DIR/scripts" "$GATE_DIR/test-output"
cp "$PROJECT_DIR/compose.yaml" "$GATE_DIR/compose.yaml"
cp "$PROJECT_DIR/.env.example" "$GATE_DIR/.env"
cp "$PROJECT_DIR/scripts/update.sh" "$PROJECT_DIR/scripts/verify-image-policy.sh" "$GATE_DIR/scripts/"
cp "$WORK_DIR/scripts/backup.sh" "$WORK_DIR/scripts/healthcheck.sh" "$GATE_DIR/scripts/"
chmod +x "$GATE_DIR/scripts/"*.sh
printf '.env\ntest-output/\n' >"$GATE_DIR/.gitignore"
git -C "$GATE_DIR" init --initial-branch=main -q
git -C "$GATE_DIR" config user.name 'Synthetic Gate Test'
git -C "$GATE_DIR" config user.email 'synthetic-gate@example.invalid'
git -C "$GATE_DIR" add .gitignore compose.yaml scripts
git -C "$GATE_DIR" commit -qm 'synthetic accepted state'
from_commit=$(git -C "$GATE_DIR" rev-parse HEAD)
printf 'reviewed target\n' >"$GATE_DIR/reviewed-target.txt"
git -C "$GATE_DIR" add reviewed-target.txt
git -C "$GATE_DIR" commit -qm 'synthetic reviewed target'
target_commit=$(git -C "$GATE_DIR" rev-parse HEAD)

write_gate_report() {
  local output=$1 compared_at=$2
  jq -n --arg comparedAt "$compared_at" --arg fromCommit "$from_commit" '
    def pass($name): {name: $name, status: "pass"};
    {schemaVersion: "1.0.0", comparedAtUtc: $comparedAt, result: "pass", checks: [
      pass("deployment-state-age"),
      (pass("repository-commit") + {actual: $fromCommit}),
      pass("repository-clean"), pass("compose-drift"), pass("image-drift"),
      (pass("running-image-drift") + {actual: {
        db: {imageId: "sha256:0000000000000000000000000000000000000000000000000000000000000001"},
        redis: {imageId: "sha256:0000000000000000000000000000000000000000000000000000000000000002"},
        app: {imageId: "sha256:0000000000000000000000000000000000000000000000000000000000000003"},
        cron: {imageId: "sha256:0000000000000000000000000000000000000000000000000000000000000003"}
      }}),
      pass("module-drift"), pass("caddy-drift"), pass("backup-age"),
      pass("independent-restore-age"), pass("restore-rto")
    ]}
  ' >"$output"
  chmod 0600 "$output"
}

run_gate_update() {
  local report=$1 scenario=$2
  install -d "$GATE_DIR/test-output/$scenario/reports"
  : >"$GATE_DIR/test-output/$scenario/docker.log"
  env \
    PATH="$WORK_DIR/bin:$PATH" \
    ESSENTIALS_OFFICE_UPDATE_GATE_TEST_MODE=true \
    FAKE_PROJECT_DIR="$GATE_DIR" \
    FAKE_DOCKER_LOG="$GATE_DIR/test-output/$scenario/docker.log" \
    FAKE_SCENARIO_DIR="$GATE_DIR/test-output/$scenario" \
    UPDATE_FROM_COMMIT="$from_commit" \
    UPDATE_APPROVED_COMMIT="$target_commit" \
    UPDATE_GATE_REPORT="$report" \
    UPDATE_HEALTHCHECK_MODE=core-only \
    UPDATE_REPORT_ROOT="$GATE_DIR/test-output/$scenario/reports" \
    "$GATE_DIR/scripts/update.sh"
}

gate_report="$GATE_DIR/test-output/gate-pass.json"
write_gate_report "$gate_report" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run_gate_update "$gate_report" gate-pass >/dev/null
rg -q "^backup $from_commit$" "$GATE_DIR/test-output/gate-pass/docker.log"
gate_result=$(find "$GATE_DIR/test-output/gate-pass/reports" -name update-result.json -print -quit)
jq -e --arg from "$from_commit" --arg target "$target_commit" \
  '.fromCommit == $from and .repositoryCommit == $target and .result == "passed"' \
  "$gate_result" >/dev/null

stale_report="$GATE_DIR/test-output/gate-stale.json"
write_gate_report "$stale_report" '2000-01-01T00:00:00Z'
if run_gate_update "$stale_report" gate-stale >/dev/null 2>&1; then
  printf 'update-rollback-test: stale production gate unexpectedly passed\n' >&2
  exit 1
fi
! rg -q '^backup ' "$GATE_DIR/test-output/gate-stale/docker.log" || {
  printf 'update-rollback-test: stale production gate reached backup\n' >&2
  exit 1
}

incomplete_report="$GATE_DIR/test-output/gate-incomplete.json"
jq 'del(.checks[] | select(.name == "caddy-drift"))' "$gate_report" >"$incomplete_report"
chmod 0600 "$incomplete_report"
if run_gate_update "$incomplete_report" gate-incomplete >/dev/null 2>&1; then
  printf 'update-rollback-test: incomplete production gate unexpectedly passed\n' >&2
  exit 1
fi

wrong_image_report="$GATE_DIR/test-output/gate-wrong-image.json"
jq '(.checks[] | select(.name == "running-image-drift").actual.app.imageId) = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  "$gate_report" >"$wrong_image_report"
chmod 0600 "$wrong_image_report"
if run_gate_update "$wrong_image_report" gate-wrong-image >/dev/null 2>&1; then
  printf 'update-rollback-test: mismatched accepted image unexpectedly passed\n' >&2
  exit 1
fi
! rg -q '^backup ' "$GATE_DIR/test-output/gate-wrong-image/docker.log" || {
  printf 'update-rollback-test: mismatched image gate reached backup\n' >&2
  exit 1
}

printf 'update-rollback-test: backup, pins, failure rollback, idempotence, fresh complete production gate, commit ancestry, and accepted running images passed\n'
