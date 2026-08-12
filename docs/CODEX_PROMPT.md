# Codex-Ausführungsprompt: Workspace Suite aufbauen

Du arbeitest im privaten Repository `itmitalles-de/cloud.itmitalles.de`, das als **Workspace Suite** weitergeführt und administrativ später in `itmitalles-de/workspace-suite` umbenannt wird. Lies zuerst `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, `compose.yaml` und alle Scripts vollständig. Der bereits laufende Nextcloud-Core auf dem NUC muss erhalten bleiben.

## Ziel

Baue aus dem validierten Nextcloud-Deployment schrittweise eine reproduzierbare Open-Source-Alternative zu Microsoft 365 / Google Workspace:

- Dateien, Freigaben und Sync
- Kalender, Kontakte und Aufgaben
- browserbasierte Dokumente, Tabellen und Präsentationen
- Chat und Videokonferenzen
- E-Mail
- persönliche Notizen, Teamwissen und Kanban

## Harte Randbedingungen

- Keine echten Nutzer-, Kunden- oder Maildaten in Git oder Demo-Seeds.
- Keine Secrets in Git, Ausgaben, Issues oder Logs.
- Keine automatische Nextcloud-Major-Aktualisierung.
- Bestehende Pfade `/opt/nextcloud` und `/srv/nextcloud`, Volumes, Caddy und `proxy_net` erhalten.
- Kein Wechsel zu Nextcloud AIO ohne separaten Migrationsvergleich und Rollback.
- mailcow nicht in die Nextcloud-Compose-Datei kopieren.
- Nextcloud ist führend für Calendar/Contacts/Tasks; SOGo bleibt optionaler Fallback.
- Demo und Produktion klar trennen.

## Reihenfolge

### 1. Grundlage produktionsfähig machen

- Reproduziere und dokumentiere den aktuellen Stand des NUC.
- Schließe öffentliche DNS-/Caddy-Erreichbarkeit nur nach Validierung der bestehenden Konfigurationsdrift ab.
- Implementiere verschlüsseltes Offsite-Backup und teste einen Restore auf Wegwerf-Infrastruktur.
- Ergänze CI für Compose-Validierung, Shell-Syntax und statische Secret-Prüfung. Hostabhängige Checks dürfen nicht fälschlich in GitHub Actions simuliert werden.

### 2. Nextcloud-Apps deklarativ verwalten

Erstelle ein idempotentes Script oder eine dokumentierte OCC-Konfiguration für:

- Talk
- Mail
- Calendar
- Contacts
- Tasks
- Notes
- Collectives
- Deck
- Tables
- Forms
- Nextcloud Office

Das Script muss App-Kompatibilität prüfen, installierte Versionen dokumentieren, bei Fehlern abbrechen und keine Major-Upgrades erzwingen. Lege ausschließlich erfundene Demo-Daten an.

### 3. Collabora Online integrieren

- Verwende einen dedizierten Collabora-Container/Service; Built-in CODE höchstens lokal.
- Führe ihn optional über ein Compose-Profil oder einen getrennten Compose-Overlay ein.
- Integriere Caddy/WebSockets korrekt und beschränke erlaubte WOPI-Hosts auf die Nextcloud-Domain.
- Teste Textdokument, Tabelle, gleichzeitiges Bearbeiten, Neustart und Dateiversionen.

### 4. Nextcloud Talk stufenweise produktionsfähig machen

- Zuerst Chat und kleine P2P-Anrufe testen.
- Danach TURN für restriktive NAT-/Mobilnetze einführen und von einem wirklich externen Netz testen.
- High-Performance-Backend erst anschließend ergänzen; getrennte Secrets für TURN, Signaling und intern.
- Dokumentiere Ports, Reverse Proxy, WebSockets, Firewall und Testkommandos.
- Keine Recording- oder SIP-Brücke im MVP.

### 5. mailcow als separaten Baustein integrieren

- Prüfe Zielhost, statische öffentliche IP, Port 25, PTR/rDNS und DNS-Verwaltung vor der Installation.
- Für Produktion bevorzugt eine separate VM/VPS; der NUC mit 16 GiB ist kein belastbarer Standardhost für Nextcloud + Collabora + Talk + vollständiges mailcow gleichzeitig.
- Folge dem Upstream-Installations-/Updateprozess; pinne Version/Commit und dokumentiere Backup/Restore.
- Konfiguriere A/MX, PTR, SPF, DKIM und DMARC.
- Binde Nextcloud Mail über IMAP/SMTP an.
- Nutze SOGo nur als Fallback-Webmail; keine parallele Kalender-/Kontaktquelle etablieren.
- In Demo-Umgebungen keinen echten externen Mailversand aktivieren.

### 6. Gemeinsamer Zugang erst zum Schluss

- Prüfe OIDC/SSO erst, wenn alle Kernmodule einzeln stabil sind.
- Kein LDAP-/Keycloak-/Authentik-Overengineering im ersten Slice.
- Ein gemeinsames Portal darf nur auf gesunde Dienste verlinken und keine Passwörter enthalten.

## Qualitätskriterien

- Bestehender Nextcloud-Core bleibt nach jeder Stufe gesund.
- Jede Komponente ist separat startbar, aktualisierbar, sicherbar und entfernbar.
- `docker compose config -q`, Shell-Syntax, Healthcheck und passende externe End-to-End-Tests sind dokumentiert und ausgeführt.
- Ein kompletter Demo-Flow funktioniert: Datei hochladen → gemeinsam bearbeiten → in Talk teilen → Aufgabe/Notiz anlegen → Mail im Nextcloud-Mailclient anzeigen.
- Abschlussbericht: Änderungen, Tests, Ressourcenverbrauch, offene Netzwerk-/DNS-Risiken und nächste drei Schritte.
