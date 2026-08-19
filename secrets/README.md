# Secrets

This directory is intentionally documentation-only. It must never contain a
secret, a generated `.env` file, a backup, or a private key.

On the NUC, `scripts/bootstrap.sh` creates `/opt/nextcloud/.env` with mode
`0600`. It contains the PostgreSQL password, the Redis password, and the
initial Nextcloud administrator password. Keep that file on the NUC only and
back it up through a protected secret-management process separate from Git.

The persistent service data lives under `/srv/nextcloud`; it is not a suitable
substitute for an offsite backup of the generated `.env` file.

The optional Namecheap Dynamic DNS integration stores its per-domain password
only in `/etc/namecheap-ddns.env` on the NUC. The interactive installer creates
that file as `root:root` with mode `0600`. It must not be copied into this
directory or any other Git working tree.

The optional Vaultwarden overlay keeps its independent operational settings in
`/opt/nextcloud/.vaultwarden.env` with mode `0600`; its data and backups live
below `/srv/vaultwarden`, never below `/srv/nextcloud`. Do not copy its
environment file, SQLite database, backups, generated keys, SMTP credentials,
or an optional Argon2 admin-token hash into Git. See
[`docs/office/VAULTWARDEN.md`](../docs/office/VAULTWARDEN.md).

The synthetic HR Lite reconciler creates a mode-`0600`
`/opt/nextcloud/.hr-lite-demo.env` only on an approved disposable instance.
It must not be used for real people or copied to Git. The Essentials+ Office module and
Visual PBX local activation files are configuration-only and use their ignored
paths documented in `config/office-modules.env.example` and
`integrations/visual-pbx.env.example`.
