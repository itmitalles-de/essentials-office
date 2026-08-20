<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use DateTimeImmutable;
use DateTimeZone;
use OCP\IGroupManager;

final class DemoSeedService {
    public function __construct(
        private Database $database,
        private OrganizationRepository $organizations,
        private CatalogRepository $catalog,
        private AvailabilityRepository $availability,
        private AppointmentRepository $appointments,
        private Identifiers $identifiers,
        private AuditService $audit,
        private IGroupManager $groupManager,
    ) {
    }

    /** @return array{id:string,slug:string,created:bool} */
    public function seed(): array {
        $existing = $this->existingOrganization('physiotherapie-beispiel');
        if ($existing !== null) {
            return ['id' => (string)$existing['organization_id'], 'slug' => (string)$existing['slug'], 'created' => false];
        }
        $groups = [
            'appointments-physio-demo-admin', 'appointments-physio-demo-manager', 'appointments-physio-demo-readonly',
        ];
        foreach ($groups as $groupId) {
            if ($this->groupManager->get($groupId) === null) {
                $this->groupManager->createGroup($groupId);
            }
        }
        return $this->database->transaction(function () use ($groups): array {
            $now = time();
            $organizationId = $this->identifiers->publicId();
            $organization = $this->organizations->create([
                'organization_id' => $organizationId, 'slug' => 'physiotherapie-beispiel',
                'name' => 'Physiotherapie Beispiel', 'description' => 'Fictional local development data for appointment testing.',
                'timezone' => 'Europe/Berlin', 'locale' => 'de', 'admin_group' => $groups[0],
                'manager_group' => $groups[1], 'readonly_group' => $groups[2], 'created_at' => $now,
            ]);
            $organization = $this->organizations->updateSettings($organizationId, [
                'public_enabled' => true, 'confirmation_text' => 'Your appointment has been recorded.',
                'contact_info' => 'Physiotherapie Beispiel, Beispielstraße 10, 10115 Berlin',
                'privacy_url' => 'https://example.invalid/privacy', 'imprint_url' => 'https://example.invalid/legal',
            ], $now);

            $location = $this->catalog->create('locations', $organizationId, $this->identifiers->publicId(), [
                'slug' => 'praxis-mitte', 'name' => 'Praxis Mitte', 'kind' => 'on_site',
                'address' => 'Beispielstraße 10, 10115 Berlin', 'room' => '', 'timezone' => 'Europe/Berlin',
                'public_notes' => 'Please arrive five minutes early.', 'directions' => 'Near the central station.',
                'accessibility' => 'Step-free access is available.', 'active' => true,
            ], $now);
            $roomOne = $this->catalog->create('resources', $organizationId, $this->identifiers->publicId(), [
                'location_id' => (int)$location['id'], 'name' => 'Behandlungsraum 1', 'resource_type' => 'room', 'capacity' => 1, 'active' => true,
            ], $now);
            $roomTwo = $this->catalog->create('resources', $organizationId, $this->identifiers->publicId(), [
                'location_id' => (int)$location['id'], 'name' => 'Behandlungsraum 2', 'resource_type' => 'room', 'capacity' => 1, 'active' => true,
            ], $now);
            $staffOne = $this->staff($organizationId, 'anna-beispiel', 'Anna Beispiel', 'Manual therapy', $now);
            $staffTwo = $this->staff($organizationId, 'max-muster', 'Max Muster', 'Exercise therapy', $now);
            $this->catalog->replaceStaffLocations($organizationId, (int)$staffOne['id'], [(string)$location['public_id']]);
            $this->catalog->replaceStaffLocations($organizationId, (int)$staffTwo['id'], [(string)$location['public_id']]);
            $services = [
                $this->service($organizationId, 'ersttermin', 'Ersttermin', 60, 6500, $now),
                $this->service($organizationId, 'physiotherapie', 'Physiotherapie', 30, 4500, $now),
                $this->service($organizationId, 'beratung', 'Telefonische Beratung', 20, 2500, $now, 'phone'),
            ];
            foreach ($services as $index => $service) {
                $this->catalog->replaceServiceStaff($organizationId, (int)$service['id'], [(string)$staffOne['public_id'], (string)$staffTwo['public_id']]);
                if ($index < 2) {
                    $this->catalog->replaceServiceLocations($organizationId, (int)$service['id'], [(string)$location['public_id']]);
                    $this->catalog->replaceResourceRequirements($organizationId, (int)$service['id'], [[
                        'resourceId' => (string)($index === 0 ? $roomOne['public_id'] : $roomTwo['public_id']), 'quantity' => 1,
                    ]]);
                }
            }

            $rules = [];
            foreach (range(1, 5) as $weekday) {
                $rules[] = ['weekday' => $weekday, 'startMinute' => 480, 'endMinute' => 1020, 'type' => 'available', 'validFrom' => '', 'validUntil' => ''];
                $rules[] = ['weekday' => $weekday, 'startMinute' => 720, 'endMinute' => 780, 'type' => 'break', 'validFrom' => '', 'validUntil' => ''];
            }
            $this->availability->replace($organizationId, 'organization', $organizationId, $rules, []);
            foreach ([$staffOne, $staffTwo] as $staff) {
                $this->availability->replace($organizationId, 'staff', (string)$staff['public_id'], $rules, []);
            }
            $absenceStart = (new DateTimeImmutable('+10 days 08:00', new DateTimeZone('Europe/Berlin')))->getTimestamp();
            $this->availability->replace($organizationId, 'staff', (string)$staffTwo['public_id'], $rules, [[
                'startsAt' => $absenceStart, 'endsAt' => $absenceStart + 28800, 'type' => 'vacation', 'reason' => 'Demo absence',
            ]]);

            $firstStart = (new DateTimeImmutable('next monday 09:00', new DateTimeZone('Europe/Berlin')))->getTimestamp();
            $this->demoAppointment($organizationId, $services[1], $staffOne, $location, $roomTwo, $firstStart, 'confirmed', 'Erika', 'Beispiel');
            $this->demoAppointment($organizationId, $services[0], $staffTwo, $location, $roomOne, $firstStart + 7200, 'pending', 'Timo', 'Test');
            $this->audit->record($organizationId, 'demo.seeded', 'system', 'organization', $organizationId, 'success', ['count' => 2]);
            return ['id' => $organizationId, 'slug' => (string)$organization['slug'], 'created' => true];
        });
    }

    /** @return array<string,mixed>|null */
    private function existingOrganization(string $slug): ?array {
        $query = $this->database->query();
        $query->select('organization_id', 'slug')->from('appt_org')
            ->where($query->expr()->eq('slug', $query->createNamedParameter($slug)));
        return $this->database->fetchOne($query);
    }

    /** @return array<string,mixed> */
    private function staff(string $organizationId, string $slug, string $name, string $qualifications, int $now): array {
        return $this->catalog->create('staff', $organizationId, $this->identifiers->publicId(), [
            'slug' => $slug, 'user_uid' => null, 'display_name' => $name, 'description' => 'Fictional demo staff member.',
            'qualifications' => $qualifications, 'timezone' => 'Europe/Berlin', 'public_booking' => true,
            'active' => true, 'calendar_uri' => '',
        ], $now);
    }

    /** @return array<string,mixed> */
    private function service(string $organizationId, string $slug, string $name, int $duration, int $priceMinor, int $now, string $type = 'on_site'): array {
        return $this->catalog->create('services', $organizationId, $this->identifiers->publicId(), [
            'slug' => $slug, 'name' => $name, 'short_name' => strtoupper(substr($slug, 0, 8)),
            'description' => 'Fictional demo service.', 'duration_min' => $duration, 'buffer_before' => 0,
            'buffer_after' => 10, 'price_min' => $priceMinor, 'price_max' => $priceMinor, 'currency' => 'EUR',
            'confirmation_mode' => 'automatic', 'min_notice_min' => 60, 'max_horizon_days' => 90,
            'cancel_notice_min' => 1440, 'resched_notice_min' => 1440, 'visibility' => 'public',
            'active' => true, 'color' => '#00679e', 'booking_notes' => '', 'preparation' => '',
            'appointment_type' => $type, 'phone_required' => false,
        ], $now);
    }

    /** @param array<string,mixed> $service
     *  @param array<string,mixed> $staff
     *  @param array<string,mixed> $location
     *  @param array<string,mixed> $resource
     */
    private function demoAppointment(string $organizationId, array $service, array $staff, array $location, array $resource, int $start, string $status, string $first, string $last): void {
        $end = $start + ((int)$service['duration_min'] * 60);
        $appointment = $this->appointments->create([
            'organization_id' => $organizationId, 'public_id' => $this->identifiers->publicId(),
            'booking_number' => $this->identifiers->bookingNumber(), 'service_id' => (int)$service['id'],
            'staff_id' => (int)$staff['id'], 'location_id' => (int)$location['id'], 'starts_at' => $start,
            'ends_at' => $end, 'busy_starts_at' => $start, 'busy_ends_at' => $end + ((int)$service['buffer_after'] * 60),
            'timezone' => 'Europe/Berlin', 'status' => $status, 'first_name' => $first, 'last_name' => $last,
            'email' => strtolower($first . '.' . $last) . '@example.invalid', 'phone' => '', 'customer_message' => '',
            'internal_note' => 'Fictional demo appointment.', 'privacy_accepted_at' => null, 'created_by_uid' => '',
            'meeting_ref' => '', 'created_at' => time(), 'updated_at' => time(), 'revision' => 1,
        ]);
        $this->appointments->replaceResources($organizationId, (int)$appointment['id'], (int)$appointment['busy_starts_at'], (int)$appointment['busy_ends_at'], [[
            'resourceInternalId' => (int)$resource['id'], 'quantity' => 1,
        ]]);
        $this->appointments->addStatusHistory($organizationId, (int)$appointment['id'], '', $status, 'system', 'demo');
    }
}
