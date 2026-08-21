<?php

declare(strict_types=1);

namespace OCA\Appointments\AppInfo;

use OCA\Appointments\Provider\DisabledMeetingProvider;
use OCA\Appointments\Provider\MeetingProvider;
use OCA\Appointments\Provider\CalendarProvider;
use OCA\Appointments\Provider\DisabledCalendarProvider;
use OCA\Appointments\Service\AuthorizationService;
use OCA\Appointments\Service\OrganizationRepository;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\IConfig;
use OCP\IL10N;
use OCP\INavigationManager;
use OCP\IURLGenerator;
use OCP\IGroupManager;
use OCP\IUserSession;

final class Application extends App implements IBootstrap {
    public const APP_ID = 'appointments';

    public function __construct() {
        parent::__construct(self::APP_ID);
    }

    public function register(IRegistrationContext $context): void {
        $context->registerServiceAlias(MeetingProvider::class, DisabledMeetingProvider::class);
        $context->registerServiceAlias(CalendarProvider::class, DisabledCalendarProvider::class);
    }

    public function boot(IBootContext $context): void {
        $context->injectFn(static function (
            IConfig $config,
            INavigationManager $navigation,
            IURLGenerator $urlGenerator,
            IL10N $l10n,
            IUserSession $userSession,
            IGroupManager $groupManager,
            OrganizationRepository $organizations,
            AuthorizationService $authorization,
        ): void {
            if ($config->getAppValue('essentialsplus', 'active.appointments', 'false') !== 'true') {
                return;
            }
            $user = $userSession->getUser();
            if ($user === null) {
                return;
            }
            $allowed = $groupManager->isAdmin($user->getUID());
            if (!$allowed) {
                foreach ($organizations->allActive() as $organization) {
                    if ($authorization->permissions((string)$organization['organization_id']) !== []) {
                        $allowed = true;
                        break;
                    }
                }
            }
            if (!$allowed) {
                return;
            }
            $navigation->add(static fn (): array => [
                'id' => self::APP_ID,
                'order' => 45,
                'href' => $urlGenerator->linkToRoute('appointments.page.index'),
                'name' => $l10n->t('Appointments'),
                'icon' => $urlGenerator->imagePath(self::APP_ID, 'app.svg'),
                'app' => self::APP_ID,
            ]);
        });
    }
}
