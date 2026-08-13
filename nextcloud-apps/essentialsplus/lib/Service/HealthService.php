<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Service;

use OCP\App\IAppManager;
use OCP\Http\Client\IClientService;
use OCP\ServerVersion;
use Throwable;

final class HealthService {
    public function __construct(
        private IAppManager $appManager,
        private IClientService $clientService,
        private ServerVersion $serverVersion,
        private StateStore $stateStore,
    ) {
    }

    /** @param array<string, mixed> $module
     *  @return array{installed: bool, configurationReady: bool, appsReady: bool, issues: list<string>}
     */
    public function readiness(array $module): array {
        $issues = [];
        $appsReady = true;
        foreach ($module['nextcloudApps'] as $app) {
            $appId = $app['id'];
            try {
                $info = $this->appManager->getAppInfo($appId);
            } catch (Throwable) {
                $info = null;
            }
            if ($info === null) {
                $appsReady = false;
                $issues[] = 'Nextcloud app package missing: ' . $appId;
                continue;
            }
            $version = $this->appManager->getAppVersion($appId);
            if ($version === ''
                || version_compare($version, $app['minVersion'], '<')
                || version_compare($version, $app['maxExclusive'], '>=')) {
                $appsReady = false;
                $issues[] = 'Nextcloud app version incompatible: ' . $appId;
            }
        }

        $configurationReady = true;
        $installed = $module['type'] !== 'external-service' && $module['type'] !== 'external-integration';
        foreach ($module['configuration']['requirements'] as $requirement) {
            if ($requirement['required'] !== true) {
                continue;
            }
            $key = $requirement['key'];
            $value = $this->stateStore->configuration($module['id'], $key);
            if ($key === 'installed') {
                $installed = $value === 'true';
                if (!$installed) {
                    $issues[] = 'External service installation is not attested.';
                }
                continue;
            }
            $valid = match ($requirement['type']) {
                'boolean', 'attestation' => $value === 'true',
                'https-url' => $this->validHttpsUrl($module, $value),
                'string' => $value !== '',
                default => false,
            };
            if (!$valid) {
                $configurationReady = false;
                $issues[] = 'Missing or invalid configuration: ' . $key;
            }
        }
        foreach ($module['secrets']['requirements'] as $requirement) {
            if ($requirement['required'] === true && !$this->stateStore->secretReady($module['id'])) {
                $configurationReady = false;
                $issues[] = 'Protected secret readiness is not attested.';
                break;
            }
        }
        if (!$installed && ($module['type'] === 'external-service' || $module['type'] === 'external-integration')) {
            $configurationReady = false;
        }
        return [
            'installed' => $installed && $appsReady,
            'configurationReady' => $configurationReady,
            'appsReady' => $appsReady,
            'issues' => $issues,
        ];
    }

    /** @param array<string, mixed> $module
     *  @return array{ok: bool, checkedAt: int, message: string, checks: list<array<string, scalar|null>>}
     */
    public function check(array $module, bool $persist = true): array {
        $checks = [];
        $ok = true;
        $version = $this->serverVersion->getVersionString();
        $nextcloudCompatible = !version_compare($version, $module['compatibility']['nextcloud']['min'], '<')
            && version_compare($version, $module['compatibility']['nextcloud']['maxExclusive'], '<');
        $checks[] = ['name' => 'nextcloud-version', 'ok' => $nextcloudCompatible, 'value' => $version];
        $ok = $ok && $nextcloudCompatible;

        $readiness = $this->readiness($module);
        $checks[] = ['name' => 'installed', 'ok' => $readiness['installed'], 'value' => null];
        $checks[] = ['name' => 'configuration', 'ok' => $readiness['configurationReady'], 'value' => null];
        $ok = $ok && $readiness['installed'] && $readiness['configurationReady'];

        foreach ($module['nextcloudApps'] as $app) {
            $enabled = $this->appManager->isEnabledForAnyone($app['id']);
            $checks[] = ['name' => 'app:' . $app['id'], 'ok' => $enabled, 'value' => $enabled ? 'enabled' : 'disabled'];
            $ok = $ok && $enabled;
        }

        if ($module['healthcheck']['kind'] === 'https' && $ok) {
            $key = $module['healthcheck']['endpointConfigurationKey'];
            $url = $this->stateStore->configuration($module['id'], $key);
            $httpOk = false;
            $status = null;
            try {
                $response = $this->clientService->newClient()->get($url, [
                    'timeout' => 8,
                    'connect_timeout' => 4,
                    'allow_redirects' => false,
                    'verify' => true,
                    'headers' => ['Accept' => 'application/json, text/plain;q=0.9, */*;q=0.1'],
                ]);
                $status = $response->getStatusCode();
                $httpOk = in_array($status, $module['healthcheck']['expectedStatuses'], true);
            } catch (Throwable) {
                $httpOk = false;
            }
            $checks[] = ['name' => 'external-health', 'ok' => $httpOk, 'value' => $status];
            $ok = $ok && $httpOk;
        }

        $message = $ok ? 'All declared checks passed.' : 'One or more declared checks failed.';
        if ($persist) {
            $this->stateStore->recordHealth($module['id'], $ok, $checks, $message);
        }
        return ['ok' => $ok, 'checkedAt' => time(), 'message' => $message, 'checks' => $checks];
    }

    /** @param array<string, mixed> $module */
    public function cachedHealthIsFresh(array $module): bool {
        $health = $this->stateStore->health($module['id']);
        return $health['ok']
            && $health['checkedAt'] > 0
            && $health['checkedAt'] + (int)$module['healthcheck']['cacheSeconds'] >= time();
    }

    /** @param array<string, mixed> $module */
    public function safeServiceUrl(array $module): ?string {
        $value = $this->stateStore->configuration($module['id'], 'serviceUrl');
        return $this->validHttpsUrl($module, $value) ? $value : null;
    }

    /** @param array<string, mixed> $module */
    public function validHttpsUrl(array $module, string $value): bool {
        if ($value === '' || filter_var($value, FILTER_VALIDATE_URL) === false) {
            return false;
        }
        $parts = parse_url($value);
        if (!is_array($parts)
            || ($parts['scheme'] ?? '') !== 'https'
            || !isset($parts['host'])
            || isset($parts['user'])
            || isset($parts['pass'])
            || isset($parts['query'])
            || isset($parts['fragment'])
            || filter_var($parts['host'], FILTER_VALIDATE_IP) !== false) {
            return false;
        }
        $suffixes = $module['healthcheck']['allowedHostSuffixes'] ?? ['.itmitalles.de', '.internal'];
        $host = strtolower((string)$parts['host']);
        foreach ($suffixes as $suffix) {
            if (str_ends_with($host, strtolower($suffix))) {
                return true;
            }
        }
        return false;
    }
}
