# Dedicated Collabora Online

The `richdocuments` app declares protected filesystem and
`prevent_group_restriction` types, so Nextcloud does not support enabling it for
selected groups. Office treats it as a platform-global app while the module is
active; document/file permissions remain authoritative. Logical deactivation
may disable the app but never deletes documents or Collabora service data.

## Deployment boundary

`compose.collabora.yaml` adds one optional `office` profile. It uses the pinned
`collabora/code:26.04.3.1.1` image and its multi-architecture digest, publishes
no host port, joins only the existing `proxy_net`, and is limited by default to
two CPUs and 3 GiB RAM. It does not alter the base Compose file or Nextcloud
volumes. Built-in CODE is not used.

Collabora terminates no TLS. Shared Caddy serves
`office.itmitalles.de` and proxies to `collabora:9980`; Caddy's normal reverse
proxy handles the HTTP upgrade used by Collabora WebSockets.

Two independent restrictions are mandatory:

- Collabora's `aliasgroup1` accepts only the dot-escaped
  `cloud.itmitalles.de` WOPI host.
- Nextcloud Office's `wopi_allowlist` explicitly accepts only the observed
  Collabora source address or its narrow service CIDR.

Do not guess the second value. Depending on split DNS and NAT hairpinning,
Nextcloud may observe the Collabora container, Caddy, or a translated address.
Confirm the path and use the narrowest stable address range.

## Enablement gate

Before starting Office:

1. Complete and review `scripts/inventory.sh`; Caddy drift must be `match`.
2. Pass an encrypted offsite restore test.
3. Publish and externally validate DNS/TLS for both cloud and office hosts.
4. Add `caddy/office.Caddyfile.example` to the complete shared Caddyfile,
   validate the complete file, then reload once.
5. Set `COLLABORA_WOPI_ALLOWLIST` locally in `.env`. Never commit `.env`.

Start only the optional service:

```bash
cd /opt/nextcloud
docker compose -f compose.yaml -f compose.collabora.yaml --profile office up -d collabora
```

After `docker compose ps` reports it healthy, configure Nextcloud:

```bash
cd /opt/nextcloud
./scripts/configure-office.sh
```

The configuration script refuses to continue unless public discovery works,
Nextcloud reaches `collabora:9980`, Nextcloud Office is installed, and an
explicit WOPI allowlist exists. It takes a backup before changing app settings.

## End-to-end acceptance

Use two fictitious demo accounts in separate browsers/networks and retain a
timestamped test record:

1. Create an ODT document, edit and save it, then download it and verify its
   contents.
2. Create an ODS spreadsheet with a formula and confirm recalculation/save.
3. Open one document concurrently as both users and verify both cursors and
   edits.
4. Restart only `collabora`, reopen both files, and verify no unsaved state was
   lost.
5. Change the document twice and restore the earlier Nextcloud file version.
6. Confirm the browser reaches only the public Office hostname and that an
   unlisted WOPI source receives HTTP 403 from Nextcloud.

Stopping or removing Collabora must leave files downloadable through
Nextcloud. Removal is `docker compose ... stop collabora`, followed by clearing
the Office URL only after confirming no active editing session.

## Updating

Office updates are separate from `scripts/update.sh`. Review Collabora release
notes, select a new exact tag, take and test a backup, update only the overlay,
then repeat discovery, ODT/ODS, concurrency, restart, and version-history tests.
