<?php

declare(strict_types=1);

namespace OCA\Appointments\Exception;

final class ValidationException extends ApiException {
    public function __construct(string $message, string $errorCode = 'validation_failed') {
        parent::__construct($message, $errorCode, 422);
    }
}
