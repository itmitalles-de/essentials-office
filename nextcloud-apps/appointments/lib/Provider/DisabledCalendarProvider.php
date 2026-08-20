<?php

declare(strict_types=1);

namespace OCA\Appointments\Provider;

final class DisabledCalendarProvider implements CalendarProvider {
    public function busyIntervals(string $organizationId, string $staffPublicId, int $from, int $to): array {
        return [];
    }

    public function upsert(string $organizationId, array $appointment, ?string $opaqueReference): ?string {
        return null;
    }

    public function cancel(string $organizationId, string $opaqueReference): void {
    }
}
