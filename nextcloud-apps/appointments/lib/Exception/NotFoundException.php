<?php

declare(strict_types=1);

namespace OCA\Appointments\Exception;

final class NotFoundException extends ApiException {
    public function __construct(string $message) {
        parent::__construct($message, 'not_found', 404);
    }
}
