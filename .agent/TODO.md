# TODO

This is the authoritative repository handoff. Do not create a competing root
task list, infer live state from dated evidence, or touch production systems.

## Appointments milestone (2026-08-20)

- [x] Add the separate native `appointments` app and optional-module contract.
- [x] Add the relational tenant schema and validate its fresh migration.
- [x] Implement services, staff profiles, locations, resources, availability,
  public booking, internal appointment management, customer self-service,
  notifications, ICS, retention, audit, observability, and fictional demo data.
- [x] Prove the complete anonymous-to-internal browser journey, cancellation and
  slot release, one-winner same-slot concurrency, and tenant isolation against
  a clean disposable Nextcloud/PostgreSQL deployment.
- [x] Pass the repository static, unit, contract, syntax, translation, and
  security checks and document all unsupported integration claims.
- [x] Re-audit customer exports, management-token scope, RBAC response fields,
  cache headers, DST ambiguity, input bounds, notifications, and the complete
  combined/isolated CI paths; fix and regression-test every confirmed issue.
- [ ] Before production publication, manually verify the real system-mail
  sender and client rendering, Caddy rate-limit/access-log behavior,
  keyboard/screen-reader behavior, and encrypted offsite restore.
- [ ] Activate CalDAV busy import/write synchronization or Nextcloud Talk only
  as a separately reviewed roadmap milestone; the current providers must remain
  disabled until their failure and retry semantics are proven.

Appointments-specific deferred product scope is authoritative in
`docs/roadmap.md`; do not add stubs or dependencies for those items merely to
make them appear present.

## Existing platform backlog (predates Appointments)

- [x] Finish the disposable TLS Vaultwarden browser flow: synthetic account
  login, organization, collection, owner/member roles, and group; then rerun
  consistent SQLite backup, checksum verification, encrypted temporary Restic
  roundtrip, and restore to a completely empty target.
- [x] Run the combined clean deployment harness with automated browser Admin
  Center, recovery, HR Lite, Intranet Lite, and Talk flows. Prove second-run
  idempotence, permissions, restart persistence, WebDAV data/share recovery,
  content/volume preservation across logical module deactivation, and complete
  resource cleanup. Exact-head GitHub Actions run `31730633740` passed all four
  jobs for `520c239`; its 13m25s combined job completed the automated browser,
  second deployment, encrypted temporary Restic, empty-target restore,
  WebDAV/share, cron, and cleanup path.
- [x] Correct every failure found by that combined run. Do not weaken assertions
  merely to make the suite green, and do not claim app-specific objects that
  could not be provisioned through supported interfaces.
- [x] Inspect the complete diff against current `origin/main`. The branch is 17
  commits ahead and 0 behind, with 128 intended changed files; PR #2 has no
  review or issue comments. Exact-head static validation and full-history
  Gitleaks passed.
- [ ] Update visible branding and documentation to **Essentials+ Office**:
  README, architecture, operations, backup/restore, security, module overview,
  `docs/CODEX_PROMPT.md`, changelog, agent decisions/architecture, and handoff.
- [ ] Create `docs/VERIFICATION_MATRIX.md` with the exact evidence classes:
  static, synthetic Compose, browser E2E, backup/restore, local fake service,
  NUC, public external, and production. Mark unsupported claims as unverified.
- [ ] Create `docs/NICE_TO_HAVE.md` containing only the requested future items;
  add no code, stubs, images, or dependencies for them.
- [x] Push the focused handoff and validation fixes to
  `agent/essentials-office-autonomous`. Code and dated verification evidence are
  pushed through runtime head `520c239` plus the following handoff-only update;
  inspect GitHub for the live state of superseding PR #2.

## Functional gaps to resolve or document honestly

- [ ] Automate Collabora create/open/edit/reload through WOPI if it can be done
  reproducibly without weakening the service boundary. Current evidence covers
  only health, discovery, host allow-list, and restart recovery.
- [x] Verify Talk P2P room/participant/message/permission flows in the combined
  run. The disposable flow passes, including outsider rejection and logical
  disable/reactivation data preservation. Keep TURN optional; implement
  HPB only if cleanly reproducible and separated. Never infer real NAT/media
  quality from a local test.
- [x] Verify HR Lite fictional directory, onboarding/offboarding, absence,
  responsibilities, templates, protected files, and least-privilege groups.
- [ ] Verify Intranet Lite fictional content, editors/readers, confidential area,
  search/API availability, backup/restore, and content-preserving deactivation.
  Targeted activation/deactivation and content preservation pass; combined
  Nextcloud restore remains unconfirmed at this pause.
- [ ] Exercise Nextcloud Mail configuration against the synthetic TLS IMAP/SMTP
  server or document the smallest supported remaining step. Do not embed mailcow.
- [ ] Verify metrics, cron freshness, backup age, last restore evidence,
  compatibility reporting, controlled patch/minor update, unexpected-major
  refusal, and the disposable failed-update/rollback path.

## Blocked — external mandatory gates

- [ ] Compare the real running Caddy configuration with the repository file.
- [ ] Verify public IPv4 and IPv6 reachability.
- [ ] Verify TCP 80/443 from a genuinely external network.
- [ ] Verify real DNS.
- [ ] Verify real TLS certificates.
- [ ] Verify actual NUC resources and runtime behavior.
- [ ] Configure and prove a real encrypted offsite provider. A temporary local
  Restic repository is not offsite evidence.
- [ ] Verify production mail deliverability and PTR/rDNS.
- [ ] Verify real Talk media quality through NAT.
- [ ] Plan and verify the real Dropbox data migration.

## Recently completed

- [x] Incorporated draft PR #1 instead of recreating it, merged current `main`
  into the local work branch, and preserved the default branch/repository.
- [x] Added the Essentials+ module manifest/reconciliation contract and safe
  Nextcloud Admin Center/API/OCC implementation.
- [x] Added separate optional Vaultwarden, Collabora, Talk/TURN, Mail, HR Lite,
  Intranet Lite, and Essentials+ Calls boundaries with inactive defaults.
- [x] Hardened secret handling, backup evidence, restore checks, metrics, image
  major-version policy, fake service contracts, and disposable test harnesses.
- [x] Proved the closed Vaultwarden product profile, TLS browser organization/
  collection/role/group flow, encrypted backup, and empty-target restore with
  synthetic data only.
- [x] Passed the exact-head combined clean deployment, automated Admin/user
  browser flow, HR/Intranet/Talk checks, second deployment, encrypted temporary
  Restic roundtrip, and full empty-target Nextcloud restore in CI run
  `31730633740`.
- [x] Kept all real NUC, Caddy, DNS, network, backups, and user data untouched.
