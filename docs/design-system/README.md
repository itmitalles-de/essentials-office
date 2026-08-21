# Simple Business design system

This product does not maintain a local copy of the visual rules. The exact
canonical source, commit, package, and version are pinned in
`/.simple-business-design-system.json`.

In the standard workspace, read the sibling checkout at
`../simple-business-design-system/docs/design-system/`. The canonical remote is
`itmitalles-de/simple-business-design-system`. Do not follow an unpinned branch.

Root-level development tooling installs the exact public `v0.1.1` release
artifact named in the manifest. It generates deterministic token CSS, the icon
sprite, and a version manifest into each owned Nextcloud app. CI rejects asset
drift and violations of the shared icon semantics. Existing owned app UI remains
legacy; this activation does not claim that every historical visual rule
violation has already been migrated. Upstream Nextcloud UI is a host-platform
exception. Generated assets stay app-local and production stays Node-free.
