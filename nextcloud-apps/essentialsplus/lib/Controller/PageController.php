<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Controller;

use OCA\EssentialsPlus\Service\ModuleService;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\IRequest;
use OCP\IUserSession;
use RuntimeException;

final class PageController extends Controller {
    public function __construct(
        string $appName,
        IRequest $request,
        private ModuleService $moduleService,
        private IUserSession $userSession,
    ) {
        parent::__construct($appName, $request);
    }

    #[NoAdminRequired]
    #[NoCSRFRequired]
    public function index(): TemplateResponse {
        $user = $this->userSession->getUser();
        if ($user === null) {
            throw new RuntimeException('Authentication required.');
        }
        return new TemplateResponse('essentialsplus', 'index', [
            'modules' => $this->moduleService->listForUser($user),
        ]);
    }
}
