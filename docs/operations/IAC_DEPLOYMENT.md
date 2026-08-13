# Reproducible repository deployment

## Contract

The base Workspace Suite is infrastructure as code made from the committed
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
shared Caddyfile. Collabora and TURN remain explicit optional overlays, and
mailcow remains a separate upstream checkout.

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
Host-dependent deployment tests remain excluded from GitHub-hosted CI.

## Deferred production-data gate

Offsite backup is not required for the current fictitious-data IaC phase. It
becomes mandatory before this deployment is used with personal, customer, or
mail data. At that gate, configure the protected Google Drive remote, upload a
restic snapshot, restore it to disposable infrastructure, and only then enable
the timer. The authoritative reminder is tracked in `wutz-io/ai-todo#26`.
