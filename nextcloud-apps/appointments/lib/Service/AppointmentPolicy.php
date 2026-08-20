<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

/** Dependency-free appointment lifecycle and notice policy. */
final class AppointmentPolicy {
    public const ACTIVE = ['pending', 'confirmed', 'rescheduled'];
    public const STATUSES = [
        'pending', 'confirmed', 'cancelled_by_customer', 'cancelled_by_staff',
        'completed', 'no_show', 'rescheduled',
    ];

    /** @var array<string,list<string>> */
    private const TRANSITIONS = [
        'pending' => ['confirmed', 'cancelled_by_customer', 'cancelled_by_staff', 'completed', 'no_show', 'rescheduled'],
        'confirmed' => ['cancelled_by_customer', 'cancelled_by_staff', 'completed', 'no_show', 'rescheduled'],
        'rescheduled' => ['confirmed', 'cancelled_by_customer', 'cancelled_by_staff', 'completed', 'no_show', 'rescheduled'],
        'cancelled_by_customer' => [],
        'cancelled_by_staff' => [],
        'completed' => [],
        'no_show' => [],
    ];

    public function isKnownStatus(string $status): bool {
        return in_array($status, self::STATUSES, true);
    }

    public function canTransition(string $from, string $to, bool $customer = false): bool {
        if ($from === $to) {
            return true;
        }
        if (!$this->isKnownStatus($from) || !$this->isKnownStatus($to)) {
            return false;
        }
        if ($customer && !in_array($to, ['cancelled_by_customer', 'rescheduled'], true)) {
            return false;
        }
        return in_array($to, self::TRANSITIONS[$from], true);
    }

    public function cancellationAllowed(int $startsAt, int $now, int $noticeMinutes): bool {
        return $startsAt > $now && ($startsAt - $now) >= max(0, $noticeMinutes) * 60;
    }

    public function rescheduleAllowed(int $startsAt, int $now, int $noticeMinutes): bool {
        return $this->cancellationAllowed($startsAt, $now, $noticeMinutes);
    }
}
