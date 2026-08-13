<?php

declare(strict_types=1);

style('essentialsplus', 'admin');
/** @var list<array<string, mixed>> $modules */
$modules = $_['modules'];
?>
<div id="app-content" class="essentialsplus-portal">
    <h1>Essentials+ Office</h1>
    <p>Hier erscheinen nur aktive, gesunde und für deine Gruppen freigegebene Module.</p>
    <?php if ($modules === []): ?>
        <p class="essentialsplus-empty">Derzeit ist kein optionales Modul für dich freigeschaltet.</p>
    <?php else: ?>
        <div class="essentialsplus-grid">
            <?php foreach ($modules as $module): ?>
                <article class="essentialsplus-module" data-module-id="<?php p($module['id']); ?>">
                    <h2><?php p($module['displayName']); ?></h2>
                    <p><?php p($module['description']); ?></p>
                    <?php if ($module['serviceUrl'] !== null): ?>
                        <a class="button primary" rel="noopener noreferrer" href="<?php p($module['serviceUrl']); ?>">Öffnen</a>
                    <?php else: ?>
                        <span class="essentialsplus-state state-enabled">aktiv</span>
                    <?php endif; ?>
                </article>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>
</div>
