# TODO

This is the authoritative repository task handoff. Product sequencing remains
documented in `docs/ARCHITECTURE.md`; do not create a competing root task list.

## Now

- [ ] On approved disposable infrastructure, validate Vaultwarden's private
  Caddy route, Web Vault organization/group/role onboarding, 2FA procedure,
  and restore using the protected matching environment file before activation.
- [ ] Complete Office Admin Center, Intranet Lite, and HR Lite's documented
  manual Nextcloud UI target states using fictional accounts, then run group
  visibility and confidential-folder permission tests.
- [ ] Review draft PR #1 (`agent/workspace-suite-iac`) in independent stages;
  validate its static checks and confirm each operational claim before merge.
- [ ] Reconcile the complete shared Caddy file with the running configuration,
  validate it, and only then reload the proxy configuration.
- [ ] Verify public IPv4/IPv6 and TCP 80/443 reachability from a genuinely
  external network before creating or enabling the production DNS path.
- [ ] Configure independently stored encrypted offsite backups and perform a
  documented restore on disposable infrastructure before production migration.

## Next

- [ ] Define users, groups, sharing policy, retention, and the Dropbox migration
  plan before importing production data.
- [ ] Introduce the documented Nextcloud apps declaratively after core recovery
  and public-access prerequisites are complete.
- [ ] Integrate and validate dedicated Collabora, then Talk P2P, TURN, and HPB in
  the staged order in `docs/ARCHITECTURE.md`.
- [ ] Evaluate mailcow only as a separately operated stack on infrastructure
  that satisfies its network, DNS, resource, backup, and restore prerequisites.
- [ ] Do not activate Visual PBX until its separate product has authentication,
  roles, secure SIP credential storage, health checks, and clarified rights,
  participation, and operating ownership.

## Later

- [ ] Evaluate OIDC/SSO and a common portal only after all core modules are
  independently stable.

## Blocked

- [ ] Public production availability is blocked until DNS, external routing,
  firewall reachability, and Caddy configuration drift are resolved and tested.
- [ ] Production mail is blocked until a suitable host has static public
  reachability, port 25, controllable PTR/rDNS, sufficient capacity, and a
  tested mail backup/restore process.

## Recently completed

- [x] Added the reproducible Nextcloud core, persistent-path layout, backup,
  update, health-check, and DDNS tooling on `main`.
- [x] Recorded Workspace Suite product boundaries and staged architecture.
- [x] Replaced the generic root handoff with this persistent task source.
- [x] Added Office (Essentials Plus) module contract and inactive Admin Center,
  Vaultwarden, HR Lite, Intranet Lite, and Visual PBX integration boundaries.
- [x] Ran local static checks and isolated synthetic Vaultwarden backup/restore;
  no NUC, DNS, Caddy, or real-account action was taken.
