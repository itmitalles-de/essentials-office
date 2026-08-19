# Essentials+ Office Admin Center

Essentials+ Office is the collaboration product. The Admin Center is a
thematically grouped administrative catalog, defined by
[`office-modules.json`](../../office-modules.json). It is intentionally a
Nextcloud configuration pattern, not another always-running portal service.

## Visibility contract

1. The `admin` group sees the complete catalog in the restricted **Essentials+
   Office Admin Center** Collectives page and can operate the module checks.
2. Every optional module begins disabled in `config/office-modules.env`.
3. Before a module is made visible, its administrator sets its config flag,
   runs `scripts/office-module-preflight.sh --module <id>`, and records the
   successful health result.
4. Administrators enable a Nextcloud app only for its contract groups with
   `occ app:enable --groups ...`; group-restricted External Sites links are
   used for external module portals. Thus ordinary users see only a module that
   is both active and assigned to their group.
5. Deactivation changes the local contract and removes only the corresponding
   restricted link/app entitlement. It must never remove an app, volume,
   database, backup, or user content.

The supported Nextcloud app controls provide group-restricted app visibility;
External Sites supports group-restricted links. The repository does not use
SQL to write Nextcloud configuration.

## One-time administrative setup

There is no stable OCC provisioning interface for Collectives pages or the
External Sites catalog. After `Collectives` is installed, perform these small,
reproducible manual actions:

1. Create a Collective called **Essentials+ Office Admin Center** and restrict membership
   to the built-in `admin` group.
2. Copy the thematic tables from
   [`office-admin-center/CATALOG.md`](../../office-admin-center/CATALOG.md)
   into that Collective.
3. Create a group-restricted External Sites link only after its module
   preflight succeeds. Use the module contract's audience group; never put
   passwords, tokens, user names, or query credentials in a link.
4. Review the catalog after every activation/deactivation. Confirm a normal
   test user outside the relevant group does not see the app or link, and an
   administrator sees the entire catalog.

These four checks are the minimum acceptance test for the Admin Center.

## Thematic modules

| Theme | Modules |
| --- | --- |
| Collaboration | Nextcloud core, Collabora, Talk, Mail |
| Knowledge and intranet | Intranet Lite |
| People operations | HR Lite |
| Security and access | Vaultwarden |
| External integrations | Essentials+ Calls |

`nextcloud-core` is the only default-active module. Collabora, Talk, Mail,
Vaultwarden, HR Lite, Intranet Lite, and Essentials+ Calls remain independent,
optional modules. No mail platform is included; Mail remains an IMAP/SMTP
integration boundary.

## Activation and deactivation

Copy the non-secret local configuration once, then edit it deliberately:

```bash
cp config/office-modules.env.example config/office-modules.env
./scripts/office-module-preflight.sh --module vaultwarden
./scripts/office-module-deactivate.sh --module vaultwarden
```

The preflight refuses disabled modules, missing health URLs, credentials in
URLs, and failed health checks. Do not switch a module to `true` until the
service is configured and healthy. The deactivation script changes only the
local flag and prints the remaining manual visibility action; it deletes no
data.
