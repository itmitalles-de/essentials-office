# TODO

This is the authoritative repository handoff. Operational/recovery gates take
priority over feature work. Never infer live state from historical or synthetic
evidence.

## Current branch completion

- [x] Inspect `main`, `origin/main`, open PRs, remote branches, recent merges,
  Actions, repository instructions, and handoff statements.
- [x] Complete the Essentials+ Office/repository rename while preserving
  technical compatibility identifiers.
- [x] Add the eleven-class verification matrix and ideas-only nice-to-have file.
- [x] Add read-only deployment collection and fail-closed drift comparison.
- [x] Add real external IPv4/IPv6 DNS/TCP/TLS/HTTP/DAV inspection tooling.
- [x] Add offsite snapshot and independent-restore receipts plus acceptance,
  service-objective, and Caddy-drift runbooks.
- [x] Pin core/test images by exact tag and digest; retain exact Action SHAs;
  add SBOM and supply-chain policy checks.
- [x] Rehearse allowed same-major pins, major refusal, backup-before-pull,
  failed pull/start/health, maintenance exit, exact-image rollback, data-marker
  preservation, and repeated idempotence.
- [x] Run the current local static suite and record its evidence boundary.
- [x] Confirm exact-code-head Actions run `32203617530`: all five jobs passed.
  Local full disposable execution could not start without interactive host
  `sudo`; the class 3–7 claim comes only from GitHub Actions.
- [x] Commit the focused change groups, push
  `operations/office-external-gates`, and open a reviewable draft PR. Do not
  merge it. Draft PR #4 is open.
- [x] Update `.agent/STATE.md` with final commits, PR number, and the exact
  code-head Actions source. GitHub remains authoritative for a later
  documentation-only head run because recording that run would create another
  commit and run recursively.

## Mandatory external gates

- [ ] Receive an approved NUC SSH alias with existing noninteractive
  authentication; do not guess an IP, seek credentials, or modify SSH config.
- [ ] Collect the deployed commit, dirty state, exact images/digests, versions,
  Compose render, mounts, health, Caddy hashes/route, backup, restore, disk, and
  inode state read-only.
- [ ] Reconcile commit, Compose, image, module, and Caddy drift without reset,
  pull, restart, reload, or overwrite.
- [ ] Assign one responsible operator and approve or replace the proposed
  24-hour RPO, 8-hour RTO, nightly backup, and quarterly restore schedule.
- [ ] Approve an independent encrypted Restic target and protected credentials;
  create and check a real snapshot without altering retention.
- [ ] Restore that snapshot into a completely empty independent host/VM, pass
  all acceptance checks, record elapsed RTO, and guard-clean decrypted staging.
- [ ] Declare the intended IPv4/IPv6 strategy and repeat the ingress checker
  from an external network after infrastructure is intentionally configured.
- [ ] Reconcile complete shared-Caddy disk/runtime state and every existing site
  before any authorized validate/reload/rollback change.
- [ ] Rehearse the reviewed exact-pin update/rollback on staging or an authorized
  disposable target before any live update.

## Optional depth only after mandatory gates

- [ ] Disposable Collabora WOPI create/open/edit/save/reload/content comparison.
- [ ] Stable Intranet Lite post-restore object assertions beyond the current
  supported synthetic files, if deterministic APIs exist.
- [ ] Nextcloud Mail account flow against the existing synthetic TLS IMAP/SMTP
  fixture; no mail platform installation.
- [ ] Additional metrics freshness and update-failure coverage.

Do not implement HPB, mailcow, OIDC/SSO, new HR/Intranet/Vaultwarden functions,
new modules, migration, public registration, Kubernetes, or production data in
this workstream.
