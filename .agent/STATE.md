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
- The consolidated branch was pushed through `d7f70ac`; draft PR #2
  (`Build Essentials+ Office modular control plane`) supersedes PR #1. PR #1
  remains open and unchanged; neither PR was merged. Later CI fixes are local
  until their next successful push.

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

- The final paused-tree `scripts/validate-static.sh` and `git diff --check`
  passed after all edits in this stage:
  all base/profile/overlay Compose renders, Bash syntax, ShellCheck,
  Python/JavaScript/PHP syntax, JSON/XML, Caddy validation, module invariants,
  unsafe-pattern checks, and update-major policy.
- `actionlint` passed for the expanded CI workflow. PR #2's full-history
  Gitleaks job passed at commit `d7f70ac`.
- Isolated Collabora image/health/discovery/restart testing passed. This was not
  a full WOPI document edit test.
- Isolated TURN authenticated allocation and secret-rotation testing passed;
  no host port was published.
- Local TLS fake-service contracts for IMAP/SMTP and Essentials+ Calls passed.
- The closed Vaultwarden product profile became healthy without a host port.
  The strengthened TLS Web Vault flow passed with two synthetic accounts,
  organization, collection, Owner/User roles, and an organization group. Its
  consistent SQLite backup, checksum validation, encrypted temporary Restic
  roundtrip, and restore into an empty target also passed. The product default
  remains closed registration; only the isolated browser fixture opens it.
- Targeted disposable HR Lite reconciliation and verification passed twice,
  including the fictional workflow and least-privilege WebDAV checks. Targeted
  Intranet Lite reconciliation passed twice, including fictional content,
  editor/reader roles, the confidential-area boundary, and OCS search-provider
  availability. These targeted runs do not replace the pending combined
  backup/restore and deactivation-preservation run.
- The module-control run exposed an overly broad secret-name rejection for the
  declared boolean Calls attestation `sipCredentialStorageReady`. The command
  now relies on the manifest schema's declared typed keys as its allow-list;
  undeclared secret-bearing input remains rejected by the automated test.
- An earlier clean disposable Nextcloud core run on this branch passed install,
  declarative app reconciliation, WebDAV byte roundtrip, app restart persistence,
  and a second idempotent deployment. That run predates the latest combined
  HR/Intranet/Talk/recovery hardening.

## Explicitly not completed in this paused stage

- The complete disposable test with browser Admin Center, recovery, HR Lite,
  Intranet Lite, and Talk flags did not finish after the latest changes. It
  passed core/app setup plus targeted HR and Intranet stages, then exposed the
  Calls attestation bug above. That fix was applied, but the subsequent run was
  intentionally interrupted for this pause before module controls, browser E2E,
  Talk, second deployment, persistence, Nextcloud restore, and final cleanup
  assertions could complete.
- Collabora create/open/edit/reload through WOPI was not automated or verified;
  only service/discovery/restart behavior was tested.
- Real Talk browser media quality, NAT traversal, audio/video, and HPB were not
  tested or claimed. HPB was not implemented.
- Nextcloud Mail account configuration against the fake server and productive
  mail delivery were not verified; only the external TLS health contract exists.
- HR Lite and Intranet Lite app-specific objects that lack stable provisioning
  APIs were not accepted manually. No manual UI acceptance is part of this task.
- Full-history gitleaks and GitHub CI for this paused commit have not yet run.
- README/architecture/operations/Codex prompt/changelog branding consolidation,
  `docs/NICE_TO_HAVE.md`, and `docs/VERIFICATION_MATRIX.md` are still unfinished.
- Draft PR #2 is open and deliberately remains a draft. No PR was merged.
- Nothing was verified on the NUC, from the public Internet, or in production.

## Resume point

Start with `.agent/TODO.md`. First rerun the complete disposable suite; the next
unproven boundary is module controls after the `sipCredentialStorageReady` fix,
followed by browser Admin Center, Talk, redeployment, persistence, and recovery.
Then run the final history scan and update documentation only from those results.
Split subsequent work into focused commits, push the current branch to draft PR
#2, and do not merge while required checks or gates are open.
