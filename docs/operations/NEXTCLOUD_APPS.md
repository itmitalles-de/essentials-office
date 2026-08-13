# Declarative Nextcloud apps

## Declaration and safety model

`config/nextcloud-apps.txt` declares these App Store IDs:

| Capability | App ID |
| --- | --- |
| Talk | `spreed` |
| Mail | `mail` |
| Calendar | `calendar` |
| Contacts | `contacts` |
| Tasks | `tasks` |
| Notes | `notes` |
| Team knowledge | `collectives` |
| Kanban | `deck` |
| Structured lists | `tables` |
| Forms | `forms` |
| Nextcloud Office | `richdocuments` |

`scripts/reconcile-apps.sh` first verifies that the running installation is
healthy, outside maintenance, does not need a database upgrade, and remains on
Nextcloud major 34. It then downloads the App Store catalog filtered for the
exact Nextcloud version and requires a compatible release for every declared
app before making the first change.

The script never uses OCC's `--force` option. Missing apps are installed,
disabled apps are enabled, and enabled apps are left unchanged. A consistent
backup is taken before the first mutation. Any failed command aborts the run.
An explicit `--update` updates only declared apps through OCC's compatible
release resolver; it does not change the Nextcloud image or major version.

## Operation

Read-only drift and compatibility check:

```bash
cd /opt/nextcloud
./scripts/reconcile-apps.sh --check
```

Install/enable missing apps:

```bash
cd /opt/nextcloud
./scripts/reconcile-apps.sh
```

Deliberately update declared apps after reviewing their release notes:

```bash
cd /opt/nextcloud
./scripts/reconcile-apps.sh --update
```

Every successful run writes a non-secret JSON inventory below ignored
`reports/`, including installed versions and the latest versions compatible at
that timestamp. Preserve the relevant report with the external operational
change record rather than committing runtime state automatically.

## Rollback

An app can be disabled independently with OCC if its data migration is known to
be reversible. If the app changed its schema or shared data, restore the backup
taken immediately before reconciliation into disposable infrastructure first,
then follow the full recovery procedure. Do not downgrade an app package over a
newer schema blindly.

## Demo data boundary

This repository creates no users or seeded records automatically. A production
operator can therefore run reconciliation without introducing demo data. When
the demo flow is executed, use only the fictitious identities and reserved
`.invalid` mail domain defined in `DEMO_FLOW.md`; generate their passwords
locally and never commit them. Nextcloud remains canonical for Calendar,
Contacts, and Tasks. SOGo must not be used to seed parallel groupware data.
