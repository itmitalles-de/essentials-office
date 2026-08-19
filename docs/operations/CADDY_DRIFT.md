# Shared Caddy drift, reload, and rollback

## Safety boundary

Caddy is shared infrastructure outside this Compose project. A matching disk
and runtime hash is necessary but not sufficient: the intended
`cloud.itmitalles.de` route must also exist, and every unrelated site must be
preserved. No command in the default inspection path reloads Caddy.

## Read-only inspection

From the Nextcloud checkout, collect the deployment state and review the Caddy
section:

```bash
cd /opt/nextcloud
sudo ./scripts/collect-deployment-state.sh /tmp/essentials-office-state
```

The collector records hashes only, not the complete shared configuration. It
compares the adapted on-disk configuration with the runtime admin API and
checks separately whether the expected hostname and upstream route appear.
Stop when disk validation is unavailable, the hashes differ, runtime cannot be
read, or the expected route is absent.

For a manual read-only confirmation in the separately managed Caddy checkout:

```bash
cd /opt/caddy
umask 077
docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose exec -T caddy caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile > /tmp/caddy-disk.json
docker compose exec -T caddy wget -qO- http://127.0.0.1:2019/config/ > /tmp/caddy-runtime.json
jq -S -c . /tmp/caddy-disk.json | sha256sum
jq -S -c . /tmp/caddy-runtime.json | sha256sum
```

The temporary JSON contains the complete shared routing topology. Keep it
local, mode `0600`, and remove it after comparison; do not commit it.

## Protected backup

Only an authorized operator may proceed after inventorying every existing site
block and reconciling disk/runtime state. In the separately managed Caddy
checkout, copy the complete Caddyfile to a root-protected UTC-stamped backup and
record its hash. Never back up only the Essentials+ Office fragment.

```bash
cd /opt/caddy
sudo install -d -o root -g root -m 0700 /var/backups/caddy
backup_file="/var/backups/caddy/Caddyfile.before-essentials-office.$(date -u +%Y%m%dT%H%M%SZ)"
test ! -e "$backup_file"
sudo install -o root -g root -m 0600 Caddyfile "$backup_file"
sudo sha256sum "$backup_file"
```

## Validate and reload

Edit the existing complete file once. Do not append the example blindly and do
not replace unrelated sites. Validate and inspect the semantic adapted-JSON
diff before the single authorized reload:

```bash
docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

The reload command is not part of inspection. Run it only after the backup,
validation, reviewed diff, maintenance approval, and rollback owner are present.
Then recollect disk/runtime hashes and check every previous site locally before
running the external ingress checker.

The complete controlled sequence is:

1. Record the current deployment report and full Caddy container image ID.
2. Copy the complete Caddyfile to a root-protected UTC-stamped backup on the
   same host and record its SHA-256.
3. Edit the existing complete file once. Do not append the example blindly and
   do not replace unrelated sites.
4. Run `caddy validate` against the edited complete file inside the same pinned
   Caddy image.
5. Diff the adapted old and new JSON. The only intended semantic change must be
   the reviewed Essentials+ Office route.
6. Reload once through Caddy's supported command.
7. Recollect disk/runtime hashes and run local route checks, then the external
   ingress checker from a genuinely external network.

## Rollback

If validation, reload, route, or unrelated-site checks fail:

1. Restore the complete protected Caddyfile backup, never only one site block.
2. Validate that complete rollback file.
3. Reload it once.
4. Confirm the runtime hash matches the restored disk hash.
5. Recheck every previously inventoried site and the Essentials+ Office route.
6. Keep the failed change and secret-free diff in the operational record.

The rollback file must first replace the complete edited Caddyfile, then pass
the same `caddy validate` command. Only then perform one reload and recollect
the hashes. Never reload a partial fragment.

If the runtime admin API cannot be read, do not assume a reload fixed the
problem. Leave the gate failed and escalate to the Caddy operator.
