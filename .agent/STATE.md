# Current State

## Project goal

Operate **Office**, the Essentials Plus collaboration product, as a reproducible
self-hosted platform growing from a stable Nextcloud core through independently
operable modules.

## Current status

- Default branch: `main` at `e810fcf` before this handoff migration.
- The default branch implements the Nextcloud core: Nextcloud 34 Apache,
  PostgreSQL 17, Redis 7, a dedicated cron container, bootstrap/update/backup/
  health scripts, shared-Caddy integration, and optional Namecheap IPv4 DDNS.
- The last runtime state recorded by the repository was verified on 2026-08-12:
  Nextcloud 34.0.2 was installed on the NUC and the four core containers were
  healthy. This migration did not independently inspect the NUC.
- The same recorded state says `cloud.itmitalles.de` was not publicly live.
- No open GitHub issues were present when this handoff was written.
- The repository name and deployment paths remain unchanged; no repository
  rename, DNS, NUC, Caddy, or real-account change was performed in this stage.

## Working

- Compose isolates PostgreSQL and Redis on the internal `backend` network.
- The app reaches shared Caddy through external `proxy_net`; app and cron use a
  separate egress network.
- Bootstrap preserves existing secrets/data, creates missing paths, derives the
  trusted proxy CIDR, and validates Compose.
- Local consistent backup creation, cron execution, app restart persistence,
  and core health checks are recorded as tested on 2026-08-12.
- Namecheap DDNS scripts and systemd units are committed; the recorded host
  timer was intentionally disabled pending local credentials and DNS setup.
- An Essentials Plus module contract and Office Admin Center catalog are
  committed. All optional modules begin inactive. Administrators get the full
  catalog; ordinary users require both a healthy module and group entitlement.
- Vaultwarden `1.37.1` is an optional profile with no host port, a private Caddy
  example, closed signup default, independent SQLite data/secrets/backups, and
  an isolated synthetic startup/health/backup/empty-target-restore test passed
  locally on 2026-08-13. It was not configured on the NUC.
- HR Lite has synthetic templates plus supported OCC/WebDAV/OCS reconciliation
  and verification scripts. Intranet Lite has optional app/group reconciliation.
  Neither was run on a Nextcloud host in this work.
- Visual PBX is represented only by a disabled, credential-free link/health
  contract. No PBX container, public route, or shared data was added.

## Active work

- Draft PR #1, `agent/workspace-suite-iac`, proposes a much larger reproducible
  deployment layer, offsite backup/restore tooling, app reconciliation,
  Collabora/Talk overlays, CI, and mailcow integration guidance.
- None of PR #1 is part of `main` yet. Review and validate it before merge, and
  do not infer that its modules are deployed.

## Recently completed

- Documented Workspace Suite scope, architecture, rollout order, and current
  deployment status.
- Added a safe Namecheap IPv4 DDNS updater and timer installer.
- Added a generic root handoff in `e810fcf`; this migration replaced it with
  the single `.agent/TODO.md` task source.

## Known issues

- Public DNS, genuinely external TCP 80/443 reachability, and shared-Caddy
  configuration reconciliation are not verified complete.
- Local backups share the same NVMe as the service. Restore testing and encrypted
  offsite storage are still required before production data migration.
- The recorded DDNS path supports IPv4 `A` records only; it does not solve a
  changing IPv6 prefix or CGNAT/DS-Lite.
- Collabora, production Talk infrastructure, mailcow, declarative app management,
  and OIDC/SSO are planned or proposed, not implemented on `main`.
- Vaultwarden's private DNS/Caddy integration, Office Admin Center Collective,
  HR Lite Forms/Tables/Deck/Calendar/Collectives target state, Intranet Lite UI
  state, and real user visibility checks are not host-verified.
- Visual PBX cannot be activated until its separate product supplies auth,
  roles, secure SIP secret storage, a health endpoint, and a cleared
  rights/participation/operations position.
- User/group policy, retention, sharing policy, and Dropbox migration planning
  remain undefined.

## Next recommended tasks

1. On an approved disposable target, configure private Vaultwarden Caddy/DNS,
   create a synthetic Web Vault owner/organisation/2FA flow, and prove restore
   with the protected local environment file before enabling an entitlement.
2. Complete and verify Office Admin Center, Intranet Lite, and HR Lite manual UI
   target states with fictional accounts and group-visibility testing.
3. Review draft PR #1 and separately reconcile Caddy/DNS/offsite recovery;
   maintain the distinction between committed code and verified host state.

The authoritative prioritized list is `.agent/TODO.md`.

## Relevant files

- `README.md`: deployment, operations, security, and open operational items
- `docs/ARCHITECTURE.md`: product ownership and rollout order
- `compose.yaml`: implemented core topology on `main`
- `scripts/bootstrap.sh`, `scripts/backup.sh`, `scripts/update.sh`: lifecycle
- `scripts/healthcheck.sh`: host/runtime validation
- `secrets/README.md`: secret-storage boundary
- `Caddyfile.example`: shared-proxy site fragment
- `office-modules.json`: versioned Office module and entitlement contract
- `docs/office/`: Admin Center, Vaultwarden, HR Lite, and Intranet Lite guides
- `docs/integrations/VISUAL_PBX.md`: disabled PBX boundary and release gates

## Validation

- Documentation migration: repository links and referenced paths checked.
- `bash -n scripts/*.sh` is safe to run without a deployment.
- `docker compose config -q` requires a populated local `.env`; use a temporary
  environment derived from `.env.example` for static validation.
- Runtime health, DNS, TLS, restore, and public reachability were not revalidated
  on the NUC during the earlier documentation-only migration.
- On 2026-08-13 the local isolated `tests/vaultwarden-backup-restore.sh` passed:
  pinned profile start/health, no host port, SQLite backup integrity, and empty
  target restore with synthetic data. Static base/overlay Compose, shell syntax,
  contract JSON, and secret scan also passed locally. HR/Office host checks were
  not run because no approved target deployment was supplied.

## Last handoff

2026-08-13: implemented the Office modular contract, inactive Vaultwarden,
HR Lite, Intranet Lite, and Visual PBX boundary. Reconfirm commit/branch and
CI status after committing/pushing this change.
