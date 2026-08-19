# Offsite backup and independent restore acceptance

## Gate state

This gate is **open** until one encrypted snapshot from the real deployment has
been restored and verified on infrastructure that is physically and
administratively independent of the NUC. The local encrypted Restic test in CI
is class 7 evidence; this runbook targets class 8. A second directory, disk, or
VM backed only by the NUC does not qualify.

As of 2026-08-19 the repository contains no approved provider configuration,
credentials, snapshot receipt, or independent restore-host receipt. No cloud
resource may be purchased and no existing retention policy may be changed by
this runbook.

## Prerequisites

- A reviewed Restic repository endpoint independent of the NUC.
- Protected repository and password files plus any backend-native credential
  file, all root-owned and mode `0400` or `0600`.
- A second Linux machine or VM whose disks, failure domain, and administrative
  access do not depend on the NUC.
- Enough empty capacity for the encrypted repository checkout, decrypted
  backup, PostgreSQL restore, and Nextcloud files.
- The repository commit recorded in the backup and Docker/Compose on the
  independent host.
- A named operator, maintenance window, and approved place for the
  secret-redacted acceptance receipt.
- No production routing from the restore host and no reuse of a populated
  database or data directory.

## Source-side snapshot

Run only after read-only deployment-state collection confirms the intended
checkout and local backup path. Do not alter Restic retention or prune data.

```bash
cd /opt/nextcloud
sudo ./scripts/offsite-backup.sh
```

Acceptance requires all of the following in the source-side record:

- local backup completed with PostgreSQL dump, filesystem archive, redacted
  Compose render, version metadata, and valid SHA-256 checksums;
- Restic created a snapshot and returned its full ID and UTC time;
- `restic check --read-data-subset` succeeded at the configured percentage;
- the protected receipt identifies the source host and repository commit,
  records a clean dirty-state result, and contains no repository URL,
  credentials, users, shares, or filenames.

An upload without the repository check and snapshot receipt is not accepted.
Each upload keeps an immutable root-only receipt named by its full snapshot ID
in addition to the `last-offsite-snapshot.json` pointer. Transfer the selected
secret-redacted receipt to the independent host through an approved protected
channel. This does not transfer repository credentials.

## Independent empty-target restore

On the independent host, use the same protected Restic configuration and a
fresh clone of the recorded commit. The stage directory must not pre-exist.
The staging script resolves the selector to one full snapshot ID and writes a
root-protected metadata file inside that stage. The restore receipt refuses an
independence claim unless the supplied full ID matches this actual staged ID
and the immutable checked-snapshot receipt matches the restored backup commit,
dirty state, and timestamp.

```bash
git clone https://github.com/itmitalles-de/essentials-office.git /opt/nextcloud
cd /opt/nextcloud
git switch --detach <recorded-commit>
sudo ./scripts/offsite-restore-stage.sh <snapshot-id>
sudo RESTORE_RTO_STARTED_AT_UTC=<incident-declaration-utc> \
  RESTORE_SOURCE_EVIDENCE_FILE=<protected-offsite-snapshot-receipt> \
  RESTORE_SOURCE_SNAPSHOT_ID=<snapshot-id> \
  RESTORE_INDEPENDENT_INFRASTRUCTURE=true \
  RESTORE_STAGE_DIRECTORY=<stage> \
  RESTORE_EVIDENCE_OUTPUT=/var/lib/essentials-office/evidence/last-independent-restore.json \
  RESTORE_ENV_FILE=<stage>/opt/nextcloud/.env \
  ./scripts/restore-test.sh <stage>/srv/nextcloud/backups/<backup-utc>
sudo RESTORE_EVIDENCE_FILE=/var/lib/essentials-office/evidence/last-independent-restore.json \
  ./scripts/cleanup-restore-stage.sh <stage>
```

Before cleanup, verify the staged directory is the newly generated direct
child reported by `offsite-restore-stage.sh`. Never substitute a source-system
path or an existing data directory.

## Mandatory acceptance checks

The independent-host receipt is accepted only when it records all of these as
passing:

1. Backup checksums and safe archive paths.
2. Empty PostgreSQL, Redis, Nextcloud, and cron target creation.
3. PostgreSQL logical restore and readiness.
4. Redis rebuilt empty and answering its authenticated health probe.
5. `occ status`: installed, outside maintenance, no database upgrade needed.
6. Controlled `occ maintenance:repair` and successful core-integrity check.
7. Nextcloud core and enabled/disabled app versions recorded.
8. Cron container running and Nextcloud background mode set to cron.
9. Synthetic WebDAV upload/download/delete roundtrip with matching bytes after
   restore.
10. Synthetic share metadata exists after restore.
11. Existing stable HR Lite/Intranet Lite assertions, when their fixtures are
    present; absence must be explicit and is not silently accepted.
12. Restore stage removed after the receipt has been reviewed and copied to the
    approved operational record.
13. Source NUC containers, files, configuration, and maintenance state are
    unchanged except for the intentional source backup and evidence receipt.

## Acceptance record

Record observation UTC time, source and restore host labels, full source commit,
staged snapshot ID/time, backup timestamp, Restic check scope, restore start/end time,
elapsed restore duration, core/app versions, each check result, cleanup result,
operator, and proof boundary. Never record
passwords, tokens, repository URLs containing credentials, user names, share
names, or file names.

If no approved target or independent host exists, this document and the
executable scripts are the completed preparation. The gate remains open.
