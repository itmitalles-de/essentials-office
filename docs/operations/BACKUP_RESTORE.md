# Encrypted offsite backup and restore

## Design

`scripts/backup.sh` remains the consistency boundary. It enables maintenance
mode, stops cron, creates a PostgreSQL custom-format dump, archives `html` and
`data`, records the repository commit, and creates checksums. It does not copy
the live PostgreSQL directory. Redis holds cache, locks, and session state; a
disaster restore recreates it empty instead of reviving a stale live AOF.
PostgreSQL ownership and ACL metadata remains in the dump: Nextcloud 34 may
create a separate application login rather than using `POSTGRES_USER` directly.

`scripts/offsite-backup.sh` then sends the completed backup directory and the
NUC-local `.env` to a restic repository. Restic encrypts content and metadata.
The repository location and password are read from separate root-only files;
neither appears in the repository or the command line. The script finishes
with `restic check --read-data-subset`, defaulting to five percent.

The local archive contains Nextcloud's `config.php`, which itself contains
database/cache credentials. Local backups therefore remain mode `0700` and
must be treated as sensitive even though `.env` is excluded from them.

## One-time setup

Install the pinned and checksum-verified restic 0.19.1 and rclone 1.75.0
binaries with `scripts/install-backup-tools.sh`. The backup script rejects
restic versions below the tested baseline.
Select a target that is physically and administratively independent of the
NUC. A second directory on the same NVMe is not offsite.

## Google Drive target

Google Drive is connected through restic's rclone backend. Restic performs
encryption and deduplication locally; Drive stores the resulting repository
objects. Use a dedicated rclone remote named `gdrive` and the `drive.file`
scope. That scope permits access to files created by this rclone identity
instead of granting access to every existing Drive file.

Install the pinned tools, create the protected configuration directory, and
run rclone's interactive setup directly on the NUC:

```bash
cd /opt/nextcloud
sudo ./scripts/install-backup-tools.sh
sudo install -d -o root -g root -m 0700 /etc/nextcloud
sudo rclone config --config /etc/nextcloud/rclone.conf
sudo chown root:root /etc/nextcloud/rclone.conf
sudo chmod 0600 /etc/nextcloud/rclone.conf
```

Choose `gdrive` as the remote name, `drive` as the storage type,
`drive.file` as the scope, and no Shared Drive unless that is intentional. The
OAuth flow opens a short-lived local callback listener. For a headless SSH
session, follow rclone's documented remote-setup flow; never paste the token or
the resulting config into Git, chat, an issue, or a log.

Set the protected repository file to exactly:

```text
rclone:gdrive:workspace-suite/nextcloud-restic
```

Set `RCLONE_CONFIG=/etc/nextcloud/rclone.conf` in
`/etc/nextcloud/offsite-backup.env`. Keep a second, independent copy of the
restic repository password in a password manager or offline recovery record.
The Drive repository is unrecoverable if the NUC and the only password copy
are lost together.

Create the protected configuration without putting a repository URL or
password in shell history:

```bash
sudo install -d -o root -g root -m 0700 /etc/nextcloud
sudo install -o root -g root -m 0600 /opt/nextcloud/config/offsite-backup.env.example /etc/nextcloud/offsite-backup.env
sudo sh -c 'umask 077; openssl rand -base64 48 > /etc/nextcloud/restic-password'
sudo install -o root -g root -m 0600 /dev/null /etc/nextcloud/restic-repository
sudoedit /etc/nextcloud/restic-repository
sudoedit /etc/nextcloud/offsite-backup.env
```

The repository file contains exactly the restic repository location. Backend
credentials belong in the protected environment file or a backend-native
credential file referenced from it. Do not embed credentials in the repository
URL when the backend offers a separate mechanism.

Initialize once and create the first snapshot:

```bash
cd /opt/nextcloud
sudo ./scripts/offsite-backup.sh --init
```

For an existing restic repository, omit `--init`. A successful upload is not a
restore test.

## Disposable restore test

The restore test extracts only the expected archive roots into a newly created
`/tmp/nextcloud-restore-test.*` directory. It starts PostgreSQL, Redis, and
Nextcloud on one Docker-internal network, publishes no ports, restores the
logical dump, disables the maintenance flag captured in the filesystem
snapshot, checks OCC/PostgreSQL/Redis, and destroys the test project.

Test the latest local backup:

```bash
cd /opt/nextcloud
sudo ./scripts/restore-test.sh
```

To prove offsite recovery, stage a restic snapshot with the same protected
configuration. The script creates a new unique directory and never overwrites
an earlier restore:

```bash
cd /opt/nextcloud
sudo ./scripts/offsite-restore-stage.sh
sudo RESTORE_ENV_FILE=/srv/nextcloud/restore-output/restic-restore.<ID>/opt/nextcloud/.env \
  /opt/nextcloud/scripts/restore-test.sh \
  /srv/nextcloud/restore-output/restic-restore.<ID>/srv/nextcloud/backups/<UTC_TIMESTAMP>
sudo ./scripts/cleanup-restore-stage.sh \
  /srv/nextcloud/restore-output/restic-restore.<ID>
```

The cleanup is deliberately explicit and accepts only a generated direct child
of `/srv/nextcloud/restore-output`. It contains decrypted secrets and backup
data; after removal it is not locally recoverable.

## Scheduling

Install the committed systemd units only after both the first backup and the
offsite restore test pass:

```bash
sudo install -o root -g root -m 0644 /opt/nextcloud/systemd/nextcloud-offsite-backup.service /etc/systemd/system/
sudo install -o root -g root -m 0644 /opt/nextcloud/systemd/nextcloud-offsite-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nextcloud-offsite-backup.timer
```

Review the timer and service status without printing their environment. Run a
periodic `RESTIC_READ_DATA_SUBSET=100%` check from the protected config during a
maintenance window. Retention and pruning are deliberately not automated here:
deletion policy requires a separate, explicit decision.

## Production recovery order

1. Use a patched replacement host and keep public routing disabled.
2. Check out the commit recorded in `repository-commit.txt`.
3. Restore `.env` from restic with mode `0600` and recreate `proxy_net`.
4. Restore `html` and `data`; create empty PostgreSQL and Redis directories with
   the images' expected ownership.
5. Start only PostgreSQL. Recreate the application login named in the protected
   `config.php`, without exposing its password, then restore
   `nextcloud.pg.dump` with ownership and ACL metadata as the administrative
   PostgreSQL user.
6. Start Redis and Nextcloud, inspect OCC status, then disable maintenance mode.
7. Start cron, restore cron mode, and run the local and public health checks.
8. Enable Caddy/public routing only after data, shares, DAV, and security
   warnings have been reviewed.

Rollback is replacement of the disposable/replacement host from the previous
known-good snapshot. Never restore a dump over a populated live database.
