<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\Exception\ForbiddenException;
use OCP\IGroupManager;
use OCP\IL10N;
use OCP\IUserSession;

final class AuthorizationService {
    public const VIEW = 'appointments.view';
    public const MANAGE_APPOINTMENTS = 'appointments.manage_appointments';
    public const UPDATE_OWN = 'appointments.update_own';
    public const MANAGE_CATALOG = 'appointments.manage_catalog';
    public const MANAGE_AVAILABILITY = 'appointments.manage_availability';
    public const MANAGE_OWN_AVAILABILITY = 'appointments.manage_own_availability';
    public const MANAGE_SETTINGS = 'appointments.manage_settings';

    public function __construct(
        private IUserSession $userSession,
        private IGroupManager $groupManager,
        private OrganizationRepository $organizations,
        private Database $database,
        private IL10N $l10n,
    ) {
    }

    public function currentUserId(): string {
        $uid = $this->userSession->getUser()?->getUID();
        if ($uid === null) {
            throw new ForbiddenException($this->l10n->t('Authentication is required.'));
        }
        return $uid;
    }

    /** @return list<string> */
    public function permissions(string $organizationId): array {
        $organization = $this->organizations->requireById($organizationId);
        $uid = $this->currentUserId();
        if ($this->groupManager->isAdmin($uid) || $this->groupManager->isInGroup($uid, (string)$organization['admin_group'])) {
            return self::permissionsForRole(true, false, false, false);
        }
        if ($this->groupManager->isInGroup($uid, (string)$organization['manager_group'])) {
            return self::permissionsForRole(false, true, false, false);
        }
        if ($this->groupManager->isInGroup($uid, (string)$organization['readonly_group'])) {
            return self::permissionsForRole(false, false, true, false);
        }
        if ($this->staffIdForUser($organizationId, $uid) !== null) {
            return self::permissionsForRole(false, false, false, true);
        }
        return [];
    }

    /** @return list<string> */
    public static function permissionsForRole(bool $administrator, bool $manager, bool $readOnly, bool $staff): array {
        if ($administrator) {
            return [self::VIEW, self::MANAGE_APPOINTMENTS, self::MANAGE_CATALOG, self::MANAGE_AVAILABILITY, self::MANAGE_SETTINGS];
        }
        if ($manager) {
            return [self::VIEW, self::MANAGE_APPOINTMENTS, self::MANAGE_AVAILABILITY];
        }
        if ($readOnly) {
            return [self::VIEW];
        }
        if ($staff) {
            return [self::VIEW, self::UPDATE_OWN, self::MANAGE_OWN_AVAILABILITY];
        }
        return [];
    }

    public function assert(string $organizationId, string $permission): void {
        if (!in_array($permission, $this->permissions($organizationId), true)) {
            throw new ForbiddenException($this->l10n->t('You are not allowed to perform this action.'));
        }
    }

    public function assertGlobalAdmin(): void {
        if (!$this->isGlobalAdmin()) {
            throw new ForbiddenException($this->l10n->t('Administrator permissions are required.'));
        }
    }

    public function isGlobalAdmin(): bool {
        return $this->groupManager->isAdmin($this->currentUserId());
    }

    public function staffIdForCurrentUser(string $organizationId): ?int {
        return $this->staffIdForUser($organizationId, $this->currentUserId());
    }

    public function staffPublicIdForCurrentUser(string $organizationId): ?string {
        $query = $this->database->query();
        $query->select('public_id')->from('appt_staff')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('user_uid', $query->createNamedParameter($this->currentUserId())))
            ->andWhere($query->expr()->eq('active', $query->createNamedParameter(true, \OCP\DB\QueryBuilder\IQueryBuilder::PARAM_BOOL)))
            ->setMaxResults(1);
        $row = $this->database->fetchOne($query);
        return $row === null ? null : (string)$row['public_id'];
    }

    public function canViewAll(string $organizationId): bool {
        $permissions = $this->permissions($organizationId);
        return in_array(self::MANAGE_APPOINTMENTS, $permissions, true)
            || ($this->isReadOnlyMember($organizationId) && in_array(self::VIEW, $permissions, true));
    }

    public function assertOwnStaff(string $organizationId, int $staffId): void {
        if ($this->staffIdForCurrentUser($organizationId) !== $staffId) {
            throw new ForbiddenException($this->l10n->t('You may only access your own appointments or availability.'));
        }
    }

    private function isReadOnlyMember(string $organizationId): bool {
        $organization = $this->organizations->requireById($organizationId);
        return $this->groupManager->isInGroup($this->currentUserId(), (string)$organization['readonly_group']);
    }

    private function staffIdForUser(string $organizationId, string $uid): ?int {
        $query = $this->database->query();
        $query->select('id')->from('appt_staff')
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('user_uid', $query->createNamedParameter($uid)))
            ->andWhere($query->expr()->eq('active', $query->createNamedParameter(true, \OCP\DB\QueryBuilder\IQueryBuilder::PARAM_BOOL)))
            ->setMaxResults(1);
        $row = $this->database->fetchOne($query);
        return $row === null ? null : (int)$row['id'];
    }
}
