#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
WORK_DIR=$(mktemp -d /tmp/essentials-office-state-compare.XXXXXX)

cleanup() {
  find "$WORK_DIR" -xdev -depth -delete
}
trap cleanup EXIT INT TERM

for command in date jq python3; do
  command -v "$command" >/dev/null 2>&1 || exit 1
done

collected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
snapshot_time=$(date -u -d '11 hours ago' +%Y-%m-%dT%H:%M:%SZ)
restore_time=$(date -u -d '9 days ago' +%Y-%m-%dT%H:%M:%SZ)
restore_started=$(date -u -d '217 hours ago' +%Y-%m-%dT%H:%M:%SZ)
restored_snapshot_time=$(date -u -d '218 hours ago' +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg collectedAt "$collected_at" --arg snapshotTime "$snapshot_time" \
  --arg restoreTime "$restore_time" --arg restoreStarted "$restore_started" \
  --arg restoredSnapshotTime "$restored_snapshot_time" '{
  schemaVersion: "1.0.0",
  collectedAtUtc: $collectedAt,
  host: "source-nuc",
  repository: {commit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", dirty: false},
  compose: {renderedSha256: "compose-redacted-a", effectiveConfigurationSha256: "compose-effective-a"},
  runtime: {
    images: [{requested: "example:1@sha256:abc", imageId: "sha256:abc", repoDigests: ["example@sha256:abc"]}],
    containers: [{service: "app", imageReference: "example:1@sha256:abc", imageId: "sha256:abc"}]
  },
  nextcloud: {modules: [{id: "nextcloud-core", version: "1.0.0", state: "enabled", desired: true, active: true}]},
  backup: {
    local: {latest: "20260819T010000Z"},
    offsite: {
      snapshotId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      snapshotTimeUtc: $snapshotTime, sourceHost: "source-nuc",
      repositoryCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      repositoryDirty: false,
      backupTimestamp: "20260819T010000Z", checkScope: "5%", repositoryCheckPassed: true
    },
    independentRestore: {
      startedAtUtc: $restoreStarted,
      completedAtUtc: $restoreTime,
      durationSeconds: 3600,
      rtoStartScope: "incident-declared-to-service-validated",
      restoreHost: "independent-restore-host",
      sourceSnapshotId: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      sourceSnapshotTimeUtc: $restoredSnapshotTime,
      sourceRepositoryCheckPassed: true,
      sourceCheckScope: "5%",
      repositoryCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      repositoryDirty: false,
      backupTimestamp: "20260810T220000Z",
      independentInfrastructure: true,
      cleanupRecorded: true,
      checks: {checksums: true, archivePaths: true, occ: true, repair: true,
        coreIntegrity: true, database: true, redis: true, cron: true,
        webdavRoundtrip: true, shares: true},
      nextcloud: {version: "34.0.2", apps: {enabled: {}, disabled: {}}},
      optionalObjects: {hrLite: "not-present", intranetLite: "not-present"}
    }
  },
  caddy: {
    runtimeHash: "caddy-a", expectedFragmentHash: "fragment-a",
    expectedRoute: "cloud.itmitalles.de", diskRuntime: "match",
    runtimeHasExpectedHost: true, runtimeHasExpectedUpstream: true
  }
}' >"$WORK_DIR/expected.json"
cp "$WORK_DIR/expected.json" "$WORK_DIR/actual-pass.json"

python3 "$PROJECT_DIR/scripts/compare-deployment-state.py" \
  "$WORK_DIR/expected.json" "$WORK_DIR/actual-pass.json" >"$WORK_DIR/pass.json"
jq -e '.result == "pass" and (.failedChecks | length == 0)' "$WORK_DIR/pass.json" >/dev/null

jq '.collectedAtUtc = "2000-01-01T00:00:00Z"' "$WORK_DIR/actual-pass.json" >"$WORK_DIR/stale.json"
if python3 "$PROJECT_DIR/scripts/compare-deployment-state.py" \
  "$WORK_DIR/expected.json" "$WORK_DIR/stale.json" >"$WORK_DIR/stale-result.json"; then
  printf 'deployment-state-comparison-test: stale collection unexpectedly passed\n' >&2
  exit 1
fi
jq -e '.failedChecks | index("deployment-state-age") != null' "$WORK_DIR/stale-result.json" >/dev/null

jq '
  .repository.commit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  | .repository.dirty = true
  | .compose.effectiveConfigurationSha256 = "compose-effective-b"
  | .runtime.images[0].imageId = "sha256:def"
  | .runtime.containers[0].imageId = "sha256:def"
  | .nextcloud.modules[0].active = false
  | .backup.offsite = null
  | .backup.independentRestore = null
  | .caddy.diskRuntime = "different"
  | .caddy.runtimeHash = "caddy-b"
  | .caddy.runtimeHasExpectedHost = false
' "$WORK_DIR/expected.json" >"$WORK_DIR/actual-fail.json"

if python3 "$PROJECT_DIR/scripts/compare-deployment-state.py" \
  "$WORK_DIR/expected.json" "$WORK_DIR/actual-fail.json" >"$WORK_DIR/fail.json"; then
  printf 'deployment-state-comparison-test: drift unexpectedly passed\n' >&2
  exit 1
fi
jq -e '
  .result == "fail" and
  (["repository-commit", "repository-clean", "compose-drift", "image-drift", "running-image-drift", "module-drift",
    "caddy-drift", "backup-age", "independent-restore-age", "restore-rto"] - .failedChecks | length == 0)
' "$WORK_DIR/fail.json" >/dev/null

printf 'deployment-state-comparison-test: matching state passes and operational drift fails closed\n'
