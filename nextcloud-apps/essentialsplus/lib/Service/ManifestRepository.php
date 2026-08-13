<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Service;

use RuntimeException;

final class ManifestRepository {
    /** @var array<string, mixed>|null */
    private ?array $catalog = null;

    public function __construct(private ?string $manifestPath = null) {
        $this->manifestPath ??= dirname(__DIR__, 2) . '/resources/office-modules.json';
    }

    /** @return array<string, mixed> */
    public function catalog(): array {
        if ($this->catalog !== null) {
            return $this->catalog;
        }
        if (!is_file($this->manifestPath) || is_link($this->manifestPath)) {
            throw new RuntimeException('The Essentials+ Office module manifest is missing or unsafe.');
        }
        $raw = file_get_contents($this->manifestPath);
        if ($raw === false) {
            throw new RuntimeException('The Essentials+ Office module manifest cannot be read.');
        }
        try {
            $catalog = json_decode($raw, true, 64, JSON_THROW_ON_ERROR);
        } catch (\JsonException $exception) {
            throw new RuntimeException('The Essentials+ Office module manifest is invalid JSON.', 0, $exception);
        }
        if (!is_array($catalog)) {
            throw new RuntimeException('The Essentials+ Office module manifest must be an object.');
        }
        $this->validate($catalog);
        $this->catalog = $catalog;
        return $catalog;
    }

    /** @return list<array<string, mixed>> */
    public function modules(): array {
        /** @var list<array<string, mixed>> $modules */
        $modules = $this->catalog()['modules'];
        return $modules;
    }

    /** @return array<string, mixed> */
    public function module(string $id): array {
        foreach ($this->modules() as $module) {
            if ($module['id'] === $id) {
                return $module;
            }
        }
        throw new RuntimeException('Unknown Essentials+ Office module: ' . $id);
    }

    /** @return list<array<string, mixed>> */
    public function groups(): array {
        /** @var list<array<string, mixed>> $groups */
        $groups = $this->catalog()['groups'];
        return $groups;
    }

    /** @param array<string, mixed> $catalog */
    private function validate(array $catalog): void {
        $expectedStates = ['not_installed', 'needs_configuration', 'disabled', 'enabled', 'degraded'];
        if (($catalog['schemaVersion'] ?? null) !== '1.0.0'
            || ($catalog['product']['displayName'] ?? null) !== 'Essentials+ Office'
            || ($catalog['states'] ?? null) !== $expectedStates
            || !is_array($catalog['groups'] ?? null)
            || !is_array($catalog['modules'] ?? null)) {
            throw new RuntimeException('The Essentials+ Office module contract header is incompatible.');
        }

        $groupIds = [];
        foreach ($catalog['groups'] as $group) {
            if (!is_array($group) || !is_string($group['id'] ?? null) || isset($groupIds[$group['id']])) {
                throw new RuntimeException('The module contract contains an invalid or duplicate catalog group.');
            }
            $groupIds[$group['id']] = true;
        }

        $moduleIds = [];
        $requiredKeys = [
            'id', 'version', 'group', 'displayName', 'description', 'type', 'required', 'defaultState',
            'dependencies', 'conflicts', 'compatibility', 'configuration', 'secrets', 'groups', 'roles',
            'nextcloudApps', 'composeServices', 'externalServices', 'jobs', 'webhooks', 'healthcheck',
            'dataOwnership', 'backup', 'restore', 'export', 'activation', 'deactivation', 'update',
        ];
        foreach ($catalog['modules'] as $module) {
            if (!is_array($module)) {
                throw new RuntimeException('Every module manifest must be an object.');
            }
            foreach ($requiredKeys as $key) {
                if (!array_key_exists($key, $module)) {
                    throw new RuntimeException('A module manifest is missing required field: ' . $key);
                }
            }
            $id = $module['id'];
            if (!is_string($id) || preg_match('/^[a-z][a-z0-9-]+$/D', $id) !== 1 || isset($moduleIds[$id])) {
                throw new RuntimeException('The module contract contains an invalid or duplicate module ID.');
            }
            if (!isset($groupIds[$module['group']]) || !in_array($module['defaultState'], $expectedStates, true)) {
                throw new RuntimeException('Module ' . $id . ' references an invalid group or state.');
            }
            if (($module['dataOwnership']['sharedDatabase'] ?? null) !== false
                || ($module['deactivation']['deletesData'] ?? null) !== false
                || ($module['deactivation']['stopsService'] ?? null) !== false
                || ($module['activation']['hostControl'] ?? null) !== false) {
                throw new RuntimeException('Module ' . $id . ' violates an Essentials+ Office safety invariant.');
            }
            $moduleIds[$id] = true;
        }
        foreach ($catalog['modules'] as $module) {
            foreach (array_merge($module['dependencies'], $module['conflicts']) as $relatedId) {
                if (!isset($moduleIds[$relatedId])) {
                    throw new RuntimeException('Module ' . $module['id'] . ' references unknown module ' . $relatedId . '.');
                }
            }
        }
    }
}
