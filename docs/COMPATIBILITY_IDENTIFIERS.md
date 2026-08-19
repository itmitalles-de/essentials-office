# Essentials+ Office compatibility identifiers

This document separates current product and repository names from technical
identifiers that remain stable to avoid an unnecessary migration.

| Kind | Current value | Status | Reason |
| --- | --- | --- | --- |
| Visible product name | **Essentials+ Office** | current | Public and operator-facing name. |
| GitHub repository | `itmitalles-de/essentials-office` | current | The administrative repository rename is complete. |
| Public Nextcloud service | `cloud.itmitalles.de` | intentionally unchanged | It is a service hostname, not the repository name. DNS and ingress remain separate operational gates. |
| Target checkout | `/opt/nextcloud` | intentionally unchanged | Existing scripts, service records, and recovery procedures depend on this path. |
| Persistent data root | `/srv/nextcloud` | intentionally unchanged | Renaming a populated data tree would add recovery risk without product value. |
| Shared proxy network | `proxy_net` | intentionally unchanged | The separately operated Caddy stack and Nextcloud use this interface. |
| Core Compose project | `nextcloud` | intentionally unchanged | Changing it would rename containers and networks and can cause unintended replacement resources. |
| Core container names | `nextcloud-app`, `nextcloud-cron`, `nextcloud-db`, `nextcloud-redis` | intentionally unchanged | Existing monitoring, Caddy routing, and runbooks refer to these identifiers. |
| Nextcloud volumes and service names | existing values in `compose.yaml` | intentionally unchanged | They are runtime identities, not visible branding. |
| Nextcloud app ID | `essentialsplus` | intentionally unchanged | App IDs are upgrade and database identifiers and must not be cosmetically renamed. |
| Module contract product ID | `essentialsplus-office` | intentionally unchanged | It is a versioned machine identifier already used by tests and persisted app state. |

Historical local checkout names, old Git branches, backup tags, or initialized
Restic repository paths may also remain in operational records. They do not
change the current product or repository name. Never move or rename an
initialized offsite repository merely for branding; create a reviewed migration
with a verified restore if such a change is ever required.
