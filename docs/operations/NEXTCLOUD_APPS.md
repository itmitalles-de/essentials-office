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

Repository-owned native apps are versioned with this repository instead of the
App Store:

| Capability | App ID | Source |
| --- | --- | --- |
| Essentials+ module control plane | `essentialsplus` | `nextcloud-apps/essentialsplus` |
| Appointment booking | `appointments` | `nextcloud-apps/appointments` |

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

Optional repository apps are copied through a same-filesystem staging
directory with ownership checks. Installing `appointments` leaves it disabled;
the Essentials+ module activation performs the health-gated global enable that
its anonymous routes require. Deactivation disables code execution but keeps
all appointment tables for retention/export and later reactivation.

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

Install the Appointments package without publishing it:

```bash
cd /opt/nextcloud
sudo ./scripts/reconcile-apps.sh --module appointments
```

Activation and organization setup are documented in
[Appointments](../appointments.md).

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
