<?php

declare(strict_types=1);

namespace OCA\Appointments\Provider;

interface MeetingProvider {
    /**
     * Return only an opaque private reference. Provider-specific URLs must not
     * be exposed by slot or catalog APIs and must never be logged.
     */
    public function create(string $organizationId, string $appointmentPublicId, int $startsAt, int $endsAt): ?string;

    public function cancel(string $opaqueReference): void;
}
