#!/usr/bin/env python3
"""Compare two redacted Essentials+ Office deployment-state reports without mutation."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import sys
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expected", type=pathlib.Path, help="approved expected deployment-state.json")
    parser.add_argument("actual", type=pathlib.Path, help="newly collected deployment-state.json")
    parser.add_argument("--expected-repo-commit", help="override expected.repository.commit")
    parser.add_argument("--max-collection-age-hours", type=float, default=1.0)
    parser.add_argument("--max-backup-age-hours", type=float, default=30.0)
    parser.add_argument("--max-restore-age-hours", type=float, default=2400.0)
    parser.add_argument("--max-rto-hours", type=float, default=8.0)
    parser.add_argument("--output-dir", type=pathlib.Path)
    return parser.parse_args()


def load(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("schemaVersion") != "1.0.0":
        raise ValueError(f"unsupported or missing deployment-state schema: {path}")
    return value


def iso_time(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        result = dt.datetime.fromisoformat(normalized)
    except ValueError:
        try:
            result = dt.datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc)
        except ValueError:
            return None
    if result.tzinfo is None:
        result = result.replace(tzinfo=dt.timezone.utc)
    return result.astimezone(dt.timezone.utc)


def age_hours(now: dt.datetime, value: str | None) -> float | None:
    parsed = iso_time(value)
    if parsed is None:
        return None
    return (now - parsed).total_seconds() / 3600.0


def full_snapshot_id(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def full_commit(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 40
        and all(character in "0123456789abcdef" for character in value)
    )


def image_map(state: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for item in state.get("runtime", {}).get("images", []) or []:
        requested = item.get("requested")
        if isinstance(requested, str):
            result[requested] = {
                "imageId": item.get("imageId"),
                "repoDigests": sorted(item.get("repoDigests") or []),
            }
    return result


def running_image_map(state: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for item in state.get("runtime", {}).get("containers", []) or []:
        service = item.get("service")
        if isinstance(service, str):
            result[service] = {
                "imageReference": item.get("imageReference"),
                "imageId": item.get("imageId"),
            }
    return result


def module_map(state: dict[str, Any]) -> dict[str, dict[str, Any]] | None:
    modules = state.get("nextcloud", {}).get("modules")
    if modules is None:
        return None
    return {
        item["id"]: {
            "version": item.get("version"),
            "state": item.get("state"),
            "desired": item.get("desired"),
            "active": item.get("active"),
        }
        for item in modules
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }


def check(name: str, ok: bool, expected: Any, actual: Any, detail: str) -> dict[str, Any]:
    return {
        "name": name,
        "status": "pass" if ok else "fail",
        "expected": expected,
        "actual": actual,
        "detail": detail,
    }


def compare(expected: dict[str, Any], actual: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    now = dt.datetime.now(dt.timezone.utc)
    collected_at = actual.get("collectedAtUtc")
    collection_age = age_hours(now, collected_at)
    checks: list[dict[str, Any]] = []

    checks.append(check(
        "deployment-state-age",
        collection_age is not None and 0 <= collection_age <= args.max_collection_age_hours,
        {"maxHours": args.max_collection_age_hours},
        {"collectedAtUtc": collected_at, "ageHours": collection_age},
        "The actual read-only collection must be current and must not have a future timestamp.",
    ))

    expected_commit = args.expected_repo_commit or expected.get("repository", {}).get("commit")
    actual_commit = actual.get("repository", {}).get("commit")
    checks.append(check(
        "repository-commit",
        full_commit(expected_commit) and actual_commit == expected_commit,
        expected_commit,
        actual_commit,
        "The deployed checkout must equal the explicitly approved commit.",
    ))
    checks.append(check(
        "repository-clean",
        actual.get("repository", {}).get("dirty") is False,
        False,
        actual.get("repository", {}).get("dirty"),
        "A dirty deployment is reported, never reset automatically.",
    ))

    expected_compose = {
        "redacted": expected.get("compose", {}).get("renderedSha256"),
        "effective": expected.get("compose", {}).get("effectiveConfigurationSha256"),
    }
    actual_compose = {
        "redacted": actual.get("compose", {}).get("renderedSha256"),
        "effective": actual.get("compose", {}).get("effectiveConfigurationSha256"),
    }
    checks.append(check(
        "compose-drift",
        all(expected_compose.values()) and actual_compose == expected_compose,
        expected_compose,
        actual_compose,
        "The redacted render and protected whole-configuration fingerprint must both match.",
    ))

    expected_images = image_map(expected)
    actual_images = image_map(actual)
    checks.append(check(
        "image-drift",
        bool(expected_images) and actual_images == expected_images,
        expected_images,
        actual_images,
        "Requested pins, local image IDs, and repository digests must match.",
    ))

    expected_running_images = running_image_map(expected)
    actual_running_images = running_image_map(actual)
    checks.append(check(
        "running-image-drift",
        bool(expected_running_images) and actual_running_images == expected_running_images,
        expected_running_images,
        actual_running_images,
        "Actual per-service container image references and IDs must match the accepted runtime.",
    ))

    expected_modules = module_map(expected)
    actual_modules = module_map(actual)
    checks.append(check(
        "module-drift",
        bool(expected_modules) and actual_modules == expected_modules,
        expected_modules,
        actual_modules,
        "Module version, state, desired state, and active state are compared without configuration values.",
    ))

    expected_caddy = expected.get("caddy", {})
    actual_caddy = actual.get("caddy", {})
    caddy_ok = (
        actual_caddy.get("diskRuntime") == "match"
        and actual_caddy.get("runtimeHasExpectedHost") is True
        and actual_caddy.get("runtimeHasExpectedUpstream") is True
        and actual_caddy.get("expectedRoute") == expected_caddy.get("expectedRoute")
        and bool(expected_caddy.get("expectedFragmentHash"))
        and actual_caddy.get("expectedFragmentHash") == expected_caddy.get("expectedFragmentHash")
        and bool(expected_caddy.get("runtimeHash"))
        and actual_caddy.get("runtimeHash") == expected_caddy.get("runtimeHash")
    )
    checks.append(check(
        "caddy-drift",
        caddy_ok,
        {
            "runtimeHash": expected_caddy.get("runtimeHash"),
            "expectedFragmentHash": expected_caddy.get("expectedFragmentHash"),
            "route": expected_caddy.get("expectedRoute"),
            "diskRuntime": "match",
        },
        {
            "runtimeHash": actual_caddy.get("runtimeHash"),
            "expectedFragmentHash": actual_caddy.get("expectedFragmentHash"),
            "route": actual_caddy.get("expectedRoute"),
            "diskRuntime": actual_caddy.get("diskRuntime"),
            "hostPresent": actual_caddy.get("runtimeHasExpectedHost"),
            "upstreamPresent": actual_caddy.get("runtimeHasExpectedUpstream"),
        },
        "A baseline hash, matching disk/runtime state, hostname, and upstream are all required.",
    ))

    backup = actual.get("backup", {})
    offsite = backup.get("offsite") or {}
    local = backup.get("local") or {}
    backup_time = offsite.get("snapshotTimeUtc") or local.get("latest")
    backup_source = "offsite" if offsite.get("snapshotTimeUtc") else "local-fallback"
    backup_age = age_hours(now, backup_time)
    offsite_ok = (
        backup_source == "offsite"
        and full_snapshot_id(offsite.get("snapshotId"))
        and offsite.get("repositoryCheckPassed") is True
        and isinstance(offsite.get("checkScope"), str)
        and bool(offsite.get("checkScope"))
        and full_commit(actual_commit)
        and offsite.get("repositoryCommit") == actual_commit
        and offsite.get("repositoryDirty") is False
        and isinstance(actual.get("host"), str)
        and bool(actual.get("host"))
        and offsite.get("sourceHost") == actual.get("host")
        and backup_age is not None
        and 0 <= backup_age <= args.max_backup_age_hours
    )
    checks.append(check(
        "backup-age",
        offsite_ok,
        {
            "source": "checked-offsite-receipt",
            "maxHours": args.max_backup_age_hours,
            "repositoryCommit": actual_commit,
            "sourceHost": actual.get("host"),
        },
        {
            "source": backup_source,
            "snapshotId": offsite.get("snapshotId"),
            "timestamp": backup_time,
            "ageHours": backup_age,
            "repositoryCheckPassed": offsite.get("repositoryCheckPassed"),
            "repositoryCommit": offsite.get("repositoryCommit"),
            "repositoryDirty": offsite.get("repositoryDirty"),
            "sourceHost": offsite.get("sourceHost"),
        },
        "A checked offsite receipt tied to this host and commit is required; a local backup or snapshot listing is insufficient.",
    ))

    restore = backup.get("independentRestore") or {}
    restore_time = restore.get("completedAtUtc")
    restore_age = age_hours(now, restore_time)
    restore_duration = restore.get("durationSeconds")
    restore_started = iso_time(restore.get("startedAtUtc"))
    restore_completed = iso_time(restore_time)
    restored_snapshot_time = iso_time(restore.get("sourceSnapshotTimeUtc"))
    nextcloud_evidence = restore.get("nextcloud") or {}
    restore_checks = restore.get("checks") or {}
    required_restore_checks = {
        "checksums", "archivePaths", "occ", "repair", "coreIntegrity",
        "database", "redis", "cron", "webdavRoundtrip", "shares",
    }
    optional_objects = restore.get("optionalObjects") or {}
    restore_ok = (
        restore.get("independentInfrastructure") is True
        and isinstance(restore.get("restoreHost"), str)
        and bool(restore.get("restoreHost"))
        and restore.get("restoreHost") != actual.get("host")
        and full_snapshot_id(restore.get("sourceSnapshotId"))
        and restored_snapshot_time is not None
        and restore_started is not None
        and 0 <= (restore_started - restored_snapshot_time).total_seconds() / 3600.0 <= args.max_backup_age_hours
        and restore.get("sourceRepositoryCheckPassed") is True
        and isinstance(restore.get("sourceCheckScope"), str)
        and bool(restore.get("sourceCheckScope"))
        and restore.get("repositoryCommit") == actual_commit
        and restore.get("repositoryDirty") is False
        and isinstance(restore.get("backupTimestamp"), str)
        and bool(restore.get("backupTimestamp"))
        and restore_age is not None
        and 0 <= restore_age <= args.max_restore_age_hours
        and restore.get("cleanupRecorded") is True
        and required_restore_checks.issubset(restore_checks)
        and all(restore_checks.get(name) is True for name in required_restore_checks)
        and isinstance(nextcloud_evidence.get("version"), str)
        and nextcloud_evidence.get("version") not in ("", "unknown")
        and isinstance(nextcloud_evidence.get("apps"), dict)
        and isinstance(nextcloud_evidence.get("apps", {}).get("enabled"), dict)
        and isinstance(nextcloud_evidence.get("apps", {}).get("disabled"), dict)
        and optional_objects.get("hrLite") in ("passed", "not-present")
        and optional_objects.get("intranetLite") in ("passed", "not-present")
    )
    checks.append(check(
        "independent-restore-age",
        restore_ok,
        {"independentInfrastructure": True, "maxHours": args.max_restore_age_hours, "cleanupRecorded": True},
        {
            "completedAtUtc": restore_time,
            "ageHours": restore_age,
            "independentInfrastructure": restore.get("independentInfrastructure"),
            "restoreHost": restore.get("restoreHost"),
            "sourceSnapshotId": restore.get("sourceSnapshotId"),
            "sourceSnapshotTimeUtc": restore.get("sourceSnapshotTimeUtc"),
            "sourceRepositoryCheckPassed": restore.get("sourceRepositoryCheckPassed"),
            "sourceCheckScope": restore.get("sourceCheckScope"),
            "repositoryCommit": restore.get("repositoryCommit"),
            "repositoryDirty": restore.get("repositoryDirty"),
            "cleanupRecorded": restore.get("cleanupRecorded"),
        },
        "Only a complete independent restore receipt satisfies this gate.",
    ))
    rto_hours = (
        restore_duration / 3600.0
        if isinstance(restore_duration, (int, float)) and restore_duration >= 0
        else None
    )
    calculated_duration = (
        (restore_completed - restore_started).total_seconds()
        if restore_started is not None and restore_completed is not None
        else None
    )
    duration_consistent = (
        isinstance(restore_duration, (int, float))
        and calculated_duration is not None
        and calculated_duration >= 0
        and abs(calculated_duration - restore_duration) <= 1
    )
    checks.append(check(
        "restore-rto",
        rto_hours is not None and rto_hours <= args.max_rto_hours
        and duration_consistent
        and restore.get("rtoStartScope") == "incident-declared-to-service-validated",
        {"maxHours": args.max_rto_hours, "scope": "incident-declared-to-service-validated"},
        {"durationSeconds": restore_duration, "durationHours": rto_hours,
         "calculatedDurationSeconds": calculated_duration,
         "scope": restore.get("rtoStartScope")},
        "The independent restore receipt must demonstrate the approved RTO.",
    ))

    failed = [item["name"] for item in checks if item["status"] != "pass"]
    return {
        "schemaVersion": "1.0.0",
        "comparedAtUtc": now.isoformat().replace("+00:00", "Z"),
        "expectedReport": str(args.expected),
        "actualReport": str(args.actual),
        "result": "pass" if not failed else "fail",
        "failedChecks": failed,
        "checks": checks,
    }


def render_markdown(result: dict[str, Any]) -> str:
    lines = [
        "# Essentials+ Office deployment drift",
        "",
        f"- Compared (UTC): `{result['comparedAtUtc']}`",
        f"- Result: **{result['result']}**",
        "",
        "| Check | Result | Detail |",
        "| --- | --- | --- |",
    ]
    for item in result["checks"]:
        lines.append(f"| {item['name']} | {item['status']} | {item['detail']} |")
    lines.extend([
        "",
        "A failed report is evidence of drift, staleness, or missing evidence. This tool changes nothing.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    if (args.max_collection_age_hours <= 0 or args.max_backup_age_hours <= 0
            or args.max_restore_age_hours <= 0 or args.max_rto_hours <= 0):
        raise ValueError("age and RTO thresholds must be greater than zero")
    expected = load(args.expected)
    actual = load(args.actual)
    result = compare(expected, actual, args)
    payload = json.dumps(result, indent=2, sort_keys=True) + "\n"

    if args.output_dir is None:
        sys.stdout.write(payload)
    else:
        args.output_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        if any(args.output_dir.iterdir()):
            raise ValueError(f"output directory must be empty: {args.output_dir}")
        json_path = args.output_dir / "deployment-drift.json"
        markdown_path = args.output_dir / "deployment-drift.md"
        checksum_path = args.output_dir / "deployment-drift.sha256"
        json_path.write_text(payload, encoding="utf-8")
        markdown_path.write_text(render_markdown(result), encoding="utf-8")
        checksum_lines = []
        for path in (json_path, markdown_path):
            checksum_lines.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}")
            path.chmod(0o600)
        checksum_path.write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")
        checksum_path.chmod(0o600)
        print(f"compare-deployment-state: wrote {args.output_dir}")
    return 0 if result["result"] == "pass" else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"compare-deployment-state: {error}", file=sys.stderr)
        raise SystemExit(2)
