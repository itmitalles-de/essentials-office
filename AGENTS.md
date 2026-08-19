# Repository agent guide

## Purpose and boundaries

This repository deploys **Essentials+ Office**, currently a reproducible
Nextcloud core for `cloud.itmitalles.de`. The repository is persistent project
memory; a chat or agent session is temporary working memory.

Files, Calendar, Contacts, Tasks, and the existing default-inactive modules are
in scope. Mail is only an external IMAP/SMTP integration boundary. mailcow,
HPB, OIDC/SSO, migrations, public registration, and new modules are out of
scope while the operating and recovery gates remain open.

## Startup

1. Inspect `git status` and preserve all existing worktree changes.
2. Read `.agent/STATE.md` for the last verified repository and runtime state.
3. Read `.agent/TODO.md` when continuing existing work.
4. Read `.agent/DECISIONS.md` or `.agent/ARCHITECTURE.md` only when relevant.
5. Inspect recent relevant commits and the specific implementation area needed.
6. Check open pull requests before treating branch-only work as implemented.

For broad product work, read `README.md` and `docs/ARCHITECTURE.md`. Demand-load
operational documents and scripts only for the component being changed.

## Current operational boundary

- Preserve the existing Nextcloud 34, PostgreSQL 17, Redis 7, and cron core.
- Preserve `/opt/nextcloud`, `/srv/nextcloud`, shared Caddy, and `proxy_net`.
- Treat runtime facts in documentation as dated observations, not live proof.
- Keep `implemented`, `planned`, and `blocked` states explicit.
- Do not adopt Nextcloud AIO without a migration comparison, rollback, and an
  explicit durable decision.
- Do not perform automatic major-version upgrades.

## Safety and data

- Never commit `.env`, credentials, private keys, backups, mailboxes, or user data.
- Keep generated service secrets local and mode `0600`; see `secrets/README.md`.
- Before persistent-data changes, define backup, restore, and rollback steps.
- Do not recursively change ownership on a populated data tree.
- Do not expose PostgreSQL or Redis host ports.
- Reconcile the complete shared Caddy configuration before any reload.
- Keep demo data fictional and demo mail delivery non-production.

## Working conventions

- Inspect before editing and preserve the existing deployment topology.
- Do not add product modules until deployed revision, drift, independent
  offsite recovery, RPO/RTO ownership, ingress, and update/rollback are accepted.
- Keep Mail provider-neutral and limited to an IMAP/SMTP integration boundary;
  do not install or operate a mail platform from this repository.
- Keep Nextcloud canonical for calendars, contacts, and tasks.
- Use targeted `rg` searches and narrow file reads.
- Avoid recursive documentation ingestion, giant log dumps, and rereading large
  files when a focused excerpt is sufficient.
- Run scoped checks first. Use isolated or subagent investigations, where
  supported, only for large independent areas such as mail or Talk.
- Record durable findings in `.agent/` rather than leaving them only in chat.

## Validation

Use checks proportional to the change:

- `docker compose config -q`
- `bash -n scripts/*.sh`
- `./scripts/healthcheck.sh` on the configured host
- `./scripts/healthcheck.sh --file-roundtrip` for an authenticated persistence test

For operational changes, also test restart persistence and the documented
rollback. DNS, TLS, DAV, Talk, TURN, Collabora, and mail checks require their
component-specific external tests; do not claim them from static validation.

## Handoff

Before ending substantial work:

1. Validate the changed scope and record what was actually run.
2. Update `.agent/STATE.md` with concise verified reality.
3. Update `.agent/TODO.md`, the authoritative repository task handoff.
4. Record a durable decision in `.agent/DECISIONS.md` only when one was made.
5. Update `.agent/ARCHITECTURE.md` only when the implemented architecture changed.

Assume the next session has no useful memory of the current conversation.

When visible context use reaches roughly 50-70%, prefer a coherent stopping
point, validate it, update the handoff, and continue in a fresh session. Do not
interrupt an atomic change merely to satisfy that guideline.

For an unspecified continuation request, read the state and TODO, inspect Git
status and recent relevant commits, then continue the highest-priority unfinished
task without redoing completed work.
