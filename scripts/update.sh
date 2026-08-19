#!/usr/bin/env bash
# Apply reviewed same-major image pins with backup, health gate, and image rollback.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
REPORT_ROOT=${UPDATE_REPORT_ROOT:-"$PROJECT_DIR/reports"}
WAIT_TIMEOUT=${UPDATE_WAIT_TIMEOUT_SECONDS:-600}
HEALTH_MODE=${UPDATE_HEALTHCHECK_MODE:-full}
GATE_REPORT=${UPDATE_GATE_REPORT:-/var/lib/essentials-office/evidence/approved-deployment-drift.json}
GATE_MAX_AGE=${UPDATE_GATE_MAX_AGE_SECONDS:-3600}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
REPORT_DIR="$REPORT_ROOT/update-$STAMP-$$"
ROLLBACK_FILE="$REPORT_DIR/update-rollback-compose.yaml"
MAINTENANCE_ENABLED=false
ROLLBACK_ARMED=false
REPORT_CREATED=false
VERIFY_GATE_IMAGES=false
GATE_TEST_MODE=${ESSENTIALS_OFFICE_UPDATE_GATE_TEST_MODE:-false}

die() {
  printf 'update: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose -f "$PROJECT_DIR/compose.yaml" "$@"
}

occ() {
  compose exec -T -u www-data app php occ "$@"
}

write_image_state() {
  local output=$1 service container_id image_id first=true
  printf '{\n' >"$output"
  for service in db redis app cron; do
    container_id=$(compose ps -q "$service")
    [ -n "$container_id" ] || return 1
    image_id=$(docker inspect --format '{{.Image}}' "$container_id")
    [[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
    if [ "$first" = false ]; then printf ',\n' >>"$output"; fi
    first=false
    printf '  "%s": "%s"' "$service" "$image_id" >>"$output"
  done
  printf '\n}\n' >>"$output"
}

write_rollback_override() {
  local state_file=$1 service image_id
  printf 'services:\n' >"$ROLLBACK_FILE"
  for service in db redis app cron; do
    image_id=$(jq -r --arg service "$service" '.[$service]' "$state_file")
    [[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]] || die "invalid rollback image ID for $service"
    printf '  %s:\n    image: %s\n' "$service" "$image_id" >>"$ROLLBACK_FILE"
  done
  chmod 0600 "$ROLLBACK_FILE"
}

rollback_images() {
  local rollback_ok=true
  printf 'update: attempting rollback to the exact pre-update image IDs\n' >&2
  if ! docker compose -f "$PROJECT_DIR/compose.yaml" -f "$ROLLBACK_FILE" \
    up -d --wait --wait-timeout "$WAIT_TIMEOUT"; then
    rollback_ok=false
    printf 'update: WARNING: previous images did not start cleanly\n' >&2
  fi
  if ! docker compose -f "$PROJECT_DIR/compose.yaml" -f "$ROLLBACK_FILE" \
    exec -T -u www-data app php occ maintenance:mode --off >/dev/null; then
    rollback_ok=false
    printf 'update: WARNING: maintenance mode could not be disabled after rollback\n' >&2
  else
    MAINTENANCE_ENABLED=false
  fi
  if ! "$SCRIPT_DIR/healthcheck.sh" --core-only; then
    rollback_ok=false
    printf 'update: WARNING: rolled-back core health check failed\n' >&2
  fi
  jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson ok "$rollback_ok" \
    '{attemptedAtUtc: $at, passed: $ok}' >"$REPORT_DIR/rollback-result.json"
  chmod 0600 "$REPORT_DIR/rollback-result.json"
  [ "$rollback_ok" = true ]
}

on_exit() {
  local status=$?
  trap - EXIT INT TERM
  if [ "$status" -ne 0 ] && [ "$ROLLBACK_ARMED" = true ]; then
    rollback_images || status=1
  elif [ "$status" -ne 0 ] && [ "$MAINTENANCE_ENABLED" = true ]; then
    if ! occ maintenance:mode --off >/dev/null; then
      printf 'update: WARNING: maintenance mode could not be disabled automatically\n' >&2
      status=1
    fi
  fi
  if [ "$REPORT_CREATED" = true ]; then
    printf '%s\n' "$status" >"$REPORT_DIR/exit-status"
    chmod 0600 "$REPORT_DIR/exit-status"
  fi
  exit "$status"
}
trap on_exit EXIT INT TERM

if [ "${EUID}" -ne 0 ]; then
  if [ "${ESSENTIALS_OFFICE_UPDATE_TEST_MODE:-false}" != true ] && [ "$GATE_TEST_MODE" != true ]; then
    exec sudo -- "$0" "$@"
  fi
  case "$PROJECT_DIR" in
    /tmp/essentials-office-update-test.*|/tmp/essentials-office-update-gate-test.*) ;;
    *) die 'unprivileged test mode is restricted to a generated update-test checkout' ;;
  esac
fi

[ "$#" -eq 0 ] || die 'usage: update.sh'
for command in chmod cp date docker git install jq stat; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
case "$WAIT_TIMEOUT" in ''|*[!0-9]*) die 'UPDATE_WAIT_TIMEOUT_SECONDS must be a positive integer' ;; esac
[ "$WAIT_TIMEOUT" -gt 0 ] || die 'UPDATE_WAIT_TIMEOUT_SECONDS must be greater than zero'
case "$GATE_MAX_AGE" in ''|*[!0-9]*) die 'UPDATE_GATE_MAX_AGE_SECONDS must be a positive integer' ;; esac
[ "$GATE_MAX_AGE" -gt 0 ] || die 'UPDATE_GATE_MAX_AGE_SECONDS must be greater than zero'
case "$HEALTH_MODE" in full|core-only) ;; *) die 'UPDATE_HEALTHCHECK_MODE must be full or core-only' ;; esac
case "$GATE_TEST_MODE" in true|false) ;; *) die 'ESSENTIALS_OFFICE_UPDATE_GATE_TEST_MODE must be true or false' ;; esac
[ "$GATE_TEST_MODE" = false ] || case "$PROJECT_DIR" in
  /tmp/essentials-office-update-gate-test.*) ;;
  *) die 'gate test mode is restricted to a generated gate-test checkout' ;;
esac
[ -f "$PROJECT_DIR/.env" ] || die 'missing .env; run bootstrap.sh first'

cd "$PROJECT_DIR"
if [ "${ESSENTIALS_OFFICE_UPDATE_TEST_MODE:-false}" = true ]; then
  repository_commit=synthetic-unit-test
  repository_from_commit=synthetic-unit-test
elif [ "${ESSENTIALS_OFFICE_UPDATE_DISPOSABLE:-false}" = true ]; then
  case "$PROJECT_DIR" in
    /tmp/essentials-office-deploy-test.*) ;;
    *) die 'disposable update mode is restricted to a generated deploy-test checkout' ;;
  esac
  repository_commit=synthetic-disposable
  repository_from_commit=synthetic-disposable
else
  approved_commit=${UPDATE_APPROVED_COMMIT:-}
  repository_from_commit=${UPDATE_FROM_COMMIT:-}
  [[ "$approved_commit" =~ ^[0-9a-f]{40}$ ]] || die 'UPDATE_APPROVED_COMMIT must be the reviewed full commit'
  [[ "$repository_from_commit" =~ ^[0-9a-f]{40}$ ]] || die 'UPDATE_FROM_COMMIT must be the previously accepted full commit'
  repository_commit=$(git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null) ||
    die 'deployment checkout is not a Git worktree'
  [ "$repository_commit" = "$approved_commit" ] || die 'deployed commit differs from UPDATE_APPROVED_COMMIT'
  [ -z "$(git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" status --porcelain)" ] ||
    die 'deployment checkout is dirty; reconcile without resetting it'
  git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" \
    merge-base --is-ancestor "$repository_from_commit" "$repository_commit" ||
    die 'UPDATE_FROM_COMMIT is not an ancestor of the approved target commit'
  [ -f "$GATE_REPORT" ] || die "approved passing drift report is missing: $GATE_REPORT"
  if [ "$GATE_TEST_MODE" = false ]; then
    [ "$(stat -c '%u' "$GATE_REPORT")" = 0 ] || die 'approved drift report must be owned by root'
  fi
  case "$(stat -c '%a' "$GATE_REPORT")" in
    400|600) ;;
    *) die 'approved drift report must have mode 0400 or 0600' ;;
  esac
  jq -e '
    def required: ["deployment-state-age", "repository-commit", "repository-clean",
      "compose-drift", "image-drift", "running-image-drift", "module-drift",
      "caddy-drift", "backup-age", "independent-restore-age", "restore-rto"];
    . as $report |
    .schemaVersion == "1.0.0" and .result == "pass" and
    (.checks | length > 0) and all(.checks[]; .status == "pass") and
    all(required[]; . as $name |
      any($report.checks[]; .name == $name and .status == "pass"))
  ' "$GATE_REPORT" >/dev/null ||
    die 'approved drift report does not pass every operational check'
  gate_report_time=$(jq -r '.comparedAtUtc // empty' "$GATE_REPORT")
  gate_report_epoch=$(date -u -d "$gate_report_time" +%s 2>/dev/null) ||
    die 'approved drift report has no valid comparison time'
  gate_report_age=$(( $(date -u +%s) - gate_report_epoch ))
  [ "$gate_report_age" -ge 0 ] && [ "$gate_report_age" -le "$GATE_MAX_AGE" ] ||
    die 'approved drift report is stale or dated in the future'
  gate_report_commit=$(jq -r '.checks[] | select(.name == "repository-commit") | .actual' "$GATE_REPORT")
  [ "$gate_report_commit" = "$repository_from_commit" ] ||
    die 'approved drift report does not describe UPDATE_FROM_COMMIT'
  VERIFY_GATE_IMAGES=true
fi
compose config -q
"$SCRIPT_DIR/verify-image-policy.sh" "$PROJECT_DIR/compose.yaml"
install -d -m 0700 "$REPORT_DIR"
REPORT_CREATED=true

write_image_state "$REPORT_DIR/images-before.json" || die 'all four core services must be running before update'
chmod 0600 "$REPORT_DIR/images-before.json"
if [ "$VERIFY_GATE_IMAGES" = true ]; then
  jq -e --slurpfile running "$REPORT_DIR/images-before.json" '
    ([.checks[] | select(.name == "running-image-drift")][0].actual // {}) as $approved
    | $running[0] as $current
    | all(["db", "redis", "app", "cron"][];
        . as $service |
          ($current[$service] | type == "string") and
          $approved[$service].imageId == $current[$service])
  ' "$GATE_REPORT" >/dev/null ||
    die 'running pre-update image IDs differ from the approved drift report'
fi
write_rollback_override "$REPORT_DIR/images-before.json"
cp "$PROJECT_DIR/compose.yaml" "$REPORT_DIR/compose.requested.yaml"
chmod 0600 "$REPORT_DIR/compose.requested.yaml"

if [[ "$repository_from_commit" =~ ^[0-9a-f]{40}$ ]]; then
  BACKUP_REPOSITORY_COMMIT="$repository_from_commit" "$SCRIPT_DIR/backup.sh"
else
  "$SCRIPT_DIR/backup.sh"
fi
if ! compose pull; then
  die 'image pull failed; running containers and maintenance state are unchanged'
fi

occ maintenance:mode --on >/dev/null
MAINTENANCE_ENABLED=true
ROLLBACK_ARMED=true
compose stop --timeout 30 cron >/dev/null
compose up -d --wait --wait-timeout "$WAIT_TIMEOUT"

occ status --output=json | jq -e \
  '.installed == true and .maintenance == true and .needsDbUpgrade == false' >/dev/null ||
  die 'updated Nextcloud did not reach the expected pre-release maintenance state'
occ maintenance:mode --off >/dev/null
MAINTENANCE_ENABLED=false

if [ "$HEALTH_MODE" = core-only ]; then
  "$SCRIPT_DIR/healthcheck.sh" --core-only
else
  "$SCRIPT_DIR/healthcheck.sh"
fi
ROLLBACK_ARMED=false
write_image_state "$REPORT_DIR/images-after.json" || die 'could not record updated image state'
chmod 0600 "$REPORT_DIR/images-after.json"
jq -n \
  --arg completedAtUtc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repositoryCommit "$repository_commit" --arg fromCommit "$repository_from_commit" \
  --slurpfile before "$REPORT_DIR/images-before.json" --slurpfile after "$REPORT_DIR/images-after.json" \
  '{completedAtUtc: $completedAtUtc, repositoryCommit: $repositoryCommit,
    fromCommit: $fromCommit,
    result: "passed", before: $before[0], after: $after[0], dataRestorePerformed: false}' \
  >"$REPORT_DIR/update-result.json"
chmod 0600 "$REPORT_DIR/update-result.json"

printf 'update: reviewed same-major pins passed backup, start, maintenance, and health gates\n'
printf 'update: rollback evidence retained in %s\n' "$REPORT_DIR"
