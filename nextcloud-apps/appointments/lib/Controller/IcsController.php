<?php

declare(strict_types=1);

namespace OCA\Appointments\Controller;

use OCA\Appointments\Exception\ApiException;
use OCA\Appointments\Service\AppointmentService;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\AnonRateLimit;
use OCP\AppFramework\Http\Attribute\PublicPage;
use OCP\AppFramework\Http\Attribute\UserRateLimit;
use OCP\AppFramework\Http\DataDownloadResponse;
use OCP\AppFramework\Http\JSONResponse;
use OCP\AppFramework\Http\Response;
use OCP\IL10N;
use OCP\IRequest;
use Psr\Log\LoggerInterface;
use Throwable;

final class IcsController extends Controller {
    public function __construct(
        string $appName,
        IRequest $request,
        private AppointmentService $appointments,
        private IL10N $l10n,
        private LoggerInterface $logger,
    ) {
        parent::__construct($appName, $request);
    }

    #[PublicPage]
    #[AnonRateLimit(limit: 10, period: 60)]
    #[UserRateLimit(limit: 10, period: 60)]
    public function download(string $token): Response {
        try {
            $response = new DataDownloadResponse($this->appointments->icsByCustomer($token), 'appointment.ics', 'text/calendar; charset=utf-8');
        } catch (ApiException $exception) {
            $response = new JSONResponse(['error' => ['code' => $exception->getErrorCode(), 'message' => $exception->getMessage()]], $exception->getHttpStatus());
        } catch (Throwable $exception) {
            $this->logger->error('Appointments ICS generation failed.', [
                'app' => 'appointments',
                'errorType' => 'internal',
                'exceptionClass' => $exception::class,
            ]);
            $response = new JSONResponse(['error' => ['code' => 'internal_error', 'message' => $this->l10n->t('The calendar file could not be created.')]], 500);
        }
        $response->addHeader('Cache-Control', 'no-store');
        $response->addHeader('Pragma', 'no-cache');
        return $response;
    }
}
