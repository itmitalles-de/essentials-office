# Dated validation record

The authoritative status model is `docs/VERIFICATION_MATRIX.md`. Evidence does
not inherit between its eleven classes.

## Current branch checks — 2026-08-19

| Field | Value |
| --- | --- |
| Environment | local Codex workspace and GitHub-hosted runner |
| Exact code head | `2a26fc9c1df1c016294b2f83f57b87ad62fabfc7` |
| Method | local `scripts/validate-static.sh`; Actions run `32203617530` |
| Result | all five jobs passed; current synthetic classes 1–7 pass |
| Boundary | synthetic only; not the NUC, independent offsite restore, ingress success, or production |

The static suite passed base/profile/restore Compose renders, Bash/ShellCheck,
Python/JavaScript/PHP/JSON/XML parsing, Caddy validation, module contracts,
exact image/action pin policies, full-history Gitleaks, SBOM pin policy,
deployment-state comparison fixtures, patch/minor/major update policy, and
failed-pull/start/health rollback rehearsal.

A full local disposable run was attempted but did not start because host `sudo`
requires interactive authentication. No password was requested or supplied and
no runtime state changed. Current class 3–7 evidence therefore comes only from
the exact-code-head GitHub Actions run.

The first PR run, `32201954244` at `5bc726c`, passed static validation,
secret-scan, SBOM, and isolated modules but failed in backup. It correctly
stopped cron for consistency and then incorrectly required cron to be running
while collecting image provenance. Commit `6e9ca74` moved app and image
inventory to the backup start, before maintenance and cron stop; no recovery
assertion was removed or weakened.

The subsequent run at `6e9ca74` was superseded when the fully pinned
`actions/upload-artifact` runtime was updated from warning-producing v4.6.2 to
official v7.0.1 at `1102168`.

Run `32202678355` at `1102168` then passed static, secret, SBOM, isolated
modules, backup provenance, module/browser flows, redeployment, and two update
rehearsals. It failed only when the post-update WebDAV persistence probe tried
to reuse its disposable credential from the replaced app container's `/tmp`.
Commit `2a26fc9` reprovisions only that protected synthetic probe credential;
the persisted remote-object byte comparison and deletion remain unchanged.
Run `32203617530` then passed all five jobs at that final code head. Its
`disposable-office` job passed deployment, module and browser flows, read-only
state/redaction, restart persistence, two exact-pin update rehearsals, WebDAV
persistence, consistent backup, encrypted temporary Restic repository and full
read check, empty-target restore with OCC/repair/core/database/Redis/cron/
WebDAV/share/object checks, receipt validation, and guarded cleanup.

## Historical synthetic evidence — 2026-08-13

GitHub Actions run `31730633740` on commit `520c239` passed static validation,
the full-history secret scan, isolated modules, and the combined disposable
Office job. The GitHub-hosted runner used fictional data and proved a clean
Nextcloud deployment, app reconciliation, Admin Center/user browser journey,
HR/Intranet/Talk protocol flows, restart persistence, second-run idempotence,
consistent PostgreSQL/files backup, temporary encrypted Restic repository,
and empty-target restore with OCC, database, Redis, cron, WebDAV bytes, share
metadata, and cleanup.

That is historical class 1–7 evidence. It is neither a real provider snapshot
nor a restore on infrastructure independent of the NUC.

The later `main` Actions run `31735217485` on commit
`17081f20704e77dea6d1c983bdf8f2bde779e8f2` passed all jobs except the Admin
Center browser step, which timed out after earlier disposable assertions. The
current branch preserves those assertions and adds bounded waits and browser
diagnostics; exact-code-head run `32203617530` passed that browser flow.

## Historical NUC evidence — 2026-08-13

The host recorded only as `NUC` was observed read-only at clean commit
`3888bae`. Core health, cron, local backup checksums, same-host disposable
restore, disk/runtime Caddy equality, and absence of PostgreSQL/Redis host ports
were recorded. The intended Caddy route was absent. Details and limitations are
in `docs/operations/NUC_BASELINE.md`.

This is stale class 6 and 9 evidence. The current host alias, deployed commit,
dirty state, image digests, and drift are unknown.

## Current external evidence — 2026-08-19T00:39:49Z

From `external-codex-runner`, `scripts/check-external-ingress.sh` tested
`cloud.itmitalles.de` with expected strategy `either` and certificate name
`cloud.itmitalles.de`, using a clean worktree at
`5bc726c7dedceb0f4d59d2d7d3da22555ead9188`. No `A` or `AAAA` records were
returned, so TCP, TLS, HTTP, DAV, and upload-path checks were not applicable.
The JSON SHA-256 was
`7d8e8018a9b7ce802f2bec021e8c41b1d360551e270bb6e522e33759fd39efb2`.
Result: class 10 fail/not publicly live at that time. `either` was only the
minimum availability probe; the operator has not approved a final strategy.

## Unaccepted gates

- current deployed revision and configuration drift;
- real encrypted offsite snapshot and repository-check receipt;
- independent empty-target restore and timed RTO;
- named operator and approved RPO/RTO;
- successful real DNS/TLS/IPv4/IPv6/HTTP/DAV ingress;
- live update and rollback acceptance;
- production readiness.
