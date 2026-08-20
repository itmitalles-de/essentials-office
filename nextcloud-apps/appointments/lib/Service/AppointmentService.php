<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\Exception\ForbiddenException;
use OCA\Appointments\Exception\ApiException;
use OCA\Appointments\Exception\ConflictException;
use OCA\Appointments\Exception\NotFoundException;
use OCA\Appointments\Exception\ValidationException;
use OCA\Appointments\Provider\MeetingProvider;
use OCP\IL10N;
use OCP\IURLGenerator;
use OCP\IUserManager;

final class AppointmentService {
    public function __construct(
        private AppointmentRepository $appointments,
        private OrganizationRepository $organizations,
        private CatalogRepository $catalog,
        private AvailabilityService $availability,
        private AuthorizationService $authorization,
        private InputValidator $validator,
        private FormAnswerValidator $answerValidator,
        private AppointmentPolicy $policy,
        private Identifiers $identifiers,
        private TokenService $tokens,
        private OutboxService $outbox,
        private ReminderService $reminders,
        private AuditService $audit,
        private Database $database,
        private IcsService $ics,
        private MeetingProvider $meetingProvider,
        private IURLGenerator $urlGenerator,
        private IUserManager $userManager,
        private IL10N $l10n,
    ) {
    }

    /** @return list<array<string,mixed>> */
    public function listInternal(string $organizationId, array $filters): array {
        $this->authorization->assert($organizationId, AuthorizationService::VIEW);
        $organization = $this->organizations->requireById($organizationId);
        foreach (['from', 'to'] as $rangeKey) {
            if (isset($filters[$rangeKey]) && is_string($filters[$rangeKey]) && preg_match('/^\d{4}-\d{2}-\d{2}$/D', $filters[$rangeKey])) {
                $range = $this->validator->localDayRange($filters[$rangeKey], (string)$organization['timezone']);
                $filters[$rangeKey] = $range[$rangeKey === 'to' ? 'to' : 'from'];
            }
        }
        if (isset($filters['query']) && !isset($filters['search'])) {
            $filters['search'] = $filters['query'];
        }
        foreach (['staffId' => ['staff', 'staffInternalId'], 'serviceId' => ['services', 'serviceInternalId'], 'locationId' => ['locations', 'locationInternalId'], 'resourceId' => ['resources', 'resourceInternalId']] as $key => [$entity, $target]) {
            if (isset($filters[$key]) && (string)$filters[$key] !== '') {
                $filters[$target] = (int)$this->catalog->require($entity, $organizationId, (string)$filters[$key])['id'];
            }
        }
        $ownStaffId = $this->authorization->canViewAll($organizationId) ? null : $this->authorization->staffIdForCurrentUser($organizationId);
        if ($ownStaffId === null && !$this->authorization->canViewAll($organizationId)) {
            throw new ForbiddenException($this->l10n->t('You are not allowed to view appointments.'));
        }
        return array_map(fn (array $row): array => $this->present($row, true), $this->appointments->list($organizationId, $filters, $ownStaffId));
    }

    /** @return array<string,mixed> */
    public function getInternal(string $organizationId, string $appointmentPublicId): array {
        $this->authorization->assert($organizationId, AuthorizationService::VIEW);
        $appointment = $this->appointments->requireByPublicId($organizationId, $appointmentPublicId);
        if (!$this->authorization->canViewAll($organizationId)) {
            $this->authorization->assertOwnStaff($organizationId, (int)$appointment['staff_id']);
        }
        return $this->present($appointment, true);
    }

    /** @return array<string,mixed> */
    public function createInternal(string $organizationId, array $input): array {
        $this->authorization->assert($organizationId, AuthorizationService::MANAGE_APPOINTMENTS);
        try {
            return $this->create($this->organizations->requireById($organizationId), $input, false);
        } catch (ApiException $exception) {
            $this->recordBookingFailure($organizationId, $exception);
            throw $exception;
        }
    }

    /** @return array<string,mixed> */
    public function bookPublic(string $organizationSlug, array $input): array {
        $organization = $this->organizations->requirePublicBySlug($organizationSlug);
        $antiSpam = is_array($input['antiSpam'] ?? null) ? $input['antiSpam'] : [];
        if (trim((string)($antiSpam['website'] ?? '')) !== '') {
            throw new ValidationException($this->l10n->t('The booking request could not be accepted.'));
        }
        $startedAt = filter_var($antiSpam['bookingStartedAt'] ?? null, FILTER_VALIDATE_INT);
        $now = time();
        if ($startedAt === false || $startedAt <= 0 || $startedAt > $now || $now - $startedAt < (int)$organization['min_form_seconds'] || $now - $startedAt > 86400) {
            throw new ValidationException($this->l10n->t('The booking form was submitted too quickly or has expired.'));
        }
        if (!$this->validator->boolean($input, 'privacyAccepted')) {
            throw new ValidationException($this->l10n->t('Privacy consent is required.'));
        }
        try {
            return $this->create($organization, $input, true);
        } catch (ApiException $exception) {
            $this->recordBookingFailure((string)$organization['organization_id'], $exception);
            throw $exception;
        }
    }

    /** @return array<string,mixed> */
    public function updateInternal(string $organizationId, string $appointmentPublicId, array $input): array {
        $permissions = $this->authorization->permissions($organizationId);
        if (!in_array(AuthorizationService::MANAGE_APPOINTMENTS, $permissions, true)) {
            if (!in_array(AuthorizationService::UPDATE_OWN, $permissions, true)) {
                throw new ForbiddenException($this->l10n->t('You are not allowed to update appointments.'));
            }
            $current = $this->appointments->requireByPublicId($organizationId, $appointmentPublicId);
            $this->authorization->assertOwnStaff($organizationId, (int)$current['staff_id']);
            $allowed = ['internalNote'];
            if (array_diff(array_keys($input), $allowed) !== []) {
                throw new ForbiddenException($this->l10n->t('You may only update your own internal appointment note.'));
            }
            return $this->updateInternalNote($organizationId, $appointmentPublicId, $input);
        }

        $result = $this->database->transaction(function () use ($organizationId, $appointmentPublicId, $input): array {
            $organization = $this->organizations->lock($organizationId);
            $current = $this->appointments->lock($organizationId, $appointmentPublicId);
            if (!in_array((string)$current['status'], AppointmentPolicy::ACTIVE, true)) {
                throw new ValidationException($this->l10n->t('A closed appointment cannot be edited.'));
            }
            $currentService = $this->catalog->requireInternal('services', $organizationId, (int)$current['service_id']);
            $currentStaff = $this->catalog->requireInternal('staff', $organizationId, (int)$current['staff_id']);
            $currentLocation = $current['location_id'] === null ? null : $this->catalog->requireInternal('locations', $organizationId, (int)$current['location_id']);
            $service = isset($input['serviceId']) && (string)$input['serviceId'] !== ''
                ? $this->catalog->require('services', $organizationId, (string)$input['serviceId'])
                : $currentService;
            $startsAt = $this->startsAt($input, (string)$organization['timezone'], (int)$current['starts_at']);
            $staffPublicId = isset($input['staffId']) && (string)$input['staffId'] !== '' ? (string)$input['staffId'] : (string)$currentStaff['public_id'];
            $locationPublicId = array_key_exists('locationId', $input)
                ? (($input['locationId'] === null || (string)$input['locationId'] === '') ? null : (string)$input['locationId'])
                : ($currentLocation === null ? null : (string)$currentLocation['public_id']);
            $schedulingChanged = (int)$service['id'] !== (int)$current['service_id']
                || !hash_equals((string)$currentStaff['public_id'], $staffPublicId)
                || ($currentLocation === null ? null : (string)$currentLocation['public_id']) !== $locationPublicId
                || $startsAt !== (int)$current['starts_at'];
            if ($schedulingChanged) {
                $slot = $this->availability->requireBookableSlot($organization, [
                    'serviceId' => (string)$service['public_id'], 'start' => $startsAt,
                    'staffId' => $staffPublicId, 'locationId' => $locationPublicId,
                ], false, (int)$current['id']);
                [$staff, $location, $resources] = $this->resolveSlotEntities($organizationId, $service, $slot);
            } else {
                $slot = ['start' => (int)$current['starts_at'], 'end' => (int)$current['ends_at']];
                $staff = $currentStaff;
                $location = $currentLocation;
                $resources = [];
            }
            $contact = $this->contact($input['contact'] ?? [
                'firstName' => $current['first_name'], 'lastName' => $current['last_name'],
                'email' => $current['email'], 'phone' => $current['phone'],
            ], (bool)$service['phone_required']);
            $answers = null;
            $serviceChanged = (int)$service['id'] !== (int)$current['service_id'];
            if (array_key_exists('formAnswers', $input) || $serviceChanged) {
                $answers = $this->answerValidator->validate(
                    $organizationId,
                    (int)$service['id'],
                    $input['formAnswers'] ?? [],
                    false,
                );
            }
            $status = (string)$current['status'];
            if (isset($input['status']) && (string)$input['status'] !== $status) {
                // Status changes use setInternalStatus(), which owns reminder and mail side effects.
                throw new ValidationException($this->l10n->t('The appointment status transition is not allowed.'));
            }
            $now = time();
            $busyStart = $slot['start'] - ((int)$service['buffer_before'] * 60);
            $busyEnd = $slot['end'] + ((int)$service['buffer_after'] * 60);
            $this->appointments->update($organizationId, (int)$current['id'], [
                'service_id' => (int)$service['id'], 'staff_id' => (int)$staff['id'],
                'location_id' => $location === null ? null : (int)$location['id'],
                'starts_at' => $slot['start'], 'ends_at' => $slot['end'],
                'busy_starts_at' => $busyStart, 'busy_ends_at' => $busyEnd,
                'timezone' => (string)$organization['timezone'],
                'status' => $status, 'first_name' => $contact['firstName'], 'last_name' => $contact['lastName'],
                'email' => $contact['email'], 'phone' => $contact['phone'],
                'customer_message' => $this->limited($input['customerNote'] ?? $current['customer_message'], 5000),
                'internal_note' => $this->limited($input['internalNote'] ?? $current['internal_note'], 10000),
                'updated_at' => $now, 'cancelled_at' => str_starts_with($status, 'cancelled_') ? $now : null,
                'revision' => (int)$current['revision'] + 1,
            ]);
            if ($schedulingChanged) {
                $this->appointments->replaceResources($organizationId, (int)$current['id'], $busyStart, $busyEnd, $resources);
            }
            if ($answers !== null) {
                $this->appointments->replaceAnswers($organizationId, (int)$current['id'], $answers);
            }
            if ($status !== (string)$current['status']) {
                $this->appointments->addStatusHistory($organizationId, (int)$current['id'], (string)$current['status'], $status, 'user', 'staff');
            }
            $this->audit->record($organizationId, 'appointment.updated', 'user', 'appointment', $appointmentPublicId, 'success', ['status' => $status, 'revision' => (int)$current['revision'] + 1]);
            $updated = $this->appointments->requireByPublicId($organizationId, $appointmentPublicId);
            if ($schedulingChanged) {
                $this->reminders->replaceForAppointment($updated);
            }
            return [
                'appointment' => $updated,
                'outboxIds' => $schedulingChanged ? [$this->enqueueNotification($organization, $updated, $service, $location, 'rescheduled')] : [],
            ];
        });
        $this->scheduleOutbox($result['outboxIds']);
        return $this->present($result['appointment'], true);
    }

    /** @return array<string,mixed> */
    public function setInternalStatus(string $organizationId, string $appointmentPublicId, string $status): array {
        $permissions = $this->authorization->permissions($organizationId);
        $manager = in_array(AuthorizationService::MANAGE_APPOINTMENTS, $permissions, true);
        if (!$manager && !in_array(AuthorizationService::UPDATE_OWN, $permissions, true)) {
            throw new ForbiddenException($this->l10n->t('You are not allowed to update appointment status.'));
        }
        $result = $this->database->transaction(function () use ($organizationId, $appointmentPublicId, $status, $manager): array {
            $organization = $this->organizations->lock($organizationId);
            $appointment = $this->appointments->lock($organizationId, $appointmentPublicId);
            if (!$manager) {
                $this->authorization->assertOwnStaff($organizationId, (int)$appointment['staff_id']);
                if (!in_array($status, ['confirmed', 'completed', 'no_show', 'cancelled_by_staff'], true)) {
                    throw new ForbiddenException($this->l10n->t('This status is not available for your appointment.'));
                }
            }
            if (!$this->policy->canTransition((string)$appointment['status'], $status)) {
                throw new ValidationException($this->l10n->t('The appointment status transition is not allowed.'));
            }
            if ($status === (string)$appointment['status']) {
                return ['appointment' => $appointment, 'outboxIds' => []];
            }
            $now = time();
            $this->appointments->update($organizationId, (int)$appointment['id'], [
                'status' => $status, 'updated_at' => $now,
                'cancelled_at' => str_starts_with($status, 'cancelled_') ? $now : null,
                'revision' => (int)$appointment['revision'] + 1,
            ]);
            $this->appointments->addStatusHistory($organizationId, (int)$appointment['id'], (string)$appointment['status'], $status, 'user', 'staff');
            $this->audit->record($organizationId, 'appointment.status_changed', 'user', 'appointment', $appointmentPublicId, 'success', ['previous_status' => (string)$appointment['status'], 'status' => $status]);
            $updated = $this->appointments->requireByPublicId($organizationId, $appointmentPublicId);
            if (!in_array($status, AppointmentPolicy::ACTIVE, true)) {
                $this->reminders->replaceForAppointment($updated);
            }
            $service = $this->catalog->requireInternal('services', $organizationId, (int)$updated['service_id']);
            $location = $updated['location_id'] === null ? null : $this->catalog->requireInternal('locations', $organizationId, (int)$updated['location_id']);
            $notify = in_array($status, ['confirmed', 'cancelled_by_staff'], true);
            return ['appointment' => $updated, 'outboxIds' => $notify ? [$this->enqueueNotification($organization, $updated, $service, $location, $status)] : []];
        });
        $this->scheduleOutbox($result['outboxIds']);
        return $this->present($result['appointment'], true);
    }

    /** @return array<string,mixed> */
    public function manageView(string $token): array {
        return $this->managePayload($this->tokens->resolve($token));
    }

    /** @return array<string,mixed> */
    public function manageSlots(string $token, array $input): array {
        $appointment = $this->tokens->resolve($token);
        $organizationId = (string)$appointment['organization_id'];
        $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
        if (!in_array((string)$appointment['status'], AppointmentPolicy::ACTIVE, true)
            || !$this->policy->rescheduleAllowed((int)$appointment['starts_at'], time(), (int)$service['resched_notice_min'])) {
            throw new ValidationException($this->l10n->t('The appointment can no longer be rescheduled.'));
        }
        $staff = $this->catalog->requireInternal('staff', $organizationId, (int)$appointment['staff_id']);
        $location = $appointment['location_id'] === null
            ? null
            : $this->catalog->requireInternal('locations', $organizationId, (int)$appointment['location_id']);
        $input['staffId'] = (string)$staff['public_id'];
        if ($location === null) {
            unset($input['locationId']);
        } else {
            $input['locationId'] = (string)$location['public_id'];
        }
        $result = $this->availability->managementSlots($appointment, $input);
        $result['slots'] = array_values(array_filter(
            $result['slots'],
            static fn (array $slot): bool => (string)$slot['staffId'] === (string)$staff['public_id']
                && ($slot['locationId'] ?? null) === ($location === null ? null : (string)$location['public_id']),
        ));
        return $result;
    }

    /** @return array<string,mixed> */
    public function cancelByCustomer(string $token): array {
        $resolved = $this->tokens->resolve($token);
        $result = $this->database->transaction(function () use ($resolved, $token): array {
            $organizationId = (string)$resolved['organization_id'];
            $organization = $this->organizations->lock($organizationId);
            $validated = $this->resolveTokenAfterOrganizationLock($token, $organizationId);
            $appointment = $this->appointments->lock($organizationId, (string)$validated['public_id']);
            $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
            if (!$this->policy->cancellationAllowed((int)$appointment['starts_at'], time(), (int)$service['cancel_notice_min'])) {
                throw new ValidationException($this->l10n->t('The cancellation deadline has passed.'));
            }
            if (!$this->policy->canTransition((string)$appointment['status'], 'cancelled_by_customer', true)) {
                throw new ValidationException($this->l10n->t('The appointment cannot be cancelled.'));
            }
            $now = time();
            $this->appointments->update($organizationId, (int)$appointment['id'], [
                'status' => 'cancelled_by_customer', 'cancelled_at' => $now, 'updated_at' => $now,
                'revision' => (int)$appointment['revision'] + 1,
            ]);
            $this->appointments->addStatusHistory($organizationId, (int)$appointment['id'], (string)$appointment['status'], 'cancelled_by_customer', 'customer', 'token');
            $this->audit->record($organizationId, 'appointment.cancelled', 'customer', 'appointment', (string)$appointment['public_id'], 'success', ['status' => 'cancelled_by_customer']);
            $updated = $this->appointments->requireByPublicId($organizationId, (string)$appointment['public_id']);
            $this->reminders->replaceForAppointment($updated);
            $location = $updated['location_id'] === null ? null : $this->catalog->requireInternal('locations', $organizationId, (int)$updated['location_id']);
            $outboxIds = [$this->enqueueNotification($organization, $updated, $service, $location, 'cancelled_by_customer')];
            $staff = $this->catalog->requireInternal('staff', $organizationId, (int)$updated['staff_id']);
            $staffOutbox = $this->enqueueStaffNotification($organization, $updated, $service, $staff, 'cancelled_by_customer');
            if ($staffOutbox !== null) {
                $outboxIds[] = $staffOutbox;
            }
            return ['appointment' => $updated, 'outboxIds' => $outboxIds];
        });
        $this->scheduleOutbox($result['outboxIds']);
        return $this->managePayload($result['appointment']);
    }

    /** @return array<string,mixed> */
    public function rescheduleByCustomer(string $token, array $input): array {
        $resolved = $this->tokens->resolve($token);
        $result = $this->database->transaction(function () use ($resolved, $input, $token): array {
            $organizationId = (string)$resolved['organization_id'];
            $organization = $this->organizations->lock($organizationId);
            $validated = $this->resolveTokenAfterOrganizationLock($token, $organizationId);
            $appointment = $this->appointments->lock($organizationId, (string)$validated['public_id']);
            $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
            if (!$this->policy->rescheduleAllowed((int)$appointment['starts_at'], time(), (int)$service['resched_notice_min'])) {
                throw new ValidationException($this->l10n->t('The rescheduling deadline has passed.'));
            }
            if (!$this->policy->canTransition((string)$appointment['status'], 'rescheduled', true)) {
                throw new ValidationException($this->l10n->t('The appointment cannot be rescheduled.'));
            }
            $startsAt = $this->validator->timestamp(['startsAt' => $input['startsAt'] ?? null], 'startsAt');
            $staff = $this->catalog->requireInternal('staff', $organizationId, (int)$appointment['staff_id']);
            $location = $appointment['location_id'] === null
                ? null
                : $this->catalog->requireInternal('locations', $organizationId, (int)$appointment['location_id']);
            $slot = $this->availability->requireBookableSlot($organization, [
                'serviceId' => (string)$service['public_id'], 'start' => $startsAt,
                'staffId' => (string)$staff['public_id'],
                'locationId' => $location === null ? null : (string)$location['public_id'],
            ], false, (int)$appointment['id'], true);
            [$staff, $location, $resources] = $this->resolveSlotEntities($organizationId, $service, $slot);
            $busyStart = $slot['start'] - ((int)$service['buffer_before'] * 60);
            $busyEnd = $slot['end'] + ((int)$service['buffer_after'] * 60);
            $this->appointments->update($organizationId, (int)$appointment['id'], [
                'staff_id' => (int)$staff['id'], 'location_id' => $location === null ? null : (int)$location['id'],
                'starts_at' => $slot['start'], 'ends_at' => $slot['end'], 'busy_starts_at' => $busyStart,
                'busy_ends_at' => $busyEnd, 'status' => 'rescheduled', 'updated_at' => time(),
                'timezone' => (string)$organization['timezone'], 'cancelled_at' => null,
                'revision' => (int)$appointment['revision'] + 1,
            ]);
            $this->appointments->replaceResources($organizationId, (int)$appointment['id'], $busyStart, $busyEnd, $resources);
            $this->appointments->addStatusHistory($organizationId, (int)$appointment['id'], (string)$appointment['status'], 'rescheduled', 'customer', 'token');
            $this->audit->record($organizationId, 'appointment.rescheduled', 'customer', 'appointment', (string)$appointment['public_id'], 'success', ['previous_status' => (string)$appointment['status'], 'status' => 'rescheduled']);
            $updated = $this->appointments->requireByPublicId($organizationId, (string)$appointment['public_id']);
            $this->reminders->replaceForAppointment($updated);
            $outboxIds = [$this->enqueueNotification($organization, $updated, $service, $location, 'rescheduled')];
            $staffOutbox = $this->enqueueStaffNotification($organization, $updated, $service, $staff, 'rescheduled');
            if ($staffOutbox !== null) {
                $outboxIds[] = $staffOutbox;
            }
            return ['appointment' => $updated, 'outboxIds' => $outboxIds];
        });
        $this->scheduleOutbox($result['outboxIds']);
        return $this->managePayload($result['appointment']);
    }

    /** @return array<string,mixed> */
    public function updateContactByCustomer(string $token, array $input): array {
        $resolved = $this->tokens->resolve($token);
        return $this->database->transaction(function () use ($resolved, $input, $token): array {
            $organizationId = (string)$resolved['organization_id'];
            $this->organizations->lock($organizationId);
            $validated = $this->resolveTokenAfterOrganizationLock($token, $organizationId);
            $appointment = $this->appointments->lock($organizationId, (string)$validated['public_id']);
            if (!in_array((string)$appointment['status'], AppointmentPolicy::ACTIVE, true)) {
                throw new ValidationException($this->l10n->t('Contact details for a closed appointment cannot be changed.'));
            }
            $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
            $contact = $this->contact($input['contact'] ?? [], (bool)$service['phone_required']);
            $this->appointments->update($organizationId, (int)$appointment['id'], [
                'first_name' => $contact['firstName'], 'last_name' => $contact['lastName'],
                'email' => $contact['email'], 'phone' => $contact['phone'], 'updated_at' => time(),
                'revision' => (int)$appointment['revision'] + 1,
            ]);
            $this->audit->record($organizationId, 'appointment.contact_updated', 'customer', 'appointment', (string)$appointment['public_id']);
            return $this->managePayload($this->appointments->requireByPublicId($organizationId, (string)$appointment['public_id']));
        });
    }

    /** @return array<string,mixed> */
    public function exportByCustomer(string $token): array {
        $appointment = $this->tokens->resolve($token);
        $public = $this->present($appointment, false);
        return [
            'appointment' => $public,
            'formAnswers' => $this->appointments->exportAnswers((string)$appointment['organization_id'], (int)$appointment['id'], true),
            'statusHistory' => $this->appointments->exportStatusHistory((string)$appointment['organization_id'], (int)$appointment['id']),
        ];
    }

    public function icsByCustomer(string $token): string {
        $appointment = $this->tokens->resolve($token);
        $organizationId = (string)$appointment['organization_id'];
        $organization = $this->organizations->requireById($organizationId);
        $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
        $location = $appointment['location_id'] === null ? null : $this->catalog->requireInternal('locations', $organizationId, (int)$appointment['location_id']);
        return $this->ics->render($appointment, $service, $location, (string)$organization['name']);
    }

    /** @return array<string,mixed> */
    private function create(array $organization, array $input, bool $public): array {
        $organizationId = (string)$organization['organization_id'];
        $result = $this->database->transaction(function () use ($organizationId, $input, $public): array {
            $organization = $this->organizations->lock($organizationId);
            if ($public && (!$organization['active'] || !$organization['public_enabled'])) {
                throw new NotFoundException($this->l10n->t('The booking page was not found.'));
            }
            $service = $this->catalog->require('services', $organizationId, $this->validator->string($input, 'serviceId', 64));
            $startsAt = $this->startsAt($input, (string)$organization['timezone']);
            $slot = $this->availability->requireBookableSlot($organization, [
                'serviceId' => (string)$service['public_id'], 'serviceSlug' => $input['serviceSlug'] ?? null,
                'start' => $startsAt, 'staffId' => $input['staffId'] ?? null, 'locationId' => $input['locationId'] ?? null,
            ], $public);
            [$staff, $location, $resources] = $this->resolveSlotEntities($organizationId, $service, $slot);
            $contact = $this->contact($input['contact'] ?? [], (bool)$service['phone_required']);
            $answers = $this->answerValidator->validate($organizationId, (int)$service['id'], $input['formAnswers'] ?? [], $public);
            $status = $public
                ? ((string)$service['confirmation_mode'] === 'automatic' ? 'confirmed' : 'pending')
                : $this->validator->enum($input, 'status', ['pending', 'confirmed'], 'confirmed');
            $now = time();
            $publicId = $this->identifiers->publicId();
            $meetingReference = '';
            if ((string)$service['appointment_type'] === 'video') {
                $meetingReference = $this->meetingProvider->create($organizationId, $publicId, $slot['start'], $slot['end']) ?? '';
            }
            $appointment = $this->appointments->create([
                'organization_id' => $organizationId, 'public_id' => $publicId,
                'booking_number' => $this->identifiers->bookingNumber(), 'service_id' => (int)$service['id'],
                'staff_id' => (int)$staff['id'], 'location_id' => $location === null ? null : (int)$location['id'],
                'starts_at' => $slot['start'], 'ends_at' => $slot['end'],
                'busy_starts_at' => $slot['start'] - ((int)$service['buffer_before'] * 60),
                'busy_ends_at' => $slot['end'] + ((int)$service['buffer_after'] * 60),
                'timezone' => (string)$organization['timezone'],
                'status' => $status, 'first_name' => $contact['firstName'], 'last_name' => $contact['lastName'],
                'email' => $contact['email'], 'phone' => $contact['phone'],
                'customer_message' => $this->limited($input[$public ? 'message' : 'customerNote'] ?? '', 5000),
                'internal_note' => $public ? '' : $this->limited($input['internalNote'] ?? '', 10000),
                'privacy_accepted_at' => $public ? $now : null, 'created_by_uid' => $public ? '' : $this->authorization->currentUserId(),
                'meeting_ref' => $meetingReference, 'created_at' => $now, 'updated_at' => $now, 'revision' => 1,
            ]);
            $this->appointments->replaceResources($organizationId, (int)$appointment['id'], (int)$appointment['busy_starts_at'], (int)$appointment['busy_ends_at'], $resources);
            $this->appointments->replaceAnswers($organizationId, (int)$appointment['id'], $answers);
            $this->reminders->replaceForAppointment($appointment);
            $this->appointments->addStatusHistory($organizationId, (int)$appointment['id'], '', $status, $public ? 'customer' : 'user', $public ? 'token' : 'staff');
            $rawToken = $this->tokens->create($organizationId, (int)$appointment['id'], max($now + 2592000, (int)$appointment['starts_at'] + 7776000));
            $this->audit->record($organizationId, 'appointment.created', $public ? 'customer' : 'user', 'appointment', $publicId, 'success', ['status' => $status, 'source' => $public ? 'public' : 'internal']);
            $eventType = $status === 'pending' ? 'booking_pending' : 'booking_confirmed';
            $outboxIds = [$this->enqueueNotification($organization, $appointment, $service, $location, $eventType, $rawToken)];
            if ($public) {
                $staffOutbox = $this->enqueueStaffNotification($organization, $appointment, $service, $staff, $eventType);
                if ($staffOutbox !== null) {
                    $outboxIds[] = $staffOutbox;
                }
            }
            return ['appointment' => $appointment, 'managementToken' => $rawToken, 'outboxIds' => $outboxIds];
        });
        $this->scheduleOutbox($result['outboxIds']);
        return [
            'appointment' => $this->present($result['appointment'], !$public),
            'managementToken' => $result['managementToken'],
            'message' => (string)$organization['confirmation_text'],
        ];
    }

    /** @return array<string,mixed> */
    private function updateInternalNote(string $organizationId, string $appointmentPublicId, array $input): array {
        return $this->database->transaction(function () use ($organizationId, $appointmentPublicId, $input): array {
            $this->organizations->lock($organizationId);
            $appointment = $this->appointments->lock($organizationId, $appointmentPublicId);
            $this->authorization->assertOwnStaff($organizationId, (int)$appointment['staff_id']);
            $this->appointments->update($organizationId, (int)$appointment['id'], [
                'internal_note' => $this->limited($input['internalNote'] ?? '', 10000),
                'updated_at' => time(), 'revision' => (int)$appointment['revision'] + 1,
            ]);
            $this->audit->record($organizationId, 'appointment.internal_note_updated', 'user', 'appointment', $appointmentPublicId);
            return $this->present($this->appointments->requireByPublicId($organizationId, $appointmentPublicId), true);
        });
    }

    /** @return array{0:array<string,mixed>,1:?array<string,mixed>,2:list<array{resourceInternalId:int,quantity:int}>} */
    private function resolveSlotEntities(string $organizationId, array $service, array $slot): array {
        $staff = $this->catalog->require('staff', $organizationId, (string)$slot['staffId']);
        $location = $slot['locationId'] === null ? null : $this->catalog->require('locations', $organizationId, (string)$slot['locationId']);
        $resourceIds = array_fill_keys($slot['resourceIds'], true);
        $resources = [];
        foreach ($this->catalog->resourceRequirements($organizationId, (int)$service['id']) as $requirement) {
            if (!isset($resourceIds[$requirement['resourceId']])) {
                throw new ValidationException($this->l10n->t('A required resource is unavailable.'));
            }
            $resources[] = ['resourceInternalId' => $requirement['resourceInternalId'], 'quantity' => $requirement['quantity']];
        }
        return [$staff, $location, $resources];
    }

    /** @return array{firstName:string,lastName:string,email:string,phone:string} */
    private function contact(mixed $value, bool $phoneRequired): array {
        if (!is_array($value)) {
            throw new ValidationException($this->l10n->t('Contact details are invalid.'));
        }
        $firstName = $this->limited($value['firstName'] ?? '', 255, true);
        $lastName = $this->limited($value['lastName'] ?? '', 255, true);
        $email = $this->validator->email((string)($value['email'] ?? ''));
        $phone = $this->limited($value['phone'] ?? '', 64, $phoneRequired);
        if ($phone !== '' && !preg_match('/^[0-9+() .\/-]{3,64}$/D', $phone)) {
            throw new ValidationException($this->l10n->t('The phone number is invalid.'));
        }
        return ['firstName' => $firstName, 'lastName' => $lastName, 'email' => $email, 'phone' => $phone];
    }

    private function startsAt(array $input, string $timezone, ?int $default = null): int {
        if (isset($input['startsAtLocal']) && (string)$input['startsAtLocal'] !== '') {
            return $this->validator->localDateTime((string)$input['startsAtLocal'], $timezone);
        }
        if (isset($input['startsAt'])) {
            return $this->validator->timestamp($input, 'startsAt');
        }
        if (isset($input['start'])) {
            return $this->validator->timestamp($input, 'start');
        }
        if ($default !== null) {
            return $default;
        }
        throw new ValidationException($this->l10n->t('The appointment start is required.'));
    }

    /** @return array<string,mixed> */
    private function present(array $appointment, bool $internal): array {
        $organizationId = (string)$appointment['organization_id'];
        $organization = $this->organizations->requireById($organizationId);
        $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
        $staff = $this->catalog->requireInternal('staff', $organizationId, (int)$appointment['staff_id']);
        $location = $appointment['location_id'] === null ? null : $this->catalog->requireInternal('locations', $organizationId, (int)$appointment['location_id']);
        $result = [
            'id' => (string)$appointment['public_id'], 'bookingNumber' => (string)$appointment['booking_number'],
            'serviceId' => (string)$service['public_id'], 'serviceName' => (string)$service['name'],
            'staffId' => (string)$staff['public_id'], 'staffName' => (string)$staff['display_name'],
            'locationId' => $location === null ? null : (string)$location['public_id'],
            'locationName' => $location === null ? '' : (string)$location['name'],
            'startsAt' => (new \DateTimeImmutable('@' . $appointment['starts_at']))->format(DATE_ATOM),
            'endsAt' => (new \DateTimeImmutable('@' . $appointment['ends_at']))->format(DATE_ATOM),
            'startTimestamp' => (int)$appointment['starts_at'], 'endTimestamp' => (int)$appointment['ends_at'],
            'timezone' => (string)$appointment['timezone'], 'status' => (string)$appointment['status'],
            'contact' => ['firstName' => (string)$appointment['first_name'], 'lastName' => (string)$appointment['last_name'], 'email' => (string)$appointment['email'], 'phone' => (string)$appointment['phone']],
            'customerNote' => (string)$appointment['customer_message'],
            'cancellationAllowed' => $this->policy->cancellationAllowed((int)$appointment['starts_at'], time(), (int)$service['cancel_notice_min']) && in_array((string)$appointment['status'], AppointmentPolicy::ACTIVE, true),
            'rescheduleAllowed' => $this->policy->rescheduleAllowed((int)$appointment['starts_at'], time(), (int)$service['resched_notice_min']) && in_array((string)$appointment['status'], AppointmentPolicy::ACTIVE, true),
            'cancellationPolicy' => $this->policyText($service),
        ];
        if ($internal) {
            $conflicts = $this->appointments->conflictTypes($organizationId, $appointment);
            if (!(bool)$service['active'] || !(bool)$staff['active'] || ($location !== null && !(bool)$location['active'])) {
                $conflicts[] = 'configuration';
                $conflicts = array_values(array_unique($conflicts));
            }
            $result['internalNote'] = (string)$appointment['internal_note'];
            $result['revision'] = (int)$appointment['revision'];
            $result['resourceIds'] = $this->appointments->resourcePublicIds($organizationId, (int)$appointment['id']);
            $result['formAnswers'] = $this->appointments->exportAnswers($organizationId, (int)$appointment['id']);
            $result['hasConflict'] = $conflicts !== [];
            $result['conflicts'] = $conflicts;
        }
        return $result;
    }

    /** @return array<string,mixed> */
    private function managePayload(array $appointment): array {
        $organizationId = (string)$appointment['organization_id'];
        $organization = $this->organizations->requireById($organizationId);
        $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
        $staff = $this->catalog->requireInternal('staff', $organizationId, (int)$appointment['staff_id']);
        $location = $appointment['location_id'] === null ? null : $this->catalog->requireInternal('locations', $organizationId, (int)$appointment['location_id']);
        $presented = $this->present($appointment, false);
        $presented['service'] = ['id' => (string)$service['public_id'], 'name' => (string)$service['name']];
        $presented['staff'] = ['id' => (string)$staff['public_id'], 'displayName' => (string)$staff['display_name']];
        $presented['location'] = $location === null ? null : ['id' => (string)$location['public_id'], 'name' => (string)$location['name']];
        $presented['publicInstructions'] = (string)$service['booking_notes'];
        $active = in_array((string)$appointment['status'], AppointmentPolicy::ACTIVE, true);
        $canCancel = $active && $this->policy->cancellationAllowed((int)$appointment['starts_at'], time(), (int)$service['cancel_notice_min']);
        $canReschedule = $active && $this->policy->rescheduleAllowed((int)$appointment['starts_at'], time(), (int)$service['resched_notice_min']);
        return [
            'appointment' => $presented,
            'organization' => [
                'name' => (string)$organization['name'], 'timezone' => (string)$organization['timezone'],
                'locale' => (string)$organization['locale'],
            ],
            'permissions' => ['canCancel' => $canCancel, 'canReschedule' => $canReschedule, 'canUpdateContact' => $active],
            'cancellationPolicy' => $this->policyText($service),
        ];
    }

    private function policyText(array $service): string {
        return $this->l10n->t(
            'Cancellation is possible until %1$s minutes before the appointment; rescheduling until %2$s minutes before it.',
            [(string)$service['cancel_notice_min'], (string)$service['resched_notice_min']],
        );
    }

    private function enqueueNotification(array $organization, array $appointment, array $service, ?array $location, string $eventType, ?string $rawToken = null): int {
        $manageUrl = $rawToken === null ? '' : $this->urlGenerator->linkToRouteAbsolute('appointments.page.manage') . '#' . rawurlencode($rawToken);
        $staff = $this->catalog->requireInternal('staff', (string)$organization['organization_id'], (int)$appointment['staff_id']);
        $plainTemplate = match ([$location !== null, $manageUrl !== '']) {
            [true, true] => 'Your appointment {bookingNumber} with {organization} for {service} is scheduled at {startsAt} with {staff} at {location}. Manage it securely: {manageUrl}',
            [true, false] => 'Your appointment {bookingNumber} with {organization} for {service} is scheduled at {startsAt} with {staff} at {location}.',
            [false, true] => 'Your appointment {bookingNumber} with {organization} for {service} is scheduled at {startsAt} with {staff}. Manage it securely: {manageUrl}',
            default => 'Your appointment {bookingNumber} with {organization} for {service} is scheduled at {startsAt} with {staff}.',
        };
        return $this->outbox->enqueue(
            (string)$organization['organization_id'], (int)$appointment['id'], $eventType,
            (string)$appointment['public_id'] . ':' . $eventType . ':' . (int)$appointment['revision'],
            (string)$appointment['email'], (string)$organization['locale'], [
                'subject' => match ($eventType) {
                    'booking_pending' => 'Appointment request received',
                    'cancelled_by_customer', 'cancelled_by_staff' => 'Appointment cancelled',
                    'rescheduled' => 'Appointment rescheduled',
                    default => 'Appointment confirmed',
                },
                'organizationName' => (string)$organization['name'],
                'plainTemplate' => $plainTemplate,
                'parameters' => [
                    'bookingNumber' => (string)$appointment['booking_number'], 'service' => (string)$service['name'],
                    'organization' => (string)$organization['name'],
                    'staff' => (string)$staff['display_name'], 'location' => (string)($location['name'] ?? ''),
                    'startsAt' => (new \DateTimeImmutable('@' . $appointment['starts_at']))->setTimezone(new \DateTimeZone((string)$organization['timezone']))
                        ->format((string)$organization['locale'] === 'de' ? 'd.m.Y H:i T' : 'Y-m-d H:i T'),
                    'manageUrl' => $manageUrl,
                ],
                'ics' => $this->ics->render($appointment, $service, $location, (string)$organization['name']),
            ],
        );
    }

    private function enqueueStaffNotification(array $organization, array $appointment, array $service, array $staff, string $eventType): ?int {
        $uid = (string)($staff['user_uid'] ?? '');
        if ($uid === '') {
            return null;
        }
        $recipient = $this->userManager->get($uid)?->getEMailAddress() ?? '';
        if (!$this->outboxRecipientValid($recipient)) {
            return null;
        }
        $template = match ($eventType) {
            'cancelled_by_customer', 'cancelled_by_staff' => 'Appointment {bookingNumber} with {organization} for {service} at {startsAt} was cancelled.',
            'rescheduled' => 'Appointment {bookingNumber} with {organization} for {service} was moved to {startsAt}.',
            default => 'A new appointment {bookingNumber} with {organization} for {service} is scheduled at {startsAt}.',
        };
        return $this->outbox->enqueue(
            (string)$organization['organization_id'], (int)$appointment['id'], 'staff_' . $eventType,
            (string)$appointment['public_id'] . ':staff:' . $eventType . ':' . (int)$appointment['revision'],
            $recipient, (string)$organization['locale'], [
                'subject' => 'Appointment staff notification', 'organizationName' => (string)$organization['name'],
                'plainTemplate' => $template, 'parameters' => [
                    'bookingNumber' => (string)$appointment['booking_number'], 'organization' => (string)$organization['name'],
                    'service' => (string)$service['name'],
                    'startsAt' => (new \DateTimeImmutable('@' . $appointment['starts_at']))->setTimezone(new \DateTimeZone((string)$organization['timezone']))
                        ->format((string)$organization['locale'] === 'de' ? 'd.m.Y H:i T' : 'Y-m-d H:i T'),
                ],
            ],
        );
    }

    private function outboxRecipientValid(string $recipient): bool {
        return filter_var($recipient, FILTER_VALIDATE_EMAIL) !== false && mb_strlen($recipient) <= 320;
    }

    /** @param list<int> $ids */
    private function scheduleOutbox(array $ids): void {
        foreach (array_values(array_unique($ids)) as $id) {
            try {
                $this->outbox->schedule($id);
            } catch (\Throwable) {
                // The durable pending row remains discoverable by OutboxSweepJob.
            }
        }
    }

    private function limited(mixed $value, int $maximum, bool $required = false): string {
        $value = trim((string)$value);
        if (($required && $value === '') || mb_strlen($value) > $maximum) {
            throw new ValidationException($this->l10n->t('A text field is invalid.'));
        }
        return $value;
    }

    private function recordBookingFailure(string $organizationId, ApiException $exception): void {
        try {
            $this->audit->record(
                $organizationId,
                $exception instanceof ConflictException ? 'appointment.slot_conflict' : 'appointment.booking_failed',
                'system',
                'appointment',
                '',
                'failed',
                ['reason_code' => $exception->getErrorCode()],
            );
        } catch (\Throwable) {
            // Failure telemetry must never replace the safe API error.
        }
    }

    /** @return array<string,mixed> */
    private function resolveTokenAfterOrganizationLock(string $token, string $organizationId): array {
        $appointment = $this->tokens->resolve($token);
        if (!hash_equals($organizationId, (string)$appointment['organization_id']) || $appointment['anonymized_at'] !== null) {
            throw new NotFoundException($this->l10n->t('The management link is invalid or has expired.'));
        }
        return $appointment;
    }
}
