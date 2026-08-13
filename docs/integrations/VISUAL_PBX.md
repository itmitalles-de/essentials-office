# Visual PBX integration boundary

Visual PBX belongs to the separate `itmitalles-de/visual-pbx` product. Office
contains no PBX service, source merge, database, secret, Docker host port, or
Caddy route. `integrations/visual-pbx.env.example` describes an optional,
disabled portal-link/health-check contract only.

## Release gates

Do not set `VISUAL_PBX_ENABLED=true` or publish an Office link until the Visual
PBX product independently has:

1. authentication and role enforcement;
2. secure SIP credential storage;
3. a credential-free HTTPS portal and health endpoint;
4. a documented successful health check; and
5. clarified rights, participation, and operational ownership.

Only after all gates pass may an administrator create an `office-user`-
restricted External Sites link. The URL must contain no credentials or query
tokens. Validate the inactive default with:

```bash
cp integrations/visual-pbx.env.example integrations/visual-pbx.env
./scripts/visual-pbx-contract-check.sh
```

With an enabled contract, run `--check-health` before making a link visible.
OIDC/SSO and groups mapping are later architecture stages, not part of this
integration. The currently unprotected PBX proof of concept must never be
publicly proxied through Office.
