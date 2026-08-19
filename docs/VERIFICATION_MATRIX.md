# Essentials+ Office verification matrix

## Reading rules

Evidence classes are independent. A pass in one class does not make any other
class green. Every runtime claim records its observation date, observed host or
environment, Git commit, method, and proof boundary. `Open` and `unknown` are
valid results and must not be rewritten as passes.

| Class | Meaning | Current evidence | Status |
| --- | --- | --- | --- |
| 1. Static | Source, schemas, policies, and review without rendering or runtime | 2026-08-19 local Codex workspace based on `17081f2` plus this working tree; targeted source/history review and static policy suite passed. Boundary: not yet an exact committed PR head. | Working-tree pass |
| 2. Syntax/Render | Parsers, linters, Compose/Caddy render, and policy checks | 2026-08-19 same workspace/tree; `scripts/validate-static.sh` passed all Compose profiles, restore model, parsers, ShellCheck, Caddy validation, exact-pin policies, and full-history Gitleaks. Boundary: no service runtime. | Working-tree pass |
| 3. Synthetic Compose | Disposable containers with fictional data | Historical CI run `31730633740` on GitHub-hosted runner, commit `520c239`; clean core, module, persistence, and cleanup flow. Boundary: not the NUC, offsite, ingress, or production. | Historical pass |
| 4. Browser-E2E | Browser interaction against disposable services | Run `31730633740` passed Admin Center/user portal at `520c239`. Run `31734149298` passed the Vaultwarden browser flow at `ce483e4`. The later `main` run `31735217485` at `17081f2` timed out in Admin Center Browser-E2E after other assertions passed. | Current-head failure recorded |
| 5. Local fake service | Local protocol fixture, not a real provider | Historical CI at `520c239` passed TLS IMAP/SMTP and Essentials+ Calls contracts; method: loopback fake services; boundary: no Nextcloud Mail account, delivery, PBX, or production service. | Historical pass |
| 6. Backup | Consistent backup-format creation and checksum verification | Historical NUC observation on 2026-08-13, observed host recorded only as `NUC` in the source document, commit `3888bae`; local backup and checksum verification. Boundary: same-host storage and stale observation. | Historical pass |
| 7. Local encrypted Restic test | Encrypted Restic repository and restore on the same disposable runner | CI run `31730633740`, GitHub-hosted runner, commit `520c239`; temporary repository, full read check, empty-target restore. Boundary: not physically or administratively independent. | Historical pass |
| 8. Independent offsite restore | Real encrypted snapshot restored on infrastructure independent of the NUC | No approved provider credentials, snapshot receipt, or independent restore host is present in repository evidence as of 2026-08-19. | Open — externally blocked |
| 9. Real NUC | Read-only observation of the actual deployment host | Historical observation only: 2026-08-13, host identified in Git solely as `NUC`, deployed commit `3888bae`, SSH inventory. Current authorized target alias and deployed revision are unknown. | Open — current access unproven |
| 10. Real DNS/TLS/Ingress | Public checks from a network outside the deployment LAN | 2026-08-18T23:53:19Z, `external-codex-runner`, working tree based on `17081f2`; `scripts/check-external-ingress.sh cloud.itmitalles.de either cloud.itmitalles.de` returned no A or AAAA records. Boundary: with no address, TCP, TLS, HTTP, DAV, and upload-path checks cannot run. | Fail — not publicly live |
| 11. Production | Real production workload and accepted operating responsibility | No production acceptance, operator assignment, independent restore, or current ingress/deployment proof exists. | Not accepted |

## Gate matrix

| Gate | Required accepting class | Repository capability | Last evidence | Current result |
| --- | --- | --- | --- | --- |
| Deployed Git revision | 9 or 11 | `scripts/collect-deployment-state.sh` | Historical NUC commit `3888bae` on 2026-08-13 | Unknown |
| Configuration drift | 9 or 11 | Collector plus `scripts/compare-deployment-state.py` | Historical Caddy disk/runtime match only, 2026-08-13 | Unknown |
| Encrypted offsite snapshot | 8 | Restic upload and repository check | Local temporary Restic only at `520c239` | Open |
| Independent restore | 8 | Empty-target restore harness and acceptance runbook | Same-runner empty-target restore only at `520c239` | Open |
| RPO/RTO and ownership | explicit operator decision | `docs/operations/SERVICE_LEVEL_OBJECTIVES.md` | No binding decision | Proposed/open |
| DNS/TLS/Ingress | 10 | `scripts/check-external-ingress.sh` | External run on 2026-08-18T23:53:19Z found no A/AAAA; later checks were not applicable | Fail — not live |
| Controlled update/rollback | 3, then 9 before live use | `scripts/update.sh`, policy, and failure-injection rehearsal | 2026-08-19 working-tree test passed allowed pins, major refusal, backup-first, failed pull/start/health, maintenance exit, exact-image rollback, data-marker preservation, and idempotence | Repository rehearsal pass; live gate open |

## Evidence recording template

Use this minimum record for every new operational assertion:

| Field | Value |
| --- | --- |
| Observed at (UTC) | ISO 8601 timestamp |
| Observed host/environment | Explicit host or environment class; do not infer it |
| Repository commit | Full 40-character commit or `unknown` |
| Method | Exact script/runbook and relevant options |
| Evidence class | One class from 1 through 11 |
| Result | pass, fail, open, or unknown |
| Proof boundary | What this observation does not establish |
