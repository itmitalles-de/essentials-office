<?php

declare(strict_types=1);

return [
    'routes' => [
        ['name' => 'page#index', 'url' => '/', 'verb' => 'GET'],
        ['name' => 'page#book', 'url' => '/book/{organizationSlug}', 'verb' => 'GET'],
        ['name' => 'page#manage', 'url' => '/manage', 'verb' => 'GET'],

        ['name' => 'internal_api#context', 'url' => '/api/v1/context', 'verb' => 'GET'],
        ['name' => 'internal_api#createOrganization', 'url' => '/api/v1/organizations', 'verb' => 'POST'],
        ['name' => 'internal_api#catalog', 'url' => '/api/v1/organizations/{organizationId}/catalog', 'verb' => 'GET'],
        ['name' => 'internal_api#listAppointments', 'url' => '/api/v1/organizations/{organizationId}/appointments', 'verb' => 'GET'],
        ['name' => 'internal_api#searchAppointments', 'url' => '/api/v1/organizations/{organizationId}/appointments/search', 'verb' => 'POST'],
        ['name' => 'internal_api#getAppointment', 'url' => '/api/v1/organizations/{organizationId}/appointments/{appointmentId}', 'verb' => 'GET'],
        ['name' => 'internal_api#createAppointment', 'url' => '/api/v1/organizations/{organizationId}/appointments', 'verb' => 'POST'],
        ['name' => 'internal_api#updateAppointment', 'url' => '/api/v1/organizations/{organizationId}/appointments/{appointmentId}', 'verb' => 'PUT'],
        ['name' => 'internal_api#setAppointmentStatus', 'url' => '/api/v1/organizations/{organizationId}/appointments/{appointmentId}/status', 'verb' => 'POST'],

        ['name' => 'internal_api#createService', 'url' => '/api/v1/organizations/{organizationId}/services', 'verb' => 'POST'],
        ['name' => 'internal_api#updateService', 'url' => '/api/v1/organizations/{organizationId}/services/{id}', 'verb' => 'PUT'],
        ['name' => 'internal_api#createStaff', 'url' => '/api/v1/organizations/{organizationId}/staff', 'verb' => 'POST'],
        ['name' => 'internal_api#updateStaff', 'url' => '/api/v1/organizations/{organizationId}/staff/{id}', 'verb' => 'PUT'],
        ['name' => 'internal_api#createLocation', 'url' => '/api/v1/organizations/{organizationId}/locations', 'verb' => 'POST'],
        ['name' => 'internal_api#updateLocation', 'url' => '/api/v1/organizations/{organizationId}/locations/{id}', 'verb' => 'PUT'],
        ['name' => 'internal_api#createResource', 'url' => '/api/v1/organizations/{organizationId}/resources', 'verb' => 'POST'],
        ['name' => 'internal_api#updateResource', 'url' => '/api/v1/organizations/{organizationId}/resources/{id}', 'verb' => 'PUT'],
        ['name' => 'internal_api#putAvailability', 'url' => '/api/v1/organizations/{organizationId}/availability/{subjectType}/{subjectId}', 'verb' => 'PUT'],
        ['name' => 'internal_api#getAvailability', 'url' => '/api/v1/organizations/{organizationId}/availability/{subjectType}/{subjectId}', 'verb' => 'GET'],
        ['name' => 'internal_api#slots', 'url' => '/api/v1/organizations/{organizationId}/slots', 'verb' => 'GET'],
        ['name' => 'internal_api#putSettings', 'url' => '/api/v1/organizations/{organizationId}/settings', 'verb' => 'PUT'],

        ['name' => 'public_api#catalog', 'url' => '/public/v1/{organizationSlug}/catalog', 'verb' => 'GET'],
        ['name' => 'public_api#slots', 'url' => '/public/v1/{organizationSlug}/slots', 'verb' => 'GET'],
        ['name' => 'public_api#book', 'url' => '/public/v1/{organizationSlug}/book', 'verb' => 'POST'],
        ['name' => 'public_api#manage', 'url' => '/public/v1/manage/view', 'verb' => 'POST'],
        ['name' => 'public_api#manageSlots', 'url' => '/public/v1/manage/slots', 'verb' => 'POST'],
        ['name' => 'public_api#cancel', 'url' => '/public/v1/manage/cancel', 'verb' => 'POST'],
        ['name' => 'public_api#reschedule', 'url' => '/public/v1/manage/reschedule', 'verb' => 'POST'],
        ['name' => 'public_api#updateContact', 'url' => '/public/v1/manage/contact', 'verb' => 'POST'],
        ['name' => 'public_api#export', 'url' => '/public/v1/manage/export', 'verb' => 'POST'],
        ['name' => 'ics#download', 'url' => '/public/v1/manage/ics', 'verb' => 'POST'],
    ],
];
