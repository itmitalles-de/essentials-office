# Simple Business design system

This product does not maintain a local copy of the visual rules. The exact
canonical source, commit, package, and version are pinned in
`/.simple-business-design-system.json`.

In the standard workspace, read the sibling checkout at
`../simple-business-design-system/docs/design-system/`. The canonical remote is
`itmitalles-de/simple-business-design-system`. Do not follow an unpinned branch.

Package and product-CI activation is intentionally pending because GitHub
Actions is currently blocked before checkout by the organization billing or
spending-limit state. Existing owned app UI remains legacy; new work must not
expand rule violations while migration is pending. Upstream Nextcloud UI is a
host-platform exception. Generated CSS/SVG stays app-local and production stays
Node-free.
