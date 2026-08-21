<?php

declare(strict_types=1);

namespace OCA\Appointments\Exception;

final class ForbiddenException extends ApiException {
    public function __construct(string $message) {
        parent::__construct($message, 'forbidden', 403);
    }
}
