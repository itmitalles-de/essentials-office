# Optional Intranet Lite

Intranet Lite is Office's lightweight, Nextcloud-native intranet module:

- **Collectives** for durable internal knowledge;
- **Teams** (`circles` app) for membership and collaboration scope;
- **Dashboard** for each permitted user's overview;
- **Announcement Center** for administrator announcements.

It is off by default and is not a reason to install Wiki.js or BookStack in
parallel. A future standalone wiki requires its own product decision, data
ownership, lifecycle, and migration plan.

## Controlled activation

1. Copy `config/office-modules.env.example` locally and set only
   `OFFICE_MODULE_INTRANET_LITE_ENABLED=true` after reviewing scope.
2. Run `./scripts/intranet-lite-reconcile.sh --reconcile`. It enables compatible
   prerequisites only for `admin` and `office-user`; it never removes data.
3. Create the Intranet Collective, approved Teams, Dashboard widgets, and the
   first synthetic announcement manually. These apps lack a stable complete
   provisioning API, so record those four actions as the reproducible manual
   target state.
4. Run `./scripts/office-module-preflight.sh --module intranet-lite` and then
   perform the Admin Center visibility test with an `office-user` member and a
   user outside that group.

Disabling the module removes its entitlement/links only after administrator
review; do not delete app data, Collectives content, Teams, or volumes.
