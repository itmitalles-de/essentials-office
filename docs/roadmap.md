# Appointments roadmap

This roadmap contains intentionally deferred work. It is not evidence that a
feature is installed, enabled, or available in production. The implemented and
verified boundary is documented in [appointments.md](appointments.md).

## Next production milestones

- Add a credential-safe CalDAV provider that writes, updates, and cancels
  appointment events while reading external busy intervals. Keep Appointments
  authoritative, expose retry/dead-letter state, and test against a disposable
  Nextcloud Calendar instance before activation.
- Add a Nextcloud Talk meeting provider only after a stable supported creation
  API and authorization model have been verified. Meeting URLs must remain
  encrypted at rest and visible only to authorized staff and the matching
  customer-management token.
- Add configurable German public-holiday sources by federal state, plus an
  explicit refresh/audit workflow. Do not hard-code holiday dates in the UI.
- Add richer notification-template previews, daily staff digests, and optional
  self-hosted CAPTCHA or proof-of-work providers when the built-in honeypot,
  timing checks, and rate limits are insufficient.
- Add custom-domain routing only together with tenant-safe host validation,
  certificate automation, collision handling, and documented rollback.

## Deliberately outside the first MVP

- Native smartphone applications
- Payment during booking
- Health-insurance billing, electronic patient records, clinical documentation,
  and prescription management
- Waitlists with automatic promotion
- Recurring and group appointments
- SMS delivery
- Google Calendar and Microsoft 365 OAuth synchronization
- Video-conference providers other than a future Nextcloud Talk integration
- Customer ratings or a public provider marketplace
- AI-based appointment prioritization or no-show prediction

Each future item needs a separate security, privacy, migration, rollback, and
test plan before implementation.
