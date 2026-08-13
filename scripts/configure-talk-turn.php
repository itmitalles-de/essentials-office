<?php

declare(strict_types=1);

use OCP\IConfig;

// Executed through PHP stdin inside the Nextcloud app container. The root-only
// TURN secret is read from its read-only Compose mount, never argv or logs.
require_once '/var/www/html/lib/base.php';

$server = getenv('TURN_SERVER');
if (!is_string($server) || preg_match('/^[A-Za-z0-9.-]+:[0-9]{1,5}$/D', $server) !== 1) {
    fwrite(STDERR, "configure-talk-turn: invalid TURN_SERVER\n");
    exit(1);
}
$secretPath = '/run/secrets/talk-turn-shared';
if (!is_file($secretPath) || is_link($secretPath)) {
    fwrite(STDERR, "configure-talk-turn: protected secret mount is unavailable\n");
    exit(1);
}
$secret = trim((string)file_get_contents($secretPath));
if (preg_match('/^[a-fA-F0-9]{64}$/D', $secret) !== 1) {
    fwrite(STDERR, "configure-talk-turn: protected secret has an invalid format\n");
    exit(1);
}

/** @var IConfig $config */
$config = \OC::$server->get(IConfig::class);
$raw = $config->getAppValue('spreed', 'turn_servers', '[]');
try {
    $decoded = json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    fwrite(STDERR, "configure-talk-turn: existing Talk TURN configuration is invalid\n");
    exit(1);
}
if (!is_array($decoded)) {
    fwrite(STDERR, "configure-talk-turn: existing Talk TURN configuration has an invalid shape\n");
    exit(1);
}
$servers = array_values(array_filter(
    $decoded,
    static fn (mixed $entry): bool => !is_array($entry)
        || ($entry['schemes'] ?? null) !== 'turn'
        || ($entry['server'] ?? null) !== $server
        || ($entry['protocols'] ?? null) !== 'udp,tcp',
));
$servers[] = [
    'schemes' => 'turn',
    'server' => $server,
    'secret' => $secret,
    'protocols' => 'udp,tcp',
];
$config->setAppValue('spreed', 'turn_servers', json_encode($servers, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES));
$secret = str_repeat("\0", strlen($secret));
unset($secret);
fwrite(STDOUT, "configure-talk-turn: protected Nextcloud setting updated\n");
