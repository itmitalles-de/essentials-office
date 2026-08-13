# HR Lite

HR Lite is a small, fictional Nextcloud workflow, not an HR platform. It uses
groups and permissions plus Nextcloud Tables, Forms, Deck, Calendar,
Collectives, and a protected file area. It does not implement payroll,
recruiting/ATS, time tracking, performance reviews, direct database writes, or
claims of legal/DSGVO compliance.

## Roles and least privilege

| Group | Purpose | May access confidential HR documents |
| --- | --- | --- |
| `hr-admin` | Owns HR workflow and protected documents | yes |
| `manager` | Reviews the assigned synthetic absence/onboarding tasks | no, unless HR explicitly shares a specific item |
| `employee` | Submits own synthetic forms and sees only own request status | no |

`hr-lite-reconcile.sh` creates only `hr-demo-admin`, `manager-demo`, and
`employee-demo`. Their generated local passwords are kept in an ignored,
mode-`0600` `.hr-lite-demo.env`. They are demonstration accounts only.

## Reconciled technical baseline

Run the script only on a disposable or approved Nextcloud instance:

```bash
./scripts/hr-lite-reconcile.sh --url https://cloud.example.internal
./scripts/hr-lite-verify.sh --url https://cloud.example.internal
```

It idempotently enables/installs compatible `calendar`, `deck`, `forms`,
`tables`, and `collectives` through OCC; creates the three groups and fictional
accounts; uploads the committed templates through WebDAV; and shares **HR Lite
- Confidential** only with `hr-admin` via the supported OCS Share API. The
verification checks app state, group membership, and, with `--url`, proves that
the manager cannot reach that confidential folder. No SQL is used.

## Required manual configuration

Nextcloud 34 provides no stable public provisioning API for Forms, Tables,
Deck boards, Calendar resources, or Collectives page content. Complete these
small manual steps after the baseline script, then retain screenshots or a
change record outside Git:

1. In **Tables**, create `HR Lite directory` with synthetic account, manager,
   department label, start date, and responsible person columns. Restrict edit
   access to `hr-admin`; do not enter real people.
2. In **Forms**, create `HR Lite – Onboarding` for `employee` with synthetic
   employee reference, manager, start date, equipment/access needs, and
   responsible `hr-admin`. Direct results to `hr-admin`.
3. In **Deck**, create `HR Lite – Lifecycle` with `New`, `In progress`,
   `Ready`, `Completed`, and `Closed` stacks. Copy the onboarding and
   offboarding checklists from `hr-lite/templates/`, assigning each card to a
   responsible `hr-admin` or manager.
4. In **Forms**, create `HR Lite – Absence request` with start/end, reason
   category, responsible manager, and status. Record the resulting status in a
   restricted Table: `submitted`, `manager review`, `approved`, `rejected`, or
   `cancelled`.
5. In **Calendar**, create only synthetic onboarding/check-in entries; grant
   managers access only to their necessary events. In **Collectives**, publish
   the non-confidential templates. Keep the committed protected WebDAV folder
   for confidential documents.

Repeat `hr-lite-verify.sh` after any role or share change. It is the required
target-state/least-privilege check when manual app configuration cannot be
provisioned safely.
