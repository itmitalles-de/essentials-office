<?php

declare(strict_types=1);

return [
    'routes' => [
        ['name' => 'page#index', 'url' => '/', 'verb' => 'GET'],
        ['name' => 'api#list', 'url' => '/api/v1/modules', 'verb' => 'GET'],
        ['name' => 'api#audit', 'url' => '/api/v1/audit', 'verb' => 'GET'],
        ['name' => 'api#enable', 'url' => '/api/v1/modules/{id}/enable', 'verb' => 'POST'],
        ['name' => 'api#disable', 'url' => '/api/v1/modules/{id}/disable', 'verb' => 'POST'],
        ['name' => 'api#doctor', 'url' => '/api/v1/modules/{id}/doctor', 'verb' => 'POST'],
        ['name' => 'api#visibility', 'url' => '/api/v1/modules/{id}/visibility', 'verb' => 'POST'],
    ],
];
