<?php

declare(strict_types=1);

namespace OCA\Appointments\Exception;

use RuntimeException;

class ApiException extends RuntimeException {
    public function __construct(
        string $message,
        private readonly string $errorCode,
        private readonly int $httpStatus,
    ) {
        parent::__construct($message);
    }

    public function getErrorCode(): string {
        return $this->errorCode;
    }

    public function getHttpStatus(): int {
        return $this->httpStatus;
    }
}
