# Changelog

## Unreleased — operating and recovery gates

### Changed

- Completed visible naming for **Essentials+ Office** and the repository
  `itmitalles-de/essentials-office` while preserving documented runtime
  compatibility identifiers.
- Replaced floating core image tags with reviewed exact tag-and-digest pins.
- Made update orchestration back up first, refuse unexpected majors, record old
  image IDs, and roll images back after start or health failure.
- Tightened offsite and restore evidence with secret-redacted receipts, core
  integrity, WebDAV roundtrip, share, cron, and stable object checks.
- Capture app and exact running-image evidence before the consistency snapshot
  intentionally stops cron; the first PR run exposed and preserved this
  ordering failure instead of weakening the backup assertion.
- Reprovision the disposable WebDAV probe credential after the update rehearsal
  intentionally replaces the app container; the remote-object persistence and
  byte-comparison assertions remain unchanged.
- Added bounded browser waits and diagnostics for the Admin Center timeout
  observed in `main` Actions run `31735217485`.
- Refreshed the exact `actions/upload-artifact` pin to v7.0.1, removing the
  deprecated Node 20 runtime warning without changing artifact retention.

### Added

- Eleven-class verification matrix and compatibility-identifier register.
- Read-only deployment-state collector and fail-closed drift comparator.
- External IPv4/IPv6 DNS, TCP, TLS, HTTP, and DAV checker.
- Independent offsite acceptance, service-objective, and Caddy-drift runbooks.
- Exact-pin supply-chain policy, repository SBOM job, and disposable
  update/rollback failure tests.

### Operational status

- No module or live service was activated by these changes.
- Exact-code-head Actions run `32203617530` passed all five jobs, including the
  full disposable Office/recovery job; this is synthetic classes 1–7 only.
- The deployed revision and drift remain unknown because no authorized NUC
  target alias was available on 2026-08-19.
- The clean exact-code-head external check at 2026-08-19T00:39:49Z found no
  `A` or `AAAA` for `cloud.itmitalles.de`; the service was not publicly live at
  that observation.
- A real encrypted offsite snapshot, independent restore, named operator, and
  approved RPO/RTO remain open external gates.

## 2026-08-13 — modular control plane merged

- Added the `essentialsplus` Nextcloud app and versioned Essentials+ Office module contract.
- Added default-inactive Collabora, Talk/TURN, Vaultwarden, Mail integration,
  HR Lite, Intranet Lite, and Essentials+ Calls boundaries.
- Added synthetic disposable browser, protocol, backup, local encrypted Restic,
  and empty-target restore coverage. These results are historical classes 1–7,
  not current NUC, independent offsite, ingress, or production evidence.
