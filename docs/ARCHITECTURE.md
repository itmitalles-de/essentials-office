# Workspace Suite architecture

## Ziel

Workspace Suite ist ein integriertes Produkt, aber kein einzelner untrennbarer Compose-Stack. Die Benutzeroberfläche wirkt zusammenhängend; die operativen Bausteine bleiben getrennt aktualisierbar und wiederherstellbar.

| Fähigkeit | Führendes System | Betriebsform |
| --- | --- | --- |
| Dateien, Freigaben, Versionen | Nextcloud Files | bestehender Core auf dem NUC |
| Kalender, Kontakte, Aufgaben | Nextcloud | Nextcloud Apps / CalDAV / CardDAV |
| Dokumente, Tabellen, Präsentationen | Nextcloud Office + Collabora | separater Collabora-Service |
| Chat und Meetings | Nextcloud Talk | App zuerst; TURN/HPB als eigene Stufe |
| E-Mail-Transport und Postfächer | mailcow | separater Upstream-Stack, produktiv bevorzugt auf geeigneter VM/VPS |
| Webmail | Nextcloud Mail | IMAP/SMTP gegen mailcow |
| Fallback-Webmail | SOGo | von mailcow bereitgestellt, optional |
| Persönliche Notizen | Notes | Nextcloud App |
| Teamwissen | Collectives | Nextcloud App |
| Kanban und Aufgabenplanung | Deck | Nextcloud App |
| Strukturierte Listen/Formulare | Tables / Forms | Nextcloud Apps |
| Identität/SSO | später OIDC | erst nach stabilen Kernmodulen |

## Harte Grenzen

- Keine gemeinsame Datenbank zwischen Nextcloud, Collabora und mailcow.
- Keine doppelte Kalender-/Kontakte-Hoheit in Nextcloud und SOGo.
- Keine Produktion-Mailzustellung über eine ungeprüfte dynamische Heim-IP.
- Kein öffentlicher Demo-Mailversand und keine echten Postfächer in Beispieldaten.
- Kein Big-Bang-Deployment aller Komponenten.

## Ausbaureihenfolge

1. Bestehenden Nextcloud-Core öffentlich sicher erreichbar machen, Restore und Offsite-Backup testen.
2. Nextcloud Apps deklarativ installieren und einen Fake-Demo-Datensatz anlegen.
3. Collabora als optionalen Service integrieren und gemeinsames Editieren testen.
4. Talk lokal sowie extern P2P testen; danach TURN; HPB erst für belastbare Mehrparteien-Meetings.
5. mailcow auf geeigneter Infrastruktur separat aufbauen und über Nextcloud Mail integrieren.
6. Erst danach OIDC/SSO und ein gemeinsames Portal ergänzen.

## Kapazitätsentscheidung

Der NUC besitzt 16 GiB RAM. mailcow dokumentiert mindestens 6 GiB RAM plus Swap; Nextcloud, PostgreSQL, Redis, Collabora und Talk benötigen zusätzlich Ressourcen. Deshalb ist „alles produktiv auf einem NUC“ kein belastbarer Standard. Für Demo/Entwicklung sind selektiv aktivierte Profile möglich; für Produktion sollten Mail und gegebenenfalls TURN/HPB getrennt betrieben werden.

## Reproduzierbare Betriebsbausteine

| Baustein | Repository-Artefakt | Standardzustand |
| --- | --- | --- |
| Nextcloud Core | `compose.yaml` | bestehend, unverändert führend |
| Verschlüsseltes Offsite-Backup | `scripts/offsite-backup.sh` | erst nach Restic-Zielkonfiguration |
| Wegwerf-Restore | `tests/restore/compose.yaml` | nur für expliziten Testlauf |
| Nextcloud Apps | `config/nextcloud-apps.txt` | explizit abzugleichen |
| Collabora | `compose.collabora.yaml`, Profil `office` | aus |
| TURN | `compose.talk-turn.yaml`, Profil `talk-turn` | aus |
| Talk HPB | nur dokumentierte spätere Stufe | nicht implementiert |
| mailcow | separater Upstream-Checkout, Commit in `mailcow/UPSTREAM_COMMIT` | nicht installiert |

Optionale Profile dürfen den Core nicht zum Starten benötigen. Umgekehrt darf
das Stoppen eines Profils den Core, seine Volumes oder `proxy_net` nicht
entfernen. Öffentliche Routen werden erst nach dem Caddy-Drift-Gate ergänzt.
