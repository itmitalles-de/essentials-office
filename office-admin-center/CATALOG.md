# Office Admin Center

**Office** is the Essentials Plus collaboration product. This page is the complete
administrator catalog; it is not an entitlement list for ordinary users.

## Collaboration

| Module | Default | Audience when active | Activation gate |
| --- | --- | --- | --- |
| Files and groupware | active | all authenticated users | existing Nextcloud health check |
| Office documents | inactive | `office-user` | configured Collabora plus HTTPS health check |
| Chat and meetings | inactive | `office-user` | configured Talk path plus HTTPS health check |
| Mail | inactive | `office-user` | separately operated mailcow/host plus HTTPS health check |

## Knowledge and intranet

| Module | Default | Audience when active | Activation gate |
| --- | --- | --- | --- |
| Intranet Lite | inactive | `office-user` | Collectives, Teams, Dashboard, and Announcement Center are compatible and enabled |

Intranet Lite uses Nextcloud Collectives, Teams (the `circles` app), Dashboard,
and Announcement Center. Do not install Wiki.js or BookStack as a second,
parallel default wiki.

## People operations

| Module | Default | Audience when active | Activation gate |
| --- | --- | --- | --- |
| HR Lite | inactive | `hr-admin`, `manager`, `employee` | synthetic workflow has passed its group and permission check |

## Security and integrations

| Module | Default | Audience when active | Activation gate |
| --- | --- | --- | --- |
| Password vault | inactive | `office-user` | isolated Vaultwarden health check and private HTTPS route |
| Visual PBX | inactive | `office-user` | separate product has all release gates and a successful health check |

Disabling a module only removes its entitlement/link after the relevant manual
administration action. It never removes a database, volume, backup, or user
content.
