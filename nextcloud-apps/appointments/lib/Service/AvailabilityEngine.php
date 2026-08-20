<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use DateTimeImmutable;
use DateTimeZone;

/**
 * Pure UTC availability calculation. All interval ends are exclusive.
 * Weekly rules use ISO weekdays and local minutes in the subject time zone.
 */
final class AvailabilityEngine {
    /**
     * @param array{
     *   now: int, rangeStart: int, rangeEnd: int, timezone: string, slotInterval: int,
     *   durationMinutes: int, bufferBeforeMinutes: int, bufferAfterMinutes: int,
     *   minimumNoticeMinutes: int, maximumHorizonDays: int,
     *   staff: list<array<string,mixed>>, locations: list<array<string,mixed>>, locationRequired?: bool,
     *   resources: list<array<string,mixed>>, organization?: array<string,mixed>
     * } $input
     * @return list<array{start: int, end: int, staffId: string, locationId: ?string, resourceIds: list<string>}>
     */
    public function calculate(array $input): array {
        $earliest = max((int)$input['rangeStart'], (int)$input['now'] + ((int)$input['minimumNoticeMinutes'] * 60));
        $latest = min((int)$input['rangeEnd'], (int)$input['now'] + ((int)$input['maximumHorizonDays'] * 86400));
        if ($latest <= $earliest || $input['staff'] === []) {
            return [];
        }

        $timezone = new DateTimeZone((string)$input['timezone']);
        $durationSeconds = (int)$input['durationMinutes'] * 60;
        $beforeSeconds = (int)$input['bufferBeforeMinutes'] * 60;
        $afterSeconds = (int)$input['bufferAfterMinutes'] * 60;
        $cursor = intdiv($earliest + 59, 60) * 60;
        $slots = [];

        for (; $cursor + $durationSeconds <= $latest; $cursor += 60) {
            $local = (new DateTimeImmutable('@' . $cursor))->setTimezone($timezone);
            $localMinute = ((int)$local->format('G') * 60) + (int)$local->format('i');
            if ($localMinute % (int)$input['slotInterval'] !== 0 || $cursor % 60 !== 0) {
                continue;
            }
            $startsAt = $cursor;
            $endsAt = $startsAt + $durationSeconds;
            $busyStartsAt = $startsAt - $beforeSeconds;
            $busyEndsAt = $endsAt + $afterSeconds;

            if (isset($input['organization'])
                && !$this->subjectAvailable($input['organization'], $busyStartsAt, $busyEndsAt)) {
                continue;
            }
            if (isset($input['service'])
                && !$this->subjectAvailable($input['service'], $busyStartsAt, $busyEndsAt)) {
                continue;
            }
            $locations = $input['locations'] === []
                ? (!empty($input['locationRequired']) ? [] : [null])
                : $input['locations'];
            foreach ($locations as $location) {
                if ($location !== null && !$this->subjectAvailable($location, $busyStartsAt, $busyEndsAt)) {
                    continue;
                }
                foreach ($input['staff'] as $staff) {
                    $staffLocationIds = $staff['locationIds'] ?? [];
                    if ($location !== null && $staffLocationIds !== []
                        && !in_array((string)$location['id'], $staffLocationIds, true)) {
                        continue;
                    }
                    if (!$this->subjectAvailable($staff, $busyStartsAt, $busyEndsAt)) {
                        continue;
                    }
                    if (!$this->resourcesAvailable(
                        $input['resources'],
                        $busyStartsAt,
                        $busyEndsAt,
                        $location === null ? null : (string)$location['id'],
                    )) {
                        continue;
                    }
                    $slots[] = [
                        'start' => $startsAt,
                        'end' => $endsAt,
                        'staffId' => (string)$staff['id'],
                        'locationId' => $location === null ? null : (string)$location['id'],
                        'resourceIds' => array_values(array_map(
                            static fn (array $resource): string => (string)$resource['id'],
                            $input['resources'],
                        )),
                    ];
                    break 2;
                }
            }
            if (count($slots) >= 500) {
                break;
            }
        }
        return $slots;
    }

    /** @param array<string, mixed> $subject */
    public function subjectAvailable(array $subject, int $startsAt, int $endsAt): bool {
        if ($endsAt <= $startsAt) {
            return false;
        }
        foreach ($subject['exceptions'] ?? [] as $exception) {
            if ($this->overlaps($startsAt, $endsAt, (int)$exception['startsAt'], (int)$exception['endsAt'])
                && (string)$exception['type'] !== 'available') {
                return false;
            }
        }
        foreach ($subject['busy'] ?? [] as $busy) {
            if ($this->overlaps($startsAt, $endsAt, (int)$busy['startsAt'], (int)$busy['endsAt'])) {
                return false;
            }
        }
        foreach ($subject['exceptions'] ?? [] as $exception) {
            if ((string)$exception['type'] === 'available'
                && (int)$exception['startsAt'] <= $startsAt
                && (int)$exception['endsAt'] >= $endsAt) {
                return true;
            }
        }
        foreach ($this->weeklyWindows($subject, $startsAt, $endsAt) as $window) {
            if ($window['type'] === 'available' && $window['startsAt'] <= $startsAt && $window['endsAt'] >= $endsAt) {
                foreach (['break', 'blocked'] as $blockedType) {
                    foreach ($this->weeklyWindows($subject, $startsAt, $endsAt, $blockedType) as $break) {
                        if ($this->overlaps($startsAt, $endsAt, $break['startsAt'], $break['endsAt'])) {
                            continue 3;
                        }
                    }
                }
                return true;
            }
        }
        return false;
    }

    /** @param list<array<string, mixed>> $resources */
    private function resourcesAvailable(array $resources, int $startsAt, int $endsAt, ?string $locationId): bool {
        foreach ($resources as $resource) {
            if (isset($resource['locationId']) && $resource['locationId'] !== null
                && (string)$resource['locationId'] !== (string)$locationId) {
                return false;
            }
            if (!$this->subjectAvailable($resource, $startsAt, $endsAt)) {
                return false;
            }
            $used = 0;
            foreach ($resource['allocations'] ?? [] as $allocation) {
                if ($this->overlaps($startsAt, $endsAt, (int)$allocation['startsAt'], (int)$allocation['endsAt'])) {
                    $used += (int)$allocation['quantity'];
                }
            }
            if ($used + (int)$resource['requiredQuantity'] > (int)$resource['capacity']) {
                return false;
            }
        }
        return true;
    }

    /** @param array<string, mixed> $subject
     *  @return list<array{startsAt:int,endsAt:int,type:string}>
     */
    private function weeklyWindows(array $subject, int $startsAt, int $endsAt, ?string $onlyType = null): array {
        $timezone = new DateTimeZone((string)$subject['timezone']);
        $firstLocalDate = (new DateTimeImmutable('@' . ($startsAt - 86400)))->setTimezone($timezone)->setTime(0, 0);
        $lastLocalDate = (new DateTimeImmutable('@' . ($endsAt + 86400)))->setTimezone($timezone)->setTime(0, 0);
        $windows = [];
        for ($date = $firstLocalDate; $date <= $lastLocalDate; $date = $date->modify('+1 day')) {
            $isoDate = $date->format('Y-m-d');
            $weekday = (int)$date->format('N');
            foreach ($subject['rules'] ?? [] as $rule) {
                $type = (string)$rule['type'];
                if ((int)$rule['weekday'] !== $weekday || ($onlyType !== null && $type !== $onlyType)) {
                    continue;
                }
                if (($rule['validFrom'] ?? '') !== '' && $isoDate < $rule['validFrom']) {
                    continue;
                }
                if (($rule['validUntil'] ?? '') !== '' && $isoDate > $rule['validUntil']) {
                    continue;
                }
                $startMinute = (int)$rule['startMinute'];
                $endMinute = (int)$rule['endMinute'];
                $start = $date->modify(sprintf('+%d minutes', $startMinute));
                $endBase = $endMinute <= $startMinute ? $date->modify('+1 day') : $date;
                $end = $endBase->modify(sprintf('+%d minutes', $endMinute));
                $windows[] = ['startsAt' => $start->getTimestamp(), 'endsAt' => $end->getTimestamp(), 'type' => $type];
            }
        }
        return $windows;
    }

    private function overlaps(int $leftStart, int $leftEnd, int $rightStart, int $rightEnd): bool {
        return $leftStart < $rightEnd && $leftEnd > $rightStart;
    }
}
