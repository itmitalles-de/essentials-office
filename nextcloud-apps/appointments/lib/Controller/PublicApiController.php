<?php

declare(strict_types=1);

namespace OCA\Appointments\Controller;

use OCA\Appointments\Service\AppointmentService;
use OCA\Appointments\Service\AvailabilityService;
use OCA\Appointments\Service\CatalogService;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\AnonRateLimit;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\Attribute\PublicPage;
use OCP\AppFramework\Http\Attribute\UserRateLimit;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IL10N;
use OCP\IRequest;
use Psr\Log\LoggerInterface;

final class PublicApiController extends Controller {
    use ApiResponseTrait;

    public function __construct(
        string $appName,
        IRequest $request,
        private CatalogService $catalogService,
        private AvailabilityService $availabilityService,
        private AppointmentService $appointmentService,
        private IL10N $l10n,
        private LoggerInterface $logger,
    ) {
        parent::__construct($appName, $request);
    }

    #[PublicPage]
    #[NoCSRFRequired]
    #[AnonRateLimit(limit: 60, period: 60)]
    #[UserRateLimit(limit: 60, period: 60)]
    public function catalog(string $organizationSlug, ?string $service = null): JSONResponse {
        $response = $this->respond(fn (): array => $this->catalogService->publicCatalog($organizationSlug, $service));
        $response->addHeader('Cache-Control', 'private, max-age=30');
        return $response;
    }

    #[PublicPage]
    #[NoCSRFRequired]
    #[AnonRateLimit(limit: 60, period: 60)]
    #[UserRateLimit(limit: 60, period: 60)]
    public function slots(string $organizationSlug): JSONResponse {
        $response = $this->respond(fn (): array => $this->availabilityService->publicSlots($organizationSlug, $this->request->getParams()));
        $response->addHeader('Cache-Control', 'private, max-age=10');
        return $response;
    }

    #[PublicPage]
    #[AnonRateLimit(limit: 12, period: 60)]
    #[UserRateLimit(limit: 12, period: 60)]
    public function book(string $organizationSlug): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->bookPublic($organizationSlug, $this->request->getParams()), true, 201);
    }

    #[PublicPage]
    #[AnonRateLimit(limit: 30, period: 60)]
    #[UserRateLimit(limit: 30, period: 60)]
    public function manage(string $token): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->manageView($token), true);
    }

    #[PublicPage]
    #[AnonRateLimit(limit: 20, period: 60)]
    #[UserRateLimit(limit: 20, period: 60)]
    public function manageSlots(string $token): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->manageSlots($token, $this->request->getParams()), true);
    }

    #[PublicPage]
    #[AnonRateLimit(limit: 8, period: 60)]
    #[UserRateLimit(limit: 8, period: 60)]
    public function cancel(string $token): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->cancelByCustomer($token), true);
    }

    #[PublicPage]
    #[AnonRateLimit(limit: 8, period: 60)]
    #[UserRateLimit(limit: 8, period: 60)]
    public function reschedule(string $token): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->rescheduleByCustomer($token, $this->request->getParams()), true);
    }

    #[PublicPage]
    #[AnonRateLimit(limit: 8, period: 60)]
    #[UserRateLimit(limit: 8, period: 60)]
    public function updateContact(string $token, array $contact = []): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->updateContactByCustomer($token, ['contact' => $contact]), true);
    }

    #[PublicPage]
    #[AnonRateLimit(limit: 8, period: 60)]
    #[UserRateLimit(limit: 8, period: 60)]
    public function export(string $token): JSONResponse {
        $response = $this->respond(fn (): array => $this->appointmentService->exportByCustomer($token), true);
        $response->addHeader('Content-Disposition', 'attachment; filename="appointment-data.json"');
        return $response;
    }
}
