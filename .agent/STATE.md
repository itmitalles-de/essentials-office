# Current State

## Repository and product

- Visible product: **Essentials+ Office**.
- GitHub repository: `itmitalles-de/essentials-office`; the rename is complete.
- Compatibility identifiers intentionally retained: `cloud.itmitalles.de`,
  `/opt/nextcloud`, `/srv/nextcloud`, `proxy_net`, existing Compose/service
  identities, app ID `essentialsplus`, and product ID `essentialsplus-office`.
- Default branch: `main`. Current work branch:
  `operations/office-external-gates`.

At initial inspection on 2026-08-19, local and `origin/main` were both
`17081f20704e77dea6d1c983bdf8f2bde779e8f2` and no PR was open. The three other
remote work branches were merged into `main`; recent merges were PR #2 at
`bd266f3` and PR #3 at `17081f2`. The latest `main` Actions run
`31735217485` passed static, secret-scan, and isolated-module jobs but timed out
in Admin Center Browser-E2E inside `disposable-office`.

Current delivery is draft PR
[#4](https://github.com/itmitalles-de/essentials-office/pull/4), which remains
unmerged. Its code head is
`2a26fc9c1df1c016294b2f83f57b87ad62fabfc7`; the focused commits are `47a3cd8`
(rename/evidence boundaries), `5c8f680` (operational tooling), `5bc726c`
(recovery/update rehearsals), and `6e9ca74` (capture backup runtime evidence
before the intentional cron stop), `1102168` (refresh the pinned artifact-upload
runtime), and `2a26fc9` (reprovision only the disposable WebDAV probe credential
after intentional app-container replacement). Exact-code-head Actions run
`32203617530` passed all five jobs and is the acceptance source for repository
classes 1–7.

## Operational-gates branch

This branch adds no product module and activates nothing. It adds or hardens:

- complete Essentials+ Office/repository rename documentation plus a register
  of compatibility identifiers;
- an eleven-class verification matrix with no evidence inheritance;
- read-only deployment-state collection as secret-redacted JSON/Markdown/SHA,
  and a fail-closed comparator for commit, dirty state, redacted/effective
  Compose, configured/running images, modules, Caddy, evidence freshness,
  backup age, restore age, and demonstrated RTO;
- an external IPv4/IPv6 DNS/TCP/TLS/HTTP/DAV checker that tests every resolved
  address independently and never changes DNS, router, or Caddy;
- root-only Restic snapshot and independent-restore receipts;
- empty-target restore checks for OCC, repair, core integrity, database, Redis,
  cron, WebDAV upload/download/delete, shares, and stable HR/Intranet fixtures;
- exact tag-and-digest pins for Nextcloud 34.0.2, PostgreSQL 17.10, Redis
  7.4.10, runtime/test containers, and Actions;
- controlled same-major update orchestration with pre-update backup, exact old
  image-ID rollback, reliable maintenance exit, and failure injection tests;
- SBOM generation and supply-chain policy checks; and
- bounded Browser-E2E waits and diagnostics for the observed `main` timeout.

Optional Collabora, Talk/TURN, Vaultwarden, Mail integration, HR Lite, Intranet
Lite, and Essentials+ Calls retain their previous default-inactive boundaries.
No HPB, mail platform, OIDC/SSO, migration, new Vaultwarden function, or new
module was added.

## Evidence

### Current branch, repository classes 1–7

On 2026-08-19, exact code head `2a26fc9c1df1c016294b2f83f57b87ad62fabfc7`
passed the local `scripts/validate-static.sh` suite: Compose/profile renders,
syntax, ShellCheck, module contracts, exact pins, full-history Gitleaks, SBOM
policy, drift fixtures, update policy, and failed pull/start/health rollback
rehearsals. Actions run `32203617530` passed static validation, full-history
secret scan, SBOM, isolated modules, and the complete disposable Office job.
The latter passed deployment, module reconciliation, read-only state/redaction,
Admin Center browser flow, restart persistence, two update rehearsals, local
encrypted Restic, full empty-target restore, evidence receipt, and guarded
cleanup. This remains synthetic evidence and cannot establish the NUC, offsite
independence, successful ingress, or production.

The full local disposable suite did not start because host `sudo` required
interactive authentication. No password was requested or supplied. Current
class 3–7 evidence therefore comes only from the exact-code-head Actions run.

### Historical synthetic classes 1–7

Actions run `31730633740` on commit `520c239` passed the combined disposable
browser/module/backup/local-encrypted-Restic/empty-target-restore flow. It used
fictional data on one GitHub-hosted runner and is not offsite or live evidence.
The later `main` timeout at `17081f2` remains historical failure evidence;
exact-code-head run `32203617530` passed the bounded Admin Center browser flow.

### External and live classes 8–11

- External ingress observation at `2026-08-19T00:39:49Z` from
  `external-codex-runner`, clean commit
  `5bc726c7dedceb0f4d59d2d7d3da22555ead9188`: no `A` or `AAAA` for
  `cloud.itmitalles.de`; all later ingress checks were not applicable. The JSON
  SHA-256 was
  `7d8e8018a9b7ce802f2bec021e8c41b1d360551e270bb6e522e33759fd39efb2`.
- SSH configuration, repository documentation, scripts, and existing
  noninteractive paths were inspected on 2026-08-19. No alias could be tied to
  the NUC, so no authentication was attempted and no configuration changed.
- Historical NUC evidence exists only for 2026-08-13 at clean commit
  `3888bae`, with the host recorded merely as `NUC`. It cannot establish current
  revision or drift.
- No approved Restic provider credentials, real snapshot receipt, independent
  restore host/receipt, named operator, approved RPO/RTO, or production
  acceptance exists in repository evidence.

## Gate status

| Gate | Current result |
| --- | --- |
| Deployed Git revision | unknown; current NUC access unavailable |
| Compose/image/module/Caddy drift | unknown; collector ready |
| Real encrypted offsite snapshot | externally blocked; no approved target/credentials |
| Independent restore | externally blocked; no independent host/receipt |
| RPO/RTO | proposed 24h/8h; operator and approval unassigned |
| DNS/TLS/ingress | fail/not publicly live at last external observation |
| Update/rollback | repository rehearsal passes; live acceptance blocked by earlier gates |
| Production | not accepted |

## Resume point

The branch is committed, pushed, and in an unmerged draft PR. Inspect the live
PR for the newest self-referential documentation-only CI run rather than
inferring it from this committed file. The next single useful external
operating action is to provide an approved noninteractive SSH alias for the
real NUC and collect its read-only baseline. Do not update, pull, restart,
reload Caddy, enable modules, or import real data before reconciliation and
independent recovery acceptance.
