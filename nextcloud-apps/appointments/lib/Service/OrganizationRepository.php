<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\Exception\NotFoundException;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IL10N;

final class OrganizationRepository {
    public function __construct(private Database $database, private IL10N $l10n) {
    }

    /** @return array<string, mixed> */
    public function create(array $values): array {
        $query = $this->database->query();
        $query->insert('appt_org')->values([
            'organization_id' => $query->createNamedParameter($values['organization_id']),
            'slug' => $query->createNamedParameter($values['slug']),
            'name' => $query->createNamedParameter($values['name']),
            'description' => $query->createNamedParameter($values['description']),
            'contact_info' => $query->createNamedParameter(''),
            'timezone' => $query->createNamedParameter($values['timezone']),
            'locale' => $query->createNamedParameter($values['locale']),
            'admin_group' => $query->createNamedParameter($values['admin_group']),
            'manager_group' => $query->createNamedParameter($values['manager_group']),
            'readonly_group' => $query->createNamedParameter($values['readonly_group']),
            'public_enabled' => $query->createNamedParameter(false, IQueryBuilder::PARAM_BOOL),
            'active' => $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL),
            'slot_interval' => $query->createNamedParameter(15, IQueryBuilder::PARAM_INT),
            'min_form_seconds' => $query->createNamedParameter(3, IQueryBuilder::PARAM_INT),
            'retention_days' => $query->createNamedParameter(730, IQueryBuilder::PARAM_INT),
            'created_at' => $query->createNamedParameter($values['created_at'], IQueryBuilder::PARAM_INT),
            'updated_at' => $query->createNamedParameter($values['created_at'], IQueryBuilder::PARAM_INT),
        ])->executeStatement();
        return $this->requireById($values['organization_id']);
    }

    /** @return array<string, mixed> */
    public function requireById(string $organizationId): array {
        $row = $this->findBy('organization_id', $organizationId, false);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The organization was not found.'));
        }
        return $row;
    }

    /** @return array<string, mixed> */
    public function requirePublicBySlug(string $slug): array {
        $row = $this->findBy('slug', $slug, true);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The booking page was not found.'));
        }
        return $row;
    }

    /** @return list<array<string, mixed>> */
    public function allActive(): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_org')
            ->where($query->expr()->eq('active', $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL)))
            ->orderBy('name', 'ASC');
        return array_map($this->normalize(...), $this->database->fetchAll($query));
    }

    /** @return list<array<string,mixed>> */
    public function all(): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_org')->orderBy('name', 'ASC');
        return array_map($this->normalize(...), $this->database->fetchAll($query));
    }

    /** @param list<string> $groupIds */
    public function anyRoleGroupAssigned(array $groupIds): bool {
        if ($groupIds === []) {
            return false;
        }
        $query = $this->database->query();
        $conditions = [];
        foreach (['admin_group', 'manager_group', 'readonly_group'] as $column) {
            $conditions[] = $query->expr()->in($column, $query->createNamedParameter($groupIds, IQueryBuilder::PARAM_STR_ARRAY));
        }
        $query->select('organization_id')->from('appt_org')
            ->where($query->expr()->orX(...$conditions))->setMaxResults(1);
        return $this->database->fetchOne($query) !== null;
    }

    /** @return array<string, mixed> */
    public function lock(string $organizationId): array {
        $query = $this->database->query();
        $query->select('*')->from('appt_org')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->forUpdate();
        $row = $this->database->fetchOne($query);
        if ($row === null) {
            throw new NotFoundException($this->l10n->t('The organization was not found.'));
        }
        return $this->normalize($row);
    }

    /** @return array<string, mixed> */
    public function updateSettings(string $organizationId, array $values, int $now): array {
        $allowed = [
            'name', 'description', 'contact_info', 'timezone', 'locale', 'admin_group', 'manager_group', 'readonly_group',
            'public_enabled', 'active', 'slot_interval', 'min_form_seconds', 'retention_days', 'privacy_url',
            'imprint_url', 'confirmation_text', 'accent_color',
        ];
        $query = $this->database->query();
        $query->update('appt_org');
        foreach ($allowed as $column) {
            if (!array_key_exists($column, $values)) {
                continue;
            }
            $type = in_array($column, ['public_enabled', 'active'], true)
                ? IQueryBuilder::PARAM_BOOL
                : (in_array($column, ['slot_interval', 'min_form_seconds', 'retention_days'], true)
                    ? IQueryBuilder::PARAM_INT
                    : IQueryBuilder::PARAM_STR);
            $query->set($column, $query->createNamedParameter($values[$column], $type));
        }
        $query->set('updated_at', $query->createNamedParameter($now, IQueryBuilder::PARAM_INT))
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->executeStatement();
        return $this->requireById($organizationId);
    }

    /** @return array<string, mixed>|null */
    private function findBy(string $column, string $value, bool $publicOnly): ?array {
        $query = $this->database->query();
        $query->select('*')->from('appt_org')
            ->where($query->expr()->eq($column, $query->createNamedParameter($value)));
        if ($publicOnly) {
            $query->andWhere($query->expr()->eq('active', $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL)))
                ->andWhere($query->expr()->eq('public_enabled', $query->createNamedParameter(true, IQueryBuilder::PARAM_BOOL)));
        }
        $row = $this->database->fetchOne($query);
        return $row === null ? null : $this->normalize($row);
    }

    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    private function normalize(array $row): array {
        foreach (['public_enabled', 'active'] as $column) {
            $row[$column] = Database::bool($row[$column]);
        }
        foreach (['slot_interval', 'min_form_seconds', 'retention_days', 'created_at', 'updated_at'] as $column) {
            $row[$column] = (int)$row[$column];
        }
        return $row;
    }
}
