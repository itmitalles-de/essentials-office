<?php

declare(strict_types=1);

namespace OCA\Appointments\Controller;

use OCA\Appointments\Service\AppointmentService;
use OCA\Appointments\Service\AvailabilityService;
use OCA\Appointments\Service\CatalogService;
use OCA\Appointments\Service\OrganizationService;
use OCA\Appointments\Service\AuthorizationService;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IL10N;
use OCP\IRequest;
use OCP\IUserManager;
use Psr\Log\LoggerInterface;

final class InternalApiController extends Controller {
    use ApiResponseTrait;

    public function __construct(
        string $appName,
        IRequest $request,
        private OrganizationService $organizations,
        private CatalogService $catalogService,
        private AppointmentService $appointmentService,
        private AvailabilityService $availabilityService,
        private AuthorizationService $authorization,
        private IUserManager $userManager,
        private IL10N $l10n,
        private LoggerInterface $logger,
    ) {
        parent::__construct($appName, $request);
    }

    #[NoAdminRequired]
    public function context(): JSONResponse {
        return $this->respond(function (): array {
            $result = ['organizations' => $this->organizations->context(), 'users' => []];
            if ($this->authorization->isGlobalAdmin()) {
                $result['users'] = array_map(static fn (\OCP\IUser $user): array => [
                    'uid' => $user->getUID(), 'displayName' => $user->getDisplayName(),
                ], array_values($this->userManager->search('', 100)));
            }
            return $result;
        }, true);
    }

    #[NoAdminRequired]
    public function createOrganization(array $organization = []): JSONResponse {
        $input = $organization !== [] ? $organization : $this->request->getParams();
        return $this->respond(fn (): array => ['organization' => $this->organizations->create($input)], true, 201);
    }

    #[NoAdminRequired]
    public function catalog(string $organizationId): JSONResponse {
        return $this->respond(fn (): array => $this->catalogService->internalCatalog($organizationId), true);
    }

    #[NoAdminRequired]
    public function listAppointments(
        string $organizationId,
        ?string $from = null,
        ?string $to = null,
        ?string $staffId = null,
        ?string $locationId = null,
        ?string $serviceId = null,
        ?string $status = null,
        ?string $resourceId = null,
    ): JSONResponse {
        return $this->respond(fn (): array => ['appointments' => $this->appointmentService->listInternal($organizationId, array_filter([
            'from' => $from, 'to' => $to, 'staffId' => $staffId, 'locationId' => $locationId,
            'serviceId' => $serviceId, 'status' => $status, 'resourceId' => $resourceId,
        ], static fn (mixed $value): bool => $value !== null && $value !== ''))], true);
    }

    #[NoAdminRequired]
    public function searchAppointments(string $organizationId): JSONResponse {
        return $this->respond(fn (): array => ['appointments' => $this->appointmentService->listInternal($organizationId, $this->request->getParams())], true);
    }

    #[NoAdminRequired]
    public function getAppointment(string $organizationId, string $appointmentId): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->getInternal($organizationId, $appointmentId), true);
    }

    #[NoAdminRequired]
    public function createAppointment(string $organizationId): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->createInternal($organizationId, $this->request->getParams()), true, 201);
    }

    #[NoAdminRequired]
    public function updateAppointment(string $organizationId, string $appointmentId): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->updateInternal($organizationId, $appointmentId, $this->request->getParams()), true);
    }

    #[NoAdminRequired]
    public function setAppointmentStatus(string $organizationId, string $appointmentId, string $status): JSONResponse {
        return $this->respond(fn (): array => $this->appointmentService->setInternalStatus($organizationId, $appointmentId, $status), true);
    }

    #[NoAdminRequired]
    public function createService(string $organizationId): JSONResponse { return $this->saveCatalog('services', $organizationId, null); }
    #[NoAdminRequired]
    public function updateService(string $organizationId, string $id): JSONResponse { return $this->saveCatalog('services', $organizationId, $id); }
    #[NoAdminRequired]
    public function createStaff(string $organizationId): JSONResponse { return $this->saveCatalog('staff', $organizationId, null); }
    #[NoAdminRequired]
    public function updateStaff(string $organizationId, string $id): JSONResponse { return $this->saveCatalog('staff', $organizationId, $id); }
    #[NoAdminRequired]
    public function createLocation(string $organizationId): JSONResponse { return $this->saveCatalog('locations', $organizationId, null); }
    #[NoAdminRequired]
    public function updateLocation(string $organizationId, string $id): JSONResponse { return $this->saveCatalog('locations', $organizationId, $id); }
    #[NoAdminRequired]
    public function createResource(string $organizationId): JSONResponse { return $this->saveCatalog('resources', $organizationId, null); }
    #[NoAdminRequired]
    public function updateResource(string $organizationId, string $id): JSONResponse { return $this->saveCatalog('resources', $organizationId, $id); }

    #[NoAdminRequired]
    public function getAvailability(string $organizationId, string $subjectType, string $subjectId): JSONResponse {
        return $this->respond(fn (): array => $this->availabilityService->getAvailability($organizationId, $subjectType, $subjectId), true);
    }

    #[NoAdminRequired]
    public function putAvailability(string $organizationId, string $subjectType, string $subjectId, array $rules = [], array $exceptions = []): JSONResponse {
        return $this->respond(fn (): array => $this->availabilityService->replaceAvailability($organizationId, $subjectType, $subjectId, ['rules' => $rules, 'exceptions' => $exceptions]), true);
    }

    #[NoAdminRequired]
    public function slots(string $organizationId): JSONResponse {
        return $this->respond(fn (): array => $this->availabilityService->internalSlots($organizationId, $this->request->getParams()), true);
    }

    #[NoAdminRequired]
    public function putSettings(string $organizationId): JSONResponse {
        return $this->respond(fn (): array => ['organization' => $this->organizations->updateSettings($organizationId, $this->request->getParams())], true);
    }

    private function saveCatalog(string $type, string $organizationId, ?string $id): JSONResponse {
        return $this->respond(function () use ($type, $organizationId, $id): array {
            $input = $this->request->getParams();
            return match ($type) {
                'services' => $this->catalogService->saveService($organizationId, $id, $input),
                'staff' => $this->catalogService->saveStaff($organizationId, $id, $input),
                'locations' => $this->catalogService->saveLocation($organizationId, $id, $input),
                'resources' => $this->catalogService->saveResource($organizationId, $id, $input),
            };
        }, true, $id === null ? 201 : 200);
    }
}
