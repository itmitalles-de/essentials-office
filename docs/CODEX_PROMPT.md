# Codex execution guide: Office (Essentials Plus)

Work in the private repository `itmitalles-de/cloud.itmitalles.de`. The product
is **Office**, under the Essentials Plus brand. Do not rename the repository as
part of normal implementation work. Read `AGENTS.md`, `.agent/STATE.md`,
`.agent/TODO.md`, `README.md`, `docs/ARCHITECTURE.md`, `compose.yaml`, and the
affected scripts before changing anything. Preserve the existing Nextcloud core
on the NUC, `/opt/nextcloud`, `/srv/nextcloud`, shared Caddy, and `proxy_net`.

## Implemented reality first

Treat `.agent/STATE.md` and current code as truth. Historical completed work in
this document is not an implementation queue. PR #1 is a draft and must not be
described as deployed. Host, DNS, Caddy, NUC, and real-account changes require
an explicitly provided deployment process; do not infer that authority.

## Product contract

Office uses `office-modules.json` as its Essentials Plus module contract:

- Nextcloud is the core for files and canonical calendar, contacts, and tasks.
- Collabora, Talk, Mail/mailcow, Vaultwarden, HR Lite, Intranet Lite, and
  Visual PBX are independent optional modules, never a big-bang Compose stack.
- The Office Admin Center is a restricted Nextcloud Collectives catalog.
  Administrators see all thematic modules; ordinary users see only healthy,
  activated modules explicitly limited to groups they belong to.
- An external service becomes visible only after configuration and a successful
  documented health check. A disabled module never loses its data or volumes.
- Intranet Lite is Collectives, Teams, Dashboard, and Announcement Center;
  never install Wiki.js or BookStack as a parallel default wiki.
- mailcow is a separate upstream stack or host. Never put it in `compose.yaml`.
- Visual PBX remains in `itmitalles-de/visual-pbx`. Office only owns an inactive
  portal/health contract, never PBX source, ports, proxying, credentials, or a
  shared data store.

## Current completed implementation

- The default core remains Nextcloud 34 Apache, PostgreSQL 17, Redis 7, cron,
  shared-Caddy topology, backups, update tooling, health checks, and optional
  Namecheap IPv4 DDNS.
- Vaultwarden has a pinned `1.37.1` optional profile, closed signups, no host
  port, private Caddy fragment, separate secrets/data, health check, consistent
  SQLite backup, empty-target restore, update/rollback guide, and a synthetic
  isolated container-level restore test. It is not enabled on the NUC.
- HR Lite has fictional-only templates, supported OCC/WebDAV/OCS reconciliation,
  group/permission verification, and manual steps for APIs that do not support
  reliable provisioning. It is not configured on the NUC.
- Intranet Lite has the optional app/group reconciler and manual target state;
  it is inactive.
- Visual PBX has a disabled, credential-free integration contract and a test
  that rejects a PBX service or public Caddy proxy in this repository.
- The Office Admin Center contract, grouped catalog, activation preflight, and
  non-destructive deactivation helper are implemented.

## Hard constraints

- Never commit `.env`, generated module files, real user data, mailboxes,
  private keys, backups, SIP credentials, SMTP credentials, or tokens.
- Do not perform automatic Nextcloud major upgrades or migrate to AIO without a
  separate comparison, rollback, and explicit durable decision.
- Nextcloud Passwords is not a group vault; do not introduce Passbolt for the
  web-only Vaultwarden MVP.
- Do not claim GDPR/compliance, 2FA enforcement, external reachability, or
  runtime health unless verified in the actual relevant environment.
- Never use direct SQL writes against Nextcloud. Use OCC, WebDAV, OCS, or a
  documented minimum manual action.
- Do not publish the unprotected Visual PBX proof of concept.

## Validation expectations

- `docker compose config -q` for the base and every new profile/overlay;
- `bash -n scripts/*.sh tests/*.sh` and `./scripts/check-secrets.sh --tracked`;
- runtime start/health/backup/empty-target restore for an isolated Vaultwarden
  profile using synthetic data only;
- idempotent HR Lite reconciliation and group/permission tests on an approved
  disposable Nextcloud instance;
- default-disabled Visual PBX contract check; and
- existing Nextcloud host checks only on the configured host, never faked in CI.

When a component cannot be checked without unavailable deployment authority,
document the exact blocker and do not substitute static success for a runtime
claim. Update `.agent/STATE.md`, `.agent/TODO.md`, and architecture handoff
files to match verified reality before ending substantial work.
