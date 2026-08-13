# mailcow integration boundary

mailcow is not part of the Nextcloud Compose project. Production installation
belongs on a separate, supported VM/VPS with a static public IP and controllable
PTR/rDNS. The NUC is not the default mail host.

## Hard preflight

Run `scripts/check-mail-host.sh` on the proposed mail VM before cloning
mailcow. It requires at least 6 GiB RAM plus 1 GiB swap, a supported
architecture/virtualization boundary, Docker 24+, Compose v2, free mail/web
ports, exactly one expected public A record, matching PTR, and outbound TCP 25.
The provider must separately confirm that the address and PTR are durable and
that inbound TCP 25 is allowed.

No target currently satisfies these gates in repository evidence. Therefore no
mailcow stack is installed or started by this repository change.

## Pinned upstream lifecycle

`UPSTREAM_VERSION` and `UPSTREAM_COMMIT` record the reviewed mailcow release
`2026-07a` and its exact commit. On the approved mail host, clone the upstream
repository into `/opt/mailcow-dockerized`, verify the tag resolves to that
commit, check out the exact commit, run upstream `generate_config.sh`, review
`mailcow.conf`, and start mailcow with its own Compose project. Never copy its
Compose services into this repository.

Before every update:

1. Read the upstream release and upgrade notes.
2. Run the upstream `helper-scripts/backup_and_restore.sh backup all` flow.
3. Export that backup encrypted and offsite.
4. Record the new reviewed commit in `UPSTREAM_COMMIT`.
5. Update using the upstream process and repeat SMTP/IMAP/TLS/DNS tests.

Restore uses the upstream helper on an initialized, empty mailcow installation
at the compatible commit. Preserve the original `mailcow.conf`, including
Maildir layout values, and test restoration on a disposable VM.

## DNS and TLS acceptance

Production requires all of the following before mail migration:

- `A` for the mail hostname to the static address;
- `MX` for the mail domain to that hostname;
- provider-controlled PTR/rDNS back to the same hostname;
- a restrictive SPF policy matching the actual send path;
- mailcow-generated DKIM published under the selected selector;
- DMARC beginning in monitoring mode, with policy tightened after reviewing
  legitimate traffic;
- externally valid SMTP, submission, IMAPS, and HTTPS certificates.

After publishing the records, run `scripts/check-mail-dns.sh`. Also test SMTP
delivery in both directions, TLS names and chains, authentication, spam-folder
placement, and restore. Never paste DKIM private keys, mailbox passwords, or
message headers into Git or issues.

## Nextcloud Mail and SOGo

Create mailbox credentials only in the approved secret manager. Configure the
Nextcloud Mail app per user against mailcow IMAPS and submission; do not seed
real mailboxes. SOGo remains an optional fallback webmail. Calendar, Contacts,
and Tasks stay canonical in Nextcloud; do not enable a parallel SOGo
groupware workflow.

For a demo, use only reserved `.invalid` identities on a private network and
block outbound TCP 25 at the demo egress boundary. Local delivery between demo
mailboxes may still exercise IMAP/SMTP and Nextcloud Mail. Do not publish demo
MX records or enable external delivery.
