<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use DateTimeImmutable;

final class IcsService {
    /** @param array<string,mixed> $appointment
     *  @param array<string,mixed> $service
     *  @param array<string,mixed>|null $location
     */
    public function render(array $appointment, array $service, ?array $location, string $organizationName): string {
        $cancelled = in_array($appointment['status'], ['cancelled_by_customer', 'cancelled_by_staff'], true);
        $description = $this->escape('Booking number: ' . $appointment['booking_number']);
        $lines = [
            'BEGIN:VCALENDAR',
            'VERSION:2.0',
            'PRODID:-//Essentials Plus//Appointments 1.0//EN',
            'CALSCALE:GREGORIAN',
            'METHOD:PUBLISH',
            'BEGIN:VEVENT',
            'UID:' . $this->escape((string)$appointment['public_id'] . '@appointments.essentialsplus'),
            'DTSTAMP:' . $this->utc(time()),
            'DTSTART:' . $this->utc((int)$appointment['starts_at']),
            'DTEND:' . $this->utc((int)$appointment['ends_at']),
            'SUMMARY:' . $this->escape((string)$service['name'] . ' · ' . $organizationName),
            'DESCRIPTION:' . $description,
            'STATUS:' . ($cancelled ? 'CANCELLED' : 'CONFIRMED'),
            'SEQUENCE:' . max(0, (int)$appointment['revision'] - 1),
        ];
        if ($location !== null) {
            $locationText = trim((string)$location['name'] . ' ' . (string)$location['address']);
            if ($locationText !== '') {
                $lines[] = 'LOCATION:' . $this->escape($locationText);
            }
        }
        $lines[] = 'END:VEVENT';
        $lines[] = 'END:VCALENDAR';
        $folded = [];
        foreach ($lines as $line) {
            array_push($folded, ...$this->fold($line));
        }
        return implode("\r\n", $folded) . "\r\n";
    }

    private function utc(int $timestamp): string {
        return (new DateTimeImmutable('@' . $timestamp))->format('Ymd\THis\Z');
    }

    private function escape(string $value): string {
        return str_replace(["\\", ";", ",", "\r", "\n"], ["\\\\", '\\;', '\\,', '', '\\n'], $value);
    }

    /** @return list<string> */
    private function fold(string $line): array {
        $result = [];
        $prefix = '';
        while (strlen($line) > ($prefix === '' ? 75 : 74)) {
            $limit = $prefix === '' ? 75 : 74;
            $chunk = mb_strcut($line, 0, $limit, 'UTF-8');
            $result[] = $prefix . $chunk;
            $line = substr($line, strlen($chunk));
            $prefix = ' ';
        }
        $result[] = $prefix . $line;
        return $result;
    }
}
