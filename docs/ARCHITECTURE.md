# Essentials+ Office architecture

## Product and operating model

**Essentials+ Office** is the collaboration product. It is an integrated
user experience, not a single inseparable Compose stack. The existing Nextcloud
core remains the canonical file and groupware platform; optional components
remain independently startable, updateable, backupable, and removable from the
user interface without deleting data.

| Capability | Leading system | Operating form | Current state |
| --- | --- | --- | --- |
| Files, shares, versions | Nextcloud Files | core Compose stack | implemented; current NUC state unknown |
| Calendar, contacts, tasks | Nextcloud | Nextcloud apps / CalDAV / CardDAV | implemented core boundary |
| Documents, spreadsheets, presentations | Nextcloud Office + Collabora | separate optional Collabora service | overlay implemented; inactive |
| Chat and meetings | Nextcloud Talk | app plus separate optional TURN service | overlay/contract implemented; inactive |
| Mail | Nextcloud Mail | IMAP/SMTP integration boundary only | contract and synthetic TLS fixture implemented; inactive |
| Intranet Lite | Collectives, Teams, Dashboard, Announcement Center | Nextcloud-native composite | contract and reconciler implemented; inactive |
| HR Lite | Groups, Tables, Forms, Deck, Calendar, Collectives, files | limited Nextcloud workflow | contract/templates/reconciler implemented; inactive |
| Password vault | Vaultwarden | separate service and optional Compose profile | overlay/backup/restore implemented; inactive |
| Calls | Essentials+ Calls | external integration only | disabled integration contract only |

## Essentials+ Office module contract and Admin Center

[`office-modules.json`](../office-modules.json) is the versioned module
contract. Modules are grouped as Collaboration, Knowledge and intranet, People
operations, Security and access, and External integrations. `nextcloud-core` is
the only default-active module. Administrators see the full catalog through a
restricted Essentials+ Office Admin Center Collective; ordinary users see a module only
when it is active, healthy, and restricted to a group they belong to.

External services must pass a configured health check before an administrator
publishes their group-restricted link. Deactivation removes an entitlement or
link only; it never removes data, volumes, databases, or backups. The repository
does not contain a second portal service or automatic DNS/NUC change.

## Hard boundaries

- Preserve `/opt/nextcloud`, `/srv/nextcloud`, shared Caddy, and `proxy_net`.
- Nextcloud, Collabora, Vaultwarden, TURN, and Essentials+ Calls share neither a
  database nor secrets.
- Nextcloud is canonical for calendar, contacts, and tasks. Mail remains an
  integration boundary; this repository does not install a mail platform.
- Vaultwarden has a separate `/srv/vaultwarden` persistence/backup boundary;
  its profile publishes no host port and is private by default.
- Intranet Lite is Collectives/Teams/Dashboard/Announcement Center only;
  Wiki.js and BookStack are not parallel default deployments.
- HR Lite uses only synthetic data and supported OCC/WebDAV/OCS interactions;
  no payroll, ATS, time tracking, or Nextcloud SQL manipulation.
- Essentials+ Calls has no service, Caddy route, public proxy, credentials,
  source merge, or shared store in this repository.
- No big-bang Compose deployment and no automatic major-version upgrades.
- HPB, mailcow installation, OIDC/SSO, user migration, and new module work are
  outside the current operating-gates scope.

## Deployment topology

```text
internet
   |
shared Caddy (outside this repository) ---- private, opt-in route ---- Vaultwarden :8080
   | proxy_net                                                  (no host port)
Nextcloud app :80
   |                 \
internal backend       egress
PostgreSQL + Redis     cron

Collabora / Talk+TURN / Vaultwarden: separate optional lifecycles
Essentials+ Calls: external integration only
```

The default `compose.yaml` starts only the existing Nextcloud core. The
Vaultwarden profile adds one container on `proxy_net`, no host port, and no
connection to the Nextcloud backend. This repository installs no Caddy route;
the live route is unknown until the complete shared configuration is collected,
reconciled, and validated.

## Staged rollout

1. Establish the actual deployed commit and configuration drift read-only.
2. Accept a real encrypted offsite snapshot through an independent empty-target
   restore, then assign RPO/RTO and operating responsibility.
3. Prove DNS, IPv4/IPv6, TCP, TLS, HTTP, and DAV from an external network and
   reconcile shared Caddy without altering unrelated sites.
4. Rehearse the exact-pinned update and rollback path before any live update.
5. Only after those gates, accept each already implemented optional module in a
   separate disposable and operational stage. Default state remains inactive.

## Capacity decision

The historical read-only NUC observation on 2026-08-13 at deployed commit
`3888bae` recorded 14 GiB usable RAM and roughly 111 MiB of idle core-container
memory. That point sample is neither current capacity nor load evidence. A
fresh collector report and workload measurement are required before activating
Collabora, Talk/TURN, or Vaultwarden. A fully active Essentials+ Office estate
on one NUC is not a production default.
