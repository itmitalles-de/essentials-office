#!/usr/bin/env bash
# Collect a secret-redacted, read-only deployment state as JSON, Markdown, and SHA-256.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUTPUT_DIR=${1:-"$PROJECT_DIR/reports/deployment-state-$STAMP"}
CADDY_PROJECT_DIR=${CADDY_PROJECT_DIR:-/opt/caddy}
EXPECTED_ROUTE=${EXPECTED_ROUTE:-cloud.itmitalles.de}
OFFSITE_EVIDENCE_FILE=${OFFSITE_EVIDENCE_FILE:-/var/lib/essentials-office/evidence/last-offsite-snapshot.json}
RESTORE_EVIDENCE_FILE=${RESTORE_EVIDENCE_FILE:-/var/lib/essentials-office/evidence/last-independent-restore.json}
WORK_DIR=

die() {
  printf 'collect-deployment-state: %s\n' "$*" >&2
  exit 1
}

env_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROJECT_DIR/.env"
}

occ() {
  docker compose exec -T -u www-data app php occ "$@"
}

git_repo() {
  git -c safe.directory="$PROJECT_DIR" -C "$PROJECT_DIR" "$@"
}

cleanup() {
  local status=$?
  if [ -n "$WORK_DIR" ] && [[ "$WORK_DIR" == /tmp/essentials-office-state.* ]]; then
    find "$WORK_DIR" -xdev -depth -delete
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

[ "$#" -le 1 ] || die 'usage: collect-deployment-state.sh [EMPTY_OUTPUT_DIRECTORY]'
for command in awk chmod cmp curl date df docker find git head hostname install jq mktemp mv python3 sed sha256sum sort stat tail tr; do
  command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[ -f "$PROJECT_DIR/.env" ] || die "missing $PROJECT_DIR/.env; run this only on a configured deployment"
case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$PWD/$OUTPUT_DIR" ;;
esac
[ "$OUTPUT_DIR" != / ] || die 'output directory must not be the filesystem root'
if [ -e "$OUTPUT_DIR" ]; then
  [ -d "$OUTPUT_DIR" ] || die "output path exists and is not a directory: $OUTPUT_DIR"
  [ -z "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit)" ] || die "output directory must be empty: $OUTPUT_DIR"
else
  install -d -m 0700 "$OUTPUT_DIR"
fi

cd "$PROJECT_DIR"
docker compose config -q
WORK_DIR=$(mktemp -d /tmp/essentials-office-state.XXXXXX)
chmod 0700 "$WORK_DIR"

collected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
host_name=$(hostname)
if git_repo rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  commit=$(git_repo rev-parse HEAD)
  branch=$(git_repo branch --show-current)
  [ -n "$branch" ] || branch=detached
  if [ -z "$(git_repo status --porcelain)" ]; then
    dirty=false
  else
    dirty=true
  fi
  remote=$(git_repo config --get remote.origin.url 2>/dev/null || printf unknown)
else
  commit=unknown
  branch=unknown
  dirty=null
  remote=unknown
fi
remote=$(printf '%s\n' "$remote" | sed -E \
  -e 's#(https?|ssh)://[^/@]+@#\1://[REDACTED]@#' \
  -e 's#^[^/@:]+@([^:]+:)#[REDACTED]@\1#')

docker compose config --format json >"$WORK_DIR/compose.raw.json"
jq '
  def redact_sensitive:
    walk(
      if type == "object" then
        with_entries(
          if (.key | test("(?i)(password|secret|token|credential|private[_-]?key|api[_-]?key)"))
          then .value = "[REDACTED]"
          else .
          end
        )
      else . end
    );
  .services |= with_entries(
    .value |= (
      if has("environment") then .environment |= with_entries(.value = "[REDACTED]") else . end
      | if has("env_file") then .env_file = ["[REDACTED]"] else . end
    )
  )
  | redact_sensitive
' "$WORK_DIR/compose.raw.json" >"$WORK_DIR/compose.redacted.json"
compose_hash=$(jq -S -c . "$WORK_DIR/compose.redacted.json" | sha256sum | awk '{print $1}')
compose_effective_hash=$(jq -S -c . "$WORK_DIR/compose.raw.json" | sha256sum | awk '{print $1}')
compose_project=$(jq -r '.name // "unknown"' "$WORK_DIR/compose.raw.json")

first_container=$(docker compose ps --all -q | head -n 1 || true)
if [ -n "$first_container" ]; then
  compose_files=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$first_container" 2>/dev/null || true)
fi
compose_files=${compose_files:-${COMPOSE_FILE:-$PROJECT_DIR/compose.yaml}}
printf '%s\n' "$compose_files" | tr ',:' '\n' | jq -R -s 'split("\n") | map(select(length > 0))' >"$WORK_DIR/compose-files.json"

mapfile -t container_ids < <(docker compose ps --all -q)
if [ "${#container_ids[@]}" -gt 0 ]; then
  docker inspect "${container_ids[@]}" | jq '[.[] | {
    name: (.Name | ltrimstr("/")),
    service: (.Config.Labels["com.docker.compose.service"] // "unknown"),
    imageReference: .Config.Image,
    imageId: .Image,
    state: .State.Status,
    health: (.State.Health.Status // "not-configured"),
    restartCount: .RestartCount,
    networks: ((.NetworkSettings.Networks // {}) | keys | sort),
    mountTargets: ([.Mounts[]?.Destination] | unique | sort)
  }] | sort_by(.service, .name)' >"$WORK_DIR/containers.json"
else
  printf '[]\n' >"$WORK_DIR/containers.json"
fi

mapfile -t configured_images < <(docker compose config --images | sort -u)
printf '[]\n' >"$WORK_DIR/images.json"
if [ "${#configured_images[@]}" -gt 0 ]; then
  for image in "${configured_images[@]}"; do
    if docker image inspect "$image" >"$WORK_DIR/image.inspect.json" 2>/dev/null; then
      jq --arg requested "$image" '.[0] | {
        requested: $requested,
        imageId: .Id,
        repoDigests: ((.RepoDigests // []) | sort),
        repoTags: ((.RepoTags // []) | sort)
      }' "$WORK_DIR/image.inspect.json" >"$WORK_DIR/image.item.json"
    else
      jq -n --arg requested "$image" '{requested: $requested, imageId: null, repoDigests: [], repoTags: []}' \
        >"$WORK_DIR/image.item.json"
    fi
    jq --slurpfile item "$WORK_DIR/image.item.json" '. + $item' "$WORK_DIR/images.json" >"$WORK_DIR/images.next.json"
    mv "$WORK_DIR/images.next.json" "$WORK_DIR/images.json"
  done
fi
jq 'sort_by(.requested)' "$WORK_DIR/images.json" >"$WORK_DIR/images.sorted.json"

if occ status --output=json >"$WORK_DIR/occ-status.raw.json" 2>/dev/null; then
  jq '{installed, version, versionstring, edition, maintenance, needsDbUpgrade, productname}' \
    "$WORK_DIR/occ-status.raw.json" >"$WORK_DIR/occ-status.json"
else
  printf 'null\n' >"$WORK_DIR/occ-status.json"
fi
if occ app:list --output=json >"$WORK_DIR/apps.raw.json" 2>/dev/null; then
  jq '{enabled: (.enabled | to_entries | map({id: .key, version: .value}) | sort_by(.id)),
       disabled: (.disabled | to_entries | map({id: .key, version: .value}) | sort_by(.id))}' \
    "$WORK_DIR/apps.raw.json" >"$WORK_DIR/apps.json"
else
  printf 'null\n' >"$WORK_DIR/apps.json"
fi
if occ essentialsplus:module:list --output=json >"$WORK_DIR/modules.raw.json" 2>/dev/null; then
  jq '[.modules[]? | {id, version, state, desired, active,
      health: {ok: .health.ok, fresh: .health.fresh, checkedAt: .health.checkedAt}}] | sort_by(.id)' \
    "$WORK_DIR/modules.raw.json" >"$WORK_DIR/modules.json"
else
  printf 'null\n' >"$WORK_DIR/modules.json"
fi

if docker compose exec -T db sh -ec \
  'exec psql -X -A -t -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  >"$WORK_DIR/database.raw.json" 2>/dev/null <<'SQL'
SELECT json_build_object(
  'serverVersion', current_setting('server_version'),
  'currentSchema', current_schema(),
  'publicTableCount', (SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = 'public'),
  'hasMigrationsTable', to_regclass('public.oc_migrations') IS NOT NULL
);
SQL
then
  jq . "$WORK_DIR/database.raw.json" >"$WORK_DIR/database.json" 2>/dev/null || printf 'null\n' >"$WORK_DIR/database.json"
else
  printf 'null\n' >"$WORK_DIR/database.json"
fi

background_mode=$(occ config:app:get core backgroundjobs_mode 2>/dev/null || true)
last_cron=$(occ config:app:get core lastcron 2>/dev/null || true)
jq -n --arg mode "$background_mode" --arg last "$last_cron" \
  '{backgroundMode: (if $mode == "" then null else $mode end),
    lastCronEpoch: (if ($last | test("^[0-9]+$")) then ($last | tonumber) else null end)}' \
  >"$WORK_DIR/cron.json"

data_root=$(env_value NEXTCLOUD_DATA_ROOT)
[ -n "$data_root" ] || die 'NEXTCLOUD_DATA_ROOT is empty in .env'
df -P -B1 "$data_root" | awk 'NR == 2 {print $2, $3, $4, $5, $6}' >"$WORK_DIR/df.blocks"
df -P -i "$data_root" | awk 'NR == 2 {print $2, $3, $4, $5, $6}' >"$WORK_DIR/df.inodes"
read -r fs_total fs_used fs_available fs_percent fs_mount <"$WORK_DIR/df.blocks"
read -r inode_total inode_used inode_available inode_percent _inode_mount <"$WORK_DIR/df.inodes"
jq -n \
  --arg dataRoot "$data_root" --arg mount "$fs_mount" \
  --argjson total "$fs_total" --argjson used "$fs_used" --argjson available "$fs_available" \
  --arg percent "$fs_percent" --argjson inodeTotal "$inode_total" --argjson inodeUsed "$inode_used" \
  --argjson inodeAvailable "$inode_available" --arg inodePercent "$inode_percent" \
  '{dataRoot: $dataRoot, mountTarget: $mount,
    bytes: {total: $total, used: $used, available: $available, usedPercent: $percent},
    inodes: {total: $inodeTotal, used: $inodeUsed, available: $inodeAvailable, usedPercent: $inodePercent}}' \
  >"$WORK_DIR/capacity.json"

backup_root="$data_root/backups"
latest_backup=
if [ -d "$backup_root" ]; then
  latest_backup=$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | sort | tail -n 1)
fi
jq -n --arg root "$backup_root" --arg latest "$latest_backup" \
  '{root: $root, latest: (if $latest == "" then null else $latest end)}' >"$WORK_DIR/local-backup.json"

printf 'null\n' >"$WORK_DIR/offsite.json"
if [ -r "$OFFSITE_EVIDENCE_FILE" ] && jq empty "$OFFSITE_EVIDENCE_FILE" >/dev/null 2>&1; then
  jq '{snapshotId, snapshotTimeUtc, sourceHost, repositoryCommit, repositoryDirty, backupTimestamp,
       checkScope, repositoryCheckPassed}' \
    "$OFFSITE_EVIDENCE_FILE" >"$WORK_DIR/offsite.json"
fi

printf 'null\n' >"$WORK_DIR/restore.json"
if [ -r "$RESTORE_EVIDENCE_FILE" ] && jq empty "$RESTORE_EVIDENCE_FILE" >/dev/null 2>&1; then
  jq '{startedAtUtc, completedAtUtc, durationSeconds, rtoStartScope, restoreHost, sourceSnapshotId,
       sourceSnapshotTimeUtc, sourceRepositoryCheckPassed, sourceCheckScope,
       repositoryCommit, repositoryDirty, backupTimestamp, independentInfrastructure, checks,
       nextcloud, optionalObjects, cleanupRecorded}' \
    "$RESTORE_EVIDENCE_FILE" >"$WORK_DIR/restore.json"
fi

jq -n --arg expectedRoute "$EXPECTED_ROUTE" --arg expectedHash "$(sha256sum "$PROJECT_DIR/Caddyfile.example" | awk '{print $1}')" \
  '{projectDirectory: null, composeFile: null, diskHash: null, runtimeHash: null,
    expectedFragmentHash: $expectedHash, diskRuntime: "unavailable",
    expectedRoute: $expectedRoute, diskHasExpectedHost: null,
    runtimeHasExpectedHost: null, runtimeHasExpectedUpstream: null,
    localStatusHttpCode: null, localStatusInstalled: null}' >"$WORK_DIR/caddy.json"

caddy_compose=
caddy_container=
for candidate in compose.yaml docker-compose.yml docker-compose.yaml; do
  if [ -f "$CADDY_PROJECT_DIR/$candidate" ]; then
    caddy_compose="$CADDY_PROJECT_DIR/$candidate"
    break
  fi
done
if [ -n "$caddy_compose" ]; then
  caddy_container=$(docker compose -f "$caddy_compose" ps -q caddy 2>/dev/null || true)
fi
if [ -n "$caddy_compose" ] && [ -n "$caddy_container" ]; then
  disk_runtime=unavailable
  disk_hash=
  runtime_hash=
  disk_host=null
  runtime_host=null
  runtime_upstream=null
  if docker compose -f "$caddy_compose" exec -T caddy \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 \
    && docker compose -f "$caddy_compose" exec -T caddy cat /etc/caddy/Caddyfile >"$WORK_DIR/Caddyfile" 2>/dev/null \
    && docker compose -f "$caddy_compose" exec -T caddy \
      caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile >"$WORK_DIR/caddy-disk.json" 2>/dev/null; then
    disk_hash=$(sha256sum "$WORK_DIR/Caddyfile" | awk '{print $1}')
    jq -S -c . "$WORK_DIR/caddy-disk.json" >"$WORK_DIR/caddy-disk.canonical"
    disk_host=$(jq --arg host "$EXPECTED_ROUTE" '[.. | strings | select(. == $host)] | length > 0' "$WORK_DIR/caddy-disk.json")
    if docker compose -f "$caddy_compose" exec -T caddy \
      wget -qO- http://127.0.0.1:2019/config/ >"$WORK_DIR/caddy-runtime.json" 2>/dev/null; then
      jq -S -c . "$WORK_DIR/caddy-runtime.json" >"$WORK_DIR/caddy-runtime.canonical"
      runtime_hash=$(sha256sum "$WORK_DIR/caddy-runtime.canonical" | awk '{print $1}')
      runtime_host=$(jq --arg host "$EXPECTED_ROUTE" '[.. | strings | select(. == $host)] | length > 0' "$WORK_DIR/caddy-runtime.json")
      runtime_upstream=$(jq '[.. | strings | select(. == "nextcloud-app:80")] | length > 0' "$WORK_DIR/caddy-runtime.json")
      if cmp -s "$WORK_DIR/caddy-disk.canonical" "$WORK_DIR/caddy-runtime.canonical"; then
        disk_runtime=match
      else
        disk_runtime=different
      fi
    fi
  else
    disk_runtime=invalid-on-disk
  fi
  local_code=$(curl --insecure --silent --show-error --output "$WORK_DIR/local-status.json" \
    --write-out '%{http_code}' --resolve "$EXPECTED_ROUTE:443:127.0.0.1" \
    "https://$EXPECTED_ROUTE/status.php" 2>/dev/null || true)
  local_installed=null
  if jq -e '.installed == true' "$WORK_DIR/local-status.json" >/dev/null 2>&1; then
    local_installed=true
  elif [ -s "$WORK_DIR/local-status.json" ]; then
    local_installed=false
  fi
  jq -n \
    --arg projectDirectory "$CADDY_PROJECT_DIR" --arg composeFile "$caddy_compose" \
    --arg diskHash "$disk_hash" --arg runtimeHash "$runtime_hash" \
    --arg expectedHash "$(sha256sum "$PROJECT_DIR/Caddyfile.example" | awk '{print $1}')" \
    --arg diskRuntime "$disk_runtime" --arg expectedRoute "$EXPECTED_ROUTE" \
    --argjson diskHost "$disk_host" --argjson runtimeHost "$runtime_host" \
    --argjson runtimeUpstream "$runtime_upstream" --arg localCode "$local_code" \
    --argjson localInstalled "$local_installed" \
    '{projectDirectory: $projectDirectory, composeFile: $composeFile,
      diskHash: (if $diskHash == "" then null else $diskHash end),
      runtimeHash: (if $runtimeHash == "" then null else $runtimeHash end),
      expectedFragmentHash: $expectedHash, diskRuntime: $diskRuntime,
      expectedRoute: $expectedRoute, diskHasExpectedHost: $diskHost,
      runtimeHasExpectedHost: $runtimeHost, runtimeHasExpectedUpstream: $runtimeUpstream,
      localStatusHttpCode: (if $localCode == "" then null else $localCode end),
      localStatusInstalled: $localInstalled}' >"$WORK_DIR/caddy.json"
elif [ -n "$caddy_compose" ]; then
  jq --arg projectDirectory "$CADDY_PROJECT_DIR" --arg composeFile "$caddy_compose" \
    '.projectDirectory = $projectDirectory | .composeFile = $composeFile |
     .diskRuntime = "runtime-unavailable"' "$WORK_DIR/caddy.json" >"$WORK_DIR/caddy.next.json"
  mv "$WORK_DIR/caddy.next.json" "$WORK_DIR/caddy.json"
fi

jq -n \
  --arg collectedAtUtc "$collected_at" --arg host "$host_name" \
  --arg repoPath "$PROJECT_DIR" --arg commit "$commit" --arg branch "$branch" \
  --argjson dirty "$dirty" --arg remote "$remote" --arg composeProject "$compose_project" \
  --arg composeHash "$compose_hash" --arg composeEffectiveHash "$compose_effective_hash" \
  --slurpfile composeFiles "$WORK_DIR/compose-files.json" \
  --slurpfile rendered "$WORK_DIR/compose.redacted.json" \
  --slurpfile containers "$WORK_DIR/containers.json" \
  --slurpfile images "$WORK_DIR/images.sorted.json" \
  --slurpfile status "$WORK_DIR/occ-status.json" --slurpfile apps "$WORK_DIR/apps.json" \
  --slurpfile modules "$WORK_DIR/modules.json" --slurpfile database "$WORK_DIR/database.json" \
  --slurpfile cron "$WORK_DIR/cron.json" --slurpfile capacity "$WORK_DIR/capacity.json" \
  --slurpfile localBackup "$WORK_DIR/local-backup.json" --slurpfile offsite "$WORK_DIR/offsite.json" \
  --slurpfile restore "$WORK_DIR/restore.json" --slurpfile caddy "$WORK_DIR/caddy.json" \
  '{schemaVersion: "1.0.0", collectedAtUtc: $collectedAtUtc, host: $host,
    repository: {path: $repoPath, commit: $commit, branch: $branch, dirty: $dirty, remote: $remote},
    compose: {project: $composeProject, files: $composeFiles[0],
      renderedSha256: $composeHash, effectiveConfigurationSha256: $composeEffectiveHash,
      rendered: $rendered[0]},
    runtime: {containers: $containers[0], images: $images[0]},
    nextcloud: {status: $status[0], apps: $apps[0], modules: $modules[0], database: $database[0], cron: $cron[0]},
    capacity: $capacity[0],
    backup: {local: $localBackup[0], offsite: $offsite[0], independentRestore: $restore[0]},
    caddy: $caddy[0]}' >"$OUTPUT_DIR/deployment-state.json"

python3 - "$OUTPUT_DIR/deployment-state.json" "$OUTPUT_DIR/deployment-state.md" <<'PY'
import json
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
state = json.loads(source.read_text(encoding="utf-8"))
repo = state["repository"]
containers = state["runtime"]["containers"]
lines = [
    "# Essentials+ Office deployment state",
    "",
    f"- Collected (UTC): `{state['collectedAtUtc']}`",
    f"- Host: `{state['host']}`",
    f"- Repository: `{repo['path']}`",
    f"- Git: `{repo['commit']}` on `{repo['branch']}`, dirty=`{str(repo['dirty']).lower()}`",
    f"- Remote: `{repo['remote']}`",
    f"- Compose project: `{state['compose']['project']}`",
    f"- Redacted Compose SHA-256: `{state['compose']['renderedSha256']}`",
    f"- Effective Compose fingerprint: `{state['compose']['effectiveConfigurationSha256']}`",
    "",
    "## Containers",
    "",
    "| Service | Container | State | Health | Restarts | Image ID |",
    "| --- | --- | --- | --- | ---: | --- |",
]
for item in containers:
    lines.append(
        f"| {item['service']} | {item['name']} | {item['state']} | {item['health']} | "
        f"{item['restartCount']} | `{item['imageId'] or 'unavailable'}` |"
    )
backup = state["backup"]
caddy = state["caddy"]
lines.extend([
    "",
    "## Recovery evidence",
    "",
    f"- Latest local backup: `{backup['local']['latest'] or 'unknown'}`",
    f"- Latest offsite snapshot: `{(backup['offsite'] or {}).get('snapshotId', 'unknown')}`",
    f"- Latest independent restore: `{(backup['independentRestore'] or {}).get('completedAtUtc', 'unknown')}`",
    "",
    "## Caddy and route",
    "",
    f"- Disk/runtime: `{caddy['diskRuntime']}`",
    f"- Disk hash: `{caddy['diskHash'] or 'unknown'}`",
    f"- Runtime hash: `{caddy['runtimeHash'] or 'unknown'}`",
    f"- Expected route: `{caddy['expectedRoute']}`",
    f"- Runtime expected host: `{caddy['runtimeHasExpectedHost']}`",
    f"- Runtime expected upstream: `{caddy['runtimeHasExpectedUpstream']}`",
    f"- Local status route HTTP: `{caddy['localStatusHttpCode'] or 'unknown'}`",
    "",
    "The JSON file is authoritative. Environment values, tokens, credentials, users, shares, and filenames are not collected.",
    "The effective Compose fingerprint covers the unredacted in-memory render but exposes no source values; keep the report protected.",
])
target.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

(
  cd "$OUTPUT_DIR"
  sha256sum deployment-state.json deployment-state.md >deployment-state.sha256
)
chmod 0600 "$OUTPUT_DIR"/deployment-state.json "$OUTPUT_DIR"/deployment-state.md "$OUTPUT_DIR"/deployment-state.sha256
printf 'collect-deployment-state: wrote redacted read-only evidence to %s\n' "$OUTPUT_DIR"
