# Appointments (Termine)

## Scope and status

Appointments is a native, repository-owned Nextcloud app for Essentials+
Office. It provides a tenant-scoped appointment domain, internal scheduling,
public self-service booking, resources, customer-management links, email
outbox/reminders, and ICS export. It reuses Nextcloud authentication, users,
groups, system mail, PostgreSQL, Redis, and cron; it does not introduce another
identity store or service database.

The app is an optional module. Installing its package and running its database
migration does not publish a booking page. An administrator must activate the
module and explicitly enable each organization's public page.

The current milestone deliberately keeps Appointments authoritative. It does
not yet update or delete objects in an external CalDAV calendar, create
Nextcloud Talk rooms, send SMS, take payments, or provide clinical records.
See [roadmap.md](roadmap.md) for deferred work.

## Architecture

```text
anonymous browser                        authenticated Nextcloud user
        |                                             |
 public booking/manage controllers      internal page and API controllers
        |                                             |
        +---------------- authorization/validation ---+
                              |
                    booking and availability services
                              |
            PostgreSQL transaction + organization row lock
                  /                  |                 \
          appointment data      mail outbox       immutable audit
                                    |
                             Nextcloud cron
                                    |
                         Nextcloud system mailer
```

The application package lives in `nextcloud-apps/appointments`. Vanilla
JavaScript and PHP templates match the existing repository stack; there is no
second frontend build toolchain. The natural Nextcloud public URL is
`/apps/appointments/book/{organizationSlug}`. A shorter `/book/...` URL would
require a separately reviewed proxy rewrite and is not assumed.

## Data model

The first migration creates typed relational tables with the `appt_` prefix.
All domain tables carry `organization_id`; joins repeat it so every query can
and must apply the tenant predicate.

| Area | Tables |
| --- | --- |
| Tenant and public settings | `appt_org` |
| Catalog | `appt_services`, `appt_staff`, `appt_locations`, `appt_resources` |
| Catalog assignments | `appt_service_staff`, `appt_service_loc`, `appt_staff_loc`, `appt_resource_req` |
| Availability | `appt_avail_rules`, `appt_avail_except` |
| Booking | `appt_appointments`, `appt_resource_alloc`, `appt_status_history` |
| Custom fields | `appt_form_fields`, `appt_form_answers` |
| Customer access | `appt_tokens` |
| Notifications | `appt_reminders`, `appt_mail_outbox` |
| Audit | `appt_audit` |

Numeric keys remain internal. Organization, service, staff, location,
resource, and appointment APIs expose random public identifiers or slugs.
Booking numbers are random display references and are not database sequences.
Frequently used tenant/time, staff/time, location/time, resource/time, slug,
token-hash, and outbox/reminder ranges are indexed.

The migration is forward-only. Before updating an already enabled app, the
repository installer takes the standard complete Nextcloud backup. Rollback
means disabling the logical module and restoring that pre-update backup into
an empty target; manually dropping appointment tables is not a supported
rollback.

## Authentication, tenants, and permissions

Public booking needs no Office account. Internal APIs always use the current
Nextcloud session and normal CSRF protection.

Each organization references three existing Nextcloud groups: administrator,
manager/reception, and read-only. Organization creation can create safe default
group names, but users are still managed by Nextcloud. A staff profile may
reference a Nextcloud UID for own-calendar access.

Staff account UIDs and calendar bindings are returned only to catalog
administrators. Mail/calendar failure diagnostics require settings permission;
ordinary staff, reception, and read-only catalogs omit those fields.

The effective permission model is:

| Role | Access |
| --- | --- |
| Nextcloud or organization administrator | All appointments and configuration |
| Manager/reception | All appointments and operational availability |
| Staff profile | Own appointments, permitted own status/note changes, own availability |
| Read-only | All appointment calendar data, no mutations |

Every repository lookup combines the organization predicate with the requested
public identifier. Staff-only access adds the mapped internal staff key. A
valid identifier from another organization therefore does not authorize a
read or mutation. Nextcloud instance administrators remain explicit
cross-organization super-administrators.

## Availability and time handling

Persisted instants use Unix timestamps in UTC. Organization, staff, and
location configuration uses IANA time-zone names and defaults to
`Europe/Berlin`. Local dates are converted using PHP's time-zone database;
ambiguous or nonexistent local times around daylight-saving changes are not
silently treated as ordinary slots.

The server-side engine intersects:

- service duration and before/after buffers;
- weekly staff, location, and resource intervals;
- blocked weekly intervals and one-off exceptions such as leave, holidays, or
  emergency blocks;
- existing active appointments;
- resource quantities and capacities;
- minimum notice, maximum booking horizon, and the organization's 5/10/15/30
  minute slot grid.

The browser only displays candidates. Creation and rescheduling always run the
same calculation again on the server.

### Atomic booking

All booking, rescheduling, cancellation, and availability mutations follow one
write protocol:

1. Begin a database transaction.
2. Lock the matching `appt_org` row with `SELECT ... FOR UPDATE`.
3. Reload configuration and revalidate the complete slot.
4. Check staff, location, and resource overlap/capacity.
5. Write the appointment, resource allocations, status history, token,
   notification outbox, and audit entry.
6. Commit, then wake the background-job path.

This intentionally serializes writes per small organization. It is portable
through Nextcloud's database API and prevents two application workers from
confirming the same slot. A rejected race returns HTTP 409. Higher-throughput
installations may later introduce narrower deterministic locks or native range
constraints, but must preserve this protocol's correctness.

Cancelling changes the status to a non-blocking state; the next availability
read can offer the released slot again.

## Public booking and customer management

The booking flow selects a service, location/type, staff member or any
available staff member, date, slot, contact details, custom answers, and privacy
consent. Public catalog responses contain no customer or internal staff data.
`internal` services are never returned. A `direct_link` service is returned
only when its exact slug was explicitly requested.

The public surface uses Nextcloud anonymous and authenticated rate limits,
server-side length/type validation, a honeypot, and a configurable minimum form
completion time. It has no tracking script, remote font, forced CAPTCHA, or
third-party asset.

Each booking receives a random management token with at least 256 bits of
entropy. Only its SHA-256 digest is stored. The raw token is delivered as a URL
fragment:

```text
/apps/appointments/manage#<token>
```

Fragments are not sent in HTTP request targets and therefore do not enter
Caddy or Apache access logs. The management client removes the fragment from
the visible URL immediately and sends the token only in CSRF-protected POST
bodies. View, cancellation, rescheduling, contact update, ICS download, and
data export similarly use token-in-body endpoints. Sensitive responses are
marked `no-store`.

The token grants access to one appointment only. Cancellation and rescheduling
deadlines are checked on every mutation; inactive, expired, revoked, or
anonymized records fail closed. Public responses never contain internal notes,
audit metadata, provider references, or unrelated appointments.
Customer rescheduling changes only the time and remains pinned to the originally
booked staff member and location. A caller cannot widen that scope by adding or
removing identifiers from the API request.

## API surface

Internal routes are below `/apps/appointments/api/v1`:

- context and organization onboarding;
- tenant-scoped catalog reads;
- appointment list/search/filter, create, update, and status changes;
- service, staff, location, and resource create/update;
- weekly availability and one-off exception replacement;
- booking-page and retention settings.

Public routes are below `/apps/appointments/public/v1`:

- organization catalog and slot lookup;
- atomic booking;
- token-in-body view, cancellation, rescheduling, contact update, ICS, and
  data-subject export.

Public identifiers are opaque strings. Error responses use stable HTTP classes:
422 for validation, 403 for authorization, 404 for scoped absence, 409 for a
slot or uniqueness conflict, and 429 for platform rate limits. The API is currently
an application API, not a compatibility promise for third-party clients.

## Email, reminders, and jobs

Appointments uses `OCP\Mail\IMailer`, which means the Nextcloud **system mail**
configuration must work. Installing the Nextcloud Mail client app alone does
not configure transactional delivery.

Configure the sender under **Administration settings -> Basic settings ->
Email server** and use Nextcloud's test-mail action before publishing a booking
page. SMTP credentials remain in the existing Nextcloud secret/configuration
boundary; Appointments adds no SMTP environment variable and never writes
credentials to its tables or logs.

Booking and status transactions create encrypted outbox records with unique
idempotency keys. Jobs receive only internal numeric record IDs, never customer
details or raw tokens. A queued attempt may run after commit; a timed sweep also
finds work if scheduling the immediate job failed. Retry uses delayed backoff,
and terminal failures remain visible as non-PII operational state. Recipient
and payload ciphertext is removed after successful delivery or retention.

Messages have translated HTML and plain-text bodies, identify the service,
assigned staff, time and applicable location, and include an ICS attachment.
Reminder rows and outbox entries use unique idempotency keys, so repeated cron
execution cannot create a second logical reminder. Delivery is at-least-once:
as with any SMTP sender, a process failure after the remote server accepted a
message but before the local success commit can produce a duplicate. The fixed
MVP reminder offsets are 24 hours and 2 hours before the appointment;
per-organization offsets and a daily overview remain roadmap work.

Required workers are the existing Nextcloud cron container and the Appointments
outbox, reminder, and retention jobs declared in `appinfo/info.xml`.

## Calendar and meeting integration

Appointments is the source of truth for this milestone. It produces RFC 5545
ICS data for customer downloads and mail attachments. Appointment changes and
cancellations are reflected in newly generated ICS data.

Nextcloud's public calendar API supports event search/availability and create,
but does not provide a stable generic update/delete interface. A disabled
calendar-provider boundary is included, but no provider is active. Therefore this
milestone does **not** claim CalDAV write/update/delete synchronization or
external-busy conflict prevention. A future provider must keep Appointments
authoritative, read busy intervals, expose sync failures/retries, and avoid
silent loss. Nextcloud remains canonical for ordinary shared calendars.

A meeting-provider interface exists with a disabled safe default. No video URL
is generated or exposed until a reviewed Nextcloud Talk provider is configured.

## Installation, activation, and migration

1. Take or verify a complete Nextcloud backup.
2. Reconcile the repository package for module `appointments`.
3. Activate `appointments` through the Essentials+ Admin Center or its OCC
   module command. Activation runs the migration and the app health gate.
4. Open Appointments as a Nextcloud administrator and create the first
   organization.
5. Assign users to the generated organization groups in Nextcloud.
6. Add services, staff, locations, availability, and required resources.
7. Verify Nextcloud system mail with a non-production recipient.
8. Enable the organization's public page only after privacy/legal URLs and
   cancellation rules have been reviewed.

Logical deactivation disables application access but preserves tables and
files. It does not delete customer data. Retention still needs to be considered
before prolonged deactivation.

## Administration guide

### Initial setup

- Use a unique lowercase organization slug; changing public URLs later may
  invalidate bookmarks.
- Keep `Europe/Berlin` unless the organization's actual operating zone differs.
- Configure Nextcloud group membership before granting reception or staff
  access.
- Create locations before location-bound resources.
- Set service duration, buffers, notice, horizon, deadlines, visibility, and
  confirmation mode deliberately.
- Assign at least one active staff member and working interval to every public
  service.
- Add resource requirements only after capacity and location have been checked.
- Test one booking, mail delivery, cancellation, and slot release before
  publishing the link.

### Daily operation

The internal page provides list, day, week, and month views with filters for
staff, location, service, status, and resource. Search accepts customer name,
email, phone, or booking number. Editing uses keyboard-accessible dialogs;
there is no drag-and-drop dependency.

Managers can create, move, confirm, cancel, complete, or mark no-show; status
history and audit records remain immutable. Internal notes are never copied to
public or mail responses.

### Staff guide

Staff use their existing Nextcloud account. A staff profile must reference its
UID. Staff can view their own calendar and, subject to authorization, update
their own availability, status, and internal note. They do not receive another
password or customer-account database.

## Public-page setup

Configure the organization name, description, contact information, time zone,
default language, safe accent color, privacy link, legal-notice link, and
confirmation text. Cancellation and rescheduling wording is derived from each
service's configured deadlines. Arbitrary HTML, CSS, and JavaScript are not
accepted.

Keep the page disabled until at least one service has a complete intersection
of staff, location, resource, and working-time availability. Test the page on a
phone-sized browser and with keyboard-only navigation. A service marked
`direct_link` should be shared with its explicit service query; an `internal`
service has no public route.

## Demo data

The explicit `appointments:demo:seed` OCC command creates only fictional local
data for “Physiotherapie Beispiel”: two staff profiles, three services, one
location, two rooms, regular hours, an absence, and sample appointments. It is
never called by install, deploy, migration, or production startup. The command
requires `--confirm`; a second invocation is idempotent and reports the existing
demo organization instead of duplicating it.

## Privacy and retention

- Collect only contact data and service-specific fields configured by the
  organization. No diagnosis field is created by default.
- Notes and answers are length-limited plaintext and rendered with escaping.
- Retention is configurable per organization. The retention job anonymizes old
  contact fields and answers, revokes tokens, and removes notification payloads
  while retaining the minimum operational/status record.
- The token-authenticated JSON export contains only the matching customer's
  record and public form answers; it excludes internal form fields, internal
  notes, provider bindings, and audit data.
- Application logs and metric labels contain no name, email, phone, token,
  message, booking number, or free-text note.

Organizations remain responsible for choosing a lawful retention period,
privacy wording, mail configuration, and backup retention.

## Backup and restore

The existing complete Nextcloud backup includes the Appointments schema,
configuration, status history, encrypted pending outbox, and audit data because
they live in PostgreSQL. No separate volume is introduced.

After an empty-target restore:

1. Verify `occ status` and the Appointments app version.
2. Run Nextcloud maintenance repair if the standard restore runbook requires it.
3. Verify organization counts without printing customer rows.
4. Open an internal calendar range and a disabled test booking page.
5. Inspect pending/failed job counts before cron resumes.
6. Use fictional data to test booking, ICS, cancellation, and slot release.

Never restore a database dump over a populated target. Follow
[BACKUP_RESTORE.md](operations/BACKUP_RESTORE.md) for the authoritative platform
procedure.

## Observability

`appointments:metrics` emits aggregate Prometheus text for bookings, conflicts,
pending/failed reminders, and mail failures. It does not use tenant slugs,
customer fields, booking numbers, or free text as labels. The repository's
metrics script includes it when the app is enabled. Nextcloud cron health remains
part of the platform health check.

Operational failure detail exposed to administrators is a safe error code and
attempt count, not the mail address or message body.

Controller failures are logged as structured operational metadata containing
only the app name, stable error type, and exception class. Names, addresses,
phone numbers, free text, booking numbers, management tokens, and request bodies
are deliberately excluded.

## Verification and known limitations

Repository validation covers PHP/JavaScript/Python/shell syntax,
schema/manifest/security contracts, pure unit cases for
time/availability/status policy, a disposable PostgreSQL migration, public and
internal browser journeys, tenant isolation, cancellation slot release, and
concurrent same-slot booking. Tests use fictional identities and assert the
encrypted outbox row without contacting an SMTP, calendar, meeting, SMS, or
other external provider.

The full disposable browser run created two staff profiles, assigned a service
and location, configured working hours, booked that exact service anonymously,
verified the internal appointment and outbox, proved public/internal form-answer
export separation and permission-filtered catalogs, pinned customer rescheduling
to the booked assignment, cancelled through the fragment-delivered management
token, and observed the released slot. Parallel requests for one slot produced
exactly one creation and one conflict; a second tenant could not read the
appointment. The complete combined runner also passed platform restart,
redeployment, encrypted temporary Restic, and empty-target restore checks.

Still valuable after automation:

- keyboard and screen-reader review in the exact supported browser set;
- mail rendering in the organization's real mail clients;
- a German daylight-saving booking rehearsal using the production PHP time-zone
  database;
- restore rehearsal from the organization's encrypted offsite target;
- external rate-limit and proxy-log review on the real Caddy boundary.

Current limitations are explicit: no CalDAV write/update/delete or external
busy import, no Talk room creation, no automatic German holiday feed, no
configurable reminder offsets or daily digest, no logo/profile-image upload,
no custom domain, no SMS/payment/waitlist, and no recurring or group
appointments. The organization locale controls mail and configured defaults;
the rendered public interface follows Nextcloud/browser locale negotiation.
These items must not be presented as implemented.
