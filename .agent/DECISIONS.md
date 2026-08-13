# Decisions

Only durable choices that future agents might otherwise revisit belong here.
The product capability map and rollout order remain authoritative in
`docs/ARCHITECTURE.md`.

## 2026-08-12 - Preserve the existing Nextcloud foundation

**Decision:** Keep the current Compose-managed Nextcloud core and its paths;
do not migrate to Nextcloud AIO without a separate comparison, rollback plan,
and explicit approval.

**Reason:** The Nextcloud 34, PostgreSQL, Redis, cron, Caddy, and persistence
layout is already reproducible and recorded as validated on the NUC.

**Alternatives considered:** Replacing the deployment with Nextcloud AIO.

**Consequences:** Changes must preserve `/opt/nextcloud`, `/srv/nextcloud`,
`proxy_net`, and recoverability. Major upgrades are deliberate, one-step events.

## 2026-08-12 - Keep canonical groupware ownership in Nextcloud

**Decision:** Nextcloud is the source of truth for calendars, contacts, and
tasks. SOGo may be a mail/fallback client but not a second canonical groupware.

**Reason:** Split ownership would introduce conflict and unclear recovery.

**Alternatives considered:** Parallel calendar/contact ownership in mailcow/SOGo.

**Consequences:** Integrations synchronize with or display Nextcloud-owned data;
they do not establish another authoritative store.

## 2026-08-12 - Separate module lifecycles

**Decision:** Collabora is a dedicated service; Talk, TURN, and HPB are staged
separately; mailcow remains an independent upstream stack and lifecycle.

**Reason:** The components have distinct upgrades, ports, capacity needs,
security boundaries, and restore procedures.

**Alternatives considered:** A single all-in-one Compose deployment.

**Consequences:** Modules must be optional or separate and independently
startable, updatable, testable, removable, and recoverable.

## 2026-08-12 - Keep service data and secrets outside Git

**Decision:** Persistent service data lives below `/srv/nextcloud`; generated
deployment secrets stay only in host-local protected files and separate secret
management.

**Reason:** Repository history is neither a data volume nor a secret store.

**Alternatives considered:** Committing environment files or backing up only the
Git checkout.

**Consequences:** `.env`, backups, private keys, DDNS credentials, and real user
or mailbox data must never enter commits, issues, logs, or agent-state files.

## 2026-08-12 - Use shared Caddy as the public boundary

**Decision:** The stack does not publish an application port or run another
proxy. Shared Caddy terminates HTTPS and reaches `nextcloud-app` via `proxy_net`.

**Reason:** This matches the NUC's existing multi-service proxy topology and
keeps databases internal.

**Alternatives considered:** A per-project reverse proxy or exposed app port.

**Consequences:** Any Caddy change must reconcile and validate the complete
shared configuration before reload; PostgreSQL and Redis remain unexposed.

## 2026-08-13 - Office modular contract under Essentials Plus

**Decision:** The product is Office under Essentials Plus. Define optional
modules through a versioned contract and a group-restricted Nextcloud Admin
Center rather than a new portal service or all-in-one deployment.

**Reason:** It keeps the existing Nextcloud core stable while making
entitlements, activation health gates, and data-retention behavior explicit.

**Consequences:** Administrators see the complete catalog. Users only see
healthy, activated, group-authorized modules. Deactivation never deletes data
or volumes. Repository/worktree names remain unchanged.

## 2026-08-13 - Vaultwarden remains a private, separate small-tenant module

**Decision:** Add Vaultwarden as a version-pinned optional profile with SQLite,
no host port, private Caddy example, closed signups, separate secret/data paths,
and a SQLite-backup/empty-target-restore procedure.

**Reason:** It satisfies the web-only group-vault MVP without merging data or
secrets into Nextcloud or exposing an unconfigured public service.

**Consequences:** The profile is inactive until a private route, configuration,
health check, and backup/restore validation are complete. Nextcloud Passwords
and Passbolt are not used for this scope.

## 2026-08-13 - Keep workflow and PBX boundaries narrow

**Decision:** HR Lite uses supported Nextcloud functions with synthetic data;
Intranet Lite uses Collectives/Teams/Dashboard/Announcement Center; Visual PBX
remains only a disabled external contract.

**Reason:** The apps lack a stable full provisioning API and the PBX proof of
concept lacks production release gates.

**Consequences:** Manual UI steps are documented and checked by target-state
verification. No SQL hacks, standalone default wiki, PBX proxy, credentials,
or shared data stores are introduced.
