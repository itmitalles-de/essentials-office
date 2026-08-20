# Essentials+ Office

Open-source collaboration and office platform built on the existing Nextcloud
foundation for `cloud.itmitalles.de`. The repository extends that foundation
without replacing its deployment, identity, calendar, storage, or recovery
boundaries.



> The visible product name is **Essentials+ Office**. Historical repository and
> host paths remain unchanged unless a separate operational migration is
> approved.

## Product scope

Essentials+ Office is composed of independently operable modules:

- Nextcloud Files, sharing, versions and sync
- Calendar, Contacts and Tasks as the canonical groupware data store
- Nextcloud Talk; TURN and the high-performance backend are separate production stages
- Nextcloud Office with a dedicated Collabora Online container for browser-based documents, spreadsheets and presentations
- Nextcloud Mail connected to mailcow over IMAP/SMTP
- Appointments (Termine) for tenant-scoped services, availability, public
  booking, resources, reminders, customer-management tokens, and ICS export
- Notes for personal notes, Collectives for shared knowledge, Deck for Kanban, plus Tables and Forms
- mailcow as an independently managed mail subsystem; SOGo is an optional fallback webmail, not a second canonical calendar/contact system
- centralized OIDC/SSO only after the core modules are stable

The current NUC deployment contains only the validated Nextcloud core. This
repository now defines declarative apps, an optional dedicated Collabora
overlay, an optional coturn overlay, encrypted offsite backup automation, and
an isolated restore test. These additions are disabled until their documented
gates pass; their presence in Git does not mean they are deployed. The Talk
high-performance backend remains a later stage. mailcow remains a separately
pinned upstream project and must not be pasted into the Nextcloud Compose file:
it has its own lifecycle, ports, DNS, backups and substantial memory
requirements. A production mail system should use infrastructure with a static
address and controllable PTR/rDNS rather than relying on a residential dynamic
connection.

The repository deliberately contains no secrets and no user data. It deploys
Nextcloud 34 (Apache), PostgreSQL 17, Redis 7, and a dedicated Nextcloud cron
container. Caddy remains a shared, independent reverse-proxy stack on the NUC.

## Current deployment status

Status verified on 2026-08-12:

- The repository is checked out on the NUC at `/opt/nextcloud`; persistent data
  is stored below `/srv/nextcloud`.
- Nextcloud 34.0.2 is installed and outside maintenance mode. The application,
  PostgreSQL, Redis, and cron containers are running; the database and
  application health checks pass.
- Cron execution, local backup creation, and application-container restart
  persistence have been tested. PostgreSQL and Redis publish no host ports.
- The Namecheap DDNS script and systemd units are installed on the NUC, but the
  timer remains disabled until the per-domain DDNS password is entered locally
  and the `cloud` A + Dynamic DNS record exists at Namecheap.
- `https://cloud.itmitalles.de` is **not publicly live**. Public DNS has no
  `cloud` A/AAAA record, router reachability is not yet verified from a truly
  external network, and the shared Caddy configuration must be reconciled
  before its existing configuration is reloaded.
- Local backups exist on the same NVMe. A tested restore plus encrypted offsite
  backup remain mandatory before production data is migrated.
- A 2026-08-13 follow-up authenticated to the NUC, confirmed that public DNS
  still has no `cloud` A/AAAA record, proved Caddy disk/runtime equivalence,
  measured the core, and restored a fresh live backup on isolated disposable
  infrastructure. See [NUC baseline and validation gate](docs/operations/NUC_BASELINE.md).

## Reproducible operations

The base stack remains `compose.yaml`. Optional capabilities are independent:

| Capability | Artifact | Default |
| --- | --- | --- |
| Idempotent core/app deployment | `scripts/deploy.sh --apps` | explicit |
| Encrypted offsite backup | `scripts/offsite-backup.sh` | not scheduled |
| Disposable restore | `scripts/restore-test.sh` | run on demand |
| Declared Nextcloud apps | `scripts/reconcile-apps.sh` | no implicit mutation |
| Dedicated Collabora | `compose.collabora.yaml`, profile `office` | off |
| coturn | `compose.talk-turn.yaml`, profile `talk-turn` | off |
| mailcow | separate upstream checkout pinned by `mailcow/UPSTREAM_COMMIT` | not installed |
| Appointments | native app in `nextcloud-apps/appointments` | optional; public pages off per organization |

Operational runbooks:

- [IaC deployment](docs/operations/IAC_DEPLOYMENT.md)
- [Backup and restore](docs/operations/BACKUP_RESTORE.md)
- [Nextcloud apps](docs/operations/NEXTCLOUD_APPS.md)
- [Collabora](docs/operations/COLLABORA.md)
- [Talk and TURN](docs/operations/TALK.md)
- [mailcow boundary](mailcow/README.md)
- [Fictitious end-to-end demo](docs/operations/DEMO_FLOW.md)
- [Appointments architecture, operation, security, and user guide](docs/appointments.md)
- [Appointments roadmap](docs/roadmap.md)

## Architecture

```text
Internet over IPv4 and/or IPv6
        |
  cloud.itmitalles.de (DNS-only A/AAAA)
        |
  Caddy :443 on proxy_net
        |
  nextcloud-app :80
     |          |
 internal     egress
 backend       network
  |    |
PostgreSQL  Redis
```

`db` and `redis` are attached only to the Docker-internal `backend` network and
do not publish host ports. `app` is attached to `proxy_net` for Caddy and to a
separate non-internal egress network. `cron` uses the internal backend plus the
egress network; it does not need Caddy access. The bootstrap script reads the
real subnet of `proxy_net` and uses it as the narrow `TRUSTED_PROXIES` CIDR.

All persistent service state is below `/srv/nextcloud`:

```text
/srv/nextcloud/
├── html/       Nextcloud code, config, apps, themes
├── data/       user files
├── postgres/   PostgreSQL database files
├── redis/      Redis AOF data
└── backups/    local backup archives
```

## Prerequisites

- Ubuntu host. `scripts/provision-host.sh` installs Docker Engine, Docker
  Compose v2, and the required base tools from the official Docker apt
  repository; `--check` validates an existing host without mutation.
- A shared external Docker network named `proxy_net`, or no network with that
  name. `bootstrap.sh` creates it only when absent.
- Shared Caddy connected to that network and owning host ports 80 and 443.
- DNS administration for `itmitalles.de` and a publicly reachable IPv4 or IPv6
  path to Caddy on TCP 80 and 443. PostgreSQL and Redis require no public
  firewall rule.
- Passwordless `sudo` for the deployment account, only to create and secure
  `/srv/nextcloud` and local backup files.

The deployment is designed for the NUC's shared Caddy setup. It does not run
another proxy and never publishes a Nextcloud application host port.

## Installation

Clone this repository on the NUC at `/opt/nextcloud`, provision the host when
needed, and apply the repository state. The deployment command bootstraps the
host directories and local `.env`, validates Compose, starts the core, waits
for health, enables cron mode, and optionally reconciles all declared apps. It
never replaces an existing `.env` or changes ownership of a non-empty data
directory.

```bash
sudo install -d -m 0755 -o "$USER" -g "$USER" /opt/nextcloud
git clone https://github.com/itmitalles-de/cloud.itmitalles.de.git /opt/nextcloud
cd /opt/nextcloud
sudo ./scripts/provision-host.sh
sudo ./scripts/deploy.sh --apps
```

The internal deploy succeeds without public DNS or Caddy. After DNS and the
separately managed Caddy route are in place, run the external checks:

```bash
./scripts/healthcheck.sh --file-roundtrip
```

Use `sudo ./tests/deploy/run.sh --apps` to prove a clean deployment, all apps,
restart persistence, and a second idempotent deployment with unique temporary
paths and containers. See the [IaC runbook](docs/operations/IAC_DEPLOYMENT.md).

The initial administrator account and its generated password are in the
NUC-local `/opt/nextcloud/.env` (mode `0600`), never in Git. Store an encrypted
copy in secret management before relying on the instance.

## DNS and public reachability

Do not assume a public IPv4 address: DS-Lite and CGNAT are common. Prefer a
DNS-only `AAAA` record for `cloud` pointing to the NUC/reverse proxy's public,
routable IPv6 address. Do not point the record at a Tailscale address.

At the DNS provider, create only this record for the cloud host:

```text
Type: AAAA
Host: cloud
Value: <NUC or reverse-proxy public IPv6>
Mode: DNS only
```

The router must allow inbound IPv6 TCP 80 and 443 to the NUC. The host firewall
must allow those ports as well. Verify from an external IPv6-capable network
before relying on ACME. Caddy then obtains and renews the certificate itself.

### Namecheap Dynamic DNS on the NUC

The domain currently uses Namecheap authoritative DNS. Namecheap's native
Dynamic DNS endpoint updates only an IPv4 `A` record; it cannot update `AAAA`
records. This is useful only when the router itself has a publicly routable
IPv4 address and forwards TCP 80 and 443 to the NUC. An address returned by a
public “what is my IP” service does not prove that condition: a CGNAT gateway
returns an address as well but does not accept inbound forwarding.

In Namecheap, open **Domain List → Manage → Advanced DNS**, enable **Dynamic
DNS**, and create an **A + Dynamic DNS Record** with host `cloud`. Do not paste
the Dynamic DNS password into Git, chat, shell history, or an issue. On the NUC,
run the interactive installer from the repository checkout:

```bash
cd /opt/nextcloud
sudo ./scripts/install-namecheap-ddns.sh
```

The prompt does not echo the password. The installer writes it only to
`/etc/namecheap-ddns.env` as `root:root` with mode `0600`, performs a first
update, and enables a hardened systemd timer that refreshes the record every
five minutes. The updater supplies its HTTPS request through curl's standard
input so the password is absent from process arguments and journal messages.

Inspect the service without exposing its environment:

```bash
systemctl status --no-pager namecheap-ddns.timer
systemctl list-timers --all namecheap-ddns.timer
journalctl -u namecheap-ddns.service --since today --no-pager
```

If the Netgear WAN IPv4 is not the same address family/path shown by the NUC,
or the router offers no IPv4 port forwarding, do not enable this `A` record as
the public Nextcloud path. Namecheap cannot keep a changing IPv6 prefix updated
with its native DDNS feature. The clean alternative is to move authoritative
DNS to a provider with a scoped API token and dynamic `AAAA` support while
leaving the domain registration at Namecheap; any such migration must preserve
the complete existing zone and keep the cloud record DNS-only.

If the DNS provider is Cloudflare in a future migration, keep this record
**DNS-only** unless its upload-size limits are explicitly acceptable for the
planned Nextcloud workload. Cloudflare proxying must not be enabled blindly.

For local access, add a Split-DNS record only in the existing local DNS system,
and only if it is part of the network's established design. It should resolve
`cloud.itmitalles.de` to the NUC's LAN address; do not add it as a public DNS
record.

## Caddy integration

Copy the site block from [Caddyfile.example](Caddyfile.example) into the shared
Caddy configuration. Keep existing site blocks unchanged. Validate the complete
Caddyfile before reloading Caddy:

```bash
cd /opt/caddy
cp Caddyfile "Caddyfile.before-nextcloud.$(date -u +%Y%m%dT%H%M%SZ)"
printf '\n' >> Caddyfile
cat /opt/nextcloud/Caddyfile.example >> Caddyfile
docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

The supplied block implements the required CardDAV and CalDAV redirects and
proxies to `nextcloud-app:80` over `proxy_net`. Caddy obtains TLS certificates
only after the DNS record is publicly visible and TCP 80/443 reach it.

If Caddy's on-disk configuration and its running configuration disagree, stop
there and reconcile that drift before a reload. A reload with a stale file can
silently remove a working existing route.

## Backups

Run a backup with:

```bash
cd /opt/nextcloud
sudo ./scripts/backup.sh
```

The script takes an exclusive lock, enables maintenance mode, creates a
consistent PostgreSQL custom-format dump, archives the persistent Nextcloud
filesystem (`html` and `data`), stores a resolved but secret-redacted
Compose configuration, and reliably disables maintenance mode even when a
command fails. It intentionally does **not** copy the live PostgreSQL data
directory: the logical `pg_dump` is the consistent database backup. Redis is
also not restored from a stale AOF; it is cache/locking/session state and is
recreated empty during disaster recovery. PostgreSQL object owners and ACLs are
retained because Nextcloud 34 can use a dedicated application database role.

The default target is `<NEXTCLOUD_DATA_ROOT>/backups` (production:
`/srv/nextcloud/backups`). This is convenient for local
recovery only; it does not protect against NVMe failure, theft, fire, or a
destructive host incident. External, encrypted, tested offsite backups are a
required follow-up before treating the service as production-safe.
`scripts/offsite-backup.sh` implements that follow-up with restic, root-only
repository/password files, and a post-upload repository check. The live `.env`
is included only inside restic's encrypted snapshot. See the backup runbook for
setup and the isolated restore test.

### Restore and disaster recovery order

1. Provision a patched replacement host with Docker, Caddy, IPv6 routing, and
   the same DNS name. Do not expose the service before its data is restored.
2. Restore the protected `/opt/nextcloud/.env` from secret management with mode
   `0600`; use the committed `compose.yaml` from the same backup/repository
   revision.
3. Recreate `proxy_net`, restore `html` and `data` to `/srv/nextcloud`, and
   recreate empty `/srv/nextcloud/postgres` and `/srv/nextcloud/redis`
   directories with the UID/GID expected by their images.
4. Start only `db`, recreate the application database login from the protected
   `config.php` without logging its password, then restore `nextcloud.pg.dump`
   with `pg_restore` as the administrative database user. Preserve dump owners
   and ACLs; do not overwrite a populated database blindly.
5. Start `redis`, `app`, and `cron`; run `php occ maintenance:repair` only after
   inspecting `occ status` and the restore logs.
6. Set background jobs to cron, enable Caddy only after `occ status` is healthy,
   then run `./scripts/healthcheck.sh --file-roundtrip`.
7. Verify shares, WebDAV, a user upload/download, and administrator security
   warnings before announcing recovery.

Keep a written record of the exact repository commit and backup timestamp used
for every recovery. Test this procedure on disposable infrastructure before it
is needed.

## Updates

```bash
cd /opt/nextcloud
git pull --ff-only origin main
sudo ./scripts/update.sh
```

`update.sh` first runs a backup, verifies that the image declarations are
exactly `nextcloud:34-apache`, `postgres:17-alpine`, and `redis:7-alpine`, pulls
the current minor/patch release within those major tags, starts the controlled
Compose update, and runs `occ status` plus the health checks.

It refuses unexpected images and never performs a major upgrade. Upgrade
Nextcloud majors one at a time, following the official release path, with a
tested restore point and maintenance window.

## Validation checklist

GitHub Actions runs only repository-safe checks: base and overlay Compose
rendering, recursive Bash syntax, ShellCheck, and a full-history Gitleaks scan.
It deliberately does not simulate the NUC, Caddy, public DNS/TLS, WebDAV,
Collabora, TURN, or restore. Run the same static checks locally with:

```bash
./scripts/validate-static.sh
```

`healthcheck.sh` verifies running containers, Compose status, PostgreSQL,
Redis, installed/non-maintenance `occ` status, cron mode, public and Caddy-local
`status.php`, the public certificate, WebDAV response, and CardDAV/CalDAV
redirects. `--file-roundtrip` additionally performs an authenticated temporary
WebDAV upload/download/delete without printing credentials.

Before production use, also verify:

- `docker compose config -q` completes successfully.
- `bash -n scripts/*.sh` passes.
- `docker compose ps` shows no restart loop and PostgreSQL is healthy.
- The Caddy login page is reachable at the public URL with a valid certificate.
- Cron executes jobs; verify `occ config:app:get core backgroundjobs_mode` and
  inspect scheduled-job history after several minutes.
- Data still exists after a deliberate `docker compose restart app` during a
  maintenance window, followed by the full health check.
- `docker ps` and `ss -ltnp` show no public PostgreSQL or Redis port.
- The Nextcloud Administration overview has no unresolved security or setup
  warning that is relevant to this deployment.

## Security model

- Credentials are generated with `openssl rand` and stored only in NUC-local
  `.env` with mode `0600`.
- The Namecheap per-domain DDNS password is stored only in
  `/etc/namecheap-ddns.env` with mode `0600`; it is never passed as a process
  argument or written to the journal.
- PostgreSQL and Redis are internal-only Docker services; Redis also requires a
  password.
- Nextcloud trusts only the live `proxy_net` CIDR, not all RFC1918 networks.
- HTTPS terminates at Caddy; Nextcloud is explicitly configured for the public
  HTTPS URL and reverse-proxy headers.
- Container images are pinned to deliberate major versions. Patch/minor tags
  remain floating by design and are updated by the controlled script.

## Troubleshooting

- **Caddy cannot obtain a certificate:** check authoritative DNS propagation,
  public IPv6 reachability, router IPv6 filtering, and host firewall rules. Do
  not solve this by exposing database ports or by proxying through a service
  with unknown upload limits.
- **Trusted-domain or proxy warning:** confirm `TRUSTED_PROXIES` equals the
  output of `docker network inspect proxy_net`, then restart `app` and `cron`.
- **Permissions failure:** do not recursively `chown` a populated data tree.
  Compare ownership with the image service account and restore from backup if
  needed.
- **Backup fails in maintenance mode:** inspect the script output; its trap
  attempts to disable maintenance automatically. If it could not, run the OCC
  maintenance-off command from the app container and investigate before retrying.
- **No direct public IPv6:** document the cause. A Cloudflare Tunnel is not an
  automatic substitute for large-file Nextcloud traffic; assess transfer,
  upload, and operational constraints before adopting it.

## Open operational items

- Authenticate to the actual NUC and create a fresh read-only inventory; do not
  reload Caddy until its disk/runtime result is `match`.
- Enable Namecheap Dynamic DNS and create the `cloud` A + Dynamic DNS record,
  then enter its per-domain password locally on the NUC.
- Verify from a genuinely external network whether the Netgear router has a
  forwardable public IPv4 and whether TCP 80/443 reach Caddy. If it does not,
  choose a DNS provider with dynamic `AAAA` support and verify the IPv6 path.
- Reconcile any existing Caddy configuration drift before reloading it.
- Before any real personal, customer, or mail data is stored: configure the
  Google Drive/restic target, upload the generated `.env` only through the
  encrypted snapshot, and pass the disposable offsite restore test. This is
  deliberately deferred during the fictitious-data IaC phase.
- Reconcile the declared Nextcloud apps, then enable and accept Collabora before
  beginning TURN work. HPB remains gated on successful external TURN tests.
- Select and validate a separate mailcow VM/VPS before following the pinned
  upstream lifecycle.
- Define users, groups, sharing policy, retention, and the Dropbox migration
  plan before importing production data.
