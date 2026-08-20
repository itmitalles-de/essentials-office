<?php

declare(strict_types=1);

namespace OCA\Appointments\Provider;

final class DisabledMeetingProvider implements MeetingProvider {
    public function create(string $organizationId, string $appointmentPublicId, int $startsAt, int $endsAt): ?string {
        return null;
    }

    public function cancel(string $opaqueReference): void {
    }
}
