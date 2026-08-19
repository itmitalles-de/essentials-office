# Historical NUC baseline and current access gate

## Current status

The actual NUC deployment is **unknown** as of 2026-08-19. Safe discovery in
the local Codex workspace based on repository commit `17081f2` inspected the
available SSH configuration, documented host names, deployment scripts, Git
history, and existing noninteractive paths. It found no host alias that could
be tied to this repository and therefore made no SSH authentication attempt.
No configuration was changed, no credentials were searched, and no IP address
was guessed.

This is an access-discovery result only. It does not establish the current
deployed commit, dirty state, images, Compose model, Nextcloud version, Caddy
state, backup, or health. Those class 9 gates remain open until an authorized
alias passes noninteractive authentication and the read-only collector runs.

## Historical observation — 2026-08-13

The following evidence is retained as history and must not be treated as a
current baseline:

| Field | Recorded value |
| --- | --- |
| Observation date | 2026-08-13 (Europe/Berlin) |
| Observed host | recorded only as `NUC`; exact host name was not retained |
| Deployed Git commit | clean `main` at `3888bae` |
| Method | read-only SSH inventory, local backup, same-host disposable restore |
| Boundary | no current state, no public ingress, no offsite provider, no independent restore |

That observation recorded Nextcloud 34.0.2 with PostgreSQL 17, Redis 7, cron
mode, healthy core containers, maintenance disabled, and no database upgrade
pending. It recorded 14 GiB usable RAM, 79 GiB free on a 98 GiB root
filesystem, and about 111 MiB idle memory for the four core containers. These
are dated point samples, not current capacity evidence.

The separately managed Caddy configuration on disk adapted to the same
canonical JSON as the runtime admin API. The intended
`cloud.itmitalles.de` route was absent. A local backup named
`20260812T233152Z` passed checksums and restored into disposable containers on
the same host. PostgreSQL ownership/ACLs, Redis, OCC, and core health passed and
the test resources were removed. The source returned outside maintenance mode
with cron resumed.

That procedure proved the historical local backup format only. Restic and
rclone binaries were installed afterward, but no provider OAuth, real encrypted
snapshot, repository check receipt, or independent restore was recorded.

## Current read-only collection

Once an explicitly approved host alias exists, resolve it with `ssh -G` and
test only `BatchMode=yes` authentication. If authentication succeeds, run
`scripts/collect-deployment-state.sh` on the host and retain its JSON, Markdown,
and SHA-256 evidence outside Git after privacy review. The collector replaces
the older narrow `scripts/inventory.sh` for acceptance decisions.

The report may contain topology and version metadata but no `.env` values,
tokens, users, shares, or file names. Compare it with
`scripts/compare-deployment-state.py`. A dirty checkout, mismatch, unavailable
Caddy runtime, stale backup, or stale restore is a stop condition, not authority
to reset, pull, update, restart, or reload.

## External observation — 2026-08-19T00:39:49Z

An external Codex runner used `scripts/check-external-ingress.sh` from a clean
worktree at commit `5bc726c7dedceb0f4d59d2d7d3da22555ead9188` and found no
`A` or `AAAA` records for `cloud.itmitalles.de`. The report JSON had SHA-256
`7d8e8018a9b7ce802f2bec021e8c41b1d360551e270bb6e522e33759fd39efb2`.
Consequently TCP 80/443, TLS, HTTP, DAV, and upload-path checks were not
applicable. This is class 10 evidence that the service was not publicly live at
that instant; it says nothing about local NUC health. The `either` address
strategy was a minimum availability probe, not an approved operator decision.

## Stop conditions

Do not update the checkout, start optional modules, reload Caddy, or open public
routing while any of these remains true:

- the current NUC cannot be authenticated and collected read-only;
- the deployed commit or dirty state is unknown;
- Compose, image, module, or Caddy drift is unknown or failing;
- no accepted independent restore exists for the current backup format;
- public routing was tested only from the LAN or has conflicting address-family
  results;
- PostgreSQL or Redis publishes a host port;
- Nextcloud is in maintenance mode or requires a database upgrade.
