# Essentials+ Office verification matrix

## Reading rules

Evidence classes are independent. A pass in one class does not make any other
class green. Every runtime claim records its observation date, observed host or
environment, Git commit, method, and proof boundary. `Open` and `unknown` are
valid results and must not be rewritten as passes.

| Class | Meaning | Current evidence | Status |
| --- | --- | --- | --- |
| 1. Static | Source, schemas, policies, and review without rendering or runtime | 2026-08-19 local Codex workspace and GitHub Actions run `32203617530`, exact code head `2a26fc9c1df1c016294b2f83f57b87ad62fabfc7`; targeted source/history review and static policy suite passed. Boundary: no service runtime or live host. | Current code-head pass |
| 2. Syntax/Render | Parsers, linters, Compose/Caddy render, and policy checks | 2026-08-19 same exact code head; `scripts/validate-static.sh` passed all Compose profiles, restore model, parsers, ShellCheck, Caddy validation, exact-pin policies, and full-history Gitleaks. Boundary: no service runtime. | Current code-head pass |
| 3. Synthetic Compose | Disposable containers with fictional data | 2026-08-19 Actions run `32203617530`, GitHub-hosted runner, exact code head `2a26fc9c1df1c016294b2f83f57b87ad62fabfc7`; clean deployment, module state, restart persistence, two update rehearsals, restore and cleanup passed. Boundary: not the NUC, offsite, ingress, or production. | Current synthetic pass |
| 4. Browser-E2E | Browser interaction against disposable services | Run `32203617530` passed the bounded Admin Center/admin/user and Vaultwarden browser flows at exact code head `2a26fc9`. Historical `main` run `31735217485` timed out in Admin Center Browser-E2E. Boundary: disposable browser only. | Current synthetic pass |
| 5. Local fake service | Local protocol fixture, not a real provider | Run `32203617530` passed TLS IMAP/SMTP and Essentials+ Calls contracts at exact code head `2a26fc9`; method: loopback fake services. Boundary: no Nextcloud Mail account, delivery, PBX, or production service. | Current synthetic pass |
| 6. Backup | Consistent backup-format creation and checksum verification | Run `32203617530` passed consistent PostgreSQL/files backups, redacted metadata, exact configured/running-image evidence, and checksums at exact code head `2a26fc9`. Historical NUC backup evidence remains dated 2026-08-13 at `3888bae`. Boundary: CI backup is synthetic; historical NUC backup is stale and same-host. | Current synthetic pass; historical NUC pass |
| 7. Local encrypted Restic test | Encrypted Restic repository and restore on the same disposable runner | Run `32203617530`, exact code head `2a26fc9`; temporary encrypted repository, full read check, receipt, full empty-target restore, and guarded cleanup passed. Boundary: not physically or administratively independent. | Current synthetic pass |
| 8. Independent offsite restore | Real encrypted snapshot restored on infrastructure independent of the NUC | No approved provider credentials, snapshot receipt, or independent restore host is present in repository evidence as of 2026-08-19. | Open — externally blocked |
| 9. Real NUC | Read-only observation of the actual deployment host | Historical observation only: 2026-08-13, host identified in Git solely as `NUC`, deployed commit `3888bae`, SSH inventory. Current authorized target alias and deployed revision are unknown. | Open — current access unproven |
| 10. Real DNS/TLS/Ingress | Public checks from a network outside the deployment LAN | 2026-08-19T00:39:49Z, `external-codex-runner`, clean `5bc726c7dedceb0f4d59d2d7d3da22555ead9188`; `scripts/check-external-ingress.sh cloud.itmitalles.de either cloud.itmitalles.de` returned no A or AAAA records (JSON SHA-256 `7d8e8018a9b7ce802f2bec021e8c41b1d360551e270bb6e522e33759fd39efb2`). Boundary: `either` was only a minimum availability probe; with no address, TCP, TLS, HTTP, DAV, and upload-path checks cannot run. | Fail — not publicly live |
| 11. Production | Real production workload and accepted operating responsibility | No production acceptance, operator assignment, independent restore, or current ingress/deployment proof exists. | Not accepted |

## Gate matrix

| Gate | Required accepting class | Repository capability | Last evidence | Current result |
| --- | --- | --- | --- | --- |
| Deployed Git revision | 9 or 11 | `scripts/collect-deployment-state.sh` | Historical NUC commit `3888bae` on 2026-08-13 | Unknown |
| Configuration drift | 9 or 11 | Collector plus `scripts/compare-deployment-state.py` | Historical Caddy disk/runtime match only, 2026-08-13 | Unknown |
| Encrypted offsite snapshot | 8 | Restic upload and repository check | Current local temporary Restic only at `2a26fc9` | Open |
| Independent restore | 8 | Empty-target restore harness and acceptance runbook | Current same-runner empty-target restore only at `2a26fc9` | Open |
| RPO/RTO and ownership | explicit operator decision | `docs/operations/SERVICE_LEVEL_OBJECTIVES.md` | No binding decision | Proposed/open |
| DNS/TLS/Ingress | 10 | `scripts/check-external-ingress.sh` | Clean exact-code-head external run on 2026-08-19T00:39:49Z found no A/AAAA; later checks were not applicable | Fail — not live |
| Controlled update/rollback | 3, then 9 before live use | `scripts/update.sh`, policy, and failure-injection rehearsal | 2026-08-19 exact-code-head static failure-injection tests and two disposable exact-pin update runs passed allowed pins, major refusal, backup-first, failed pull/start/health, maintenance exit, exact-image rollback, data-marker preservation, and idempotence | Repository rehearsal pass; live gate open |

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
