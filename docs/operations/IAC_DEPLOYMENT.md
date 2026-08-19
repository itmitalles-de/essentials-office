# Reproducible repository deployment

## Contract

The Essentials+ Office core is infrastructure as code made from the committed
Compose model and idempotent host scripts. Production defaults remain:

- checkout: `/opt/nextcloud`;
- persistent state: `/srv/nextcloud`;
- Compose project: `nextcloud`;
- core containers: `nextcloud-db`, `nextcloud-redis`, `nextcloud-app`, and
  `nextcloud-cron`;
- shared external proxy network: `proxy_net`.

Host-specific configuration and generated credentials live only in
`/opt/nextcloud/.env`. They are inputs to the code, not repository content.
Re-running deployment preserves that file and every non-empty persistent
directory.

The shared Caddy stack remains separate infrastructure. This repository
supplies its Nextcloud site fragment but does not overwrite or reload the
shared Caddyfile. Collabora, TURN, and Vaultwarden remain explicit optional
services. Mail is an integration boundary; this deployment installs no mail
platform.

## Clean Ubuntu host

Check out the private repository through the operator's approved GitHub
authentication path. Do not put a token in a clone URL, shell history, or
provisioning variable. Then install the host runtime and deploy:

```bash
sudo ./scripts/provision-host.sh
sudo ./scripts/deploy.sh --apps
```

`provision-host.sh` supports Ubuntu and configures Docker's official apt
repository plus the small set of required host tools. `deploy.sh` then:

1. creates `.env` with random credentials only when it is absent;
2. creates or validates `proxy_net` and its exact trusted-proxy CIDR;
3. creates the persistent directories with image-derived UID/GID ownership;
4. validates and starts the Compose model;
5. waits for PostgreSQL, Redis, Nextcloud, and cron rather than relying on a
   fixed sleep;
6. sets Nextcloud's background mode to cron;
7. runs the internal core checks;
8. with `--apps`, compatibility-checks and reconciles the declared apps, then
   repeats the core checks.

Public DNS and Caddy are deliberately not prerequisites for the internal
deployment check. After the shared proxy route has passed its separate drift
gate, run the full public healthcheck and browser tests.

## Existing host

Run the non-mutating prerequisite check first:

```bash
./scripts/provision-host.sh --check
```

Review `.env`, especially `NEXTCLOUD_DATA_ROOT`, `PROXY_NETWORK`, trusted
domains, and trusted proxies. Then apply the same deployment command. Existing
secrets and non-empty data directories are preserved. The command performs no
Nextcloud major upgrade and does not start optional overlays.

## Disposable proof

The deployment test creates a copied checkout, generated credentials, a data
tree, four uniquely named containers, and isolated Compose/proxy networks
under generated `/tmp` names. It never attaches to the production
`proxy_net`, `/srv/nextcloud`, or production container names.

```bash
sudo ./tests/deploy/run.sh --apps
```

It proves a clean deployment, all declared apps, an application restart,
secret-file stability, and an idempotent second deployment. Its exit trap
removes the disposable containers, networks, checkout, secrets, and data.
The same disposable path runs on GitHub-hosted CI with synthetic data. It does
not model the NUC, shared Caddy, real DNS, an offsite provider, or production.

## Existing-host drift gate

Before applying repository state to an existing host, create a read-only report
with `scripts/collect-deployment-state.sh` and compare it with the reviewed
expected report using `scripts/compare-deployment-state.py`. Stop on an unknown
commit, dirty checkout, redacted/effective Compose drift, configured or running
image drift, module/Caddy drift, or stale backup and restore evidence. The
report is evidence, never authority to reset, pull, restart, or reload.

```bash
sudo ./scripts/collect-deployment-state.sh /tmp/essentials-office-state
./scripts/compare-deployment-state.py \
  /var/lib/essentials-office/evidence/approved-deployment-state.json \
  /tmp/essentials-office-state/deployment-state.json \
  --expected-repo-commit <approved-full-commit> \
  --max-collection-age-hours 1 \
  --max-backup-age-hours 30 \
  --max-restore-age-hours 2400 \
  --max-rto-hours 8 \
  --output-dir /tmp/essentials-office-drift
```

The approved report is a privacy-reviewed known-good baseline, not a copy made
automatically from the new observation. The comparator requires its Caddy hash
and expected fragment, a checked offsite receipt tied to the same source
host/commit, and an independent restore receipt tied to its immutable checked
snapshot receipt with the same source commit, a different restore-host label,
complete checks, cleanup, and demonstrated RTO. The restored snapshot need not
be the newest nightly snapshot; restore age is evaluated independently.
Missing, future-dated, or stale evidence fails closed.
The report exposes only a redacted Compose render; a separate composite
SHA-256 fingerprints the in-memory effective render so environment drift is
detectable without recording individual `.env` values. Keep this topology and
configuration fingerprint in the protected evidence store, not Git.

## Controlled update

After the reviewed expected commit and actual state compare cleanly, copy the
passing comparator JSON to the protected approved path as root, mode `0600`.
Then the authorized maintenance-window invocation is:

```bash
sudo env \
  UPDATE_FROM_COMMIT=<previously-accepted-full-commit> \
  UPDATE_APPROVED_COMMIT=<approved-full-commit> \
  UPDATE_GATE_REPORT=/var/lib/essentials-office/evidence/approved-deployment-drift.json \
  /opt/nextcloud/scripts/update.sh
```

The script independently rechecks the full target commit, clean worktree,
fast-forward ancestry from the previously accepted commit, root-owned passing
gate report no older than one hour for that previous commit, exact approved running image IDs, exact
target image policy, and running core before taking its backup. It never changes
Git itself: the reviewed checkout reconciliation is a separate operator step.
A failed pull does not enter maintenance. A failed start or health gate
uses exact pre-update image IDs and exits maintenance. That rollback never
pretends to downgrade a changed database; the accepted pre-update backup is the
schema recovery boundary.

## Mandatory recovery gate

Offsite recovery is mandatory before any production acceptance or real user
data. A local backup or temporary Restic repository is insufficient. Configure
an approved independent repository, create and check a real encrypted snapshot,
then restore it on empty infrastructure outside the NUC failure domain under
`docs/operations/OFFSITE_ACCEPTANCE.md`. Keep the timer disabled until that
class 8 acceptance succeeds and a responsible operator approves retention and
the proposed service objectives.
