# Office architecture handoff

This is a concise navigation map of the implemented default-branch architecture.
Use `README.md` for operational detail and `docs/ARCHITECTURE.md` for the
authoritative product capability map, boundaries, and staged rollout.

## Overview

`main` contains a Compose-managed Nextcloud core for a shared NUC. The product
is **Office** under Essentials Plus; optional modules are defined in
`office-modules.json` and remain independent:

```text
public DNS / external network
            |
      shared Caddy :443
            | proxy_net
      nextcloud-app :80
        /          \
 internal backend   egress
    /       \
PostgreSQL  Redis       cron -> backend + egress
```

Caddy is outside this repository. The application and cron share the Nextcloud
filesystem. PostgreSQL and Redis use an internal Docker network and expose no
host ports.

## Implementation status

| Area | State on `main` | Source |
| --- | --- | --- |
| Nextcloud 34 + cron | Implemented; last host verification recorded 2026-08-12 | `compose.yaml`, `README.md` |
| PostgreSQL 17 + Redis 7 | Implemented and internal-only | `compose.yaml` |
| Shared Caddy route | Example committed; live drift/public path unresolved | `Caddyfile.example`, `README.md` |
| Local backup/update/health | Implemented; local backup and core checks recorded tested | `scripts/` |
| Namecheap IPv4 DDNS | Tooling implemented; recorded host timer disabled | `scripts/namecheap-ddns.sh`, `systemd/` |
| Office Admin Center | Contract/catalog/preflight/deactivation helpers implemented; no live Collective recorded | `office-modules.json`, `docs/office/ADMIN_CENTER.md` |
| Vaultwarden | Pinned optional profile, private Caddy example, backup/restore test implemented; inactive/unverified on NUC | `compose.vaultwarden.yaml`, `docs/office/VAULTWARDEN.md` |
| HR Lite | Synthetic templates/reconciler/verification implemented; inactive/unverified on NUC | `hr-lite/`, `docs/office/HR_LITE.md` |
| Intranet Lite | Optional Nextcloud-native reconciliation/manual target state implemented; inactive | `docs/office/INTRANET_LITE.md` |
| Visual PBX | Disabled link/health contract only; no PBX service/proxy | `docs/integrations/VISUAL_PBX.md` |
| Offsite restore automation | Proposed in draft PR #1; not on `main` | `.agent/STATE.md` |
| Declarative apps, Collabora, Talk/TURN | Planned/proposed; not on `main` | `docs/ARCHITECTURE.md`, PR #1 |
| mailcow | Planned separate subsystem; not implemented here | `docs/ARCHITECTURE.md` |
| OIDC/SSO | Later plan only | `docs/ARCHITECTURE.md` |

Do not use manifests from an unmerged branch as evidence that a module is
deployed or operationally validated.

## Components and data flow

- `app`: Apache-based Nextcloud, connected to database/cache, egress, and Caddy.
- `cron`: the supported Nextcloud cron entrypoint; no proxy access is required.
- `db`: canonical Nextcloud relational data in PostgreSQL.
- `redis`: cache/locking service with append-only persistence and authentication.
- shared Caddy: TLS, DAV redirects, and reverse proxy to `nextcloud-app:80`.

Files enter through Caddy and Nextcloud. Nextcloud stores file content below its
persistent filesystem and metadata in PostgreSQL; Redis supports locking/cache.
The backup script places Nextcloud in maintenance mode, stops cron, uses
`pg_dump`, and archives the filesystem instead of copying live database files.

## Deployment and persistence

- Repository checkout on target host: `/opt/nextcloud`
- Persistent root: `/srv/nextcloud`
- Nextcloud application/config: `/srv/nextcloud/html`
- User files: `/srv/nextcloud/data`
- PostgreSQL files: `/srv/nextcloud/postgres`
- Redis AOF: `/srv/nextcloud/redis`
- Local backup output: `/srv/nextcloud/backups`
- Host-local secrets: `/opt/nextcloud/.env`
- Optional Vaultwarden data/backups: `/srv/vaultwarden/data`, `/srv/vaultwarden/backups`
- Optional Vaultwarden secret file: `/opt/nextcloud/.vaultwarden.env`
- Optional DDNS secret: `/etc/namecheap-ddns.env`

Local backups do not protect against host/NVMe loss. A tested restore and
encrypted independently stored backup remain production prerequisites.

## External systems and authentication

- Shared Caddy and public DNS are operational dependencies but managed outside
  this Compose stack.
- Namecheap's native DDNS path updates IPv4 `A` only; it does not provide dynamic
  `AAAA` support.
- Nextcloud's current authentication is the implemented boundary. Central OIDC/
  SSO is planned only after core modules are stable.
- mailcow, if introduced, keeps its own host/lifecycle, persistence, DNS, and
  recovery process; Nextcloud Mail connects over IMAP/SMTP.
- Vaultwarden joins `proxy_net` only in its opt-in profile, publishes no host
  port, uses no Nextcloud database/secret, and must remain private by default.
- Visual PBX remains a separate product with no Office proxy, service, source
  merge, shared database, or credentials. OIDC/SSO/groups mapping are later.

## Validation map

- Static Compose: `docker compose config -q` with a populated safe environment.
- Shell syntax: `bash -n scripts/*.sh`.
- Runtime core: `./scripts/healthcheck.sh` on the configured host.
- File persistence: `./scripts/healthcheck.sh --file-roundtrip`.
- Recovery: follow `README.md` and test on disposable infrastructure.
- Public readiness: verify DNS, TLS, DAV redirects, and external network path.
- Vaultwarden profile: `tests/vaultwarden-backup-restore.sh` uses synthetic
  data and proves startup/health/no host port/consistent backup/empty restore.
- HR Lite: run reconciliation and verification only on an approved disposable
  Nextcloud target; static repository checks cannot prove Forms/Tables UI state.

Module-specific validation belongs with the module and cannot be inferred from
the core health check.

## Important constraints

- Preserve existing paths, proxy network, data, and container boundaries.
- Never expose secrets or real user/mail data in repository artifacts.
- Keep Nextcloud canonical for Calendar, Contacts, and Tasks.
- Introduce modules incrementally; no all-at-once production deployment.
- Treat runtime status as dated evidence and reverify before operational action.
