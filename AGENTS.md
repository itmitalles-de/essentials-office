# AGENTS.md

## Produktgrenze

Dieses Repository ist **Workspace Suite**, Hauptprojekt 3 von 3. Die Domain `cloud.itmitalles.de` bleibt bestehen; der Repository-Slug soll administrativ später `workspace-suite` heißen.

Hierher gehören:

- Nextcloud Files, Calendar, Contacts, Tasks und Mail
- Nextcloud Talk einschließlich separater TURN-/HPB-Planung
- Nextcloud Office mit Collabora Online
- Notes, Collectives, Deck, Tables und Forms
- mailcow als eigenständig betriebener Mail-Baustein
- Backup, Restore, Monitoring, DNS, Reverse Proxy und später optional SSO

Nicht hierher gehören Freelancer-Abrechnung oder Shop-/ERP-Funktionen.

## Bestehende Grundlage

Der aktuelle Nextcloud-Core auf dem NUC ist validiert und darf nicht beiläufig ersetzt werden:

- Nextcloud 34, PostgreSQL 17, Redis 7, separater Cron
- gemeinsamer Caddy auf `proxy_net`
- Checkout auf dem NUC unter `/opt/nextcloud`
- persistente Daten unter `/srv/nextcloud`
- Secrets ausschließlich lokal in `.env`
- Domain derzeit noch nicht öffentlich live
- lokales Backup und Wegwerf-Restore getestet; verschlüsseltes Offsite-Backup
  ist bis unmittelbar vor der ersten Nutzung echter Daten zurückgestellt

Keine Migration zu Nextcloud AIO ohne eigenen Vergleich, Rollback und ausdrückliche Entscheidung.

## Architekturregeln

- Nextcloud bleibt kanonisch für Kalender, Kontakte und Aufgaben.
- SOGo ist optionaler Mail-/Fallback-Client, kein zweites führendes Groupware-System.
- Collabora läuft als eigener Container/Service; Built-in CODE nur für lokale Tests.
- Talk-App, TURN und High-Performance-Backend sind getrennte Ausbaustufen.
- mailcow bleibt ein eigener Upstream-Stack mit eigenem Lifecycle. Nicht in `compose.yaml` hineinkopieren.
- Mailproduktion nur mit geeigneter öffentlicher Erreichbarkeit, Port 25, PTR/rDNS sowie SPF, DKIM und DMARC.
- Kein Secret, reales Postfach oder echter Kundendatensatz im Repository oder in Demos.

## Arbeitsweise

1. Vor Änderungen README, Compose und alle betroffenen Scripts vollständig lesen.
2. Bestehende NUC-Pfade, Volumes, Container-Namen und Caddy-Routen erhalten.
3. Jede neue Komponente über ein optionales Profil oder einen klar getrennten Stack einführen.
4. Vor Änderungen an persistenten Daten: Backup, Restore-Schritt und Rollback definieren.
5. Keine automatische Major-Version-Aktualisierung.
6. Demo- und Produktionsmodus klar trennen.
7. Der aktuelle Slice priorisiert einen idempotenten IaC-Deploy aus dem
   Repository; Offsite-Backup bleibt ein dokumentiertes Gate vor echten Daten.

## Verifikation

Mindestens passend zur Änderung:

- `docker compose config -q`
- `bash -n scripts/*.sh`
- `./scripts/healthcheck.sh`; bei geeigneter Umgebung zusätzlich `--file-roundtrip`
- Neustart- und Persistenztest
- Externe Prüfung von TLS/DNS/WebDAV/CalDAV
- Bei Talk: Test aus einem fremden Mobil-/NAT-Netz, TURN UDP und TCP
- Bei Collabora: gemeinsames Bearbeiten je eines Textdokuments und einer Tabelle
- Bei mailcow: DNS, PTR, SMTP/IMAP/TLS, SPF/DKIM/DMARC und Restore

Fertig bedeutet: bestehender Nextcloud-Kern bleibt gesund, neue Module sind optional/reproduzierbar, Backups und Rollback sind dokumentiert und reale Daten bleiben geschützt.
