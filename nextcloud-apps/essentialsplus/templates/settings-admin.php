<?php

declare(strict_types=1);

script('essentialsplus', 'admin');
style('essentialsplus', 'admin');
?>
<div id="essentialsplus-admin"
     class="section essentialsplus-admin"
     data-api-url="<?php p($_['apiUrl']); ?>"
     data-audit-url="<?php p($_['auditUrl']); ?>">
    <h2>Essentials+ Office Admin-Center</h2>
    <p class="settings-hint">
        Versionierter Modulkatalog mit Health-Gates und Audit. Diese Oberfläche steuert weder Docker noch systemd,
        Caddy, DNS oder Firewall und zeigt keine Secrets an.
    </p>
    <div class="essentialsplus-banner" role="status">
        Externe Dienste werden erst nach vollständiger Konfiguration und erfolgreichem Healthcheck sichtbar.
        Deaktivieren löscht keine Daten oder Volumes.
    </div>
    <div id="essentialsplus-admin-status" aria-live="polite">Katalog wird geladen …</div>
    <div id="essentialsplus-admin-catalog"></div>
    <details class="essentialsplus-audit">
        <summary>Letzte Änderungen</summary>
        <div id="essentialsplus-admin-audit">Audit wird geladen …</div>
    </details>
</div>
