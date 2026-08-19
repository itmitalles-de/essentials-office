# Essentials+ Office architecture handoff

Use `docs/ARCHITECTURE.md` for the product map and
`docs/COMPATIBILITY_IDENTIFIERS.md` for stable runtime identities. This file is
the concise operational navigation map for the current branch.

## Core topology

```text
public DNS / external network (currently not live)
                    |
            shared Caddy :443
                    | proxy_net
            nextcloud-app :80
             /              \
    internal backend        egress
       /       \               |
 PostgreSQL   Redis           cron
```

Caddy is separately operated. PostgreSQL and Redis expose no product host port.
The app and cron share the Nextcloud filesystem. `/opt/nextcloud`,
`/srv/nextcloud`, `proxy_net`, Compose/service identities, and
`cloud.itmitalles.de` are compatibility identifiers, not stale branding.

## Product boundaries

- Nextcloud is the core for files, calendar, contacts, and tasks.
- Collabora, Talk/TURN, and Vaultwarden are separate services with independent
  lifecycle/data boundaries and inactive defaults.
- Mail is only an IMAP/SMTP integration boundary.
- HR Lite and Intranet Lite are bounded Nextcloud-native modules.
- Essentials+ Calls is only a disabled external integration.
- Only `nextcloud-core` is default-enabled in `office-modules.json`.
- No module controls Docker, systemd, DNS, Caddy, firewall, or destructive data
  deletion through the Nextcloud app.

## Persistence and recovery

- checkout: `/opt/nextcloud`
- Nextcloud data root: `/srv/nextcloud`
- local backups: `/srv/nextcloud/backups`
- host secrets: `/opt/nextcloud/.env`
- optional Vaultwarden: separate `/srv/vaultwarden` and secret file
- offsite/restore evidence: root-only files below
  `/var/lib/essentials-office/evidence`

`scripts/backup.sh` takes a logical PostgreSQL dump and archives Nextcloud
`html`/`data` under maintenance. Redis is recreated empty. A local backup and a
temporary Restic roundtrip do not close recovery acceptance. Class 8 requires a
real encrypted snapshot and empty-target restore on infrastructure independent
of the NUC.

## Drift and public boundary

`scripts/collect-deployment-state.sh` creates a secret-redacted, read-only
JSON/Markdown/SHA report. It covers Git, redacted/effective Compose fingerprints,
configured and actually running image IDs/digests, mounts, health/restarts,
Nextcloud/app/module/database/cron state,
capacity, backup/restore evidence, and Caddy hashes/route. The comparator fails
closed on missing or stale evidence and changes nothing.

The shared Caddy fragment is an expected route only. No reload is permitted
until the complete on-disk configuration validates, canonical disk/runtime
state matches, the intended host/upstream exists, and all unrelated sites are
protected. Public DNS/TLS/HTTP/DAV must be checked separately from an external
network for the declared address-family strategy.

## Current evidence boundary

- Current local classes 1–2 pass at exact code head
  `2a26fc9c1df1c016294b2f83f57b87ad62fabfc7`; Actions run `32203617530` is
  the passing corresponding class 1–7 acceptance source.
- Historical classes 1–7 passed in Actions run `31730633740` at `520c239`.
- Latest `main` run `31735217485` at `17081f2` timed out only in the Admin
  Center browser step; exact-code-head run `32203617530` passed the bounded
  Admin Center browser flow.
- Historical NUC observation: 2026-08-13, host recorded only as `NUC`, clean
  commit `3888bae`; current NUC access/revision/drift unknown.
- External ingress observation: 2026-08-19T00:39:49Z from clean `5bc726c`, no
  `A` or `AAAA`; not publicly live.
- No real offsite snapshot, independent restore, approved RPO/RTO owner, or
  production acceptance exists.

Optional module evidence never substitutes for these core operating gates.
