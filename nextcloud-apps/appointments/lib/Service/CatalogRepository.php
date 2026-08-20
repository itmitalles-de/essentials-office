<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\Exception\NotFoundException;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IL10N;

final class CatalogRepository {
    /** @var array<string, string> */
    private const TABLES = [
        'services' => 'appt_services',
        'staff' => 'appt_staff',
        'locations' => 'appt_locations',
        'resources' => 'appt_resources',
    ];

    public function __construct(private Database $database, private IL10N $l10n) {
    }

    /** @return list<array<string, mixed>> */
    public function all(string $entity, string $organizationId, bool $publicOnly = false): array {
        $table = $this->table($entity);
        $query = $this->database->query();
        $query->select('*')->from($table)
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)));
        if ($publicOnly) {
            $query->andWhere($query->expr()->eq('active', $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL)));
            if ($entity === 'services') {
                $query->andWhere($query->expr()->eq('visibility', $query->createNamedParameter('public')));
            } elseif ($entity === 'staff') {
                $query->andWhere($query->expr()->eq('public_booking', $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL)));
            }
        }
        $order = $entity === 'staff' ? 'display_name' : 'name';
        $query->orderBy($order, 'ASC');
        return array_map(fn (array $row): array => $this->normalize($entity, $row), $this->database->fetchAll($query));
    }

    /** @return array<string, mixed> */
    public function require(string $entity, string $organizationId, string $publicId): array {
        $query = $this->database->query();
        $query->select('*')->from($this->table($entity))
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('public_id', $query->createNamedParameter($publicId)));
        $row = $this->database->fetchOne($query);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The requested catalog item was not found.'));
        }
        return $this->normalize($entity, $row);
    }

    /** @return array<string, mixed> */
    public function requireServiceBySlug(string $organizationId, string $slug): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_services')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('slug', $query->createNamedParameter($slug)));
        $row = $this->database->fetchOne($query);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The requested service was not found.'));
        }
        return $this->normalize('services', $row);
    }

    /** @return array<string, mixed> */
    public function requireInternal(string $entity, string $organizationId, int $id): array {
        $query = $this->database->query();
        $query->select('*')->from($this->table($entity))
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('id', $query->createNamedParameter($id, IQueryBuilder::PARAM_INT)));
        $row = $this->database->fetchOne($query);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The requested catalog item was not found.'));
        }
        return $this->normalize($entity, $row);
    }

    /** @param array<string, mixed> $values
     *  @return array<string, mixed>
     */
    public function create(string $entity, string $organizationId, string $publicId, array $values, int $now): array {
        $query = $this->database->query();
        $parameters = [
            'organization_id' => $query->createNamedParameter($organizationId),
            'public_id' => $query->createNamedParameter($publicId),
            'created_at' => $query->createNamedParameter($now, IQueryBuilder::PARAM_INT),
            'updated_at' => $query->createNamedParameter($now, IQueryBuilder::PARAM_INT),
        ];
        foreach ($values as $column => $value) {
            $parameters[$column] = $query->createNamedParameter($value, $this->parameterType($value));
        }
        $query->insert($this->table($entity))->values($parameters)->executeStatement();
        return $this->require($entity, $organizationId, $publicId);
    }

    /** @param array<string, mixed> $values
     *  @return array<string, mixed>
     */
    public function update(string $entity, string $organizationId, string $publicId, array $values, int $now): array {
        $this->require($entity, $organizationId, $publicId);
        $query = $this->database->query();
        $query->update($this->table($entity));
        foreach ($values as $column => $value) {
            $query->set($column, $query->createNamedParameter($value, $this->parameterType($value)));
        }
        $query->set('updated_at', $query->createNamedParameter($now, IQueryBuilder::PARAM_INT))
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('public_id', $query->createNamedParameter($publicId)))
            ->executeStatement();
        return $this->require($entity, $organizationId, $publicId);
    }

    /** @param list<string> $staffPublicIds */
    public function replaceServiceStaff(string $organizationId, int $serviceId, array $staffPublicIds): void {
        $this->replaceLinks('appt_service_staff', 'staff_id', 'staff', $organizationId, $serviceId, $staffPublicIds);
    }

    /** @param list<string> $locationPublicIds */
    public function replaceServiceLocations(string $organizationId, int $serviceId, array $locationPublicIds): void {
        $this->replaceLinks('appt_service_loc', 'location_id', 'locations', $organizationId, $serviceId, $locationPublicIds);
    }

    /** @param list<array{resourceId: string, quantity: int}> $requirements */
    public function replaceResourceRequirements(string $organizationId, int $serviceId, array $requirements): void {
        $delete = $this->database->query();
        $delete->delete('appt_resource_req')
            ->where($delete->expr()->eq('organization_id', $delete->createNamedParameter($organizationId)))
            ->andWhere($delete->expr()->eq('service_id', $delete->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
        foreach ($requirements as $requirement) {
            $resource = $this->require('resources', $organizationId, $requirement['resourceId']);
            if ($requirement['quantity'] > (int)$resource['capacity']) {
                throw new \OCA\Appointments\Exception\ValidationException($this->l10n->t('A resource requirement exceeds the resource capacity.'));
            }
            $query = $this->database->query();
            $query->insert('appt_resource_req')->values([
                'organization_id' => $query->createNamedParameter($organizationId),
                'service_id' => $query->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT),
                'resource_id' => $query->createNamedParameter((int)$resource['id'], IQueryBuilder::PARAM_INT),
                'quantity' => $query->createNamedParameter($requirement['quantity'], IQueryBuilder::PARAM_INT),
            ])->executeStatement();
        }
    }

    /** @return list<string> */
    public function serviceStaffIds(string $organizationId, int $serviceId): array {
        return $this->linkedPublicIds('appt_service_staff', 'staff_id', 'appt_staff', $organizationId, $serviceId);
    }

    /** @return list<string> */
    public function serviceLocationIds(string $organizationId, int $serviceId): array {
        return $this->linkedPublicIds('appt_service_loc', 'location_id', 'appt_locations', $organizationId, $serviceId);
    }

    /** @param list<string> $locationPublicIds */
    public function replaceStaffLocations(string $organizationId, int $staffId, array $locationPublicIds): void {
        $delete = $this->database->query();
        $delete->delete('appt_staff_loc')
            ->where($delete->expr()->eq('organization_id', $delete->createNamedParameter($organizationId)))
            ->andWhere($delete->expr()->eq('staff_id', $delete->createNamedParameter($staffId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
        foreach (array_values(array_unique($locationPublicIds)) as $publicId) {
            $location = $this->require('locations', $organizationId, $publicId);
            $query = $this->database->query();
            $query->insert('appt_staff_loc')->values([
                'organization_id' => $query->createNamedParameter($organizationId),
                'staff_id' => $query->createNamedParameter($staffId, IQueryBuilder::PARAM_INT),
                'location_id' => $query->createNamedParameter((int)$location['id'], IQueryBuilder::PARAM_INT),
            ])->executeStatement();
        }
    }

    /** @return list<string> */
    public function staffLocationIds(string $organizationId, int $staffId): array {
        $query = $this->database->query();
        $query->select('l.public_id')->from('appt_staff_loc', 'sl')
            ->innerJoin('sl', 'appt_locations', 'l', $query->expr()->andX(
                $query->expr()->eq('l.id', 'sl.location_id'),
                $query->expr()->eq('l.organization_id', 'sl.organization_id'),
            ))
            ->where($query->expr()->eq('sl.organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('sl.staff_id', $query->createNamedParameter($staffId, IQueryBuilder::PARAM_INT)))
            ->orderBy('l.public_id', 'ASC');
        return array_map(static fn (array $row): string => (string)$row['public_id'], $this->database->fetchAll($query));
    }

    /** @return list<array{resourceId: string, quantity: int, resourceInternalId: int}> */
    public function resourceRequirements(string $organizationId, int $serviceId): array {
        $query = $this->database->query();
        $query->select('r.public_id', 'r.id', 'q.quantity')->from('appt_resource_req', 'q')
            ->innerJoin('q', 'appt_resources', 'r', $query->expr()->andX(
                $query->expr()->eq('r.id', 'q.resource_id'),
                $query->expr()->eq('r.organization_id', 'q.organization_id'),
            ))
            ->where($query->expr()->eq('q.organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('q.service_id', $query->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)))
            ->orderBy('r.name', 'ASC');
        return array_map(static fn (array $row): array => [
            'resourceId' => (string)$row['public_id'],
            'quantity' => (int)$row['quantity'],
            'resourceInternalId' => (int)$row['id'],
        ], $this->database->fetchAll($query));
    }

    /** @return list<array<string, mixed>> */
    public function formFields(string $organizationId, int $serviceId, bool $publicOnly): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_form_fields')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('service_id', $query->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->eq('active', $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL)));
        if ($publicOnly) {
            $query->andWhere($query->expr()->eq('visibility', $query->createNamedParameter('public')));
        }
        $query->orderBy('sort_order', 'ASC');
        return array_map(static function (array $row): array {
            $validation = json_decode((string)$row['validation_json'], true);
            return [
                'id' => (string)$row['public_id'],
                'type' => (string)$row['field_type'],
                'label' => (string)$row['label'],
                'helpText' => (string)$row['help_text'],
                'required' => Database::bool($row['required']),
                'order' => (int)$row['sort_order'],
                'visibility' => (string)$row['visibility'],
                'validation' => is_array($validation) ? $validation : [],
            ];
        }, $this->database->fetchAll($query));
    }

    /** @return list<array<string,mixed>> */
    public function formFieldDefinitions(string $organizationId, int $serviceId, bool $publicOnly): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_form_fields')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('service_id', $query->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->eq('active', $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL)));
        if ($publicOnly) {
            $query->andWhere($query->expr()->eq('visibility', $query->createNamedParameter('public')));
        }
        $query->orderBy('sort_order', 'ASC');
        return array_map(static function (array $row): array {
            try {
                $validation = json_decode((string)$row['validation_json'], true, 8, JSON_THROW_ON_ERROR);
            } catch (\JsonException) {
                $validation = [];
            }
            return [
                'internalId' => (int)$row['id'], 'id' => (string)$row['public_id'], 'type' => (string)$row['field_type'],
                'label' => (string)$row['label'], 'required' => Database::bool($row['required']),
                'visibility' => (string)$row['visibility'], 'validation' => is_array($validation) ? $validation : [],
            ];
        }, $this->database->fetchAll($query));
    }

    /** @param list<array<string, mixed>> $fields */
    public function replaceFormFields(string $organizationId, int $serviceId, array $fields, Identifiers $identifiers): void {
        $existingQuery = $this->database->query();
        $existingQuery->select('id', 'public_id')->from('appt_form_fields')
            ->where($existingQuery->expr()->eq('organization_id', $existingQuery->createNamedParameter($organizationId)))
            ->andWhere($existingQuery->expr()->eq('service_id', $existingQuery->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)));
        $existing = [];
        foreach ($this->database->fetchAll($existingQuery) as $row) {
            $existing[(string)$row['public_id']] = (int)$row['id'];
        }

        // Historical answers retain their field relation and label when fields are removed.
        $deactivate = $this->database->query();
        $deactivate->update('appt_form_fields')
            ->set('active', $deactivate->createNamedParameter(false, IQueryBuilder::PARAM_BOOL))
            ->where($deactivate->expr()->eq('organization_id', $deactivate->createNamedParameter($organizationId)))
            ->andWhere($deactivate->expr()->eq('service_id', $deactivate->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
        $seen = [];
        foreach ($fields as $field) {
            $requestedId = isset($field['id']) ? (string)$field['id'] : '';
            if ($requestedId !== '' && (!isset($existing[$requestedId]) || isset($seen[$requestedId]))) {
                throw new NotFoundException($this->l10n->t('The requested booking form field was not found.'));
            }
            if ($requestedId !== '') {
                $seen[$requestedId] = true;
                $query = $this->database->query();
                $query->update('appt_form_fields')
                    ->set('field_type', $query->createNamedParameter($field['type']))
                    ->set('label', $query->createNamedParameter($field['label']))
                    ->set('help_text', $query->createNamedParameter($field['helpText']))
                    ->set('required', $query->createNamedParameter($field['required'], IQueryBuilder::PARAM_BOOL))
                    ->set('sort_order', $query->createNamedParameter($field['order'], IQueryBuilder::PARAM_INT))
                    ->set('visibility', $query->createNamedParameter($field['visibility']))
                    ->set('validation_json', $query->createNamedParameter(json_encode($field['validation'], JSON_THROW_ON_ERROR)))
                    ->set('active', $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL))
                    ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
                    ->andWhere($query->expr()->eq('service_id', $query->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)))
                    ->andWhere($query->expr()->eq('id', $query->createNamedParameter($existing[$requestedId], IQueryBuilder::PARAM_INT)))
                    ->executeStatement();
                continue;
            }
            $query = $this->database->query();
            $query->insert('appt_form_fields')->values([
                'organization_id' => $query->createNamedParameter($organizationId),
                'public_id' => $query->createNamedParameter($identifiers->publicId()),
                'service_id' => $query->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT),
                'field_type' => $query->createNamedParameter($field['type']),
                'label' => $query->createNamedParameter($field['label']),
                'help_text' => $query->createNamedParameter($field['helpText']),
                'required' => $query->createNamedParameter($field['required'], IQueryBuilder::PARAM_BOOL),
                'sort_order' => $query->createNamedParameter($field['order'], IQueryBuilder::PARAM_INT),
                'visibility' => $query->createNamedParameter($field['visibility']),
                'validation_json' => $query->createNamedParameter(json_encode($field['validation'], JSON_THROW_ON_ERROR)),
                'active' => $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL),
            ])->executeStatement();
        }
    }

    /** @param list<string> $targetPublicIds */
    private function replaceLinks(string $table, string $targetColumn, string $entity, string $organizationId, int $serviceId, array $targetPublicIds): void {
        $delete = $this->database->query();
        $delete->delete($table)
            ->where($delete->expr()->eq('organization_id', $delete->createNamedParameter($organizationId)))
            ->andWhere($delete->expr()->eq('service_id', $delete->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
        foreach (array_values(array_unique($targetPublicIds)) as $publicId) {
            $target = $this->require($entity, $organizationId, $publicId);
            $query = $this->database->query();
            $query->insert($table)->values([
                'organization_id' => $query->createNamedParameter($organizationId),
                'service_id' => $query->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT),
                $targetColumn => $query->createNamedParameter((int)$target['id'], IQueryBuilder::PARAM_INT),
            ])->executeStatement();
        }
    }

    /** @return list<string> */
    private function linkedPublicIds(string $linkTable, string $targetColumn, string $targetTable, string $organizationId, int $serviceId): array {
        $query = $this->database->query();
        $query->select('t.public_id')->from($linkTable, 'l')
            ->innerJoin('l', $targetTable, 't', $query->expr()->andX(
                $query->expr()->eq('t.id', 'l.' . $targetColumn),
                $query->expr()->eq('t.organization_id', 'l.organization_id'),
            ))
            ->where($query->expr()->eq('l.organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('l.service_id', $query->createNamedParameter($serviceId, IQueryBuilder::PARAM_INT)))
            ->orderBy('t.public_id', 'ASC');
        return array_map(static fn (array $row): string => (string)$row['public_id'], $this->database->fetchAll($query));
    }

    private function table(string $entity): string {
        if (!isset(self::TABLES[$entity])) {
            throw new \InvalidArgumentException('Unsupported catalog entity.');
        }
        return self::TABLES[$entity];
    }

    private function parameterType(mixed $value): int|string {
        return $value === null ? IQueryBuilder::PARAM_NULL : (is_bool($value) ? IQueryBuilder::PARAM_BOOL : (is_int($value) ? IQueryBuilder::PARAM_INT : IQueryBuilder::PARAM_STR));
    }

    /** @return array<string, mixed> */
    private function normalize(string $entity, array $row): array {
        foreach (['id', 'created_at', 'updated_at'] as $column) {
            if (isset($row[$column])) {
                $row[$column] = (int)$row[$column];
            }
        }
        foreach (['active', 'public_booking', 'phone_required'] as $column) {
            if (array_key_exists($column, $row)) {
                $row[$column] = Database::bool($row[$column]);
            }
        }
        foreach (['duration_min', 'buffer_before', 'buffer_after', 'price_min', 'price_max', 'min_notice_min', 'max_horizon_days', 'cancel_notice_min', 'resched_notice_min', 'capacity', 'location_id'] as $column) {
            if (isset($row[$column])) {
                $row[$column] = (int)$row[$column];
            }
        }
        return $row;
    }
}
