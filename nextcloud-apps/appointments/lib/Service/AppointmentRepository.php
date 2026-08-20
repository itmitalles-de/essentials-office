<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\Exception\NotFoundException;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IL10N;

final class AppointmentRepository {
    public function __construct(private Database $database, private IL10N $l10n) {
    }

    /** @param array<string,mixed> $values
     *  @return array<string,mixed>
     */
    public function create(array $values): array {
        $query = $this->database->query();
        $parameters = [];
        foreach ($values as $column => $value) {
            $parameters[$column] = $query->createNamedParameter($value, $this->parameterType($value));
        }
        $query->insert('appt_appointments')->values($parameters)->executeStatement();
        return $this->requireByPublicId((string)$values['organization_id'], (string)$values['public_id']);
    }

    /** @return array<string,mixed> */
    public function requireByPublicId(string $organizationId, string $publicId): array {
        $query = $this->database->query();
        $query->select('a.*')->from('appt_appointments', 'a')
            ->where($query->expr()->eq('a.organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('a.public_id', $query->createNamedParameter($publicId)));
        $row = $this->database->fetchOne($query);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The appointment was not found.'));
        }
        return $this->normalize($row);
    }

    /** @return array<string,mixed> */
    public function requireInternal(string $organizationId, int $id): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_appointments')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('id', $query->createNamedParameter($id, IQueryBuilder::PARAM_INT)));
        $row = $this->database->fetchOne($query);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The appointment was not found.'));
        }
        return $this->normalize($row);
    }

    /** @return array<string,mixed> */
    public function lock(string $organizationId, string $publicId): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_appointments')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('public_id', $query->createNamedParameter($publicId)))
            ->forUpdate();
        $row = $this->database->fetchOne($query);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The appointment was not found.'));
        }
        return $this->normalize($row);
    }

    /** @return list<array<string,mixed>> */
    public function list(string $organizationId, array $filters, ?int $ownStaffId): array {
        $query = $this->database->query();
        $query->select('p.*')->from('appt_appointments', 'p')
            ->where($query->expr()->eq('p.organization_id', $query->createNamedParameter($organizationId)));
        if (isset($filters['resourceInternalId']) && (int)$filters['resourceInternalId'] > 0) {
            $query->innerJoin('p', 'appt_resource_alloc', 'ra', $query->expr()->andX(
                $query->expr()->eq('ra.organization_id', 'p.organization_id'),
                $query->expr()->eq('ra.appointment_id', 'p.id'),
                $query->expr()->eq('ra.resource_id', $query->createNamedParameter((int)$filters['resourceInternalId'], IQueryBuilder::PARAM_INT)),
            ));
        }
        if ($ownStaffId !== null) {
            $query->andWhere($query->expr()->eq('p.staff_id', $query->createNamedParameter($ownStaffId, IQueryBuilder::PARAM_INT)));
        }
        foreach (['from' => ['ends_at', 'gt'], 'to' => ['starts_at', 'lt']] as $key => [$column, $operator]) {
            if (isset($filters[$key]) && (int)$filters[$key] > 0) {
                $query->andWhere($query->expr()->{$operator}('p.' . $column, $query->createNamedParameter((int)$filters[$key], IQueryBuilder::PARAM_INT)));
            }
        }
        foreach (['status' => 'status', 'staffInternalId' => 'staff_id', 'serviceInternalId' => 'service_id', 'locationInternalId' => 'location_id'] as $key => $column) {
            if (isset($filters[$key]) && $filters[$key] !== '') {
                $type = $key === 'status' ? IQueryBuilder::PARAM_STR : IQueryBuilder::PARAM_INT;
                $query->andWhere($query->expr()->eq('p.' . $column, $query->createNamedParameter($filters[$key], $type)));
            }
        }
        if (isset($filters['search']) && trim((string)$filters['search']) !== '') {
            $term = '%' . $this->database->escapeLike(mb_strtolower(trim((string)$filters['search']))) . '%';
            $query->andWhere($query->expr()->orX(
                $query->expr()->like($query->func()->lower('p.first_name'), $query->createNamedParameter($term)),
                $query->expr()->like($query->func()->lower('p.last_name'), $query->createNamedParameter($term)),
                $query->expr()->like($query->func()->lower('p.email'), $query->createNamedParameter($term)),
                $query->expr()->like($query->func()->lower('p.phone'), $query->createNamedParameter($term)),
                $query->expr()->like($query->func()->lower('p.booking_number'), $query->createNamedParameter($term)),
            ));
        }
        $query->orderBy('p.starts_at', 'ASC')->setMaxResults(500);
        return array_map($this->normalize(...), $this->database->fetchAll($query));
    }

    /** @param array<string,mixed> $values */
    public function update(string $organizationId, int $appointmentId, array $values): void {
        if ($values === []) {
            return;
        }
        $query = $this->database->query();
        $query->update('appt_appointments');
        foreach ($values as $column => $value) {
            $query->set($column, $query->createNamedParameter($value, $this->parameterType($value)));
        }
        $query->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('id', $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
    }

    /** @param list<array{resourceInternalId:int,quantity:int}> $resources */
    public function replaceResources(string $organizationId, int $appointmentId, int $busyStartsAt, int $busyEndsAt, array $resources): void {
        $delete = $this->database->query();
        $delete->delete('appt_resource_alloc')
            ->where($delete->expr()->eq('organization_id', $delete->createNamedParameter($organizationId)))
            ->andWhere($delete->expr()->eq('appointment_id', $delete->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
        foreach ($resources as $resource) {
            $query = $this->database->query();
            $query->insert('appt_resource_alloc')->values([
                'organization_id' => $query->createNamedParameter($organizationId),
                'appointment_id' => $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT),
                'resource_id' => $query->createNamedParameter($resource['resourceInternalId'], IQueryBuilder::PARAM_INT),
                'quantity' => $query->createNamedParameter($resource['quantity'], IQueryBuilder::PARAM_INT),
                'busy_starts_at' => $query->createNamedParameter($busyStartsAt, IQueryBuilder::PARAM_INT),
                'busy_ends_at' => $query->createNamedParameter($busyEndsAt, IQueryBuilder::PARAM_INT),
            ])->executeStatement();
        }
    }

    public function addStatusHistory(string $organizationId, int $appointmentId, string $from, string $to, string $actorType, string $actorRef): void {
        $query = $this->database->query();
        $query->insert('appt_status_history')->values([
            'organization_id' => $query->createNamedParameter($organizationId),
            'appointment_id' => $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT),
            'from_status' => $query->createNamedParameter($from), 'to_status' => $query->createNamedParameter($to),
            'actor_type' => $query->createNamedParameter($actorType), 'actor_ref' => $query->createNamedParameter(mb_substr($actorRef, 0, 255)),
            'created_at' => $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT),
        ])->executeStatement();
    }

    /** @param list<array{fieldInternalId:int,value:mixed}> $answers */
    public function replaceAnswers(string $organizationId, int $appointmentId, array $answers): void {
        $delete = $this->database->query();
        $delete->delete('appt_form_answers')
            ->where($delete->expr()->eq('organization_id', $delete->createNamedParameter($organizationId)))
            ->andWhere($delete->expr()->eq('appointment_id', $delete->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
        foreach ($answers as $answer) {
            $query = $this->database->query();
            $query->insert('appt_form_answers')->values([
                'organization_id' => $query->createNamedParameter($organizationId),
                'appointment_id' => $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT),
                'field_id' => $query->createNamedParameter($answer['fieldInternalId'], IQueryBuilder::PARAM_INT),
                'value_json' => $query->createNamedParameter(json_encode($answer['value'], JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE)),
            ])->executeStatement();
        }
    }

    /** @return list<array<string,mixed>> */
    public function exportAnswers(string $organizationId, int $appointmentId, bool $publicOnly = false): array {
        $query = $this->database->query();
        $query->select('f.public_id', 'f.label', 'f.field_type', 'a.value_json')->from('appt_form_answers', 'a')
            ->innerJoin('a', 'appt_form_fields', 'f', $query->expr()->andX(
                $query->expr()->eq('f.id', 'a.field_id'), $query->expr()->eq('f.organization_id', 'a.organization_id'),
            ))
            ->where($query->expr()->eq('a.organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('a.appointment_id', $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT)));
        if ($publicOnly) {
            $query->andWhere($query->expr()->eq('f.visibility', $query->createNamedParameter('public')));
        }
        $query->orderBy('f.sort_order', 'ASC');
        return array_map(static function (array $row): array {
            try {
                $value = json_decode((string)$row['value_json'], true, 8, JSON_THROW_ON_ERROR);
            } catch (\JsonException) {
                $value = null;
            }
            return [
                'fieldId' => (string)$row['public_id'], 'label' => (string)$row['label'],
                'type' => (string)$row['field_type'], 'value' => $value,
            ];
        }, $this->database->fetchAll($query));
    }

    /** @return list<array<string,mixed>> */
    public function exportStatusHistory(string $organizationId, int $appointmentId): array {
        $query = $this->database->query();
        $query->select('from_status', 'to_status', 'actor_type', 'created_at')->from('appt_status_history')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('appointment_id', $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT)))
            ->orderBy('created_at', 'ASC');
        return array_map(static fn (array $row): array => [
            'from' => (string)$row['from_status'], 'to' => (string)$row['to_status'],
            'actorType' => (string)$row['actor_type'], 'changedAt' => (int)$row['created_at'],
        ], $this->database->fetchAll($query));
    }

    /** @return list<string> */
    public function resourcePublicIds(string $organizationId, int $appointmentId): array {
        $query = $this->database->query();
        $query->select('r.public_id')->from('appt_resource_alloc', 'a')
            ->innerJoin('a', 'appt_resources', 'r', $query->expr()->andX(
                $query->expr()->eq('r.organization_id', 'a.organization_id'),
                $query->expr()->eq('r.id', 'a.resource_id'),
            ))
            ->where($query->expr()->eq('a.organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('a.appointment_id', $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT)))
            ->orderBy('r.public_id', 'ASC');
        return array_map(static fn (array $row): string => (string)$row['public_id'], $this->database->fetchAll($query));
    }

    /** @param array<string,mixed> $appointment
     *  @return list<string>
     */
    public function conflictTypes(string $organizationId, array $appointment): array {
        if (!in_array((string)$appointment['status'], AppointmentPolicy::ACTIVE, true)) {
            return [];
        }

        $conflicts = [];
        $staff = $this->database->query();
        $staff->select('id')->from('appt_appointments')
            ->where($staff->expr()->eq('organization_id', $staff->createNamedParameter($organizationId)))
            ->andWhere($staff->expr()->eq('staff_id', $staff->createNamedParameter((int)$appointment['staff_id'], IQueryBuilder::PARAM_INT)))
            ->andWhere($staff->expr()->neq('id', $staff->createNamedParameter((int)$appointment['id'], IQueryBuilder::PARAM_INT)))
            ->andWhere($staff->expr()->in('status', $staff->createNamedParameter(AppointmentPolicy::ACTIVE, IQueryBuilder::PARAM_STR_ARRAY)))
            ->andWhere($staff->expr()->lt('busy_starts_at', $staff->createNamedParameter((int)$appointment['busy_ends_at'], IQueryBuilder::PARAM_INT)))
            ->andWhere($staff->expr()->gt('busy_ends_at', $staff->createNamedParameter((int)$appointment['busy_starts_at'], IQueryBuilder::PARAM_INT)))
            ->setMaxResults(1);
        if ($this->database->fetchOne($staff) !== null) {
            $conflicts[] = 'staff';
        }

        $ownAllocations = $this->database->query();
        $ownAllocations->select('resource_id', 'quantity', 'busy_starts_at', 'busy_ends_at')->from('appt_resource_alloc')
            ->where($ownAllocations->expr()->eq('organization_id', $ownAllocations->createNamedParameter($organizationId)))
            ->andWhere($ownAllocations->expr()->eq('appointment_id', $ownAllocations->createNamedParameter((int)$appointment['id'], IQueryBuilder::PARAM_INT)));
        foreach ($this->database->fetchAll($ownAllocations) as $allocation) {
            $resource = $this->database->query();
            $resource->select('capacity', 'active')->from('appt_resources')
                ->where($resource->expr()->eq('organization_id', $resource->createNamedParameter($organizationId)))
                ->andWhere($resource->expr()->eq('id', $resource->createNamedParameter((int)$allocation['resource_id'], IQueryBuilder::PARAM_INT)));
            $resourceRow = $this->database->fetchOne($resource);
            if ($resourceRow === null || !Database::bool($resourceRow['active'])) {
                $conflicts[] = 'resource';
                break;
            }

            $others = $this->database->query();
            $others->select('a.quantity')->from('appt_resource_alloc', 'a')
                ->innerJoin('a', 'appt_appointments', 'p', $others->expr()->andX(
                    $others->expr()->eq('p.organization_id', 'a.organization_id'),
                    $others->expr()->eq('p.id', 'a.appointment_id'),
                ))
                ->where($others->expr()->eq('a.organization_id', $others->createNamedParameter($organizationId)))
                ->andWhere($others->expr()->eq('a.resource_id', $others->createNamedParameter((int)$allocation['resource_id'], IQueryBuilder::PARAM_INT)))
                ->andWhere($others->expr()->neq('a.appointment_id', $others->createNamedParameter((int)$appointment['id'], IQueryBuilder::PARAM_INT)))
                ->andWhere($others->expr()->in('p.status', $others->createNamedParameter(AppointmentPolicy::ACTIVE, IQueryBuilder::PARAM_STR_ARRAY)))
                ->andWhere($others->expr()->lt('a.busy_starts_at', $others->createNamedParameter((int)$allocation['busy_ends_at'], IQueryBuilder::PARAM_INT)))
                ->andWhere($others->expr()->gt('a.busy_ends_at', $others->createNamedParameter((int)$allocation['busy_starts_at'], IQueryBuilder::PARAM_INT)));
            $used = array_sum(array_map(
                static fn (array $row): int => (int)$row['quantity'],
                $this->database->fetchAll($others),
            ));
            if ($used + (int)$allocation['quantity'] > (int)$resourceRow['capacity']) {
                $conflicts[] = 'resource';
                break;
            }
        }
        return array_values(array_unique($conflicts));
    }

    private function parameterType(mixed $value): int|string {
        return $value === null ? IQueryBuilder::PARAM_NULL : (is_bool($value) ? IQueryBuilder::PARAM_BOOL : (is_int($value) ? IQueryBuilder::PARAM_INT : IQueryBuilder::PARAM_STR));
    }

    /** @return array<string,mixed> */
    private function normalize(array $row): array {
        foreach (['id', 'service_id', 'staff_id', 'location_id', 'starts_at', 'ends_at', 'busy_starts_at', 'busy_ends_at', 'privacy_accepted_at', 'created_at', 'updated_at', 'cancelled_at', 'anonymized_at', 'revision'] as $column) {
            if (isset($row[$column])) {
                $row[$column] = (int)$row[$column];
            }
        }
        return $row;
    }
}
