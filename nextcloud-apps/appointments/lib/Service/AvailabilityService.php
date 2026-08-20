<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use DateTimeImmutable;
use OCA\Appointments\Exception\ConflictException;
use OCA\Appointments\Exception\NotFoundException;
use OCA\Appointments\Exception\ValidationException;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\IL10N;

final class AvailabilityService {
    public function __construct(
        private OrganizationRepository $organizations,
        private CatalogRepository $catalog,
        private AvailabilityRepository $availability,
        private AvailabilityEngine $engine,
        private AuthorizationService $authorization,
        private InputValidator $validator,
        private Database $database,
        private AuditService $audit,
        private ITimeFactory $time,
        private IL10N $l10n,
    ) {
    }

    /** @return array<string, mixed> */
    public function publicSlots(string $organizationSlug, array $input): array {
        $organization = $this->organizations->requirePublicBySlug($organizationSlug);
        return $this->withoutResourceIds($this->slotsForOrganization(
            $organization,
            $this->normalizeSlotInput($input, (string)$organization['timezone']),
            true,
        ));
    }

    /** @return array<string, mixed> */
    public function internalSlots(string $organizationId, array $input): array {
        $this->authorization->assert($organizationId, AuthorizationService::VIEW);
        $organization = $this->organizations->requireById($organizationId);
        return $this->slotsForOrganization($organization, $this->normalizeSlotInput($input, (string)$organization['timezone']), false);
    }

    /** @param array<string,mixed> $appointment
     *  @return array<string,mixed>
     */
    public function managementSlots(array $appointment, array $input): array {
        $organizationId = (string)$appointment['organization_id'];
        $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
        $input['serviceId'] = (string)$service['public_id'];
        $organization = $this->organizations->requireById($organizationId);
        return $this->withoutResourceIds($this->slotsForOrganization(
            $organization,
            $this->normalizeSlotInput($input, (string)$organization['timezone']),
            false,
            (int)$appointment['id'],
        ));
    }

    /**
     * Must be called while the organization row is locked.
     * @return array{start:int,end:int,staffId:string,locationId:?string,resourceIds:list<string>}
     */
    public function requireBookableSlot(
        array $organization,
        array $input,
        bool $public,
        ?int $excludeAppointmentId = null,
        bool $exactSelection = false,
    ): array {
        $input['from'] = $input['start'];
        $service = $this->resolveService((string)$organization['organization_id'], $input);
        $input['to'] = (int)$input['start'] + ((int)$service['duration_min'] * 60);
        $result = $this->slotsForOrganization($organization, $input, $public, $excludeAppointmentId);
        foreach ($result['slots'] as $slot) {
            $staffMatches = $exactSelection
                ? (string)$slot['staffId'] === (string)($input['staffId'] ?? '')
                : (!isset($input['staffId']) || $input['staffId'] === '' || $slot['staffId'] === $input['staffId']);
            $locationMatches = $exactSelection
                ? ($slot['locationId'] ?? null) === ($input['locationId'] ?? null)
                : (!isset($input['locationId']) || $input['locationId'] === '' || $slot['locationId'] === $input['locationId']);
            if ((int)$slot['startTimestamp'] === (int)$input['start']
                && $staffMatches
                && $locationMatches) {
                return [
                    'start' => (int)$slot['startTimestamp'], 'end' => (int)$slot['endTimestamp'],
                    'staffId' => (string)$slot['staffId'], 'locationId' => $slot['locationId'],
                    'resourceIds' => $slot['resourceIds'],
                ];
            }
        }
        throw new ConflictException($this->l10n->t('The selected appointment slot is no longer available.'));
    }

    /** @return array<string, mixed> */
    public function replaceAvailability(string $organizationId, string $subjectType, string $subjectId, array $input): array {
        if (!in_array($subjectType, ['organization', 'service', 'staff', 'location', 'resource'], true)) {
            throw new ValidationException($this->l10n->t('The availability subject type is invalid.'));
        }
        if ($subjectType === 'organization') {
            if ($subjectId !== $organizationId) {
                throw new ValidationException($this->l10n->t('The availability subject is invalid.'));
            }
            $this->authorization->assert($organizationId, AuthorizationService::MANAGE_AVAILABILITY);
        } elseif ($subjectType === 'staff') {
            $staff = $this->catalog->require('staff', $organizationId, $subjectId);
            $permissions = $this->authorization->permissions($organizationId);
            if (!in_array(AuthorizationService::MANAGE_AVAILABILITY, $permissions, true)) {
                if (!in_array(AuthorizationService::MANAGE_OWN_AVAILABILITY, $permissions, true)) {
                    $this->authorization->assert($organizationId, AuthorizationService::MANAGE_AVAILABILITY);
                }
                $this->authorization->assertOwnStaff($organizationId, (int)$staff['id']);
            }
        } else {
            $this->authorization->assert($organizationId, AuthorizationService::MANAGE_AVAILABILITY);
            $entity = match ($subjectType) {
                'service' => 'services', 'location' => 'locations', default => 'resources',
            };
            $this->catalog->require($entity, $organizationId, $subjectId);
        }
        $rules = $this->normalizeRules($input['rules'] ?? []);
        $exceptions = $this->normalizeExceptions($input['exceptions'] ?? []);
        $this->database->transaction(function () use ($organizationId, $subjectType, $subjectId, $rules, $exceptions): void {
            $this->organizations->lock($organizationId);
            $this->availability->replace($organizationId, $subjectType, $subjectId, $rules, $exceptions);
            $this->audit->record($organizationId, 'availability.replaced', 'user', $subjectType, $subjectId, 'success', ['count' => count($rules) + count($exceptions)]);
        });
        return ['subjectType' => $subjectType, 'subjectId' => $subjectId, 'rules' => $rules, 'exceptions' => $exceptions];
    }

    /** @return array<string,mixed> */
    public function getAvailability(string $organizationId, string $subjectType, string $subjectId): array {
        if (!in_array($subjectType, ['organization', 'service', 'staff', 'location', 'resource'], true)) {
            throw new ValidationException($this->l10n->t('The availability subject type is invalid.'));
        }
        $this->authorization->assert($organizationId, AuthorizationService::VIEW);
        if ($subjectType === 'organization') {
            if ($subjectId !== $organizationId) {
                throw new ValidationException($this->l10n->t('The availability subject is invalid.'));
            }
        } elseif ($subjectType === 'staff') {
            $staff = $this->catalog->require('staff', $organizationId, $subjectId);
            if (!$this->authorization->canViewAll($organizationId)) {
                $this->authorization->assertOwnStaff($organizationId, (int)$staff['id']);
            }
        } else {
            $entity = match ($subjectType) {
                'service' => 'services', 'location' => 'locations', default => 'resources',
            };
            $this->catalog->require($entity, $organizationId, $subjectId);
        }
        return [
            'subjectType' => $subjectType, 'subjectId' => $subjectId,
            'rules' => $this->availability->rules($organizationId, $subjectType, $subjectId),
            'exceptions' => $this->availability->exceptions($organizationId, $subjectType, $subjectId, 0, 4102444800),
        ];
    }

    /** @param array<string, mixed> $organization
     *  @return array<string, mixed>
     */
    private function slotsForOrganization(array $organization, array $input, bool $public, ?int $excludeAppointmentId = null): array {
        $organizationId = (string)$organization['organization_id'];
        $service = $this->resolveService($organizationId, $input);
        if (!$service['active']) {
            throw new NotFoundException($this->l10n->t('The requested service was not found.'));
        }
        if ($public) {
            $this->assertPublicService($service, isset($input['serviceSlug']) ? (string)$input['serviceSlug'] : null);
        }
        $now = $this->time->getTime();
        $from = isset($input['from']) ? $this->validator->timestamp($input, 'from') : $now;
        $to = isset($input['to']) ? $this->validator->timestamp($input, 'to') : $from + (14 * 86400);
        if ($to <= $from || $to - $from > 31 * 86400) {
            throw new ValidationException($this->l10n->t('The slot search range is invalid.'));
        }
        $busyFrom = $from - ((int)$service['buffer_before'] * 60);
        $busyTo = $to + ((int)$service['buffer_after'] * 60);
        $staffRows = $this->candidateStaff($organizationId, $service, $input, $public);
        $locationRows = $this->candidateLocations($organizationId, $service, $input, $public);
        $locationRows = $this->filterLocationsForResources($organizationId, $service, $locationRows);
        $locationWasRequested = isset($input['locationId']) && (string)$input['locationId'] !== '';
        $serviceHasLocations = $this->catalog->serviceLocationIds($organizationId, (int)$service['id']) !== [];
        $requiresLocation = $locationWasRequested || $serviceHasLocations || (string)$service['appointment_type'] === 'on_site';
        if ($staffRows === [] || ($requiresLocation && $locationRows === [])) {
            return ['timezone' => (string)$organization['timezone'], 'serviceId' => (string)$service['public_id'], 'slots' => []];
        }
        $organizationRules = $this->availability->rules($organizationId, 'organization', $organizationId);
        $organizationExceptions = $this->availability->exceptions($organizationId, 'organization', $organizationId, $busyFrom, $busyTo);
        $fallbackOrganizationRules = $organizationRules;
        if ($fallbackOrganizationRules === []) {
            $fallbackOrganizationRules = $this->alwaysAvailableRules();
        }
        $resourceRows = $this->requiredResources(
            $organizationId,
            $service,
            $locationRows,
            $busyFrom,
            $busyTo,
            $excludeAppointmentId,
            $fallbackOrganizationRules,
        );

        $engineInput = [
            'now' => $now, 'rangeStart' => $from, 'rangeEnd' => $to,
            'timezone' => (string)$organization['timezone'], 'slotInterval' => (int)$organization['slot_interval'],
            'durationMinutes' => (int)$service['duration_min'], 'bufferBeforeMinutes' => (int)$service['buffer_before'],
            'bufferAfterMinutes' => (int)$service['buffer_after'], 'minimumNoticeMinutes' => (int)$service['min_notice_min'],
            'maximumHorizonDays' => (int)$service['max_horizon_days'],
            'locationRequired' => $requiresLocation,
            'staff' => array_map(fn (array $row): array => $this->staffSubject($organizationId, $row, $busyFrom, $busyTo, $excludeAppointmentId), $staffRows),
            'locations' => array_map(fn (array $row): array => $this->locationSubject($organizationId, $row, $busyFrom, $busyTo, $excludeAppointmentId, $fallbackOrganizationRules), $locationRows),
            'resources' => $resourceRows,
        ];
        if ($organizationRules !== [] || $organizationExceptions !== []) {
            $effectiveOrganizationRules = $organizationRules;
            $hasSpecialOpening = count(array_filter(
                $organizationExceptions,
                static fn (array $exception): bool => (string)$exception['type'] === 'available',
            )) > 0;
            if ($effectiveOrganizationRules === [] && !$hasSpecialOpening) {
                $effectiveOrganizationRules = $this->alwaysAvailableRules();
            }
            $engineInput['organization'] = [
                'id' => $organizationId, 'timezone' => (string)$organization['timezone'], 'rules' => $effectiveOrganizationRules,
                'exceptions' => $organizationExceptions, 'busy' => [],
            ];
        }
        $serviceRules = $this->availability->rules($organizationId, 'service', (string)$service['public_id']);
        $serviceExceptions = $this->availability->exceptions($organizationId, 'service', (string)$service['public_id'], $busyFrom, $busyTo);
        if ($serviceRules !== [] || $serviceExceptions !== []) {
            $effectiveServiceRules = $serviceRules;
            $hasSpecialOpening = count(array_filter(
                $serviceExceptions,
                static fn (array $exception): bool => (string)$exception['type'] === 'available',
            )) > 0;
            if ($effectiveServiceRules === [] && !$hasSpecialOpening) {
                $effectiveServiceRules = $this->alwaysAvailableRules();
            }
            $engineInput['service'] = [
                'id' => (string)$service['public_id'], 'timezone' => (string)$organization['timezone'],
                'rules' => $effectiveServiceRules, 'exceptions' => $serviceExceptions, 'busy' => [],
            ];
        }
        $slots = array_map(static fn (array $slot): array => [
            'start' => (new DateTimeImmutable('@' . $slot['start']))->format(DATE_ATOM),
            'end' => (new DateTimeImmutable('@' . $slot['end']))->format(DATE_ATOM),
            'startsAt' => (new DateTimeImmutable('@' . $slot['start']))->format(DATE_ATOM),
            'endsAt' => (new DateTimeImmutable('@' . $slot['end']))->format(DATE_ATOM),
            'startTimestamp' => $slot['start'], 'endTimestamp' => $slot['end'],
            'staffId' => $slot['staffId'], 'locationId' => $slot['locationId'], 'resourceIds' => $slot['resourceIds'],
        ], $this->engine->calculate($engineInput));
        return ['timezone' => (string)$organization['timezone'], 'serviceId' => (string)$service['public_id'], 'slots' => $slots];
    }

    /** @param array<string,mixed> $result
     *  @return array<string,mixed>
     */
    private function withoutResourceIds(array $result): array {
        $result['slots'] = array_map(static function (array $slot): array {
            unset($slot['resourceIds']);
            return $slot;
        }, $result['slots']);
        return $result;
    }

    /** @return list<array{weekday:int,startMinute:int,endMinute:int,type:string,validFrom:string,validUntil:string}> */
    private function alwaysAvailableRules(): array {
        return array_map(static fn (int $weekday): array => [
            'weekday' => $weekday, 'startMinute' => 0, 'endMinute' => 1440,
            'type' => 'available', 'validFrom' => '', 'validUntil' => '',
        ], range(1, 7));
    }

    /** @return array<string,mixed> */
    private function normalizeSlotInput(array $input, string $defaultTimezone): array {
        if (isset($input['service']) && !isset($input['serviceSlug'])) {
            $input['serviceSlug'] = (string)$input['service'];
        }
        if (isset($input['date']) && !isset($input['from']) && !isset($input['to'])) {
            $timezone = $this->validator->timezone(['timezone' => $input['timezone'] ?? $defaultTimezone], 'timezone', $defaultTimezone);
            $range = $this->validator->localDayRange((string)$input['date'], $timezone);
            $input['from'] = $range['from'];
            $input['to'] = $range['to'];
        }
        return $input;
    }

    /** @return array<string, mixed> */
    private function resolveService(string $organizationId, array $input): array {
        if (isset($input['serviceId']) && (string)$input['serviceId'] !== '') {
            return $this->catalog->require('services', $organizationId, (string)$input['serviceId']);
        }
        if (isset($input['serviceSlug']) && (string)$input['serviceSlug'] !== '') {
            return $this->catalog->requireServiceBySlug($organizationId, (string)$input['serviceSlug']);
        }
        throw new ValidationException($this->l10n->t('A service must be selected.'));
    }

    private function assertPublicService(array $service, ?string $explicitSlug): void {
        $visibility = (string)$service['visibility'];
        if ($visibility === 'public') {
            return;
        }
        if ($visibility === 'direct_link' && $explicitSlug !== null && hash_equals((string)$service['slug'], $explicitSlug)) {
            return;
        }
        throw new NotFoundException($this->l10n->t('The requested service was not found.'));
    }

    /** @return list<array<string, mixed>> */
    private function candidateStaff(string $organizationId, array $service, array $input, bool $public): array {
        $allowed = $this->catalog->serviceStaffIds($organizationId, (int)$service['id']);
        $rows = $this->catalog->all('staff', $organizationId, $public);
        $rows = array_values(array_filter($rows, static fn (array $row): bool => (bool)$row['active']));
        if ($allowed !== []) {
            $rows = array_values(array_filter($rows, static fn (array $row): bool => in_array((string)$row['public_id'], $allowed, true)));
        }
        if (isset($input['staffId']) && (string)$input['staffId'] !== '') {
            $staffId = (string)$input['staffId'];
            $rows = array_values(array_filter($rows, static fn (array $row): bool => (string)$row['public_id'] === $staffId));
        }
        return $rows;
    }

    /** @return list<array<string, mixed>> */
    private function candidateLocations(string $organizationId, array $service, array $input, bool $public): array {
        $allowed = $this->catalog->serviceLocationIds($organizationId, (int)$service['id']);
        $rows = $this->catalog->all('locations', $organizationId, $public);
        $rows = array_values(array_filter($rows, static fn (array $row): bool => (bool)$row['active']));
        if ($allowed !== []) {
            $rows = array_values(array_filter($rows, static fn (array $row): bool => in_array((string)$row['public_id'], $allowed, true)));
        } else {
            $kind = (string)$service['appointment_type'];
            $rows = array_values(array_filter($rows, static fn (array $row): bool => (string)$row['kind'] === $kind));
        }
        if (isset($input['locationId']) && (string)$input['locationId'] !== '') {
            $locationId = (string)$input['locationId'];
            $rows = array_values(array_filter($rows, static fn (array $row): bool => (string)$row['public_id'] === $locationId));
        }
        return $rows;
    }

    /** @return list<array<string,mixed>> */
    private function filterLocationsForResources(string $organizationId, array $service, array $locations): array {
        $boundLocationIds = [];
        foreach ($this->catalog->resourceRequirements($organizationId, (int)$service['id']) as $requirement) {
            $resource = $this->catalog->requireInternal('resources', $organizationId, $requirement['resourceInternalId']);
            if (!$resource['active']) {
                return [];
            }
            if ($resource['location_id'] !== null) {
                $boundLocationIds[] = (int)$resource['location_id'];
            }
        }
        $boundLocationIds = array_values(array_unique($boundLocationIds));
        if ($boundLocationIds === []) {
            return $locations;
        }
        if (count($boundLocationIds) !== 1) {
            return [];
        }
        return array_values(array_filter(
            $locations,
            static fn (array $location): bool => (int)$location['id'] === $boundLocationIds[0],
        ));
    }

    /** @return list<array<string,mixed>> */
    private function requiredResources(
        string $organizationId,
        array $service,
        array $locations,
        int $from,
        int $to,
        ?int $excludeAppointmentId,
        array $fallbackRules,
    ): array {
        $locationInternalIds = array_map(static fn (array $row): int => (int)$row['id'], $locations);
        $organization = $this->organizations->requireById($organizationId);
        $result = [];
        foreach ($this->catalog->resourceRequirements($organizationId, (int)$service['id']) as $requirement) {
            $resource = $this->catalog->requireInternal('resources', $organizationId, $requirement['resourceInternalId']);
            if (!$resource['active'] || ($resource['location_id'] !== null && !in_array((int)$resource['location_id'], $locationInternalIds, true))) {
                return [['id' => (string)$resource['public_id'], 'timezone' => (string)$organization['timezone'], 'rules' => [], 'exceptions' => [], 'busy' => [], 'allocations' => [], 'capacity' => 0, 'requiredQuantity' => 1]];
            }
            $rules = $this->availability->rules($organizationId, 'resource', (string)$resource['public_id']);
            if ($rules === []) {
                $rules = $fallbackRules;
            }
            $result[] = [
                'id' => (string)$resource['public_id'], 'timezone' => (string)$organization['timezone'], 'rules' => $rules,
                'locationId' => $resource['location_id'] === null ? null : (string)$this->catalog->requireInternal('locations', $organizationId, (int)$resource['location_id'])['public_id'],
                'exceptions' => $this->availability->exceptions($organizationId, 'resource', (string)$resource['public_id'], $from, $to),
                'busy' => [], 'allocations' => $this->availability->resourceBusy($organizationId, (int)$resource['id'], $from, $to, $excludeAppointmentId),
                'capacity' => (int)$resource['capacity'], 'requiredQuantity' => (int)$requirement['quantity'],
            ];
        }
        return $result;
    }

    /** @return array<string,mixed> */
    private function staffSubject(string $organizationId, array $row, int $from, int $to, ?int $excludeAppointmentId): array {
        return [
            'id' => (string)$row['public_id'], 'timezone' => (string)$row['timezone'],
            'locationIds' => $this->catalog->staffLocationIds($organizationId, (int)$row['id']),
            'rules' => $this->availability->rules($organizationId, 'staff', (string)$row['public_id']),
            'exceptions' => $this->availability->exceptions($organizationId, 'staff', (string)$row['public_id'], $from, $to),
            'busy' => $this->availability->staffBusy($organizationId, (int)$row['id'], $from, $to, $excludeAppointmentId),
        ];
    }

    /** @return array<string,mixed> */
    private function locationSubject(string $organizationId, array $row, int $from, int $to, ?int $excludeAppointmentId, array $fallbackRules): array {
        $rules = $this->availability->rules($organizationId, 'location', (string)$row['public_id']);
        return [
            'id' => (string)$row['public_id'], 'timezone' => (string)$row['timezone'], 'rules' => $rules === [] ? $fallbackRules : $rules,
            'exceptions' => $this->availability->exceptions($organizationId, 'location', (string)$row['public_id'], $from, $to),
            // A location is an opening-hours/address context, not a capacity-one room.
            // Capacity constraints are represented by resources.
            'busy' => [],
        ];
    }

    /** @return list<array<string,mixed>> */
    private function normalizeRules(mixed $value): array {
        if (!is_array($value)) {
            throw new ValidationException($this->l10n->t('Availability rules are invalid.'));
        }
        $rules = [];
        foreach ($value as $rule) {
            if (!is_array($rule)) {
                throw new ValidationException($this->l10n->t('An availability rule is invalid.'));
            }
            $weekday = filter_var($rule['weekday'] ?? null, FILTER_VALIDATE_INT);
            $start = filter_var($rule['startMinute'] ?? null, FILTER_VALIDATE_INT);
            $end = filter_var($rule['endMinute'] ?? null, FILTER_VALIDATE_INT);
            $type = (string)($rule['type'] ?? 'available');
            if ($weekday === false || $weekday < 1 || $weekday > 7 || $start === false || $start < 0 || $start > 1439
                || $end === false || $end < 0 || $end > 1440 || !in_array($type, ['available', 'break', 'blocked'], true)) {
                throw new ValidationException($this->l10n->t('An availability rule is invalid.'));
            }
            $validFrom = (string)($rule['validFrom'] ?? '');
            $validUntil = (string)($rule['validUntil'] ?? '');
            foreach ([$validFrom, $validUntil] as $date) {
                $parsed = $date === '' ? null : DateTimeImmutable::createFromFormat('!Y-m-d', $date, new \DateTimeZone('UTC'));
                if ($date !== '' && ($parsed === false || $parsed->format('Y-m-d') !== $date)) {
                    throw new ValidationException($this->l10n->t('An availability rule date is invalid.'));
                }
            }
            if ($validFrom !== '' && $validUntil !== '' && $validFrom > $validUntil) {
                throw new ValidationException($this->l10n->t('An availability rule date is invalid.'));
            }
            $rules[] = ['weekday' => (int)$weekday, 'startMinute' => (int)$start, 'endMinute' => (int)$end, 'type' => $type, 'validFrom' => $validFrom, 'validUntil' => $validUntil];
        }
        return $rules;
    }

    /** @return list<array<string,mixed>> */
    private function normalizeExceptions(mixed $value): array {
        if (!is_array($value)) {
            throw new ValidationException($this->l10n->t('Availability exceptions are invalid.'));
        }
        $exceptions = [];
        foreach ($value as $exception) {
            if (!is_array($exception)) {
                throw new ValidationException($this->l10n->t('An availability exception is invalid.'));
            }
            $startsAt = $this->validator->timestamp($exception, 'startsAt');
            $endsAt = $this->validator->timestamp($exception, 'endsAt');
            $type = (string)($exception['type'] ?? 'blocked');
            if ($endsAt <= $startsAt || !in_array($type, ['available', 'blocked', 'break', 'vacation', 'holiday', 'absence'], true)) {
                throw new ValidationException($this->l10n->t('An availability exception is invalid.'));
            }
            $reason = trim((string)($exception['reason'] ?? ''));
            if (mb_strlen($reason) > 255) {
                throw new ValidationException($this->l10n->t('An availability exception reason is too long.'));
            }
            $exceptions[] = ['startsAt' => $startsAt, 'endsAt' => $endsAt, 'type' => $type, 'reason' => $reason];
        }
        return $exceptions;
    }
}
