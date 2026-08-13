# Current State

## Project goal

Operate `cloud.itmitalles.de` as a reproducible, self-hosted Workspace Suite,
growing from a stable Nextcloud core through independently operable modules.

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
- User/group policy, retention, sharing policy, and Dropbox migration planning
  remain undefined.

## Next recommended tasks

1. Review and validate draft PR #1 without conflating committed IaC with verified
   runtime state; merge only the independently safe stages.
2. Reconcile shared Caddy, DNS, and router reachability from an external network.
3. Establish encrypted offsite backup and execute a documented disposable restore.

The authoritative prioritized list is `.agent/TODO.md`.

## Relevant files

- `README.md`: deployment, operations, security, and open operational items
- `docs/ARCHITECTURE.md`: product ownership and rollout order
- `compose.yaml`: implemented core topology on `main`
- `scripts/bootstrap.sh`, `scripts/backup.sh`, `scripts/update.sh`: lifecycle
- `scripts/healthcheck.sh`: host/runtime validation
- `secrets/README.md`: secret-storage boundary
- `Caddyfile.example`: shared-proxy site fragment

## Validation

- Documentation migration: repository links and referenced paths checked.
- `bash -n scripts/*.sh` is safe to run without a deployment.
- `docker compose config -q` requires a populated local `.env`; use a temporary
  environment derived from `.env.example` for static validation.
- Runtime health, DNS, TLS, restore, and public reachability were not revalidated
  during this documentation-only migration.

## Last handoff

2026-08-13: introduced the persistent `.agent/` workflow and migrated the old
generic root `TODO.md`. Reconfirm commit/branch identifiers after this commit.
