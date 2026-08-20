<?php

declare(strict_types=1);

namespace OCA\Appointments\Controller;

use OCA\Appointments\Exception\ApiException;
use OCP\AppFramework\Http\JSONResponse;
use Throwable;

trait ApiResponseTrait {
    /** @param callable():mixed $operation */
    private function respond(callable $operation, bool $noStore = false, int $successStatus = 200): JSONResponse {
        try {
            $response = new JSONResponse($operation(), $successStatus);
        } catch (ApiException $exception) {
            $response = new JSONResponse(['error' => ['code' => $exception->getErrorCode(), 'message' => $exception->getMessage()]], $exception->getHttpStatus());
        } catch (Throwable $exception) {
            $constraint = $this->isConstraintViolation($exception);
            $this->logger->error('Appointments API request failed.', [
                'app' => 'appointments',
                'errorType' => $constraint ? 'constraint' : 'internal',
                'exceptionClass' => $exception::class,
            ]);
            $response = new JSONResponse(['error' => [
                'code' => $constraint ? 'conflict' : 'internal_error',
                'message' => $constraint
                    ? $this->l10n->t('The requested value is already in use or the slot has just been booked.')
                    : $this->l10n->t('The request could not be completed.'),
            ]], $constraint ? 409 : 500);
        }
        if ($noStore) {
            $response->addHeader('Cache-Control', 'no-store');
            $response->addHeader('Pragma', 'no-cache');
        }
        return $response;
    }

    private function isConstraintViolation(Throwable $exception): bool {
        for ($current = $exception; $current !== null; $current = $current->getPrevious()) {
            $code = (string)$current->getCode();
            if (str_starts_with($code, '23') || str_contains($current::class, 'UniqueConstraintViolation')) {
                return true;
            }
        }
        return false;
    }
}
