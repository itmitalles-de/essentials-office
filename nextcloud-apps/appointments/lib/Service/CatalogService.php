<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\Exception\ValidationException;
use OCP\IUserManager;
use OCP\IL10N;

final class CatalogService {
    public function __construct(
        private CatalogRepository $catalog,
        private OrganizationRepository $organizations,
        private OrganizationService $organizationService,
        private AuthorizationService $authorization,
        private InputValidator $validator,
        private Identifiers $identifiers,
        private Database $database,
        private AuditService $audit,
        private OperationsService $operations,
        private IUserManager $userManager,
        private IL10N $l10n,
    ) {
    }

    /** @return array<string, mixed> */
    public function internalCatalog(string $organizationId): array {
        $this->authorization->assert($organizationId, AuthorizationService::VIEW);
        $permissions = $this->authorization->permissions($organizationId);
        $result = $this->buildCatalog($this->organizations->requireById($organizationId), false);
        if (!in_array(AuthorizationService::MANAGE_CATALOG, $permissions, true)) {
            foreach ($result['staff'] as &$staff) {
                unset($staff['userUid'], $staff['calendarUri']);
            }
            unset($staff);
        }
        if (!in_array(AuthorizationService::MANAGE_SETTINGS, $permissions, true)) {
            unset($result['operations']);
        }
        return $result;
    }

    /** @return array<string, mixed> */
    public function publicCatalog(string $organizationSlug, ?string $serviceSlug = null): array {
        return $this->buildCatalog($this->organizations->requirePublicBySlug($organizationSlug), true, $serviceSlug);
    }

    /** @return array<string, mixed> */
    public function saveService(string $organizationId, ?string $publicId, array $input): array {
        $this->authorization->assert($organizationId, AuthorizationService::MANAGE_CATALOG);
        $service = $this->database->transaction(function () use ($organizationId, $publicId, $input): array {
            $this->organizations->lock($organizationId);
            $current = $publicId === null ? [] : $this->catalog->require('services', $organizationId, $publicId);
            $values = $this->serviceValues($input, $current);
            $saved = $publicId === null
                ? $this->catalog->create('services', $organizationId, $this->identifiers->publicId(), $values, time())
                : $this->catalog->update('services', $organizationId, $publicId, $values, time());
            if (array_key_exists('staffIds', $input)) {
                $this->catalog->replaceServiceStaff($organizationId, (int)$saved['id'], $this->stringList($input['staffIds']));
            }
            if (array_key_exists('locationIds', $input)) {
                $this->catalog->replaceServiceLocations($organizationId, (int)$saved['id'], $this->stringList($input['locationIds']));
            }
            if (array_key_exists('resourceRequirements', $input)) {
                $this->catalog->replaceResourceRequirements(
                    $organizationId,
                    (int)$saved['id'],
                    $this->resourceRequirements($input['resourceRequirements']),
                );
            }
            if (array_key_exists('formFields', $input)) {
                $this->catalog->replaceFormFields(
                    $organizationId,
                    (int)$saved['id'],
                    $this->formFields($input['formFields']),
                    $this->identifiers,
                );
            }
            $this->audit->record($organizationId, $publicId === null ? 'service.created' : 'service.updated', 'user', 'service', (string)$saved['public_id']);
            return $saved;
        });
        return $this->presentService($organizationId, $service, false);
    }

    /** @return array<string, mixed> */
    public function saveStaff(string $organizationId, ?string $publicId, array $input): array {
        $this->authorization->assert($organizationId, AuthorizationService::MANAGE_CATALOG);
        $staff = $this->database->transaction(function () use ($organizationId, $publicId, $input): array {
            $this->organizations->lock($organizationId);
            $current = $publicId === null ? [] : $this->catalog->require('staff', $organizationId, $publicId);
            $userUid = (string)$this->inputOrCurrent($input, 'userUid', $current, 'user_uid', '');
            if ($userUid !== '' && $this->userManager->get($userUid) === null) {
                throw new ValidationException($this->l10n->t('The selected Nextcloud user does not exist.'));
            }
            $timezoneInput = ['timezone' => $this->inputOrCurrent($input, 'timezone', $current, 'timezone', 'Europe/Berlin')];
            $values = [
                'slug' => $this->validator->slug((string)$this->requiredOrCurrent($input, 'slug', $current, 'slug')),
                'user_uid' => $userUid === '' ? null : mb_substr($userUid, 0, 255),
                'display_name' => $this->limited($this->requiredOrCurrent($input, 'displayName', $current, 'display_name'), 255, true),
                'description' => $this->limited($this->inputOrCurrent($input, 'description', $current, 'description', ''), 10000),
                'qualifications' => $this->limited($this->inputOrCurrent($input, 'qualifications', $current, 'qualifications', ''), 10000),
                'timezone' => $this->validator->timezone($timezoneInput, 'timezone'),
                'public_booking' => $this->boolOrCurrent($input, 'publicBooking', $current, 'public_booking', true),
                'active' => $this->boolOrCurrent($input, 'active', $current, 'active', true),
                'calendar_uri' => $this->limited($this->inputOrCurrent($input, 'calendarUri', $current, 'calendar_uri', ''), 255),
            ];
            $saved = $publicId === null
                ? $this->catalog->create('staff', $organizationId, $this->identifiers->publicId(), $values, time())
                : $this->catalog->update('staff', $organizationId, $publicId, $values, time());
            if (array_key_exists('locationIds', $input)) {
                $this->catalog->replaceStaffLocations($organizationId, (int)$saved['id'], $this->stringList($input['locationIds']));
            }
            $this->audit->record($organizationId, $publicId === null ? 'staff.created' : 'staff.updated', 'user', 'staff', (string)$saved['public_id']);
            return $saved;
        });
        return $this->presentStaff($staff, false);
    }

    /** @return array<string, mixed> */
    public function saveLocation(string $organizationId, ?string $publicId, array $input): array {
        $this->authorization->assert($organizationId, AuthorizationService::MANAGE_CATALOG);
        $location = $this->database->transaction(function () use ($organizationId, $publicId, $input): array {
            $this->organizations->lock($organizationId);
            $current = $publicId === null ? [] : $this->catalog->require('locations', $organizationId, $publicId);
            $timezoneInput = ['timezone' => $this->inputOrCurrent($input, 'timezone', $current, 'timezone', 'Europe/Berlin')];
            $kind = (string)$this->inputOrCurrent($input, 'kind', $current, 'kind', 'on_site');
            if (!in_array($kind, ['on_site', 'phone', 'video', 'customer_site', 'custom'], true)) {
                throw new ValidationException($this->l10n->t('The appointment location type is invalid.'));
            }
            $values = [
                'slug' => $this->validator->slug((string)$this->requiredOrCurrent($input, 'slug', $current, 'slug')),
                'name' => $this->limited($this->requiredOrCurrent($input, 'name', $current, 'name'), 255, true),
                'kind' => $kind,
                'address' => $this->limited($this->inputOrCurrent($input, 'address', $current, 'address', ''), 10000),
                'room' => $this->limited($this->inputOrCurrent($input, 'room', $current, 'room', ''), 255),
                'timezone' => $this->validator->timezone($timezoneInput, 'timezone'),
                'public_notes' => $this->limited($this->inputOrCurrent($input, 'publicNotes', $current, 'public_notes', ''), 10000),
                'directions' => $this->limited($this->inputOrCurrent($input, 'directions', $current, 'directions', ''), 10000),
                'accessibility' => $this->limited($this->inputOrCurrent($input, 'accessibility', $current, 'accessibility', ''), 10000),
                'active' => $this->boolOrCurrent($input, 'active', $current, 'active', true),
            ];
            $saved = $publicId === null
                ? $this->catalog->create('locations', $organizationId, $this->identifiers->publicId(), $values, time())
                : $this->catalog->update('locations', $organizationId, $publicId, $values, time());
            $this->audit->record($organizationId, $publicId === null ? 'location.created' : 'location.updated', 'user', 'location', (string)$saved['public_id']);
            return $saved;
        });
        return $this->presentLocation($location);
    }

    /** @return array<string, mixed> */
    public function saveResource(string $organizationId, ?string $publicId, array $input): array {
        $this->authorization->assert($organizationId, AuthorizationService::MANAGE_CATALOG);
        $resource = $this->database->transaction(function () use ($organizationId, $publicId, $input): array {
            $this->organizations->lock($organizationId);
            $current = $publicId === null ? [] : $this->catalog->require('resources', $organizationId, $publicId);
            $locationPublicId = (string)$this->inputOrCurrent($input, 'locationId', [], '', '');
            $locationId = $current['location_id'] ?? null;
            if ($locationPublicId !== '') {
                $locationId = (int)$this->catalog->require('locations', $organizationId, $locationPublicId)['id'];
            } elseif (array_key_exists('locationId', $input)) {
                $locationId = null;
            }
            $capacity = $this->integerOrCurrent($input, 'capacity', $current, 'capacity', 1, 1, 100);
            $values = [
                'location_id' => $locationId,
                'name' => $this->limited($this->requiredOrCurrent($input, 'name', $current, 'name'), 255, true),
                'resource_type' => $this->limited($this->requiredOrCurrent($input, 'type', $current, 'resource_type'), 64, true),
                'capacity' => $capacity,
                'active' => $this->boolOrCurrent($input, 'active', $current, 'active', true),
            ];
            $saved = $publicId === null
                ? $this->catalog->create('resources', $organizationId, $this->identifiers->publicId(), $values, time())
                : $this->catalog->update('resources', $organizationId, $publicId, $values, time());
            $this->audit->record($organizationId, $publicId === null ? 'resource.created' : 'resource.updated', 'user', 'resource', (string)$saved['public_id']);
            return $saved;
        });
        return $this->presentResource($organizationId, $resource);
    }

    /** @param array<string, mixed> $organization
     *  @return array<string, mixed>
     */
    private function buildCatalog(array $organization, bool $publicOnly, ?string $explicitServiceSlug = null): array {
        $organizationId = (string)$organization['organization_id'];
        $serviceRows = $this->catalog->all('services', $organizationId, false);
        if ($publicOnly) {
            $serviceRows = array_values(array_filter($serviceRows, static function (array $row) use ($explicitServiceSlug): bool {
                if (!$row['active']) {
                    return false;
                }
                if ((string)$row['visibility'] === 'public') {
                    return true;
                }
                return $explicitServiceSlug !== null && $explicitServiceSlug !== ''
                    && (string)$row['visibility'] === 'direct_link'
                    && hash_equals((string)$row['slug'], $explicitServiceSlug);
            }));
        }
        $services = array_map(
            fn (array $row): array => $this->presentService($organizationId, $row, $publicOnly),
            $serviceRows,
        );
        $result = [
            'organization' => $publicOnly ? $this->organizationService->presentPublic($organization) : $this->organizationService->present($organization),
            'services' => $services,
            'staff' => array_map(fn (array $row): array => $this->presentStaff($row, $publicOnly), $this->catalog->all('staff', $organizationId, $publicOnly)),
            'locations' => array_map($this->presentLocation(...), $this->catalog->all('locations', $organizationId, $publicOnly)),
            'resources' => $publicOnly ? [] : array_map(fn (array $row): array => $this->presentResource($organizationId, $row), $this->catalog->all('resources', $organizationId)),
        ];
        if (!$publicOnly) {
            $result['operations'] = $this->operations->forOrganization($organizationId);
            $result['settings'] = $this->organizationService->present($organization);
        }
        return $result;
    }

    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    private function presentService(string $organizationId, array $row, bool $publicOnly): array {
        $presented = [
            'id' => (string)$row['public_id'],
            'slug' => (string)$row['slug'],
            'name' => (string)$row['name'],
            'shortName' => (string)$row['short_name'],
            'description' => (string)$row['description'],
            'durationMinutes' => (int)$row['duration_min'],
            'bufferBeforeMinutes' => (int)$row['buffer_before'],
            'bufferAfterMinutes' => (int)$row['buffer_after'],
            'priceMin' => $row['price_min'] === null ? null : ((int)$row['price_min'] / 100),
            'priceMax' => $row['price_max'] === null ? null : ((int)$row['price_max'] / 100),
            'priceMinMinor' => $row['price_min'],
            'priceMaxMinor' => $row['price_max'],
            'currency' => (string)$row['currency'],
            'confirmationMode' => (string)$row['confirmation_mode'],
            'minimumNoticeMinutes' => (int)$row['min_notice_min'],
            'maximumHorizonDays' => (int)$row['max_horizon_days'],
            'cancellationNoticeMinutes' => (int)$row['cancel_notice_min'],
            'rescheduleNoticeMinutes' => (int)$row['resched_notice_min'],
            'visibility' => (string)$row['visibility'],
            'active' => (bool)$row['active'],
            'color' => (string)$row['color'],
            'bookingNotes' => (string)$row['booking_notes'],
            'preparation' => (string)$row['preparation'],
            'appointmentType' => (string)$row['appointment_type'],
            'phoneRequired' => (bool)$row['phone_required'],
            'staffIds' => $this->catalog->serviceStaffIds($organizationId, (int)$row['id']),
            'locationIds' => $this->catalog->serviceLocationIds($organizationId, (int)$row['id']),
            'resourceRequirements' => array_map(static fn (array $requirement): array => [
                'resourceId' => $requirement['resourceId'],
                'quantity' => $requirement['quantity'],
            ], $this->catalog->resourceRequirements($organizationId, (int)$row['id'])),
            'formFields' => $this->catalog->formFields($organizationId, (int)$row['id'], $publicOnly),
        ];
        if ($publicOnly) {
            unset($presented['shortName'], $presented['priceMinMinor'], $presented['priceMaxMinor'], $presented['resourceRequirements']);
        }
        return $presented;
    }

    /** @return array<string, mixed> */
    private function presentStaff(array $row, bool $publicOnly): array {
        $value = [
            'id' => (string)$row['public_id'], 'slug' => (string)$row['slug'],
            'displayName' => (string)$row['display_name'], 'description' => (string)$row['description'],
            'qualifications' => (string)$row['qualifications'], 'timezone' => (string)$row['timezone'],
            'publicBooking' => (bool)$row['public_booking'], 'active' => (bool)$row['active'],
            'locationIds' => $this->catalog->staffLocationIds((string)$row['organization_id'], (int)$row['id']),
        ];
        if (!$publicOnly) {
            $value['userUid'] = (string)($row['user_uid'] ?? '');
            $value['calendarUri'] = (string)$row['calendar_uri'];
        }
        return $value;
    }

    /** @return array<string, mixed> */
    private function presentLocation(array $row): array {
        $values = [
            'id' => (string)$row['public_id'], 'slug' => (string)$row['slug'], 'name' => (string)$row['name'],
            'kind' => (string)$row['kind'], 'address' => (string)$row['address'], 'room' => (string)$row['room'],
            'timezone' => (string)$row['timezone'], 'publicNotes' => (string)$row['public_notes'],
            'directions' => (string)$row['directions'], 'accessibility' => (string)$row['accessibility'],
            'active' => (bool)$row['active'],
        ];
        return $values;
    }

    /** @return array<string, mixed> */
    private function presentResource(string $organizationId, array $row): array {
        $locationPublicId = null;
        if ($row['location_id'] !== null) {
            $locationPublicId = (string)$this->catalog->requireInternal('locations', $organizationId, (int)$row['location_id'])['public_id'];
        }
        return [
            'id' => (string)$row['public_id'], 'name' => (string)$row['name'],
            'type' => (string)$row['resource_type'], 'locationId' => $locationPublicId,
            'capacity' => (int)$row['capacity'], 'active' => (bool)$row['active'],
        ];
    }

    /** @param array<string, mixed> $current
     *  @return array<string, mixed>
     */
    private function serviceValues(array $input, array $current): array {
        $currency = strtoupper((string)$this->inputOrCurrent($input, 'currency', $current, 'currency', 'EUR'));
        if (!preg_match('/^[A-Z]{3}$/D', $currency)) {
            throw new ValidationException($this->l10n->t('The currency code is invalid.'));
        }
        $color = (string)$this->inputOrCurrent($input, 'color', $current, 'color', '#00679e');
        if (!preg_match('/^#[0-9a-fA-F]{6}$/D', $color)) {
            throw new ValidationException($this->l10n->t('The service color is invalid.'));
        }
        $values = [
            'slug' => $this->validator->slug((string)$this->requiredOrCurrent($input, 'slug', $current, 'slug')),
            'name' => $this->limited($this->requiredOrCurrent($input, 'name', $current, 'name'), 255, true),
            'short_name' => $this->limited($this->inputOrCurrent($input, 'shortName', $current, 'short_name', ''), 80),
            'description' => $this->limited($this->inputOrCurrent($input, 'description', $current, 'description', ''), 10000),
            'duration_min' => $this->integerOrCurrent($input, 'durationMinutes', $current, 'duration_min', 30, 5, 1440),
            'buffer_before' => $this->integerOrCurrent($input, 'bufferBeforeMinutes', $current, 'buffer_before', 0, 0, 1440),
            'buffer_after' => $this->integerOrCurrent($input, 'bufferAfterMinutes', $current, 'buffer_after', 0, 0, 1440),
            'price_min' => $this->nullablePriceMinor($input, 'priceMin', $current, 'price_min'),
            'price_max' => $this->nullablePriceMinor($input, 'priceMax', $current, 'price_max'),
            'currency' => $currency,
            'confirmation_mode' => $this->choice($this->inputOrCurrent($input, 'confirmationMode', $current, 'confirmation_mode', 'automatic'), ['automatic', 'manual']),
            'min_notice_min' => $this->integerOrCurrent($input, 'minimumNoticeMinutes', $current, 'min_notice_min', 60, 0, 525600),
            'max_horizon_days' => $this->integerOrCurrent($input, 'maximumHorizonDays', $current, 'max_horizon_days', 90, 1, 730),
            'cancel_notice_min' => $this->integerOrCurrent($input, 'cancellationNoticeMinutes', $current, 'cancel_notice_min', 1440, 0, 525600),
            'resched_notice_min' => $this->integerOrCurrent($input, 'rescheduleNoticeMinutes', $current, 'resched_notice_min', 1440, 0, 525600),
            'visibility' => $this->choice($this->inputOrCurrent($input, 'visibility', $current, 'visibility', 'public'), ['public', 'direct_link', 'internal']),
            'active' => $this->boolOrCurrent($input, 'active', $current, 'active', true),
            'color' => $color,
            'booking_notes' => $this->limited($this->inputOrCurrent($input, 'bookingNotes', $current, 'booking_notes', ''), 10000),
            'preparation' => $this->limited($this->inputOrCurrent($input, 'preparation', $current, 'preparation', ''), 10000),
            'appointment_type' => $this->choice($this->inputOrCurrent($input, 'appointmentType', $current, 'appointment_type', 'on_site'), ['on_site', 'phone', 'video', 'customer_site', 'custom']),
            'phone_required' => $this->boolOrCurrent($input, 'phoneRequired', $current, 'phone_required', false),
        ];
        if ($values['price_min'] !== null && $values['price_max'] !== null && $values['price_min'] > $values['price_max']) {
            throw new ValidationException($this->l10n->t('The minimum price must not exceed the maximum price.'));
        }
        return $values;
    }

    /** @return list<string> */
    private function stringList(mixed $value): array {
        if (!is_array($value) || count(array_filter($value, 'is_string')) !== count($value)) {
            throw new ValidationException($this->l10n->t('A list of identifiers is invalid.'));
        }
        return array_values(array_unique(array_map('strval', $value)));
    }

    /** @return list<array{resourceId: string, quantity: int}> */
    private function resourceRequirements(mixed $value): array {
        if (!is_array($value)) {
            throw new ValidationException($this->l10n->t('Resource requirements are invalid.'));
        }
        $result = [];
        foreach ($value as $item) {
            if (!is_array($item) || !is_string($item['resourceId'] ?? null)) {
                throw new ValidationException($this->l10n->t('A resource requirement is invalid.'));
            }
            $quantity = filter_var($item['quantity'] ?? 1, FILTER_VALIDATE_INT);
            if ($quantity === false || $quantity < 1 || $quantity > 100) {
                throw new ValidationException($this->l10n->t('A resource quantity is invalid.'));
            }
            $result[] = ['resourceId' => $item['resourceId'], 'quantity' => (int)$quantity];
        }
        return $result;
    }

    /** @return list<array<string, mixed>> */
    private function formFields(mixed $value): array {
        if (!is_array($value)) {
            throw new ValidationException($this->l10n->t('Booking form fields are invalid.'));
        }
        $allowed = ['text', 'textarea', 'select', 'multi_select', 'checkbox', 'boolean', 'phone', 'email', 'number', 'date'];
        $result = [];
        foreach ($value as $index => $item) {
            if (!is_array($item)) {
                throw new ValidationException($this->l10n->t('A booking form field is invalid.'));
            }
            $type = (string)($item['type'] ?? '');
            if (!in_array($type, $allowed, true)) {
                throw new ValidationException($this->l10n->t('A booking form field type is invalid.'));
            }
            $label = trim((string)($item['label'] ?? ''));
            if ($label === '' || mb_strlen($label) > 255) {
                throw new ValidationException($this->l10n->t('A booking form field label is invalid.'));
            }
            $validation = $this->formFieldValidation($type, $item['validation'] ?? []);
            $result[] = [
                'id' => isset($item['id']) && is_string($item['id']) && preg_match('/^[a-z0-9]{16,64}$/D', $item['id']) ? $item['id'] : '',
                'type' => $type,
                'label' => $label,
                'helpText' => $this->limited($item['helpText'] ?? '', 1000),
                'required' => $this->validator->boolean($item, 'required', false),
                'order' => (int)($item['order'] ?? $index),
                'visibility' => $this->choice($item['visibility'] ?? 'public', ['public', 'internal']),
                'validation' => $validation,
            ];
        }
        return $result;
    }

    private function requiredOrCurrent(array $input, string $inputKey, array $current, string $column): mixed {
        if (array_key_exists($inputKey, $input)) {
            return $input[$inputKey];
        }
        if (array_key_exists($column, $current)) {
            return $current[$column];
        }
        throw new ValidationException($this->l10n->t('A required field is missing.'));
    }

    private function inputOrCurrent(array $input, string $inputKey, array $current, string $column, mixed $default): mixed {
        return array_key_exists($inputKey, $input) ? $input[$inputKey] : ($current[$column] ?? $default);
    }

    private function boolOrCurrent(array $input, string $inputKey, array $current, string $column, bool $default): bool {
        if (array_key_exists($inputKey, $input)) {
            return $this->validator->boolean($input, $inputKey, $default);
        }
        return array_key_exists($column, $current) ? Database::bool($current[$column]) : $default;
    }

    private function integerOrCurrent(array $input, string $inputKey, array $current, string $column, int $default, int $minimum, int $maximum): int {
        $value = filter_var($this->inputOrCurrent($input, $inputKey, $current, $column, $default), FILTER_VALIDATE_INT);
        if ($value === false || $value < $minimum || $value > $maximum) {
            throw new ValidationException($this->l10n->t('An integer field is outside the allowed range.'));
        }
        return (int)$value;
    }

    private function nullablePriceMinor(array $input, string $inputKey, array $current, string $column): ?int {
        $value = $this->inputOrCurrent($input, $inputKey, $current, $column, null);
        if (!array_key_exists($inputKey, $input) && array_key_exists($column, $current)) {
            return $current[$column] === null ? null : (int)$current[$column];
        }
        if ($value === null || $value === '') {
            return null;
        }
        $normalized = str_replace(',', '.', trim((string)$value));
        if (!preg_match('/^(?:0|[1-9]\d{0,8})(?:\.\d{1,2})?$/D', $normalized)) {
            throw new ValidationException($this->l10n->t('A price is invalid.'));
        }
        [$whole, $fraction] = array_pad(explode('.', $normalized, 2), 2, '');
        return ((int)$whole * 100) + (int)str_pad($fraction, 2, '0');
    }

    /** @return array<string,mixed> */
    private function formFieldValidation(string $type, mixed $value): array {
        if (!is_array($value) || count($value) > 4) {
            throw new ValidationException($this->l10n->t('Booking form validation is invalid.'));
        }
        $allowed = ['min', 'max', 'pattern', 'options'];
        if (array_diff(array_keys($value), $allowed) !== []) {
            throw new ValidationException($this->l10n->t('Booking form validation contains an unsupported rule.'));
        }
        $safe = [];
        foreach (['min', 'max'] as $key) {
            if (isset($value[$key])) {
                if (!is_int($value[$key]) && !is_float($value[$key]) && !is_numeric($value[$key])) {
                    throw new ValidationException($this->l10n->t('A booking form range is invalid.'));
                }
                $number = (float)$value[$key];
                if (!is_finite($number) || abs($number) > 1_000_000_000_000) {
                    throw new ValidationException($this->l10n->t('A booking form range is invalid.'));
                }
                $safe[$key] = $number;
            }
        }
        if (isset($safe['min'], $safe['max']) && $safe['min'] > $safe['max']) {
            throw new ValidationException($this->l10n->t('A booking form range is invalid.'));
        }
        if (isset($value['pattern'])) {
            if (!is_string($value['pattern']) || mb_strlen($value['pattern']) > 128 || str_contains($value['pattern'], "\0")) {
                throw new ValidationException($this->l10n->t('A booking form pattern is invalid.'));
            }
            $safe['pattern'] = $value['pattern'];
        }
        if (isset($value['options'])) {
            if (!in_array($type, ['select', 'multi_select'], true) || !is_array($value['options']) || count($value['options']) > 50) {
                throw new ValidationException($this->l10n->t('Booking form options are invalid.'));
            }
            $options = [];
            foreach ($value['options'] as $option) {
                if (!is_string($option) || trim($option) === '' || mb_strlen($option) > 100) {
                    throw new ValidationException($this->l10n->t('A booking form option is invalid.'));
                }
                $options[] = trim($option);
            }
            $safe['options'] = array_values(array_unique($options));
        }
        return $safe;
    }

    private function limited(mixed $value, int $maximum, bool $required = false): string {
        $value = trim((string)$value);
        if (($required && $value === '') || mb_strlen($value) > $maximum) {
            throw new ValidationException($this->l10n->t('A text field is invalid.'));
        }
        return $value;
    }

    /** @param list<string> $allowed */
    private function choice(mixed $value, array $allowed): string {
        $value = (string)$value;
        if (!in_array($value, $allowed, true)) {
            throw new ValidationException($this->l10n->t('A field contains an unsupported value.'));
        }
        return $value;
    }
}
