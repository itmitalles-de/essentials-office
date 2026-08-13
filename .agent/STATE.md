# Current State

## Product and immutable boundaries

The visible product name is **Essentials+ Office**. The repository name,
`cloud.itmitalles.de`, `/opt/nextcloud`, `/srv/nextcloud`, `proxy_net`, internal
volume names, and the default branch remain unchanged.

No real NUC, Caddy, DNS, router, firewall, Namecheap, backup, or user data was
read or changed in this work. Every runtime check described below used isolated,
randomly named disposable Docker resources. Older runtime statements in this
repository are dated evidence only, not a current live verification.

## Branch and pull-request baseline

- Current local branch: `agent/essentials-office-autonomous`.
- The branch incorporates draft PR #1 (`agent/workspace-suite-iac`) and current
  `origin/main`; PR #1 was not merged.
- Baseline commits on this branch before the paused validation stage:
  `bb3d79e`, `b888dcb`, and `b105280`.
- Draft PR #1 had no review threads. Its static CI failure was independently
  traced to ShellCheck SC2015; its history gitleaks job passed at that time.
- The paused stage has not been pushed and PR #1 has not been updated or closed.

## Implemented on this branch

- A versioned `office-modules.json` contract uses the exact states
  `not_installed`, `needs_configuration`, `disabled`, `enabled`, and `degraded`
  and the eight Essentials+ module groups.
- The AGPL Nextcloud app `essentialsplus` provides an administrator-only catalog,
  a permission-filtered user portal, an audited API, OCC list/status/enable/
  disable/doctor/configure/metrics commands, and controlled app reconciliation.
  It does not run arbitrary commands or control Docker, systemd, Caddy, DNS, or
  firewall state. Deactivation does not delete module data or volumes.
- Optional service boundaries remain separate: Collabora, Talk/TURN,
  Vaultwarden, mail integration, and Essentials+ Calls do not share a database
  or secrets with the Nextcloud core.
- Vaultwarden is pinned to `1.37.1` by digest, closed to registration by default,
  has no product host port, and keeps SQLite data, secrets, backup, and restore
  paths separate from Nextcloud.
- Synthetic HR Lite and Intranet Lite fixtures and idempotent OCC/WebDAV/OCS
  reconciliation/verification paths are present. They use fictional identities
  and supported application interfaces, not direct Nextcloud SQL changes.
- Talk TURN configuration no longer places the shared secret in process
  arguments. Redis authentication no longer places its password on the command
  line. Backup metadata now records repository/app/image evidence with secrets
  redacted. Metrics contain health/age/version state but no user data or secrets.
- Essentials+ Calls remains disabled by default and has only an external URL,
  health/version contract. No PBX code, credentials, proxy route, or database
  was added. Mail remains an integration contract, not an embedded mailcow stack.

## Verification evidence (2026-08-13, disposable only)

- `scripts/validate-static.sh` passed before the final Vaultwarden test-harness
  edits: all base/profile/overlay Compose renders, Bash syntax, ShellCheck,
  Python/JavaScript/PHP syntax, JSON/XML, Caddy validation, module invariants,
  unsafe-pattern checks, and update-major policy.
- `actionlint` passed for the expanded CI workflow.
- Isolated Collabora image/health/discovery/restart testing passed. This was not
  a full WOPI document edit test.
- Isolated TURN authenticated allocation and secret-rotation testing passed;
  no host port was published.
- Local TLS fake-service contracts for IMAP/SMTP and Essentials+ Calls passed.
- The closed Vaultwarden product profile became healthy without a host port.
  An earlier version of the isolated SQLite backup/checksum/empty-target restore
  and encrypted temporary Restic roundtrip passed.
- The strengthened Vaultwarden browser run proved TLS enforcement and reached
  successful synthetic account creation (`#/setup-extension`). It was then
  intentionally interrupted at the user's request. Its trap removed the random
  containers, network, data, and secret files.
- An earlier clean disposable Nextcloud core run on this branch passed install,
  declarative app reconciliation, WebDAV byte roundtrip, app restart persistence,
  and a second idempotent deployment. That run predates the latest combined
  HR/Intranet/Talk/recovery hardening.

## Explicitly not completed in this paused stage

- The strengthened Vaultwarden Web Vault flow did **not** yet finish login,
  organization, collection, member-role, and group verification; its subsequent
  SQLite/Restic backup and empty-target restore were therefore not rerun.
- The complete disposable test with browser Admin Center, recovery, HR Lite,
  Intranet Lite, and Talk flags was not run after the latest changes.
- Collabora create/open/edit/reload through WOPI was not automated or verified;
  only service/discovery/restart behavior was tested.
- Real Talk browser media quality, NAT traversal, audio/video, and HPB were not
  tested or claimed. HPB was not implemented.
- Nextcloud Mail account configuration against the fake server and productive
  mail delivery were not verified; only the external TLS health contract exists.
- HR Lite and Intranet Lite app-specific objects that lack stable provisioning
  APIs were not accepted manually. No manual UI acceptance is part of this task.
- Full-history gitleaks, the final static suite after the last edits, and GitHub
  CI for this paused commit have not yet run.
- README/architecture/operations/Codex prompt/changelog branding consolidation,
  `docs/NICE_TO_HAVE.md`, and `docs/VERIFICATION_MATRIX.md` are still unfinished.
- No commit from this paused stage was pushed, no superseding draft PR was
  opened, and no PR was merged.
- Nothing was verified on the NUC, from the public Internet, or in production.

## Resume point

Start with `.agent/TODO.md`. First finish the Vaultwarden browser flow, then run
the complete disposable suite and final scans. Update documentation only from
those results, split any subsequent work into focused commits, push the current
branch, and open a superseding draft PR without merging it.
