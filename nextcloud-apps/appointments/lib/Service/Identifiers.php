<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCP\Security\ISecureRandom;

final class Identifiers {
    public function __construct(private ISecureRandom $random) {
    }

    public function publicId(): string {
        return strtolower($this->random->generate(32, ISecureRandom::CHAR_ALPHANUMERIC));
    }

    public function managementToken(): string {
        return $this->random->generate(48, ISecureRandom::CHAR_ALPHANUMERIC);
    }

    public function bookingNumber(): string {
        return 'A-' . strtoupper($this->random->generate(12, ISecureRandom::CHAR_HUMAN_READABLE));
    }

    public function tokenHash(string $token): string {
        return hash('sha256', $token);
    }
}
