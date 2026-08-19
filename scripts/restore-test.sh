#!/usr/bin/env bash
# Restore one backup into an isolated, disposable Compose project.
# shellcheck disable=SC2016 # Variables in single quotes expand inside the target containers.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/tests/restore/compose.yaml"
ENV_FILE=${RESTORE_ENV_FILE:-$PROJECT_DIR/.env}
DEFAULT_BACKUP_ROOT=${BACKUP_DIR:-/srv/nextcloud/backups}
WORK_DIR=
RESTORE_ROOT=
RESTORE_PROJECT=
WEBDAV_SHARE_CHECKED=false
HR_OBJECT_RESULT=not-present
INTRANET_OBJECT_RESULT=not-present
EVIDENCE_TMP=
RESTORE_STARTED_AT=
RESTORE_STARTED_EPOCH=
CHECKSUMS_VERIFIED=false

die() {
  printf 'restore-test: %s\n' "$*" >&2
  exit 1
}

compose() {
  RESTORE_ROOT="$RESTORE_ROOT" docker compose \
    --project-name "$RESTORE_PROJECT" \
    --env-file "$ENV_FILE" \
    --file "$COMPOSE_FILE" "$@"
}

cleanup() {
  local status=$?
  if [ -n "$RESTORE_PROJECT" ] && [ -n "$RESTORE_ROOT" ]; then
    compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/nextcloud-restore-test.* ]]; then
    rm -rf --one-file-system -- "$WORK_DIR"
  fi
  if [ -n "$EVIDENCE_TMP" ] && [ -f "$EVIDENCE_TMP" ]; then
    rm -f -- "$EVIDENCE_TMP"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

for command in awk basename cat chmod cmp curl date dirname docker find grep hostname install jq mktemp mv realpath rm sha256sum sort stat tar; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required'
[ -f "$ENV_FILE" ] || die "missing environment file: $ENV_FILE"
RESTORE_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RESTORE_STARTED_EPOCH=$(date -u +%s)

if [ "$#" -gt 1 ]; then
  die 'usage: restore-test.sh [BACKUP_DIRECTORY]'
fi
backup_dir=${1:-}
if [ -z "$backup_dir" ]; then
  latest=$(find "$DEFAULT_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    ! -name '.*' -printf '%f\n' | sort | tail -n 1)
  [ -n "$latest" ] || die "no backup found below $DEFAULT_BACKUP_ROOT"
  backup_dir="$DEFAULT_BACKUP_ROOT/$latest"
fi

[ -d "$backup_dir" ] || die "backup directory not found: $backup_dir"
for file in nextcloud.pg.dump nextcloud-files.tar.gz; do
  [ -s "$backup_dir/$file" ] || die "backup artifact missing or empty: $file"
done
if [ -f "$backup_dir/SHA256SUMS" ]; then
  (cd "$backup_dir" && sha256sum --check SHA256SUMS)
  CHECKSUMS_VERIFIED=true
fi

# Reject archive paths that could escape the disposable restore root.
while IFS= read -r entry; do
  case "$entry" in
    html|html/*|data|data/*) ;;
    *) die "unexpected or unsafe archive entry: $entry" ;;
  esac
done < <(tar --list --gzip --file "$backup_dir/nextcloud-files.tar.gz")

WORK_DIR=$(mktemp -d /tmp/nextcloud-restore-test.XXXXXX)
RESTORE_ROOT="$WORK_DIR/root"
RESTORE_PROJECT="nc-restore-${RANDOM}-$$"
install -d -m 0700 "$RESTORE_ROOT/postgres" "$RESTORE_ROOT/redis"
tar --extract --gzip --file "$backup_dir/nextcloud-files.tar.gz" \
  --directory "$RESTORE_ROOT" --numeric-owner --acls --xattrs

docker run --rm --entrypoint sh \
  --volume "$RESTORE_ROOT/postgres:/target" \
  postgres:17.10-alpine@sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193 \
  -ec 'chown "$(id -u postgres):$(id -g postgres)" /target; chmod 0700 /target'
docker run --rm --entrypoint sh \
  --volume "$RESTORE_ROOT/redis:/target" \
  redis:7.4.10-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2 \
  -ec 'chown "$(id -u redis):$(id -g redis)" /target; chmod 0700 /target'

compose config -q
compose up --detach --wait db redis

# Nextcloud 34 may store a dedicated application role (for example oc_admin*)
# in config.php. Recreate that login before pg_restore applies object owners.
# The password is passed directly from config.php to PostgreSQL and is never
# emitted to stdout, the process list, or a temporary file.
compose run --rm --no-deps --entrypoint php app -r '
$CONFIG = [];
require "/var/www/html/config/config.php";
$role = $CONFIG["dbuser"] ?? "";
$password = $CONFIG["dbpassword"] ?? "";
if (!preg_match("/^[A-Za-z_][A-Za-z0-9_]*$/D", $role) || $password === "") {
    fwrite(STDERR, "restore-test: invalid database role in config.php\n");
    exit(2);
}
$pdo = new PDO(
    "pgsql:host=" . getenv("POSTGRES_HOST") . ";dbname=" . getenv("POSTGRES_DB"),
    getenv("POSTGRES_USER"),
    getenv("POSTGRES_PASSWORD"),
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
$identifier = "\"" . str_replace("\"", "\"\"", $role) . "\"";
$quotedPassword = $pdo->quote($password);
$query = $pdo->prepare("SELECT 1 FROM pg_roles WHERE rolname = :role");
$query->execute([":role" => $role]);
if ($query->fetchColumn() === false) {
    $pdo->exec("CREATE ROLE " . $identifier . " LOGIN PASSWORD " . $quotedPassword);
} else {
    $pdo->exec("ALTER ROLE " . $identifier . " LOGIN PASSWORD " . $quotedPassword);
}
' >/dev/null
compose exec -T db sh -ec \
  'exec pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
  <"$backup_dir/nextcloud.pg.dump"
compose up --detach --wait app

# The filesystem snapshot is intentionally taken while maintenance mode is on.
compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null
status=$(compose exec -T -u www-data app php occ status --output=json)
printf '%s\n' "$status" | grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' || die 'restored Nextcloud is not installed'
printf '%s\n' "$status" | grep -Eq '"maintenance"[[:space:]]*:[[:space:]]*false' || die 'restored Nextcloud remained in maintenance mode'
compose exec -T -u www-data app php occ maintenance:repair >/dev/null
post_repair_status=$(compose exec -T -u www-data app php occ status --output=json)
printf '%s\n' "$post_repair_status" | grep -Eq '"needsDbUpgrade"[[:space:]]*:[[:space:]]*false' || die 'restored Nextcloud requires a database upgrade after repair'
compose exec -T -u www-data app php occ integrity:check-core >/dev/null ||
  die 'restored Nextcloud core integrity check failed'
compose exec -T db sh -ec 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null
compose exec -T redis sh -ec 'REDISCLI_AUTH="$REDIS_PASSWORD" exec redis-cli --no-auth-warning ping' | grep -qx PONG

verify_user=$(awk -F= '$1 == "RECOVERY_TEST_USER" {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE")
verify_password=$(awk -F= '$1 == "RECOVERY_TEST_PASSWORD" {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE")
verify_owner=$(awk -F= '$1 == "NEXTCLOUD_ADMIN_USER" {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE")
if [ -n "$verify_user" ] || [ -n "$verify_password" ]; then
  [ -n "$verify_user" ] && [ -n "$verify_password" ] && [ -n "$verify_owner" ] || die 'restore verification credentials are incomplete'
  netrc="$WORK_DIR/verify.netrc"
  downloaded="$WORK_DIR/recovered-file"
  (umask 077; printf 'machine 127.0.0.1 login %s password %s\n' "$verify_user" "$verify_password" >"$netrc")
  compose cp "$netrc" app:/tmp/restore-verify.netrc >/dev/null
  compose exec -T app chmod 0600 /tmp/restore-verify.netrc

  roundtrip_name="essentialsplus-restore-roundtrip-$$.txt"
  roundtrip_source="$WORK_DIR/roundtrip-source"
  roundtrip_downloaded="$WORK_DIR/roundtrip-downloaded"
  printf 'Essentials+ Office independent restore WebDAV roundtrip\n' >"$roundtrip_source"
  compose cp "$roundtrip_source" app:/tmp/restore-roundtrip-source >/dev/null
  compose exec -T app curl --fail --silent --show-error \
    --header 'Host: restore.invalid' --netrc-file /tmp/restore-verify.netrc \
    --upload-file /tmp/restore-roundtrip-source \
    "http://127.0.0.1/remote.php/dav/files/$verify_user/$roundtrip_name" >/dev/null
  compose exec -T app curl --fail --silent --show-error \
    --header 'Host: restore.invalid' --netrc-file /tmp/restore-verify.netrc \
    --output /tmp/restore-roundtrip-downloaded \
    "http://127.0.0.1/remote.php/dav/files/$verify_user/$roundtrip_name" >/dev/null
  compose cp app:/tmp/restore-roundtrip-downloaded "$roundtrip_downloaded" >/dev/null
  cmp -- "$roundtrip_source" "$roundtrip_downloaded" ||
    die 'restored WebDAV upload/download bytes differ'
  compose exec -T app curl --fail --silent --show-error --request DELETE \
    --header 'Host: restore.invalid' --netrc-file /tmp/restore-verify.netrc \
    "http://127.0.0.1/remote.php/dav/files/$verify_user/$roundtrip_name" >/dev/null

  compose exec -T app curl --fail --silent --show-error \
    --header 'Host: restore.invalid' --netrc-file /tmp/restore-verify.netrc \
    --output /tmp/recovered-file \
    "http://127.0.0.1/remote.php/dav/files/$verify_user/essentialsplus-recovery.txt" >/dev/null
  compose cp app:/tmp/recovered-file "$downloaded" >/dev/null
  printf 'Essentials+ Office synthetic backup and share fixture\n' | cmp -- - "$downloaded" ||
    die 'restored shared WebDAV file content differs from the source fixture'
  share_count=$(compose exec -T -u www-data app php occ sharing:share:list --output=json 2>/dev/null \
    | jq --arg owner "$verify_owner" '[.[]? | select(.owner == $owner or .uid_owner == $owner)] | length' 2>/dev/null || printf 0)
  if [ "$share_count" -eq 0 ]; then
    shares=$(compose exec -T app curl --fail --silent --show-error \
      --header 'Host: restore.invalid' --header 'OCS-APIRequest: true' --header 'Accept: application/json' \
      --netrc-file /tmp/restore-verify.netrc \
      'http://127.0.0.1/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json&shared_with_me=true')
    jq -e '.ocs.data | length > 0' <<<"$shares" >/dev/null || die 'restored share metadata is missing'
  fi
  WEBDAV_SHARE_CHECKED=true
  unset verify_password
fi

hr_object="$RESTORE_ROOT/data/hr-demo-admin/files/HR Lite - Confidential/workflow-target.json"
if [ -f "$hr_object" ]; then
  cmp -- "$PROJECT_DIR/hr-lite/demo/workflow-target.json" "$hr_object" >/dev/null ||
    die 'restored HR Lite workflow target differs from the synthetic source fixture'
  HR_OBJECT_RESULT=passed
fi
intranet_object="$RESTORE_ROOT/data/intranet-editor-demo/files/Intranet Lite/handbook.md"
intranet_confidential="$RESTORE_ROOT/data/intranet-editor-demo/files/Intranet Lite - Confidential/editorial-draft.md"
if [ -f "$intranet_object" ] || [ -f "$intranet_confidential" ]; then
  [ -f "$intranet_object" ] && [ -f "$intranet_confidential" ] ||
    die 'restored Intranet Lite fixture set is incomplete'
  cmp -- "$PROJECT_DIR/intranet-lite/content/handbook.md" "$intranet_object" >/dev/null ||
    die 'restored Intranet Lite handbook differs from the synthetic source fixture'
  cmp -- "$PROJECT_DIR/intranet-lite/confidential/editorial-draft.md" "$intranet_confidential" >/dev/null ||
    die 'restored Intranet Lite confidential object differs from the synthetic source fixture'
  INTRANET_OBJECT_RESULT=passed
fi

compose up --detach cron >/dev/null
compose ps --status running --services | grep -Fxq cron || die 'restored cron service is not running'
compose exec -T -u www-data app php occ config:app:get core backgroundjobs_mode | grep -Fxq cron ||
  die 'restored Nextcloud background mode is not cron'
compose exec -T -u www-data app php occ config:app:set essentialsplus evidence.restore_test \
  --value="$(date +%s)" >/dev/null 2>&1 || true

if [ -n "${RESTORE_EVIDENCE_OUTPUT:-}" ]; then
  case "$RESTORE_EVIDENCE_OUTPUT" in /*) ;; *) die 'RESTORE_EVIDENCE_OUTPUT must be absolute' ;; esac
  : "${RESTORE_STAGE_DIRECTORY:?RESTORE_STAGE_DIRECTORY is required with RESTORE_EVIDENCE_OUTPUT}"
  case "$RESTORE_STAGE_DIRECTORY" in /*) ;; *) die 'RESTORE_STAGE_DIRECTORY must be absolute' ;; esac
  [ -d "$RESTORE_STAGE_DIRECTORY" ] || die 'RESTORE_STAGE_DIRECTORY does not exist'
  [ ! -L "$RESTORE_STAGE_DIRECTORY" ] || die 'RESTORE_STAGE_DIRECTORY must not be a symlink'
  evidence_stage=$(realpath -e -- "$RESTORE_STAGE_DIRECTORY")
  canonical_backup=$(realpath -e -- "$backup_dir")
  case "$canonical_backup" in
    "$evidence_stage"/*) ;;
    *) die 'backup directory is not inside RESTORE_STAGE_DIRECTORY' ;;
  esac
  [ "$WEBDAV_SHARE_CHECKED" = true ] ||
    die 'RESTORE_EVIDENCE_OUTPUT requires RECOVERY_TEST_USER and RECOVERY_TEST_PASSWORD verification'
  [ "$CHECKSUMS_VERIFIED" = true ] ||
    die 'RESTORE_EVIDENCE_OUTPUT requires a verified SHA256SUMS manifest'
  repository_commit=$(cat "$backup_dir/repository-commit.txt" 2>/dev/null || printf unknown)
  repository_dirty=$(jq -r '.repository.dirty' "$backup_dir/versions.json" 2>/dev/null || printf null)
  case "$repository_dirty" in true|false) ;; *) die 'backup has no reliable repository dirty state' ;; esac
  case "${RESTORE_INDEPENDENT_INFRASTRUCTURE:-false}" in
    true) independent=true ;;
    false|'') independent=false ;;
    *) die 'RESTORE_INDEPENDENT_INFRASTRUCTURE must be true or false' ;;
  esac
  source_snapshot_id=${RESTORE_SOURCE_SNAPSHOT_ID:-}
  [[ "$source_snapshot_id" =~ ^[0-9a-f]{64}$ ]] ||
    die 'RESTORE_EVIDENCE_OUTPUT requires a full RESTORE_SOURCE_SNAPSHOT_ID'
  source_snapshot_time=
  stage_metadata="$evidence_stage/.essentials-office-restore-stage.json"
  if [ "$independent" = true ]; then
    [ -f "$stage_metadata" ] && [ ! -L "$stage_metadata" ] ||
      die 'independent evidence requires the staging metadata written by offsite-restore-stage.sh'
    jq -e '.schemaVersion == "1.0.0" and
      (.snapshotId | test("^[0-9a-f]{64}$")) and
      (.snapshotTimeUtc | type == "string" and length > 0) and
      (.startedAtUtc | type == "string" and length > 0) and
      (.stagedAtUtc | type == "string" and length > 0) and
      (.durationSeconds | type == "number" and . >= 0)' "$stage_metadata" >/dev/null ||
      die 'independent restore staging metadata is invalid'
    stage_snapshot_id=$(jq -r '.snapshotId' "$stage_metadata")
    [ "$stage_snapshot_id" = "$source_snapshot_id" ] ||
      die 'RESTORE_SOURCE_SNAPSHOT_ID differs from the snapshot actually staged'
    source_snapshot_time=$(jq -r '.snapshotTimeUtc' "$stage_metadata")
    stage_started_at=$(jq -r '.startedAtUtc' "$stage_metadata")
    stage_started_epoch=$(date -u -d "$stage_started_at" +%s 2>/dev/null) ||
      die 'restore staging metadata has an invalid start time'
    rto_started_at=${RESTORE_RTO_STARTED_AT_UTC:-}
    [ -n "$rto_started_at" ] ||
      die 'independent evidence requires RESTORE_RTO_STARTED_AT_UTC from incident declaration'
    rto_started_epoch=$(date -u -d "$rto_started_at" +%s 2>/dev/null) ||
      die 'RESTORE_RTO_STARTED_AT_UTC is invalid'
    [ "$rto_started_epoch" -le "$stage_started_epoch" ] ||
      die 'RTO start must not be later than the observed Restic staging start'
    [ "$rto_started_epoch" -le "$(date -u +%s)" ] || die 'RTO start must not be in the future'
    RESTORE_STARTED_AT=$(date -u -d "@$rto_started_epoch" +%Y-%m-%dT%H:%M:%SZ)
    RESTORE_STARTED_EPOCH=$rto_started_epoch
    rto_start_scope=incident-declared-to-service-validated
    source_evidence=${RESTORE_SOURCE_EVIDENCE_FILE:-}
    case "$source_evidence" in /*) ;; *) die 'independent evidence requires an absolute RESTORE_SOURCE_EVIDENCE_FILE' ;; esac
    [ -f "$source_evidence" ] && [ ! -L "$source_evidence" ] ||
      die 'independent source snapshot evidence is missing or unsafe'
    [ "$(stat -c '%u' "$source_evidence")" = 0 ] ||
      die 'independent source snapshot evidence must be owned by root'
    case "$(stat -c '%a' "$source_evidence")" in
      400|600) ;;
      *) die 'independent source snapshot evidence must have mode 0400 or 0600' ;;
    esac
    jq -e '.schemaVersion == "1.0.0" and .repositoryCheckPassed == true and
      (.snapshotId | test("^[0-9a-f]{64}$")) and
      (.snapshotTimeUtc | type == "string" and length > 0) and
      (.checkScope | type == "string" and length > 0)' "$source_evidence" >/dev/null ||
      die 'independent source snapshot evidence is invalid or unchecked'
    source_receipt_snapshot=$(jq -r '.snapshotId' "$source_evidence")
    source_receipt_time=$(jq -r '.snapshotTimeUtc' "$source_evidence")
    source_receipt_commit=$(jq -r '.repositoryCommit' "$source_evidence")
    source_receipt_dirty=$(jq -r '.repositoryDirty' "$source_evidence")
    source_receipt_backup=$(jq -r '.backupTimestamp' "$source_evidence")
    source_check_scope=$(jq -r '.checkScope' "$source_evidence")
    [ "$source_receipt_snapshot" = "$source_snapshot_id" ] &&
      [ "$source_receipt_time" = "$source_snapshot_time" ] ||
      die 'source receipt differs from the snapshot actually staged'
    [ "$source_receipt_commit" = "$repository_commit" ] &&
      [ "$source_receipt_dirty" = "$repository_dirty" ] &&
      [ "$source_receipt_backup" = "$(basename -- "$backup_dir")" ] ||
      die 'source receipt differs from the restored backup commit, dirty state, or timestamp'
    source_repository_check_passed=true
  else
    rto_start_scope=local-restore-test-only
    source_repository_check_passed=false
    source_check_scope=
  fi
  evidence_dir=$(dirname -- "$RESTORE_EVIDENCE_OUTPUT")
  install -d -o root -g root -m 0700 "$evidence_dir"
  EVIDENCE_TMP=$(mktemp "$evidence_dir/.last-independent-restore.XXXXXX")
  chmod 0600 "$EVIDENCE_TMP"
  completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  duration_seconds=$(( $(date -u +%s) - RESTORE_STARTED_EPOCH ))
  nextcloud_version=$(jq -r '.versionstring // .version // "unknown"' <<<"$post_repair_status")
  app_versions=$(compose exec -T -u www-data app php occ app:list --output=json \
    | jq '{enabled: (.enabled // {}), disabled: (.disabled // {})}')
  jq -n \
    --arg startedAtUtc "$RESTORE_STARTED_AT" --arg completedAtUtc "$completed_at" \
    --arg rtoStartScope "$rto_start_scope" \
    --argjson durationSeconds "$duration_seconds" --arg restoreHost "$(hostname)" \
    --arg stageDirectory "$evidence_stage" \
    --arg sourceSnapshotId "$source_snapshot_id" --arg sourceSnapshotTimeUtc "$source_snapshot_time" \
    --argjson sourceRepositoryCheckPassed "$source_repository_check_passed" \
    --arg sourceCheckScope "$source_check_scope" \
    --arg repositoryCommit "$repository_commit" --argjson repositoryDirty "$repository_dirty" \
    --arg backupTimestamp "$(basename -- "$backup_dir")" \
    --argjson independentInfrastructure "$independent" --arg hrLite "$HR_OBJECT_RESULT" \
    --arg intranetLite "$INTRANET_OBJECT_RESULT" --arg nextcloudVersion "$nextcloud_version" \
    --argjson appVersions "$app_versions" \
    '{schemaVersion: "1.0.0", startedAtUtc: $startedAtUtc, completedAtUtc: $completedAtUtc,
      rtoStartScope: $rtoStartScope,
      durationSeconds: $durationSeconds, restoreHost: $restoreHost,
      stageDirectory: $stageDirectory,
      sourceSnapshotId: $sourceSnapshotId,
      sourceSnapshotTimeUtc: (if $sourceSnapshotTimeUtc == "" then null else $sourceSnapshotTimeUtc end),
      sourceRepositoryCheckPassed: $sourceRepositoryCheckPassed,
      sourceCheckScope: (if $sourceCheckScope == "" then null else $sourceCheckScope end),
      repositoryCommit: $repositoryCommit, repositoryDirty: $repositoryDirty,
      backupTimestamp: $backupTimestamp, independentInfrastructure: $independentInfrastructure,
      checks: {checksums: true, archivePaths: true, occ: true, repair: true,
        coreIntegrity: true, database: true, redis: true, cron: true,
        webdavRoundtrip: true, shares: true},
      nextcloud: {version: $nextcloudVersion, apps: $appVersions},
      optionalObjects: {hrLite: $hrLite, intranetLite: $intranetLite},
      cleanupRecorded: false}' >"$EVIDENCE_TMP"
  mv -- "$EVIDENCE_TMP" "$RESTORE_EVIDENCE_OUTPUT"
  EVIDENCE_TMP=
  chmod 0600 "$RESTORE_EVIDENCE_OUTPUT"
  printf 'restore-test: secret-redacted receipt written to %s; cleanup is not yet recorded\n' \
    "$RESTORE_EVIDENCE_OUTPUT"
fi

printf 'restore-test: empty-target restore, repair, cron, and optional WebDAV/share proof passed for %s\n' "$(basename -- "$backup_dir")"
