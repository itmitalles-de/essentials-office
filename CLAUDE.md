# Claude Code guide

Read `AGENTS.md` first. It defines the repository boundaries, safety rules,
validation expectations, and handoff workflow.

For continuation work:

1. Inspect `git status`.
2. Read `.agent/STATE.md`.
3. Read `.agent/TODO.md`.
4. Inspect recent relevant commits and open pull requests.

Demand-load these only when the task needs them:

- `.agent/DECISIONS.md` for durable constraints and ownership choices
- `.agent/ARCHITECTURE.md` for the system map and authoritative doc links
- `docs/ARCHITECTURE.md` for product boundaries and rollout order
- the affected operational documentation and scripts

Important caveats:

- The default branch is the implemented repository baseline. Never describe a
  draft pull request or roadmap item as deployed.
- Runtime claims are dated observations until verified on the target host.
- Preserve `/opt/nextcloud`, `/srv/nextcloud`, shared Caddy, and `proxy_net`.
- Never print or commit `.env` values, DDNS credentials, backups, or user data.
- Mail is only an external IMAP/SMTP integration boundary; do not install
  mailcow or another mail platform from this repository.
- Do not add modules while deployed revision, drift, independent recovery,
  RPO/RTO ownership, ingress, and update/rollback remain open.
- Do not reload shared Caddy until its complete configuration has been reconciled
  and validated.

Useful static checks:

```bash
docker compose config -q
bash -n scripts/*.sh
```

Host health and file-roundtrip checks require a configured deployment; do not
substitute static success for runtime verification.

Before ending substantial work, validate and update `.agent/STATE.md` and
`.agent/TODO.md`. Update decisions or architecture only when they truly changed.
