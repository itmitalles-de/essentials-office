# Validation report

Date: 2026-08-13 (Europe/Berlin)

## Passed in the local disposable environment

- Base Compose, Collabora overlay, TURN overlay, and restore Compose all passed
  `docker compose config -q` with non-secret validation placeholders.
- Every shell script passed `bash -n` and ShellCheck 0.11.0.
- The GitHub Actions workflow passed actionlint 1.7.12.
- Gitleaks 8.30.1 found no leak in either the complete Git history or the
  current working tree.
- The TURN config installer ran twice with identical outputs, root ownership,
  mode `0600`, and a generated 64-hex-character shared secret that was not
  printed.
- The Nextcloud App Store compatibility endpoint returned a compatible release
  for every one of the eleven declared app IDs on Nextcloud 34.0.2.
- Restic 0.19.1 initialized an encrypted disposable repository, backed up two
  fixtures, completed `check --read-data`, restored the latest snapshot, and
  reproduced both files byte-for-byte. The repository, password, and restore
  output were then removed.
- A fresh, isolated Nextcloud 34.0.2 source instance created a PostgreSQL dump
  and `html`/`data` archive. `scripts/restore-test.sh` verified checksums,
  restored them into a second internal-only Compose project, recreated the
  dedicated Nextcloud database login without printing its password, passed
  PostgreSQL/Redis/App health, and returned an installed, non-maintenance OCC
  state. Both disposable projects and their data were removed.

The first restore attempt exposed a real ownership defect in the earlier dump
format: `--no-owner --no-privileges` made Nextcloud 34's separate `oc_admin*`
database login unable to read restored tables. The final implementation keeps
object ownership/ACL metadata and creates the config-declared login before
`pg_restore`; the repeated end-to-end restore then passed.

## Verified external facts

- On 2026-08-13, public resolvers returned no `A` or `AAAA` record for
  `cloud.itmitalles.de`; public HTTPS therefore remains intentionally open.
- Namecheap nameservers remain authoritative for `itmitalles.de`.

## Passed on the NUC

- The deployed checkout was clean at commit `3888bae`; its base Compose model
  passed validation without changing the checkout.
- Nextcloud 34.0.2, PostgreSQL 17, Redis 7, and cron were running. The core
  healthchecks passed, maintenance mode was disabled, and no database upgrade
  was pending.
- The canonical JSON adapted from `/opt/caddy/Caddyfile` matched Caddy's live
  admin API configuration. PostgreSQL and Redis exposed no host ports.
- A new candidate-format backup, `20260812T233152Z`, completed and all of its
  SHA-256 checksums passed. Cron resumed and maintenance mode was disabled.
- `scripts/restore-test.sh` restored that live backup into internal-only
  disposable PostgreSQL, Redis, and Nextcloud containers, preserved the
  Nextcloud 34 database-role ownership model, and passed all health and OCC
  checks. It removed the test containers and network afterward.
- The measured idle footprint of the four core containers was approximately
  111 MiB. The host had 13 GiB available RAM, unused 4 GiB swap, and 79 GiB
  free disk space after backup.
- The pinned installer downloaded restic 0.19.1 and rclone 1.75.0 from their
  upstream release pages, verified the committed SHA-256 digests before
  installation, and verified the installed versions. The Nextcloud core
  remained healthy afterward.
- The IaC deployment test created a separate checkout and data root, unique
  core container names, a unique Compose project, and a unique external proxy
  network. It deployed a fresh Nextcloud 34.0.2 instance, passed the internal
  PostgreSQL/Redis/App/cron checks, compatibility-checked and installed all
  eleven declared apps, restarted the application container, and applied the
  same deployment a second time. The second run preserved `.env` byte-for-byte
  and treated every app as already enabled. All disposable containers,
  networks, secrets, and data were removed; the production core remained
  healthy.

The first IaC test exposed an initialization-order error in the newly
parameterized backup path: the final path was computed before the data root was
loaded. That test snapshot landed in one timestamped root directory. The exact
temporary directory was removed, final-path calculation now occurs after
validation, and the script explicitly rejects `/` as a backup root. The
corrected path is covered by the repeated test.

## Not executed or not claimable

- The restic production target and credentials do not exist in repository
  context, and Google OAuth has not yet been completed. Therefore no genuine
  offsite upload or restore of an NUC backup was performed. The encrypted
  disposable restic test and both synthetic and live backup restore tests
  passed, but they do not replace an independent target.
- WebDAV round-trip, app reconciliation, and restart persistence after app
  installation remain gated on the completed offsite-recovery stage.
- Collabora document/spreadsheet/concurrency/version tests, Talk P2P and
  external TURN tests, and the complete demo journey require DNS, browser
  clients, and the gated runtime services. They were not simulated.
- No mailcow host passed the static-IP, PTR, port-25, resource, and port gates;
  mailcow was neither cloned nor started.

## Resource statement

The NUC exposes 14 GiB usable RAM and had about 13 GiB available at the idle
sample; the Nextcloud core used approximately 111 MiB. This is a point sample,
not a peak-load measurement. The Collabora overlay enforces a configurable
default ceiling of two CPUs and 3 GiB RAM. mailcow remains excluded from the
NUC and requires at least 6 GiB RAM plus 1 GiB swap before workload-specific
headroom. Record peak CPU, RSS, swap, disk growth, and TURN bandwidth after
each live stage.
