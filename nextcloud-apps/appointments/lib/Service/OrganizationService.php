<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\Exception\ValidationException;
use OCP\IGroupManager;
use OCP\IL10N;

final class OrganizationService {
    public function __construct(
        private OrganizationRepository $organizations,
        private AuthorizationService $authorization,
        private Identifiers $identifiers,
        private InputValidator $validator,
        private IGroupManager $groupManager,
        private AuditService $audit,
        private Database $database,
        private IL10N $l10n,
    ) {
    }

    /** @return array<string, mixed> */
    public function create(array $input): array {
        $this->authorization->assertGlobalAdmin();
        $slug = $this->validator->slug($this->validator->string($input, 'slug', 80));
        $groupPrefix = 'appointments-' . $slug;
        // Role group identifiers are derived from the unique organization slug.
        // Accepting arbitrary group IDs here would make cross-column uniqueness
        // and concurrent tenant creation needlessly difficult to prove safe.
        $adminGroup = $groupPrefix . '-admin';
        $managerGroup = $groupPrefix . '-manager';
        $readonlyGroup = $groupPrefix . '-readonly';
        if (count(array_unique([$adminGroup, $managerGroup, $readonlyGroup])) !== 3) {
            throw new ValidationException($this->l10n->t('Organization role groups must be distinct.'));
        }
        if ($this->organizations->anyRoleGroupAssigned([$adminGroup, $managerGroup, $readonlyGroup])) {
            throw new ValidationException($this->l10n->t('An organization role group is already assigned to another organization.'));
        }
        foreach ([$adminGroup, $managerGroup, $readonlyGroup] as $groupId) {
            if ($this->groupManager->get($groupId) === null && $this->groupManager->createGroup($groupId) === null) {
                throw new ValidationException($this->l10n->t('An organization role group could not be created.'));
            }
        }
        $now = time();
        $organizationId = $this->identifiers->publicId();
        $organization = $this->database->transaction(function () use ($organizationId, $slug, $input, $adminGroup, $managerGroup, $readonlyGroup, $now): array {
            $created = $this->organizations->create([
                'organization_id' => $organizationId,
                'slug' => $slug,
                'name' => $this->validator->string($input, 'name', 255),
                'description' => $this->validator->string($input, 'description', 10000, false),
                'timezone' => $this->validator->timezone($input, 'timezone'),
                'locale' => $this->validator->enum($input, 'locale', ['de', 'en'], 'de'),
                'admin_group' => $adminGroup,
                'manager_group' => $managerGroup,
                'readonly_group' => $readonlyGroup,
                'created_at' => $now,
            ]);
            $this->audit->record($organizationId, 'organization.created', 'user', 'organization', $organizationId);
            return $created;
        });
        return $this->present($organization);
    }

    /** @return list<array<string, mixed>> */
    public function context(): array {
        $organizations = [];
        foreach ($this->organizations->allActive() as $organization) {
            $permissions = $this->authorization->permissions((string)$organization['organization_id']);
            if ($permissions !== []) {
                $item = $this->present($organization);
                $item['permissions'] = $permissions;
                $item['currentStaffId'] = $this->authorization->staffIdForCurrentUser((string)$organization['organization_id']);
                $item['currentStaffPublicId'] = $this->authorization->staffPublicIdForCurrentUser((string)$organization['organization_id']);
                $organizations[] = $item;
            }
        }
        return $organizations;
    }

    /** @return array<string, mixed> */
    public function updateSettings(string $organizationId, array $input): array {
        $this->authorization->assert($organizationId, AuthorizationService::MANAGE_SETTINGS);
        $values = [];
        $stringMap = [
            'name' => ['name', 255], 'description' => ['description', 10000],
            'contactInfo' => ['contact_info', 5000],
            'privacyUrl' => ['privacy_url', 1024], 'imprintUrl' => ['imprint_url', 1024],
            'confirmationText' => ['confirmation_text', 10000], 'accentColor' => ['accent_color', 16],
        ];
        foreach ($stringMap as $inputKey => [$column, $max]) {
            if (array_key_exists($inputKey, $input)) {
                $values[$column] = $this->validator->string($input, $inputKey, $max, $inputKey === 'name');
            }
        }
        foreach (['privacy_url', 'imprint_url'] as $urlColumn) {
            if (array_key_exists($urlColumn, $values)) {
                $values[$urlColumn] = $this->validator->httpsUrl((string)$values[$urlColumn]);
            }
        }
        if (isset($input['timezone'])) {
            $values['timezone'] = $this->validator->timezone($input, 'timezone');
        }
        if (isset($input['locale'])) {
            $values['locale'] = $this->validator->enum($input, 'locale', ['de', 'en'], 'de');
        }
        foreach (['publicEnabled' => 'public_enabled', 'active' => 'active'] as $inputKey => $column) {
            if (array_key_exists($inputKey, $input)) {
                $values[$column] = $this->validator->boolean($input, $inputKey);
            }
        }
        foreach ([
            'slotInterval' => ['slot_interval', 5, 30],
            'minimumFormSeconds' => ['min_form_seconds', 2, 120],
            'retentionDays' => ['retention_days', 30, 3650],
        ] as $inputKey => [$column, $minimum, $maximum]) {
            if (array_key_exists($inputKey, $input)) {
                $values[$column] = $this->validator->integer($input, $inputKey, $minimum, $maximum);
            }
        }
        if (isset($values['slot_interval']) && !in_array($values['slot_interval'], [5, 10, 15, 30], true)) {
            throw new ValidationException($this->l10n->t('The slot interval is not supported.'));
        }
        if (isset($values['accent_color']) && !preg_match('/^#[0-9a-fA-F]{6}$/D', $values['accent_color'])) {
            throw new ValidationException($this->l10n->t('The accent color is invalid.'));
        }
        $organization = $this->database->transaction(function () use ($organizationId, $values): array {
            $current = $this->organizations->lock($organizationId);
            $willBePublic = $values['public_enabled'] ?? (bool)$current['public_enabled'];
            $privacyUrl = (string)($values['privacy_url'] ?? $current['privacy_url']);
            if ($willBePublic && $privacyUrl === '') {
                throw new ValidationException($this->l10n->t('A valid privacy policy URL is required before public booking can be enabled.'));
            }
            $updated = $this->organizations->updateSettings($organizationId, $values, time());
            $this->audit->record($organizationId, 'organization.settings_updated', 'user', 'organization', $organizationId);
            return $updated;
        });
        return $this->present($organization);
    }

    /** @param array<string, mixed> $row
     *  @return array<string, mixed>
     */
    public function present(array $row): array {
        return [
            'id' => (string)$row['organization_id'],
            'slug' => (string)$row['slug'],
            'name' => (string)$row['name'],
            'description' => (string)$row['description'],
            'contactInfo' => (string)$row['contact_info'],
            'timezone' => (string)$row['timezone'],
            'locale' => (string)$row['locale'],
            'publicEnabled' => (bool)$row['public_enabled'],
            'active' => (bool)$row['active'],
            'slotInterval' => (int)$row['slot_interval'],
            'minimumFormSeconds' => (int)$row['min_form_seconds'],
            'retentionDays' => (int)$row['retention_days'],
            'privacyUrl' => (string)$row['privacy_url'],
            'imprintUrl' => (string)$row['imprint_url'],
            'confirmationText' => (string)$row['confirmation_text'],
            'accentColor' => (string)$row['accent_color'],
        ];
    }

    /** @param array<string,mixed> $row
     *  @return array<string,mixed>
     */
    public function presentPublic(array $row): array {
        return [
            'slug' => (string)$row['slug'], 'name' => (string)$row['name'],
            'description' => (string)$row['description'], 'contactInfo' => (string)$row['contact_info'],
            'timezone' => (string)$row['timezone'],
            'locale' => (string)$row['locale'], 'privacyUrl' => (string)$row['privacy_url'],
            'imprintUrl' => (string)$row['imprint_url'], 'confirmationText' => (string)$row['confirmation_text'],
            'accentColor' => (string)$row['accent_color'],
        ];
    }
}
