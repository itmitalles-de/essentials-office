# Nextcloud Talk rollout

Talk declares Nextcloud's `prevent_group_restriction` app type. Office therefore
activates the app globally when the module is enabled while keeping its catalog
entry and room participation permission-controlled. Logical deactivation may
disable the app but never deletes rooms, messages, files, or TURN state.

## Stage 1: app, chat, and small calls

Install Talk through the declarative app reconciliation. Test one-to-one chat,
file sharing from Nextcloud Files, notifications, and a two-party P2P call
before introducing TURN. Run the call once with each browser on the LAN and
once with one participant on a genuinely external mobile network. Record ICE
candidate types without recording participant addresses in Git.

No recording or SIP bridge is part of the MVP.

## Stage 2: TURN

`compose.talk-turn.yaml` provides an optional host-network coturn service. Host
networking follows coturn's recommendation for a media relay port range and
avoids publishing hundreds of Docker proxy bindings. The pinned image is
`coturn/coturn:4.17.2-r0` plus its multi-architecture digest.

The initial profile exposes:

| Protocol | Port/range | Purpose |
| --- | --- | --- |
| UDP | 3478 | STUN/TURN client traffic |
| TCP | 3478 | TURN fallback |
| UDP | 49160-49200 | relayed media |

Caddy is not a TURN proxy. The router and host/provider firewall must forward
or allow those ports directly. The initial profile disables TLS/DTLS and does
not use 5349. For clients restricted to TLS 443, deploy TURN on a separate
public IP or host; Caddy already owns 443 on the NUC. Do not silently displace
Caddy to make TURN work.

Generate the protected configuration on the TURN host:

```bash
cd /opt/nextcloud
sudo ./scripts/install-talk-turn-config.sh turn.itmitalles.de <PUBLIC_IPV4>
docker compose -f compose.yaml -f compose.talk-turn.yaml --profile talk-turn up -d turn
```

The installer writes the shared secret twice under `/etc/nextcloud`: embedded
in the root-only coturn configuration and in a separate root-only file used to
configure Talk. It never prints the secret. Neither file belongs in Git or a
backup log.

After DNS, NAT, firewall, and service health are verified, add it to Talk:

```bash
cd /opt/nextcloud
sudo TURN_SERVER=turn.itmitalles.de:3478 ./scripts/configure-talk-turn.sh
```

The script replaces only the matching `turn`/UDP+TCP entry and takes a backup
before writing the Talk setting.

### External acceptance

Run both tests from a client that is not on the NUC's LAN:

```bash
turnutils_stunclient -p 3478 turn.itmitalles.de
read -r -s -p 'TURN secret: ' TURN_TEST_SECRET; echo
turnutils_uclient -p 3478 -W "$TURN_TEST_SECRET" -v -y turn.itmitalles.de
unset TURN_TEST_SECRET
```

Then force relay candidates in a browser call and test Firefox and Chromium,
mobile data, restrictive Wi-Fi, UDP, and TCP independently. A local healthcheck
or NAT hairpin test does not satisfy this gate.

## Stage 3: high-performance backend

HPB is intentionally not instantiated yet. It starts only after Stage 2 passes
from an external restrictive network and measured call load justifies it. Its
future deployment must use separate signaling, TURN, and internal secrets,
dedicated WebSocket proxy routes, explicit media ports, its own backup/update
procedure, and an independently removable Compose project or overlay.

TURN can still be required with HPB. For maximum compatibility, TURN/TLS and
HPB may each need port 443 and therefore separate public IPs or hosts.
