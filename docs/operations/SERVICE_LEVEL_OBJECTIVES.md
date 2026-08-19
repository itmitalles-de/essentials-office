# Essentials+ Office service-level objectives

## Decision status

The values below are **proposed internal recovery objectives**, not an SLA or a
customer promise. They become binding only when an accountable operator and
their escalation path approve them after the first independent restore test.

| Item | Proposed target | Current decision/evidence |
| --- | --- | --- |
| Recovery point objective (RPO) | at most 24 hours of accepted data loss | Proposed; no binding owner decision. |
| Recovery time objective (RTO) | service restored on replacement infrastructure within 8 hours of incident declaration | Proposed; not demonstrated on independent infrastructure. |
| Backup frequency | one encrypted offsite snapshot every night after a consistent local backup | A timer unit is committed; live timer state is unknown and policy requires it disabled until class 8 acceptance. |
| Restore rehearsal frequency | quarterly and after backup-format, database-major, or storage-provider changes | Proposed. |
| Maximum accepted offsite backup age | 30 hours | Proposed; collector/comparator can enforce the threshold once evidence exists. |
| Maximum accepted independent restore age | 100 days | Proposed. |
| Responsible operator | `UNASSIGNED — one named Essentials+ Office operator required` | Gate open. |
| Maintenance window | proposed: one announced four-hour window outside business hours | Exact weekday/time unassigned. |
| Escalation | proposed: operator → infrastructure owner → service owner/data owner | People and contact channels unassigned; do not put personal contact data in Git. |

## Dependencies

- DNS must resolve the intended IPv4/IPv6 strategy and remains independently
  administered.
- Shared Caddy must retain all existing sites, have matching understood disk
  and runtime configuration, and pass validation before reload.
- The NUC remains a single compute failure domain until replacement
  infrastructure is prepared.
- The offsite provider, protected Restic password, backend credentials, and a
  second recovery copy of the password are all required for recovery.
- The Git commit recorded in the backup and the matching pinned container
  images must remain retrievable.

## Failure behavior

When a scheduled backup fails:

1. Do not delete the previous accepted snapshot or change retention.
2. Record the failure time and last successful offsite snapshot without
   including secrets or repository URLs.
3. Alert the named operator immediately after the first failure.
4. Retry only after the cause is understood; do not hide consecutive failures.
5. If snapshot age exceeds 30 hours, mark the RPO gate failed and freeze
   nonessential updates and data migrations.

When a restore rehearsal fails:

1. Keep the source service unchanged and public routing disabled on the restore
   target.
2. Preserve secret-redacted logs and the exact failed step.
3. Mark recovery acceptance failed; a successful backup does not override it.
4. Freeze updates and migrations until a new independent empty-target restore
   succeeds.
5. Remove decrypted staging data through the guarded cleanup path after the
   evidence needed for diagnosis has been reviewed.

These backup-age, restore-age, and restore-duration thresholds are surfaced by
`scripts/compare-deployment-state.py`; changing them is an operator decision,
not a way to make a failing report green.
For an independent rehearsal, RTO starts at the operator-recorded incident
declaration before repository staging or infrastructure recovery and ends only
after the restored service passes its acceptance checks. A container-only
restore duration cannot satisfy this objective.
