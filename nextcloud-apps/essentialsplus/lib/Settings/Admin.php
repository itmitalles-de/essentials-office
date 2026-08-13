<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Settings;

use OCP\AppFramework\Http\TemplateResponse;
use OCP\IURLGenerator;
use OCP\Settings\ISettings;

final class Admin implements ISettings {
    public function __construct(private IURLGenerator $urlGenerator) {
    }

    public function getForm(): TemplateResponse {
        return new TemplateResponse('essentialsplus', 'settings-admin', [
            'apiUrl' => $this->urlGenerator->linkToRoute('essentialsplus.api.list'),
            'auditUrl' => $this->urlGenerator->linkToRoute('essentialsplus.api.audit'),
        ]);
    }

    public function getSection(): string {
        return 'essentialsplus';
    }

    public function getPriority(): int {
        return 10;
    }
}
