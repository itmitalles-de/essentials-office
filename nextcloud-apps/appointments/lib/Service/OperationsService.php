<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCP\DB\QueryBuilder\IQueryBuilder;

final class OperationsService {
    public function __construct(private Database $database) {
    }

    /** @return array<string,mixed> */
    public function forOrganization(string $organizationId): array {
        $failures = [];
        $query = $this->database->query();
        $query->select('id', 'event_type', 'last_error_code', 'created_at')->from('appt_mail_outbox')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('state', $query->createNamedParameter('failed')))
            ->orderBy('created_at', 'DESC')->setMaxResults(25);
        foreach ($this->database->fetchAll($query) as $row) {
            $failures[] = [
                'kind' => 'notification', 'internalId' => (int)$row['id'], 'eventType' => (string)$row['event_type'],
                'errorCode' => (string)$row['last_error_code'], 'createdAt' => (int)$row['created_at'],
            ];
        }
        return ['failures' => $failures, 'failureCount' => count($failures)];
    }

    /** @return array<string,int> */
    public function metrics(): array {
        return [
            'booking_success' => $this->auditCount('appointment.created', 'success'),
            'booking_error' => $this->auditCount('appointment.booking_failed', 'failed'),
            'slot_conflict' => $this->auditCount('appointment.slot_conflict', 'failed'),
            'reminder_pending' => $this->stateCount('appt_reminders', 'pending'),
            'reminder_failed' => $this->stateCount('appt_reminders', 'failed'),
            'outbox_failed' => $this->stateCount('appt_mail_outbox', 'failed'),
            'calendar_sync_failed' => 0,
        ];
    }

    private function auditCount(string $action, string $outcome): int {
        $query = $this->database->query();
        $query->select($query->func()->count('*', 'count'))->from('appt_audit')
            ->where($query->expr()->eq('action', $query->createNamedParameter($action)))
            ->andWhere($query->expr()->eq('outcome', $query->createNamedParameter($outcome)));
        return (int)($this->database->fetchOne($query)['count'] ?? 0);
    }

    private function stateCount(string $table, string $state): int {
        $query = $this->database->query();
        $query->select($query->func()->count('*', 'count'))->from($table)
            ->where($query->expr()->eq('state', $query->createNamedParameter($state)));
        return (int)($this->database->fetchOne($query)['count'] ?? 0);
    }
}
