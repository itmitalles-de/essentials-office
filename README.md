# Essentials+ Office

Essentials+ Office is the self-hosted collaboration product in
[`itmitalles-de/essentials-office`](https://github.com/itmitalles-de/essentials-office).
Nextcloud is its core. The public service hostname remains
`cloud.itmitalles.de`; stable runtime paths and identifiers are listed in
[the compatibility register](docs/COMPATIBILITY_IDENTIFIERS.md).

The repository is operationally strong but is **not accepted as production
ready**. The current deployed revision, configuration drift, real encrypted
offsite snapshot, independent restore, operator-owned RPO/RTO, and current
public ingress must be proven independently. Repository or CI success does not
close those gates.

## Product scope

Essentials+ Office has a deliberately narrow product boundary:

- Nextcloud Files, sharing, versions and sync
- Calendar, Contacts and Tasks as the canonical groupware data store
- Nextcloud Talk, with TURN as a separate optional service
- Nextcloud Office with Collabora as a separate optional service
- Nextcloud Mail only as an IMAP/SMTP integration boundary
- Vaultwarden as a separate optional service
- bounded HR Lite and Intranet Lite modules using existing Nextcloud functions
- Essentials+ Calls only as a disabled external integration

Optional modules are disabled until their own gates pass. Their presence in Git
does not mean they are deployed. This work does not install mailcow, HPB, OIDC,
new password-manager functions, public registration, or additional modules.

The repository deliberately contains no secrets and no user data. It deploys
Nextcloud 34 (Apache), PostgreSQL 17, Redis 7, and a dedicated Nextcloud cron
container. The design keeps Caddy as a shared, independent reverse-proxy stack;
its current NUC state is unknown.

## Operational evidence status

| Observation | Date | Observed host/environment | Git commit | Method | Proof boundary |
| --- | --- | --- | --- | --- | --- |
| Repository baseline before this branch | 2026-08-19 | local Codex workspace | `17081f20704e77dea6d1c983bdf8f2bde779e8f2` | Git/GitHub inspection | Says nothing about the deployed host. |
| NUC core, local backup, and Caddy disk/runtime state | 2026-08-13 | historical host recorded only as `NUC` | `3888bae` | read-only SSH inventory plus local backup/restore | Historical only; hostname was not retained and the current deployed commit is unknown. |
| Full disposable Office and local encrypted Restic restore | 2026-08-13 | GitHub-hosted runner | `520c239` | Actions run `31730633740` | Synthetic and same-runner only; not offsite or live evidence. |
| Latest `main` CI | 2026-08-13 | GitHub-hosted runner | `17081f20704e77dea6d1c983bdf8f2bde779e8f2` | Actions run `31735217485` | Failed in Admin Center Browser-E2E; other jobs passed. |
| Operational-gates code-head CI | 2026-08-19 | GitHub-hosted runner | `2a26fc9c1df1c016294b2f83f57b87ad62fabfc7` | Actions run `32203617530` | All five jobs passed; synthetic classes 1–7 only, not live gates. |
| Public DNS/ingress | 2026-08-19T00:39:49Z | external Codex runner | clean `5bc726c7dedceb0f4d59d2d7d3da22555ead9188` | `check-external-ingress.sh`, expected strategy `either` | No A or AAAA records; TCP, TLS, HTTP, DAV, and upload-path checks were therefore not applicable. |
| Current NUC revision, drift, offsite restore, and production state | 2026-08-19 | no authorized target alias identified | `unknown` | safe access discovery | Open, not inferred from historical documentation. |

See the [verification matrix](docs/VERIFICATION_MATRIX.md) for the eleven
non-inheriting evidence classes and [NUC baseline](docs/operations/NUC_BASELINE.md)
for the dated historical observation.

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
| Mail integration | Nextcloud Mail plus synthetic TLS protocol fixture | off; no mail platform is installed |

Operational runbooks:

- [IaC deployment](docs/operations/IAC_DEPLOYMENT.md)
- [Backup and restore](docs/operations/BACKUP_RESTORE.md)
- [Nextcloud apps](docs/operations/NEXTCLOUD_APPS.md)
- [Collabora](docs/operations/COLLABORA.md)
- [Talk and TURN](docs/operations/TALK.md)
- [mail integration boundary](mailcow/README.md)
- [Fictitious end-to-end demo](docs/operations/DEMO_FLOW.md)

## Architecture

```text
Internet over IPv4 and/or IPv6
        |
  cloud.itmitalles.de (expected DNS-only A/AAAA; currently absent)
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
git clone https://github.com/itmitalles-de/essentials-office.git /opt/nextcloud
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

The public address-family strategy is an operator decision. A public record may
refer only to a verified, routable ingress address; a Tailscale address is not a
public DNS target. Do not infer forwardable IPv4 from an outbound address, and
do not infer IPv6 ingress from a locally assigned address.

The current external observation is dated `2026-08-19T00:39:49Z` and was made
by an external Codex runner from a clean worktree at
`5bc726c7dedceb0f4d59d2d7d3da22555ead9188`, using
`scripts/check-external-ingress.sh` with the minimal `either` strategy. It found
neither `A` nor `AAAA` for `cloud.itmitalles.de`; therefore TCP, TLS, HTTP, DAV,
and upload-path checks were not applicable. The generated JSON had SHA-256
`7d8e8018a9b7ce802f2bec021e8c41b1d360551e270bb6e522e33759fd39efb2`.
This proves only that the service was not publicly live at that observation;
it says nothing about the NUC or router. The actual address-family strategy
remains an operator decision; `either` was only the minimum availability probe.

After an operator declares the intended `ipv4-only`, `ipv6-only`, `dual-stack`,
or `either` strategy, run the external checker from a genuinely external
network. Store its JSON, Markdown, and SHA-256 outputs outside Git after a
privacy review.

### Namecheap Dynamic DNS on the NUC

The repository includes an optional Namecheap IPv4 DDNS path. Namecheap's native
Dynamic DNS endpoint updates only an IPv4 `A` record; it cannot update `AAAA`
records. This is useful only when the router itself has a publicly routable
IPv4 address and forwards TCP 80 and 443 to the NUC. An address returned by a
public “what is my IP” service does not prove that condition: a CGNAT gateway
returns an address as well but does not accept inbound forwarding.

If the responsible DNS operator has verified Namecheap as the current
authoritative provider and selected public IPv4, they may create an **A +
Dynamic DNS Record** with host `cloud`. Do not paste the Dynamic DNS password
into Git, chat, shell history, or an issue. On the authorized host, the
interactive installer is:

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

If the router WAN IPv4 is not the same address family/path shown by the NUC,
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

The site fragment in [Caddyfile.example](Caddyfile.example) is an expected route,
not authority to append to or reload the shared configuration. First collect
the on-disk and runtime hashes read-only, validate the complete Caddyfile, and
inventory every existing site. Follow the protected backup, semantic diff,
validate, reload, and rollback sequence in the
[Caddy drift runbook](docs/operations/CADDY_DRIFT.md).

The supplied block implements the required CardDAV and CalDAV redirects and
proxies to `nextcloud-app:80` over `proxy_net`. Caddy obtains TLS certificates
only after the DNS record is publicly visible and TCP 80/443 reach it.

As of 2026-08-19 no current authorized host observation exists. The historical
2026-08-13 observation at deployed commit `3888bae` found matching disk/runtime
configuration but no intended Nextcloud site; that result cannot be carried
forward to today's deployment.

## Backups

Run a backup with:

```bash
cd /opt/nextcloud
sudo ./scripts/backup.sh
```

The script takes an exclusive lock, enables maintenance mode, creates a
consistent PostgreSQL custom-format dump, archives the persistent Nextcloud
filesystem (`html` and `data`), stores a resolved but secret-redacted
Compose configuration for the recorded source commit plus declared and
actually running image evidence, and reliably disables maintenance mode even
when a command fails. It intentionally does **not** copy the live PostgreSQL data
directory: the logical `pg_dump` is the consistent database backup. Redis is
also not restored from a stale AOF; it is cache/locking/session state and is
recreated empty during disaster recovery. PostgreSQL object owners and ACLs are
retained because Nextcloud 34 can use a dedicated application database role.

The default target is `<NEXTCLOUD_DATA_ROOT>/backups` (production:
`/srv/nextcloud/backups`). This is convenient for local
recovery only; it does not protect against NVMe failure, theft, fire, or a
destructive host incident. An external encrypted snapshot and an independent
empty-target restore are required before treating the service as
production-safe.
`scripts/offsite-backup.sh` implements that follow-up with restic, root-only
repository/password files, and a post-upload repository check. The live `.env`
is included only inside restic's encrypted snapshot. See the
[backup runbook](docs/operations/BACKUP_RESTORE.md) and
[offsite acceptance contract](docs/operations/OFFSITE_ACCEPTANCE.md). As of
2026-08-19 no approved provider credentials, real snapshot receipt, or
independent restore-host receipt exists; this gate is externally blocked.

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

Updates start from a reviewed Git commit whose Nextcloud, PostgreSQL, Redis, and
optional-service images are exact tag-and-digest pins. `scripts/update.sh`
refuses an unexpected major, takes a backup before pulling, records the exact
previous image IDs, and enters maintenance mode only after a successful pull.
It requires Compose startup, OCC, database-upgrade, and health gates to pass.

A failed start or health gate restores the exact previous image IDs through a
temporary override, exits maintenance mode, and runs core health checks. A
failed pull leaves the running stack and maintenance state untouched. This is
an image rollback, not a database downgrade; the pre-update backup remains the
recovery boundary for schema-changing releases. No live update is permitted
until the current deployed revision and drift are known and an independent
restore has passed. The script enforces a matching full approved commit, clean
checkout, and root-owned all-pass drift report before its production path can
run.

## Validation checklist

GitHub Actions runs static and supply-chain checks, full-history Gitleaks,
repository SBOM generation, isolated optional-service contracts, and a
disposable Nextcloud stack with synthetic WebDAV, browser, module, backup,
encrypted local Restic, and empty-target restore flows. These remain classes
1–7; they do not prove the NUC, independent offsite recovery, public ingress,
or production. Run the repository-safe static subset locally with:

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
- Runtime and test container images are exact tag-and-digest pins. A reviewed
  patch/minor update changes both values; mutable major tags are rejected.

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

## Open operational gates

1. Provide an approved noninteractive SSH target alias for the actual NUC and
   run the read-only deployment collector. This is the next single useful
   operational action; no update, pull, restart, or Caddy reload belongs before
   it.
2. Reconcile the observed commit, Compose, images, modules, mounts, and Caddy
   hashes against the reviewed repository state.
3. Assign the operator and approve or replace the proposed RPO/RTO in the
   [service objectives](docs/operations/SERVICE_LEVEL_OBJECTIVES.md).
4. Configure an approved independent Restic target, create a real encrypted
   snapshot, and restore it on independent empty infrastructure under the
   [acceptance runbook](docs/operations/OFFSITE_ACCEPTANCE.md).
5. Declare the intended public address-family strategy, then repeat the ingress
   checker externally. Do not create DNS or change Caddy automatically.

No optional module activation, user migration, or production data belongs ahead
of these gates.
