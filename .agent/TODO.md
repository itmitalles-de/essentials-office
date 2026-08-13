# TODO

This is the authoritative repository handoff. Do not create a competing root
task list, infer live state from dated evidence, or touch production systems.

## Now — paused autonomous validation

- [x] Finish the disposable TLS Vaultwarden browser flow: synthetic account
  login, organization, collection, owner/member roles, and group; then rerun
  consistent SQLite backup, checksum verification, encrypted temporary Restic
  roundtrip, and restore to a completely empty target.
- [ ] Run the combined clean deployment harness with automated browser Admin
  Center, recovery, HR Lite, Intranet Lite, and Talk flows. Prove second-run
  idempotence, permissions, restart persistence, WebDAV data/share recovery,
  content/volume preservation across logical module deactivation, and complete
  resource cleanup. GitHub Actions run `31720924809` for exact PR head `2bea9e7`
  passed static validation, full-history secret scan, and isolated modules. Its
  combined job reached module controls and failed at a pipefail-sensitive
  `occ | rg -q` metrics assertion. The harness now captures complete metrics
  output before matching it. Targeted Intranet and Talk flows pass activation,
  permissions, disable preservation, restart, and second deployment; browser
  Admin Center and combined recovery still need the follow-up run result.
- [ ] Correct every failure found by that combined run. Do not weaken assertions
  merely to make the suite green, and do not claim app-specific objects that
  could not be provisioned through supported interfaces.
- [ ] Inspect the complete diff against `main`. The exact-tree local static
  suite, ShellCheck container, actionlint, JSON/XML/template checks, and PR-head
  full-history gitleaks passed before this pause.
- [ ] Update visible branding and documentation to **Essentials+ Office**:
  README, architecture, operations, backup/restore, security, module overview,
  `docs/CODEX_PROMPT.md`, changelog, agent decisions/architecture, and handoff.
- [ ] Create `docs/VERIFICATION_MATRIX.md` with the exact evidence classes:
  static, synthetic Compose, browser E2E, backup/restore, local fake service,
  NUC, public external, and production. Mark unsupported claims as unverified.
- [ ] Create `docs/NICE_TO_HAVE.md` containing only the requested future items;
  add no code, stubs, images, or dependencies for them.
- [ ] Push the local pause-handoff commit plus any later focused fixes to
  `agent/essentials-office-autonomous`. Code fixes are already pushed through
  `2bea9e7`; superseding PR #2 remains draft and neither PR was merged.

## Functional gaps to resolve or document honestly

- [ ] Automate Collabora create/open/edit/reload through WOPI if it can be done
  reproducibly without weakening the service boundary. Current evidence covers
  only health, discovery, host allow-list, and restart recovery.
- [ ] Verify Talk P2P room/participant/message/permission flows in the combined
  run. The targeted disposable flow passes, including disable/reactivation data
  preservation; confirm it in run `31720924809`. Keep TURN optional; implement
  HPB only if cleanly reproducible and separated. Never infer real NAT/media
  quality from a local test.
- [ ] Verify HR Lite fictional directory, onboarding/offboarding, absence,
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
- [x] Kept all real NUC, Caddy, DNS, network, backups, and user data untouched.
