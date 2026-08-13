# Optional Vaultwarden password vault

Vaultwarden is Office's optional, web-only password-vault MVP. It is the
Bitwarden-compatible Web Vault for organisations, collections, roles, and
groups. Browser extensions and native Bitwarden clients remain optional client
choices; this repository does not distribute or manage them.

The module is a separate Compose overlay, uses its own SQLite database and
secrets, and does not share a database or secret with Nextcloud. It is not a
replacement for individual Nextcloud credentials, and Nextcloud Passwords is
not used as a group vault. Passbolt is deliberately outside this web-only MVP.

## Status and boundaries

- **Implemented in this repository:** the `vaultwarden` Compose profile,
  private Caddy example, bootstrap, health check, SQLite backup/empty-target
  restore, controlled update helper, and the Office activation gate.
- **Not enabled by default:** profile, private DNS/Caddy route, and Office link
  all remain off until an administrator configures and checks them.
- **Not verified on a NUC or public DNS:** this change does not touch either.
- **Version:** `vaultwarden/server:1.37.1`, checked against the upstream latest
  GitHub release on 2026-08-13. It is deliberately version-pinned, never
  `latest`.

Vaultwarden is an unofficial Bitwarden-compatible server from the upstream
`dani-garcia/vaultwarden` project. Preserve the upstream AGPL-3.0 licence,
notices, and Web Vault/upstream notices when operating or redistributing it.
The repository does not claim Bitwarden affiliation or support.

## Private deployment

The module never publishes a Docker host port. It joins the existing external
`proxy_net` so that the already shared Caddy can reach `vaultwarden:8080`.
`Caddyfile.vaultwarden.example` is deliberately separate from the public
Nextcloud fragment and permits only Caddy's `private_ranges`; it uses Caddy's
internal CA. Keep its hostname private and make `DOMAIN` exactly match it.

```bash
sudo ./scripts/vaultwarden-bootstrap.sh --domain https://vault.internal.example
docker compose -f compose.yaml -f compose.vaultwarden.yaml --profile vaultwarden up -d
./scripts/vaultwarden-healthcheck.sh
```

The first command creates `/srv/vaultwarden/data`, `/srv/vaultwarden/backups`,
and a mode-`0600` private `.vaultwarden.env`. It does not start the service.
The environment file contains no generated default password. Signups are closed
by default. Create the first owner only through the explicitly approved
onboarding/invitation flow; do not temporarily open public registration just to
bootstrap a production vault.

The global `/admin` page is not necessary for routine organization management
and remains disabled. If it is deliberately enabled, use
`--enable-admin`; the script obtains an interactive token and stores only a
Vaultwarden-generated Argon2 hash. Never use a plaintext `ADMIN_TOKEN`.

## Organisation and 2FA operating steps

After a private HTTPS route is working, an owner uses the Web Vault to create
an organisation, collections, groups, and roles. Add only invited users, then
assign collection access through organization groups rather than sharing an
owner account. Test with a non-owner account before moving real secrets.

Require each account to enroll two-factor authentication in the Web Vault:

1. Sign in and open **Settings → Security → Two-step login**.
2. Prefer an authenticator app or a hardware security key where client support
   permits it; retain recovery material in a separately protected process.
3. Verify a second login in a private browser profile before treating setup as
   complete.

2FA policy enforcement and emergency-access policy are operational decisions;
they are not silently claimed by this repository.

## Backup, restore, update, rollback

SQLite is accepted for this small single-tenant module because backup uses the
SQLite backup API rather than a raw copy of a live WAL database. The backup
archives the database snapshot plus Vaultwarden data files separately from
Nextcloud, records checksums, and validates `PRAGMA integrity_check`.

```bash
sudo ./scripts/vaultwarden-backup.sh
sudo ./scripts/vaultwarden-restore.sh /srv/vaultwarden/backups/<timestamp> /srv/vaultwarden/restore-test
```

Restore refuses a non-empty target. Before production use, restore a backup to
an empty disposable host/path, use the protected matching `.vaultwarden.env`,
start the isolated profile, and sign in with a synthetic test account. The
repository test performs an equivalent container-level synthetic backup/restore
but does not create real vault entries.

Update only after reviewing Vaultwarden's release and changelog. Change the
pinned image tag in a reviewed commit, then run `vaultwarden-update.sh`; it
backs up first and waits for the isolated health check. To roll back, stop the
profile, restore the prior repository version and protected environment file,
restore the last known-good backup into an empty data target, and start that
previous image. Never roll back over a populated data directory.

Store an encrypted offsite copy of both the Vaultwarden backup and the private
environment file independently from Nextcloud backups and Git.
