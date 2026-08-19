# Codex execution guide: Essentials+ Office

Work in the private repository `itmitalles-de/essentials-office`. The visible
product name is **Essentials+ Office**. Preserve every compatibility identifier
listed in `docs/COMPATIBILITY_IDENTIFIERS.md`, especially
`cloud.itmitalles.de`, `/opt/nextcloud`, `/srv/nextcloud`, `proxy_net`, existing
Compose identities, and the Nextcloud app ID `essentialsplus`.

Before changing anything, inspect Git/PR/Actions state and read `AGENTS.md`,
`.agent/STATE.md`, `.agent/TODO.md`, `README.md`, the verification matrix, and
the affected code. Later merges override dated handoff claims. Do not push to
`main` and do not describe a branch, PR, CI run, or historic NUC observation as
deployed reality.

## Product boundary

- Nextcloud owns files, calendars, contacts, and tasks.
- Collabora, Talk/TURN, and Vaultwarden are separate services and stay off by
  default until their own gates pass.
- Mail is only a Nextcloud IMAP/SMTP integration boundary.
- HR Lite and Intranet Lite stay bounded Nextcloud-native modules.
- Essentials+ Calls is exclusively a disabled external integration.
- No mailcow installation, HPB, OIDC/SSO, migration, public registration,
  Kubernetes, rebranding redesign, new module, or new password-manager feature
  belongs in operating-gate work.

## Operational truth

Production readiness requires independent evidence for the deployed Git
revision, configuration drift, encrypted offsite snapshot, independent restore,
RPO/RTO ownership, real DNS/TLS/ingress, and controlled update/rollback. Use the
eleven non-inheriting classes in `docs/VERIFICATION_MATRIX.md`. Every runtime
claim must state observation UTC, observed host/environment, full commit,
method, and proof boundary.

Run `scripts/collect-deployment-state.sh` read-only on an explicitly authorized
host and compare its redacted output with `scripts/compare-deployment-state.py`.
Never print `.env`, tokens, user names, shares, or file names. Never reset,
pull, update, restart, reload Caddy, or change DNS merely to make a drift report
green.

An encrypted upload is not recovery acceptance. Class 8 requires a real
snapshot restored into an empty host or VM independent of the NUC, including
OCC, repair, database, cron, WebDAV byte roundtrip, share metadata, stable
HR/Intranet assertions when present, evidence receipt, and guarded cleanup.
Follow `docs/operations/OFFSITE_ACCEPTANCE.md`.

Public checks must run from an external network with an explicitly selected
IPv4/IPv6 strategy. Do not point public DNS at a Tailscale address, enable a
Cloudflare proxy automatically, or change DNS/router/Caddy as part of the
check. Shared Caddy must retain every existing site; follow
`docs/operations/CADDY_DRIFT.md` before any authorized reload.

## Validation and handoff

Preserve or strengthen the existing static checks, full-history secret scan,
SBOM generation, exact image/action pins, all-profile Compose rendering,
disposable cleanup, browser assertions, recovery tests, and update-failure
rehearsal. Synthetic success can close only classes 1–7. If external authority,
credentials, infrastructure, or a named operator are absent, finish the safe
tooling/runbook, record the exact blocker, and leave the gate open.

Keep `.agent/STATE.md`, `.agent/TODO.md`, `.agent/DECISIONS.md`, and
`.agent/ARCHITECTURE.md` concise and aligned with current Git and verified
evidence. No secrets, raw inventory, or production user data belong in Git.
