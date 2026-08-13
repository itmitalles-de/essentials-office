<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Service;

use OCP\IConfig;

final class StateStore {
    private const APP_ID = 'essentialsplus';

    public function __construct(private IConfig $config) {
    }

    /** @param array<string, mixed> $module */
    public function desired(array $module): bool {
        $default = $module['required'] === true || $module['defaultState'] === 'enabled' ? 'true' : 'false';
        return $this->config->getAppValue(self::APP_ID, 'desired.' . $module['id'], $default) === 'true';
    }

    public function setDesired(string $id, bool $value): void {
        $this->setBoolean('desired.' . $id, $value);
    }

    public function active(string $id): bool {
        return $this->config->getAppValue(self::APP_ID, 'active.' . $id, 'false') === 'true';
    }

    public function setActive(string $id, bool $value): void {
        $this->setBoolean('active.' . $id, $value);
    }

    public function configuration(string $id, string $key): string {
        return $this->config->getAppValue(self::APP_ID, 'configuration.' . $id . '.' . $key, '');
    }

    public function configurationUpdatedAt(string $id, string $key): int {
        return (int)$this->config->getAppValue(self::APP_ID, 'configuration_updated.' . $id . '.' . $key, '0');
    }

    public function setConfiguration(string $id, string $key, string $value): void {
        $this->config->setAppValue(self::APP_ID, 'configuration.' . $id . '.' . $key, $value);
        $this->config->setAppValue(self::APP_ID, 'configuration_updated.' . $id . '.' . $key, (string)time());
    }

    public function secretReady(string $id): bool {
        return $this->config->getAppValue(self::APP_ID, 'secret_ready.' . $id, 'false') === 'true';
    }

    public function setSecretReady(string $id, bool $ready): void {
        $this->setBoolean('secret_ready.' . $id, $ready);
    }

    /** @param list<string> $defaults
     *  @return list<string>
     */
    public function visibility(string $id, array $defaults): array {
        $raw = $this->config->getAppValue(self::APP_ID, 'visibility.' . $id, '');
        if ($raw === '') {
            return $defaults;
        }
        try {
            $groups = json_decode($raw, true, 8, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            return $defaults;
        }
        if (!is_array($groups) || count(array_filter($groups, 'is_string')) !== count($groups)) {
            return $defaults;
        }
        /** @var list<string> $groups */
        return array_values(array_unique($groups));
    }

    /** @param list<string> $groups */
    public function setVisibility(string $id, array $groups): void {
        sort($groups);
        $this->config->setAppValue(
            self::APP_ID,
            'visibility.' . $id,
            json_encode(array_values(array_unique($groups)), JSON_THROW_ON_ERROR),
        );
    }

    /** @param list<array<string, scalar|null>> $checks */
    public function recordHealth(string $id, bool $ok, array $checks, string $message): void {
        $this->setBoolean('health_ok.' . $id, $ok);
        $this->config->setAppValue(self::APP_ID, 'health_checked.' . $id, (string)time());
        $this->config->setAppValue(self::APP_ID, 'health_message.' . $id, mb_substr($message, 0, 512));
        $this->config->setAppValue(self::APP_ID, 'health_checks.' . $id, json_encode($checks, JSON_THROW_ON_ERROR));
    }

    /** @return array{ok: bool, checkedAt: int, message: string, checks: list<array<string, scalar|null>>} */
    public function health(string $id): array {
        $checks = [];
        $raw = $this->config->getAppValue(self::APP_ID, 'health_checks.' . $id, '[]');
        try {
            $decoded = json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
            if (is_array($decoded)) {
                $checks = $decoded;
            }
        } catch (\JsonException) {
            $checks = [];
        }
        return [
            'ok' => $this->config->getAppValue(self::APP_ID, 'health_ok.' . $id, 'false') === 'true',
            'checkedAt' => (int)$this->config->getAppValue(self::APP_ID, 'health_checked.' . $id, '0'),
            'message' => $this->config->getAppValue(self::APP_ID, 'health_message.' . $id, 'not checked'),
            'checks' => $checks,
        ];
    }

    public function setEvidenceTimestamp(string $key, int $timestamp): void {
        $this->config->setAppValue(self::APP_ID, 'evidence.' . $key, (string)$timestamp);
    }

    public function evidenceTimestamp(string $key): int {
        return (int)$this->config->getAppValue(self::APP_ID, 'evidence.' . $key, '0');
    }

    private function setBoolean(string $key, bool $value): void {
        $this->config->setAppValue(self::APP_ID, $key, $value ? 'true' : 'false');
    }
}
