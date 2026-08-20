<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCP\DB\QueryBuilder\IQueryBuilder;

final class RetentionService {
    public function __construct(
        private Database $database,
        private OrganizationRepository $organizations,
        private AppointmentRepository $appointments,
        private TokenService $tokens,
        private ReminderService $reminders,
        private OutboxService $outbox,
        private AuditService $audit,
    ) {
    }

    public function run(int $perOrganization = 250): void {
        foreach ($this->organizations->all() as $organization) {
            $organizationId = (string)$organization['organization_id'];
            $cutoff = time() - ((int)$organization['retention_days'] * 86400);
            foreach ($this->expiredIds($organizationId, $cutoff, $perOrganization) as $publicId) {
                $this->anonymize($organizationId, $publicId, $cutoff);
            }
            $this->outbox->purgeSensitiveForExpired($organizationId, $cutoff);
        }
    }

    /** @return list<string> */
    private function expiredIds(string $organizationId, int $cutoff, int $limit): array {
        $query = $this->database->query();
        $query->select('public_id')->from('appt_appointments')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->isNull('anonymized_at'))
            ->andWhere($query->expr()->lt('ends_at', $query->createNamedParameter($cutoff, IQueryBuilder::PARAM_INT)))
            ->orderBy('ends_at', 'ASC')->setMaxResults(max(1, min(1000, $limit)));
        return array_map(static fn (array $row): string => (string)$row['public_id'], $this->database->fetchAll($query));
    }

    private function anonymize(string $organizationId, string $publicId, int $cutoff): void {
        $this->database->transaction(function () use ($organizationId, $publicId, $cutoff): void {
            $this->organizations->lock($organizationId);
            $appointment = $this->appointments->lock($organizationId, $publicId);
            if ($appointment['anonymized_at'] !== null || (int)$appointment['ends_at'] >= $cutoff) {
                return;
            }
            $now = time();
            $this->appointments->update($organizationId, (int)$appointment['id'], [
                'first_name' => 'Anonymized', 'last_name' => 'Customer',
                'email' => 'anonymized-' . substr(hash('sha256', $publicId), 0, 20) . '@invalid.example',
                'phone' => '', 'customer_message' => '', 'internal_note' => '', 'created_by_uid' => '',
                'meeting_ref' => '', 'privacy_accepted_at' => null, 'anonymized_at' => $now, 'updated_at' => $now,
                'revision' => (int)$appointment['revision'] + 1,
            ]);
            $delete = $this->database->query();
            $delete->delete('appt_form_answers')
                ->where($delete->expr()->eq('organization_id', $delete->createNamedParameter($organizationId)))
                ->andWhere($delete->expr()->eq('appointment_id', $delete->createNamedParameter((int)$appointment['id'], IQueryBuilder::PARAM_INT)))
                ->executeStatement();
            $this->tokens->revokeForAppointment($organizationId, (int)$appointment['id']);
            $anonymized = $this->appointments->requireByPublicId($organizationId, $publicId);
            $this->reminders->replaceForAppointment(array_merge($anonymized, ['status' => 'completed']));
            $this->audit->record($organizationId, 'appointment.anonymized', 'system', 'appointment', $publicId);
        });
    }
}
