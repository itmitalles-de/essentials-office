<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCP\DB\QueryBuilder\IQueryBuilder;

final class AvailabilityRepository {
    public function __construct(private Database $database) {
    }

    /** @return list<array<string, mixed>> */
    public function rules(string $organizationId, string $subjectType, string $subjectId): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_avail_rules')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('subject_type', $query->createNamedParameter($subjectType)))
            ->andWhere($query->expr()->eq('subject_id', $query->createNamedParameter($subjectId)))
            ->orderBy('weekday', 'ASC')->addOrderBy('start_minute', 'ASC');
        return array_map(static fn (array $row): array => [
            'weekday' => (int)$row['weekday'], 'startMinute' => (int)$row['start_minute'],
            'endMinute' => (int)$row['end_minute'], 'type' => (string)$row['rule_type'],
            'validFrom' => (string)$row['valid_from'], 'validUntil' => (string)$row['valid_until'],
        ], $this->database->fetchAll($query));
    }

    /** @return list<array<string, mixed>> */
    public function exceptions(string $organizationId, string $subjectType, string $subjectId, int $from, int $to): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_avail_except')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('subject_type', $query->createNamedParameter($subjectType)))
            ->andWhere($query->expr()->eq('subject_id', $query->createNamedParameter($subjectId)))
            ->andWhere($query->expr()->lt('starts_at', $query->createNamedParameter($to, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->gt('ends_at', $query->createNamedParameter($from, IQueryBuilder::PARAM_INT)));
        return array_map(static fn (array $row): array => [
            'startsAt' => (int)$row['starts_at'], 'endsAt' => (int)$row['ends_at'],
            'type' => (string)$row['exception_type'], 'reason' => (string)$row['reason'],
        ], $this->database->fetchAll($query));
    }

    /** @return list<array{startsAt:int,endsAt:int}> */
    public function staffBusy(string $organizationId, int $staffId, int $from, int $to, ?int $excludeAppointmentId = null): array {
        $query = $this->database->query();
        $query->select('busy_starts_at', 'busy_ends_at')->from('appt_appointments')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('staff_id', $query->createNamedParameter($staffId, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->in('status', $query->createNamedParameter(AppointmentPolicy::ACTIVE, IQueryBuilder::PARAM_STR_ARRAY)))
            ->andWhere($query->expr()->lt('busy_starts_at', $query->createNamedParameter($to, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->gt('busy_ends_at', $query->createNamedParameter($from, IQueryBuilder::PARAM_INT)));
        if ($excludeAppointmentId !== null) {
            $query->andWhere($query->expr()->neq('id', $query->createNamedParameter($excludeAppointmentId, IQueryBuilder::PARAM_INT)));
        }
        return array_map(static fn (array $row): array => [
            'startsAt' => (int)$row['busy_starts_at'], 'endsAt' => (int)$row['busy_ends_at'],
        ], $this->database->fetchAll($query));
    }

    /** @return list<array{startsAt:int,endsAt:int}> */
    public function locationBusy(string $organizationId, int $locationId, int $from, int $to, ?int $excludeAppointmentId = null): array {
        $query = $this->database->query();
        $query->select('busy_starts_at', 'busy_ends_at')->from('appt_appointments')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('location_id', $query->createNamedParameter($locationId, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->in('status', $query->createNamedParameter(AppointmentPolicy::ACTIVE, IQueryBuilder::PARAM_STR_ARRAY)))
            ->andWhere($query->expr()->lt('busy_starts_at', $query->createNamedParameter($to, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->gt('busy_ends_at', $query->createNamedParameter($from, IQueryBuilder::PARAM_INT)));
        if ($excludeAppointmentId !== null) {
            $query->andWhere($query->expr()->neq('id', $query->createNamedParameter($excludeAppointmentId, IQueryBuilder::PARAM_INT)));
        }
        return array_map(static fn (array $row): array => [
            'startsAt' => (int)$row['busy_starts_at'], 'endsAt' => (int)$row['busy_ends_at'],
        ], $this->database->fetchAll($query));
    }

    /** @return list<array{startsAt:int,endsAt:int,quantity:int}> */
    public function resourceBusy(string $organizationId, int $resourceId, int $from, int $to, ?int $excludeAppointmentId = null): array {
        $query = $this->database->query();
        $query->select('a.busy_starts_at', 'a.busy_ends_at', 'a.quantity')->from('appt_resource_alloc', 'a')
            ->innerJoin('a', 'appt_appointments', 'p', $query->expr()->andX(
                $query->expr()->eq('p.id', 'a.appointment_id'),
                $query->expr()->eq('p.organization_id', 'a.organization_id'),
            ))
            ->where($query->expr()->eq('a.organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('a.resource_id', $query->createNamedParameter($resourceId, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->in('p.status', $query->createNamedParameter(AppointmentPolicy::ACTIVE, IQueryBuilder::PARAM_STR_ARRAY)))
            ->andWhere($query->expr()->lt('a.busy_starts_at', $query->createNamedParameter($to, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->gt('a.busy_ends_at', $query->createNamedParameter($from, IQueryBuilder::PARAM_INT)));
        if ($excludeAppointmentId !== null) {
            $query->andWhere($query->expr()->neq('a.appointment_id', $query->createNamedParameter($excludeAppointmentId, IQueryBuilder::PARAM_INT)));
        }
        return array_map(static fn (array $row): array => [
            'startsAt' => (int)$row['busy_starts_at'], 'endsAt' => (int)$row['busy_ends_at'], 'quantity' => (int)$row['quantity'],
        ], $this->database->fetchAll($query));
    }

    /** @param list<array<string,mixed>> $rules
     *  @param list<array<string,mixed>> $exceptions
     */
    public function replace(string $organizationId, string $subjectType, string $subjectId, array $rules, array $exceptions): void {
        foreach (['appt_avail_rules', 'appt_avail_except'] as $table) {
            $delete = $this->database->query();
            $delete->delete($table)
                ->where($delete->expr()->eq('organization_id', $delete->createNamedParameter($organizationId)))
                ->andWhere($delete->expr()->eq('subject_type', $delete->createNamedParameter($subjectType)))
                ->andWhere($delete->expr()->eq('subject_id', $delete->createNamedParameter($subjectId)))
                ->executeStatement();
        }
        foreach ($rules as $rule) {
            $query = $this->database->query();
            $query->insert('appt_avail_rules')->values([
                'organization_id' => $query->createNamedParameter($organizationId), 'subject_type' => $query->createNamedParameter($subjectType),
                'subject_id' => $query->createNamedParameter($subjectId), 'weekday' => $query->createNamedParameter($rule['weekday'], IQueryBuilder::PARAM_INT),
                'start_minute' => $query->createNamedParameter($rule['startMinute'], IQueryBuilder::PARAM_INT),
                'end_minute' => $query->createNamedParameter($rule['endMinute'], IQueryBuilder::PARAM_INT),
                'rule_type' => $query->createNamedParameter($rule['type']), 'valid_from' => $query->createNamedParameter($rule['validFrom']),
                'valid_until' => $query->createNamedParameter($rule['validUntil']),
            ])->executeStatement();
        }
        foreach ($exceptions as $exception) {
            $query = $this->database->query();
            $query->insert('appt_avail_except')->values([
                'organization_id' => $query->createNamedParameter($organizationId), 'subject_type' => $query->createNamedParameter($subjectType),
                'subject_id' => $query->createNamedParameter($subjectId), 'starts_at' => $query->createNamedParameter($exception['startsAt'], IQueryBuilder::PARAM_INT),
                'ends_at' => $query->createNamedParameter($exception['endsAt'], IQueryBuilder::PARAM_INT),
                'exception_type' => $query->createNamedParameter($exception['type']), 'reason' => $query->createNamedParameter($exception['reason']),
            ])->executeStatement();
        }
    }
}
