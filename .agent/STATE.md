# Current State

## Product and immutable boundaries

The visible product name is **Essentials+ Office**. Repository and deployment
paths, the shared `proxy_net`, and the default branch remain unchanged.

No real NUC, Caddy, DNS, router, firewall, offsite backup, mail account, or
customer data was read or changed during the Appointments work. Runtime checks
used isolated, randomly named disposable Docker resources and fictional data.

## Git baseline

- Date of this handoff: 2026-08-20.
- Current branch: `main`.
- Baseline commit: `17081f2`, equal to `origin/main` when work started.
- The Appointments milestone is intentionally uncommitted. All modified and
  untracked files shown by `git status` belong to this milestone; nothing was
  pushed.

## Appointments milestone

A separate native Nextcloud app now lives in `nextcloud-apps/appointments` and
is registered as the optional Essentials+ module `appointments`. It reuses the
existing Nextcloud users, authentication, groups, PostgreSQL, system mail, cron,
and application conventions.

Implemented scope:

- typed tenant-scoped catalog and booking schema with a forward migration;
- services, existing-user staff profiles, locations, appointment types,
  resources/capacity, assignments, custom form fields, and booking settings;
- weekly availability, breaks, exceptions, leave, holiday/manual blocks,
  buffers, notice/horizon rules, resource constraints, time zones, and DST;
- public booking without an account and internal list/day/week/month calendar;
- server-side tenant authorization and staff-own permission boundaries;
- per-organization transactional locking and complete slot revalidation for
  booking, rescheduling, cancellation, and relevant availability mutations;
- opaque public identifiers and hashed, revocable customer-management tokens;
- confirmation/reschedule/cancellation/reminder outbox, translated HTML/plain
  mail, ICS, retry/backoff, retention anonymization, audit, and metrics;
- responsive keyboard-usable German and English UI;
- explicit fictional demo seed command and complete operations documentation.

Appointments remains authoritative. A disabled CalendarProvider and
MeetingProvider define future CalDAV/Nextcloud Talk integration boundaries; no
external calendar or meeting provider is claimed as active.

## Verification evidence (2026-08-20, disposable only)

- `scripts/validate-static.sh` passed after the implementation. It includes the
  Appointments unit and contract suites, schema/manifest/security checks, PHP,
  JavaScript, Python and shell syntax, ShellCheck, and translation parity.
- A full PHP syntax pass in the Nextcloud 34 PHP image passed.
- A clean disposable deployment with Nextcloud 34, PostgreSQL 17, Redis 7, and
  cron passed installation, fresh migration, optional-module hidden state,
  explicit activation, health gate, app restart, and semantic redeployment.
- The browser run created a staff profile, assigned service and location,
  configured working hours, and booked that exact service as an anonymous
  customer. It then proved internal visibility and an encrypted outbox row.
- Customer management removed the token fragment from the URL, cancelled via a
  token-in-body request, kept rescheduling pinned to the existing staff/location
  assignment, and proved that cancellation released the slot.
- The follow-up security audit proved that customer data export includes public
  form answers but excludes internal fields, non-admin catalogs omit user/calendar
  bindings and operations, and internal JSON responses carry `no-store`.
- Unit coverage rejects nonexistent and ambiguous DST wall times, empty required
  multi-select answers, and invalid timestamp ranges. Customer notifications now
  include the assigned staff and, when applicable, location.
- Two concurrent public requests for the same slot produced one HTTP 201 and
  one HTTP 409, never two active appointments.
- A second tenant user could not read the first tenant's appointment.
- The final combined disposable runner passed HR, Intranet, Talk, Appointments,
  browser flows, restart/redeploy idempotence, encrypted temporary Restic, and a
  full empty-target Nextcloud/PostgreSQL restore. The isolated Vaultwarden,
  Collabora, TURN, mail, and Calls suites also passed.
- Actionlint and a Gitleaks scan of the complete worktree passed. One earlier
  combined run saw a non-reproduced Talk HTTP 404; a focused Talk+Appointments
  run and the complete rerun both passed, and the Talk test now reports the
  exact failing API stage if it recurs.

## Explicitly not verified or implemented

- No real SMTP delivery/client rendering, productive proxy rate limit, CalDAV
  server, Nextcloud Talk room, or offsite restore was exercised.
- CalDAV write/update/delete and external busy import remain disabled provider
  work, not a silent partial synchronization.
- Automatic German holiday feeds, configurable reminder offsets/daily digest,
  logo/profile uploads, custom domains, payments, SMS, waiting lists, and
  recurring/group appointments are roadmap items.
- No production deployment or manual accessibility/screen-reader acceptance was
  performed.

## Resume point

Review the complete uncommitted diff and current test evidence before deciding
whether to commit. The next Appointments work should be limited to real-service
acceptance (SMTP, proxy/rate limits, accessibility, backup/restore) or a
separately approved roadmap item. Do not infer production readiness from the
disposable evidence above.
