<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCP\DB\QueryBuilder\IQueryBuilder;

final class ReminderService {
    private const DEFAULT_OFFSETS = [1440 => '24_hours', 120 => '2_hours'];

    public function __construct(
        private Database $database,
        private AppointmentRepository $appointments,
        private OrganizationRepository $organizations,
        private CatalogRepository $catalog,
        private OutboxService $outbox,
        private IcsService $ics,
    ) {
    }

    /** Must run inside the appointment mutation transaction. */
    public function replaceForAppointment(array $appointment): void {
        $organizationId = (string)$appointment['organization_id'];
        $currentQuery = $this->database->query();
        $currentQuery->select('id')->from('appt_reminders')
            ->where($currentQuery->expr()->eq('organization_id', $currentQuery->createNamedParameter($organizationId)))
            ->andWhere($currentQuery->expr()->eq('appointment_id', $currentQuery->createNamedParameter((int)$appointment['id'], IQueryBuilder::PARAM_INT)))
            ->andWhere($currentQuery->expr()->in('state', $currentQuery->createNamedParameter(['pending', 'queued'], IQueryBuilder::PARAM_STR_ARRAY)));
        $cancelledIds = array_map(static fn (array $row): int => (int)$row['id'], $this->database->fetchAll($currentQuery));
        $cancel = $this->database->query();
        $cancel->update('appt_reminders')->set('state', $cancel->createNamedParameter('cancelled'))
            ->where($cancel->expr()->eq('organization_id', $cancel->createNamedParameter($organizationId)))
            ->andWhere($cancel->expr()->eq('appointment_id', $cancel->createNamedParameter((int)$appointment['id'], IQueryBuilder::PARAM_INT)))
            ->andWhere($cancel->expr()->in('state', $cancel->createNamedParameter(['pending', 'queued'], IQueryBuilder::PARAM_STR_ARRAY)))
            ->executeStatement();
        if ($cancelledIds !== []) {
            $keys = array_map(static fn (int $id): string => 'reminder:' . $id, $cancelledIds);
            $cancelOutbox = $this->database->query();
            $cancelOutbox->update('appt_mail_outbox')
                ->set('state', $cancelOutbox->createNamedParameter('cancelled'))
                ->set('last_error_code', $cancelOutbox->createNamedParameter('cancelled'))
                ->set('recipient_cipher', $cancelOutbox->createNamedParameter('[purged]'))
                ->set('payload_cipher', $cancelOutbox->createNamedParameter('[purged]'))
                ->where($cancelOutbox->expr()->in('idempotency_key', $cancelOutbox->createNamedParameter($keys, IQueryBuilder::PARAM_STR_ARRAY)))
                ->andWhere($cancelOutbox->expr()->in('state', $cancelOutbox->createNamedParameter(['pending', 'retry', 'sending'], IQueryBuilder::PARAM_STR_ARRAY)))
                ->executeStatement();
        }
        if (!in_array((string)$appointment['status'], AppointmentPolicy::ACTIVE, true)) {
            return;
        }
        foreach (self::plannedReminders((int)$appointment['starts_at'], time()) as $planned) {
            $type = $planned['type'];
            $scheduledAt = $planned['scheduledAt'];
            $existing = $this->find($organizationId, (int)$appointment['id'], $type, $scheduledAt);
            if ($existing !== null) {
                if ((string)$existing['state'] === 'cancelled') {
                    $reactivate = $this->database->query();
                    $reactivate->update('appt_reminders')
                        ->set('state', $reactivate->createNamedParameter('pending'))
                        ->set('attempts', $reactivate->createNamedParameter(0, IQueryBuilder::PARAM_INT))
                        ->where($reactivate->expr()->eq('id', $reactivate->createNamedParameter((int)$existing['id'], IQueryBuilder::PARAM_INT)))
                        ->executeStatement();
                }
                continue;
            }
            $query = $this->database->query();
            $query->insert('appt_reminders')->values([
                'organization_id' => $query->createNamedParameter($organizationId),
                'appointment_id' => $query->createNamedParameter((int)$appointment['id'], IQueryBuilder::PARAM_INT),
                'reminder_type' => $query->createNamedParameter($type),
                'scheduled_at' => $query->createNamedParameter($scheduledAt, IQueryBuilder::PARAM_INT),
                'state' => $query->createNamedParameter('pending'),
                'attempts' => $query->createNamedParameter(0, IQueryBuilder::PARAM_INT),
            ])->executeStatement();
        }
    }

    /** @return list<array{type:string,scheduledAt:int}> */
    public static function plannedReminders(int $startsAt, int $now): array {
        $planned = [];
        foreach (self::DEFAULT_OFFSETS as $minutes => $type) {
            $scheduledAt = $startsAt - ($minutes * 60);
            if ($scheduledAt > $now) {
                $planned[] = ['type' => $type, 'scheduledAt' => $scheduledAt];
            }
        }
        return $planned;
    }

    public function sweep(int $limit = 100): void {
        $query = $this->database->query();
        $query->select('id')->from('appt_reminders')
            ->where($query->expr()->eq('state', $query->createNamedParameter('pending')))
            ->andWhere($query->expr()->lte('scheduled_at', $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT)))
            ->orderBy('scheduled_at', 'ASC')->setMaxResults($limit);
        foreach ($this->database->fetchAll($query) as $row) {
            $outboxId = $this->queueReminder((int)$row['id']);
            if ($outboxId !== null) {
                try {
                    $this->outbox->schedule($outboxId);
                } catch (\Throwable) {
                    // OutboxSweepJob will retry scheduling the durable row.
                }
            }
        }
    }

    private function queueReminder(int $reminderId): ?int {
        return $this->database->transaction(function () use ($reminderId): ?int {
            $query = $this->database->query();
            $query->select('*')->from('appt_reminders')
                ->where($query->expr()->eq('id', $query->createNamedParameter($reminderId, IQueryBuilder::PARAM_INT)))
                ->forUpdate();
            $reminder = $this->database->fetchOne($query);
            if ($reminder === null || (string)$reminder['state'] !== 'pending' || (int)$reminder['scheduled_at'] > time()) {
                return null;
            }
            $organizationId = (string)$reminder['organization_id'];
            $appointment = $this->appointments->requireInternal($organizationId, (int)$reminder['appointment_id']);
            if (!in_array((string)$appointment['status'], AppointmentPolicy::ACTIVE, true) || (int)$appointment['starts_at'] <= time()) {
                $this->setState($reminderId, 'cancelled');
                return null;
            }
            $organization = $this->organizations->requireById($organizationId);
            $service = $this->catalog->requireInternal('services', $organizationId, (int)$appointment['service_id']);
            $staff = $this->catalog->requireInternal('staff', $organizationId, (int)$appointment['staff_id']);
            $location = $appointment['location_id'] === null ? null : $this->catalog->requireInternal('locations', $organizationId, (int)$appointment['location_id']);
            $outboxId = $this->outbox->enqueue(
                $organizationId, (int)$appointment['id'], 'reminder', 'reminder:' . $reminderId,
                (string)$appointment['email'], (string)$organization['locale'], [
                    'subject' => 'Appointment reminder',
                    'organizationName' => (string)$organization['name'],
                    'plainTemplate' => $location === null
                        ? 'Reminder: appointment {bookingNumber} with {organization} for {service} starts at {startsAt} with {staff}.'
                        : 'Reminder: appointment {bookingNumber} with {organization} for {service} starts at {startsAt} with {staff} at {location}.',
                    'parameters' => [
                        'bookingNumber' => (string)$appointment['booking_number'], 'service' => (string)$service['name'],
                        'organization' => (string)$organization['name'],
                        'staff' => (string)$staff['display_name'], 'location' => (string)($location['name'] ?? ''),
                        'startsAt' => (new \DateTimeImmutable('@' . $appointment['starts_at']))->setTimezone(new \DateTimeZone((string)$organization['timezone']))
                            ->format((string)$organization['locale'] === 'de' ? 'd.m.Y H:i T' : 'Y-m-d H:i T'),
                    ],
                    'ics' => $this->ics->render($appointment, $service, $location, (string)$organization['name']),
                ],
            );
            $this->setState($reminderId, 'queued');
            return $outboxId;
        });
    }

    private function setState(int $id, string $state): void {
        $query = $this->database->query();
        $query->update('appt_reminders')->set('state', $query->createNamedParameter($state))
            ->where($query->expr()->eq('id', $query->createNamedParameter($id, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
    }

    /** @return array<string,mixed>|null */
    private function find(string $organizationId, int $appointmentId, string $type, int $scheduledAt): ?array {
        $query = $this->database->query();
        $query->select('id', 'state')->from('appt_reminders')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('appointment_id', $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->eq('reminder_type', $query->createNamedParameter($type)))
            ->andWhere($query->expr()->eq('scheduled_at', $query->createNamedParameter($scheduledAt, IQueryBuilder::PARAM_INT)));
        return $this->database->fetchOne($query);
    }
}
