<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Service;

use OCP\App\IAppManager;
use OCP\IGroupManager;
use OCP\IUser;
use RuntimeException;
use Throwable;

final class ModuleService {
    public function __construct(
        private ManifestRepository $manifests,
        private StateStore $stateStore,
        private HealthService $healthService,
        private AuditService $auditService,
        private IAppManager $appManager,
        private IGroupManager $groupManager,
    ) {
    }

    /** @return array<string, mixed> */
    public function catalog(): array {
        $catalog = $this->manifests->catalog();
        $catalog['modules'] = $this->listForAdmin();
        return $catalog;
    }

    /** @return list<array<string, mixed>> */
    public function listForAdmin(): array {
        return array_map(fn (array $module): array => $this->status($module['id']), $this->manifests->modules());
    }

    /** @return list<array<string, mixed>> */
    public function listForUser(IUser $user): array {
        if ($this->groupManager->isInGroup($user->getUID(), 'admin')) {
            return $this->listForAdmin();
        }
        $visible = [];
        foreach ($this->manifests->modules() as $module) {
            $status = $this->status($module['id']);
            if ($status['state'] !== 'enabled' || $status['active'] !== true) {
                continue;
            }
            $entitled = in_array('all-authenticated', $status['visibility'], true);
            foreach ($status['visibility'] as $group) {
                if ($group !== 'all-authenticated' && $this->groupManager->isInGroup($user->getUID(), $group)) {
                    $entitled = true;
                    break;
                }
            }
            if ($entitled) {
                unset($status['diagnostics'], $status['configuration']);
                $visible[] = $status;
            }
        }
        return $visible;
    }

    /** @return array<string, mixed> */
    public function status(string $id): array {
        $module = $this->manifests->module($id);
        $readiness = $this->healthService->readiness($module);
        $desired = $this->stateStore->desired($module);
        $active = $module['required'] === true ? $this->healthService->cachedHealthIsFresh($module) : $this->stateStore->active($id);
        $health = $this->stateStore->health($id);
        $fresh = $this->healthService->cachedHealthIsFresh($module);

        if (!$readiness['installed']) {
            $state = 'not_installed';
        } elseif (!$readiness['configurationReady']) {
            $state = 'needs_configuration';
        } elseif (!$desired && $module['required'] !== true) {
            $state = 'disabled';
        } elseif ($active && $fresh) {
            $state = 'enabled';
        } else {
            $state = 'degraded';
        }

        $visibility = $this->stateStore->visibility($id, $module['groups']['default']);
        return [
            'id' => $id,
            'version' => $module['version'],
            'group' => $module['group'],
            'displayName' => $module['displayName'],
            'description' => $module['description'],
            'type' => $module['type'],
            'required' => $module['required'],
            'state' => $state,
            'desired' => $desired,
            'active' => $active && $fresh,
            'visibility' => $visibility,
            'allowedGroups' => $module['groups']['allowed'],
            'serviceUrl' => $state === 'enabled' ? $this->healthService->safeServiceUrl($module) : null,
            'configuration' => [
                'ready' => $readiness['configurationReady'],
                'secretReady' => $this->stateStore->secretReady($id),
                'requirements' => array_map(static fn (array $requirement): array => [
                    'key' => $requirement['key'],
                    'type' => $requirement['type'],
                    'required' => $requirement['required'],
                ], $module['configuration']['requirements']),
            ],
            'health' => [
                'ok' => $health['ok'],
                'fresh' => $fresh,
                'checkedAt' => $health['checkedAt'],
                'message' => $health['message'],
            ],
            'diagnostics' => [
                'issues' => $readiness['issues'],
                'checks' => $health['checks'],
                'dependencies' => $module['dependencies'],
                'conflicts' => $module['conflicts'],
                'nextcloudApps' => array_column($module['nextcloudApps'], 'id'),
                'composeServices' => $module['composeServices'],
            ],
        ];
    }

    /** @return array<string, mixed> */
    public function enable(string $id, string $actor): array {
        $module = $this->manifests->module($id);
        $this->stateStore->setDesired($id, true);
        try {
            foreach ($module['dependencies'] as $dependency) {
                if ($this->status($dependency)['state'] !== 'enabled') {
                    throw new RuntimeException('Dependency is not enabled: ' . $dependency);
                }
            }
            foreach ($module['conflicts'] as $conflict) {
                if ($this->status($conflict)['active'] === true) {
                    throw new RuntimeException('Conflicting module is active: ' . $conflict);
                }
            }
            $readiness = $this->healthService->readiness($module);
            if (!$readiness['installed']) {
                throw new RuntimeException('The module is not installed or an app version is incompatible.');
            }
            if (!$readiness['configurationReady']) {
                throw new RuntimeException('The module still needs configuration.');
            }
            $this->applyAppVisibility($module);
            $health = $this->healthService->check($module);
            if (!$health['ok']) {
                $this->stateStore->setActive($id, false);
                throw new RuntimeException('The module health check failed; it remains hidden.');
            }
            $this->stateStore->setActive($id, true);
            $this->auditService->record($actor, $id, 'enable', 'success', ['groups' => implode(',', $this->visibility($module))]);
            return $this->status($id);
        } catch (Throwable $exception) {
            $this->stateStore->setActive($id, false);
            if ($module['required'] !== true) {
                try {
                    $this->removeModuleAppEntitlements($module);
                } catch (Throwable) {
                    // Logical activation remains false even if app entitlement rollback needs repair.
                }
            }
            $this->auditService->record($actor, $id, 'enable', 'failed', ['reason' => $this->safeReason($exception)]);
            throw $exception;
        }
    }

    /** @return array<string, mixed> */
    public function disable(string $id, string $actor): array {
        $module = $this->manifests->module($id);
        if ($module['required'] === true || $module['deactivation']['allowed'] !== true) {
            throw new RuntimeException('Required module cannot be disabled: ' . $id);
        }
        $this->stateStore->setActive($id, false);
        $this->stateStore->setDesired($id, false);
        try {
            $this->removeModuleAppEntitlements($module);
            $this->auditService->record($actor, $id, 'disable', 'success', ['dataDeleted' => false, 'serviceStopped' => false]);
            return $this->status($id);
        } catch (Throwable $exception) {
            $this->auditService->record($actor, $id, 'disable', 'failed', ['reason' => $this->safeReason($exception)]);
            throw $exception;
        }
    }

    /** @return array<string, mixed> */
    public function doctor(string $id, string $actor = 'system'): array {
        $module = $this->manifests->module($id);
        try {
            $readiness = $this->healthService->readiness($module);
            if ($this->stateStore->desired($module) && $readiness['installed'] && $readiness['configurationReady']) {
                $this->applyAppVisibility($module);
            }
            $health = $this->healthService->check($module);
            $active = $this->stateStore->desired($module) && $health['ok'];
            $this->stateStore->setActive($id, $active);
            if (!$active && $module['required'] !== true) {
                $this->removeModuleAppEntitlements($module);
            }
            $this->auditService->record($actor, $id, 'doctor', $health['ok'] ? 'success' : 'failed');
            return $this->status($id);
        } catch (Throwable $exception) {
            $this->stateStore->setActive($id, false);
            if ($module['required'] !== true) {
                try {
                    $this->removeModuleAppEntitlements($module);
                } catch (Throwable) {
                    // Keep the module hidden; doctor reports the original failure.
                }
            }
            $this->auditService->record($actor, $id, 'doctor', 'failed', ['reason' => $this->safeReason($exception)]);
            throw $exception;
        }
    }

    /** @param list<string> $groups
     *  @return array<string, mixed>
     */
    public function setVisibility(string $id, array $groups, string $actor): array {
        $module = $this->manifests->module($id);
        $groups = array_values(array_unique($groups));
        if ($groups === [] || array_diff($groups, $module['groups']['allowed']) !== []) {
            throw new RuntimeException('Visibility groups must be a non-empty subset of the manifest allowlist.');
        }
        foreach ($groups as $group) {
            if ($group !== 'all-authenticated' && $this->groupManager->get($group) === null) {
                throw new RuntimeException('Visibility group does not exist: ' . $group);
            }
        }
        $this->stateStore->setVisibility($id, $groups);
        if ($this->stateStore->active($id)) {
            $this->applyAppVisibility($module);
        }
        $this->auditService->record($actor, $id, 'visibility', 'success', ['groups' => implode(',', $groups)]);
        return $this->status($id);
    }

    /** @return array<string, mixed> */
    public function configure(string $id, string $key, string $value, string $actor): array {
        $module = $this->manifests->module($id);
        if ($key === 'secretReady') {
            if ($module['secrets']['requirements'] === []) {
                throw new RuntimeException('This module has no declared secret readiness requirement.');
            }
            $this->stateStore->setSecretReady($id, $this->parseBoolean($value));
        } else {
            $requirement = null;
            foreach ($module['configuration']['requirements'] as $candidate) {
                if ($candidate['key'] === $key) {
                    $requirement = $candidate;
                    break;
                }
            }
            if ($requirement === null) {
                throw new RuntimeException('Unknown configuration key for ' . $id . ': ' . $key);
            }
            $normalized = match ($requirement['type']) {
                'boolean', 'attestation' => $this->parseBoolean($value) ? 'true' : 'false',
                'https-url' => $this->healthService->validHttpsUrl($module, $value) ? $value : throw new RuntimeException('URL must be credential-free HTTPS on an allowed host.'),
                'string' => mb_substr(trim($value), 0, 512),
                default => throw new RuntimeException('Unsupported configuration type.'),
            };
            $this->stateStore->setConfiguration($id, $key, $normalized);
        }
        $this->stateStore->setActive($id, false);
        if ($module['required'] !== true) {
            $this->removeModuleAppEntitlements($module);
        }
        $this->auditService->record($actor, $id, 'configure', 'success', ['key' => $key]);
        return $this->status($id);
    }

    /** @return list<array<string, mixed>> */
    public function audit(int $limit = 50): array {
        return $this->auditService->recent($limit);
    }

    /** @param array<string, mixed> $module */
    private function applyAppVisibility(array $module): void {
        foreach ($module['nextcloudApps'] as $app) {
            if ($this->appManager->getAppInfo($app['id']) === null) {
                throw new RuntimeException('Nextcloud app package is missing: ' . $app['id']);
            }
            $this->applyAppVisibilityForApp($app['id'], $module);
        }
    }

    /** @param array<string, mixed>|null $includingModule */
    private function applyAppVisibilityForApp(string $appId, ?array $includingModule): void {
        $groupIds = [];
        $allAuthenticated = false;
        $platformGlobal = false;
        foreach ($this->manifests->modules() as $candidate) {
            $includedExplicitly = $includingModule !== null && $candidate['id'] === $includingModule['id'];
            if (!$includedExplicitly
                && $candidate['required'] !== true
                && !$this->stateStore->active($candidate['id'])) {
                continue;
            }
            $app = $this->moduleApp($candidate, $appId);
            if ($app === null) {
                continue;
            }
            if (($app['visibilityMode'] ?? 'module-groups') === 'platform-global') {
                $platformGlobal = true;
                continue;
            }
            foreach ($this->visibility($candidate) as $groupId) {
                if ($groupId === 'all-authenticated') {
                    $allAuthenticated = true;
                    continue;
                }
                $group = $this->groupManager->get($groupId);
                if ($group === null && $candidate['groups']['autoCreate'] === true) {
                    $group = $this->groupManager->createGroup($groupId);
                }
                if ($group === null) {
                    throw new RuntimeException('Required visibility group is missing: ' . $groupId);
                }
                $groupIds[$groupId] = $group;
            }
        }
        if ($platformGlobal || $allAuthenticated) {
            $this->appManager->enableApp($appId);
            return;
        }
        if ($groupIds === []) {
            throw new RuntimeException('No active module entitlement exists for app: ' . $appId);
        }
        ksort($groupIds);
        $this->appManager->enableAppForGroups($appId, array_values($groupIds));
    }

    /** @param array<string, mixed> $module */
    private function removeModuleAppEntitlements(array $module): void {
        foreach ($module['nextcloudApps'] as $app) {
            if ($this->appRequiredByAnotherActiveModule($app['id'], $module['id'])) {
                $this->applyAppVisibilityForApp($app['id'], null);
            } elseif (($app['visibilityMode'] ?? 'module-groups') === 'platform-global') {
                // Nextcloud forbids group restriction for protected platform
                // app types such as Teams/circles. Logical module visibility
                // and content ACLs remain restricted; deactivation must not
                // disable or delete the shared platform capability.
                continue;
            } elseif ($this->appManager->isEnabledForAnyone($app['id'])) {
                $this->appManager->disableApp($app['id']);
            }
        }
    }

    /** @param array<string, mixed> $module
     *  @return list<string>
     */
    private function visibility(array $module): array {
        return $this->stateStore->visibility($module['id'], $module['groups']['default']);
    }

    private function appRequiredByAnotherActiveModule(string $appId, string $excludedId): bool {
        foreach ($this->manifests->modules() as $module) {
            if ($module['id'] === $excludedId) {
                continue;
            }
            if ($module['required'] !== true && !$this->stateStore->active($module['id'])) {
                continue;
            }
            foreach ($module['nextcloudApps'] as $app) {
                if ($app['id'] === $appId) {
                    return true;
                }
            }
        }
        return false;
    }

    /** @param array<string, mixed> $module */
    /** @param array<string, mixed> $module
     *  @return array<string, mixed>|null
     */
    private function moduleApp(array $module, string $appId): ?array {
        foreach ($module['nextcloudApps'] as $app) {
            if ($app['id'] === $appId) {
                return $app;
            }
        }
        return null;
    }

    private function parseBoolean(string $value): bool {
        return match (strtolower($value)) {
            'true', '1', 'yes' => true,
            'false', '0', 'no' => false,
            default => throw new RuntimeException('Boolean values must be true or false.'),
        };
    }

    private function safeReason(Throwable $exception): string {
        $message = preg_replace('~https?://[^[:space:]]+~', '[URL]', $exception->getMessage()) ?? 'operation failed';
        return mb_substr($message, 0, 256);
    }
}
