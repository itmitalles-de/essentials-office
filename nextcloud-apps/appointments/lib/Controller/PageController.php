<?php

declare(strict_types=1);

namespace OCA\Appointments\Controller;

use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\Attribute\PublicPage;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\IRequest;
use OCP\IURLGenerator;

final class PageController extends Controller {
    public function __construct(string $appName, IRequest $request, private IURLGenerator $urlGenerator) {
        parent::__construct($appName, $request);
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function index(): TemplateResponse {
        $context = $this->urlGenerator->linkToRoute('appointments.internal_api.context');
        return new TemplateResponse('appointments', 'index', ['apiBase' => preg_replace('~/context$~', '', $context)]);
    }

    #[PublicPage]
    #[NoCSRFRequired]
    public function book(string $organizationSlug): TemplateResponse {
        $catalog = $this->urlGenerator->linkToRoute('appointments.public_api.catalog', ['organizationSlug' => $organizationSlug]);
        return new TemplateResponse('appointments', 'public-booking', [
            'apiBase' => preg_replace('~/' . preg_quote($organizationSlug, '~') . '/catalog$~', '', $catalog),
            'organizationSlug' => $organizationSlug,
        ], 'guest');
    }

    #[PublicPage]
    #[NoCSRFRequired]
    public function manage(): TemplateResponse {
        $view = $this->urlGenerator->linkToRoute('appointments.public_api.manage');
        return new TemplateResponse('appointments', 'manage', [
            'apiBase' => preg_replace('~/manage/view$~', '', $view),
            // The raw value lives only in location.hash and is read by client-side code.
            'managementToken' => '',
        ], 'guest');
    }
}
