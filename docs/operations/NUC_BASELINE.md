# NUC baseline and validation gate

## Evidence status

The NUC was inventoried read-only over SSH on 2026-08-13 (Europe/Berlin). The
deployment at `/opt/nextcloud` was on clean `main` commit `3888bae`, used the
existing `/srv/nextcloud` storage and `proxy_net`, and passed `docker compose
config -q`. The observed core was Nextcloud 34.0.2 with PostgreSQL 17, Redis 7,
and cron mode. App, database, and Redis containers were healthy; maintenance
mode and the database-upgrade flag were both false.

The host had 14 GiB usable RAM, 4 GiB unused swap, and 79 GiB free on the 98
GiB root filesystem after the backup. The four core containers consumed about
111 MiB at idle during the sample. PostgreSQL and Redis published no host
ports. Only Caddy listened on host ports 80 and 443 among the checked service
ports.

Caddy is deployed separately from `/opt/caddy/docker-compose.yml`. Its
canonical adapted on-disk configuration exactly matched the runtime admin API
configuration. The only configured site was not the intended Nextcloud
hostname, however, and a fresh external DNS check returned no public `A` or
`AAAA` record for `cloud.itmitalles.de`. Public routing therefore remains
intentionally incomplete.

A candidate-format local backup completed as `20260812T233152Z`. All recorded
SHA-256 checksums passed. A disposable restore then recreated the captured
Nextcloud filesystem and PostgreSQL ownership/ACL state on an isolated Docker
network, passed database, Redis, application-health, and OCC checks, and
removed the temporary containers and network. Production stayed healthy, left
maintenance mode, and resumed cron after backup.

This proves the local backup format and restore procedure. It does not prove
offsite recovery: no independent restic target or protected credentials were
available. After the inventory, the checksum-pinned restic 0.19.1 and rclone
1.75.0 binaries were installed for the selected Google Drive target. OAuth,
repository initialization, upload, and offsite restore remain pending.

## Read-only inventory

Repeat the inventory before each deployment stage:

```bash
cd /opt/nextcloud
sudo ./scripts/inventory.sh /tmp/nextcloud-inventory.md
```

The report includes no environment values, credentials, user names, shares, or
file names. It records the repository revision, Compose validity, container and
OCC status, declared app versions, capacity, published database/cache ports,
local backup count, and a canonical comparison of Caddy's on-disk and running
JSON configurations.

Interpret the Caddy result as follows:

- `match`: the adapted Caddyfile and admin API state are equivalent.
- `different`: stop; reconcile the drift before any reload.
- `runtime-unavailable`: stop; validate the live configuration through an
  approved operational path before any reload.
- `invalid-on-disk`: stop; the file must not be loaded.

The inventory is evidence, not a mutation. Do not commit it without reviewing
whether local topology information should remain private.

## Deployment stop conditions

Do not enable public DNS, reload Caddy, configure Office, or enable TURN when
any of these is true:

- the actual NUC cannot be authenticated and inventoried;
- Caddy drift is not `match`;
- no verified restore exists for the current backup format;
- the public route was tested only from the LAN or through NAT hairpinning;
- `cloud.itmitalles.de` has conflicting `A` and `AAAA` reachability;
- PostgreSQL or Redis publishes a host port;
- Nextcloud is in maintenance mode or requires a database upgrade.

## Public validation boundary

DNS and TLS must be checked from a genuinely external IPv4/IPv6-capable
network. A LAN request to the router's public address does not prove inbound
reachability. Record the resolver answers, source network, timestamp, TLS
issuer/expiry, DAV status, and router/firewall path in the operational change
record without copying client IPs or credentials into Git.
