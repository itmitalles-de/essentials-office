<?php

declare(strict_types=1);

namespace OCA\Appointments\Provider;

interface CalendarProvider {
    /** @return list<array{startsAt:int,endsAt:int}> */
    public function busyIntervals(string $organizationId, string $staffPublicId, int $from, int $to): array;

    /** Return an opaque external reference; never a credential-bearing URL. */
    public function upsert(string $organizationId, array $appointment, ?string $opaqueReference): ?string;

    public function cancel(string $organizationId, string $opaqueReference): void;
}
