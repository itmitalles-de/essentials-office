# Office architecture

## Product and operating model

**Office** is the Essentials Plus collaboration product. It is an integrated
user experience, not a single inseparable Compose stack. The existing Nextcloud
core remains the canonical file and groupware platform; optional components
remain independently startable, updateable, backupable, and removable from the
user interface without deleting data.

| Capability | Leading system | Operating form | Current state |
| --- | --- | --- | --- |
| Files, shares, versions | Nextcloud Files | existing core on the NUC | implemented core |
| Calendar, contacts, tasks | Nextcloud | Nextcloud apps / CalDAV / CardDAV | implemented core boundary |
| Appointment booking | Appointments in Nextcloud | repository-owned native app, PostgreSQL, cron, system mail | implemented optional module; external CalDAV sync deferred |
| Documents, spreadsheets, presentations | Nextcloud Office + Collabora | separate Collabora service | planned optional module |
| Chat and meetings | Nextcloud Talk | app first; TURN/HPB separate stages | planned optional module |
| Email transport and mailboxes | mailcow | separate upstream stack/host | planned optional module |
| Webmail | Nextcloud Mail | IMAP/SMTP against mailcow | planned optional module |
| Fallback webmail | SOGo | supplied by mailcow, optional | planned with mailcow |
| Intranet Lite | Collectives, Teams, Dashboard, Announcement Center | Nextcloud-native composite | contract and reconciler implemented; inactive |
| HR Lite | Groups, Tables, Forms, Deck, Calendar, Collectives, files | limited Nextcloud workflow | contract/templates/reconciler implemented; inactive |
| Password vault | Vaultwarden | separate optional Compose profile | overlay/backup/restore implemented; inactive |
| Telephony | Visual PBX | separate `itmitalles-de/visual-pbx` product | disabled integration contract only |
| Identity/SSO | OIDC | later shared architecture stage | planned |

## Essentials Plus module contract and Admin Center

[`office-modules.json`](../office-modules.json) is the versioned module
contract. Modules are grouped as Collaboration, Knowledge and intranet, People
operations, Security and access, and External integrations. `nextcloud-core` is
the only default-active module. Administrators see the full catalog through a
restricted Office Admin Center Collective; ordinary users see a module only
when it is active, healthy, and restricted to a group they belong to.

External services must pass a configured health check before an administrator
publishes their group-restricted link. Deactivation removes an entitlement or
link only; it never removes data, volumes, databases, or backups. The repository
does not contain a second portal service or automatic DNS/NUC change.

Appointments is the exception that must be technically enabled instance-wide
while active because it owns anonymous public routes. Its internal controllers
still enforce organization-scoped Nextcloud-group permissions, and each public
booking page has a separate default-off organization flag. Logical module
deactivation disables the app without deleting its tables.

## Hard boundaries

- Preserve `/opt/nextcloud`, `/srv/nextcloud`, shared Caddy, and `proxy_net`.
- Nextcloud, Collabora, mailcow, Vaultwarden, and Visual PBX share neither a
  database nor secrets. mailcow remains a separate stack or host.
- Nextcloud is canonical for calendar, contacts, and tasks. SOGo is optional
  fallback webmail, never a second canonical groupware store.
- Appointments is authoritative for its booking records. The first milestone
  exports ICS but does not claim external CalDAV update/delete or busy import;
  that synchronization must stay behind a reviewed provider boundary.
- Vaultwarden has a separate `/srv/vaultwarden` persistence/backup boundary;
  its profile publishes no host port and is private by default.
- Intranet Lite is Collectives/Teams/Dashboard/Announcement Center only;
  Wiki.js and BookStack are not parallel default deployments.
- HR Lite uses only synthetic data and supported OCC/WebDAV/OCS interactions;
  no payroll, ATS, time tracking, or Nextcloud SQL manipulation.
- Visual PBX has no service, Caddy route, public proxy, credentials, source
  merge, or shared store in this repository. OIDC/SSO and group mapping are
  later stages after PBX authentication, roles, SIP-secret storage, rights, and
  health gates are independently proven.
- No big-bang Compose deployment and no automatic major-version upgrades.

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

Collabora / Talk / mailcow / Visual PBX: separate optional lifecycles
```

The default `compose.yaml` starts only the existing Nextcloud core. The
Vaultwarden profile adds one container on `proxy_net`, no host port, and no
connection to the Nextcloud backend. The Caddy route stays absent until the
complete shared configuration is reconciled and validated.

## Staged rollout

1. Keep the Nextcloud core publicly secure only after Caddy/DNS/reachability,
   offsite backup, and disposable restore prerequisites are verified.
2. Complete the Office Admin Center and synthetic HR/Intranet manual target
   states; test group visibility and least privilege.
3. Install and migrate Appointments, validate its disposable tenant/race/DST
   tests, then publish organization booking pages individually.
4. Run Vaultwarden's private-profile backup/restore and Caddy checks on an
   approved disposable target before enabling any entitlement.
5. Integrate Collabora, then Talk P2P, TURN, and HPB as separate stages.
6. Deploy mailcow separately only on suitable infrastructure, then connect
   Nextcloud Mail through IMAP/SMTP.
7. Revisit Visual PBX only after its release gates; evaluate OIDC/SSO only when
   each independently operated module is stable.

## Capacity decision

The NUC has 16 GiB RAM. The existing Nextcloud core is the baseline. The
Vaultwarden SQLite profile is small but still requires protected storage,
backups, and recovery testing. Collabora and Talk add material load; mailcow
documents at least 6 GiB RAM plus swap. A fully active Office estate on one NUC
is not a production default. For production, keep mail and potentially
TURN/HPB on separate infrastructure and measure each optional module before
activation.
