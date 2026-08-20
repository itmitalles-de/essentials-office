<?php

declare(strict_types=1);

namespace OCA\Appointments\Exception;

final class ConflictException extends ApiException {
    public function __construct(string $message, string $errorCode = 'slot_conflict') {
        parent::__construct($message, $errorCode, 409);
    }
}
