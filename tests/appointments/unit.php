<?php

declare(strict_types=1);

use OCA\Appointments\Service\AvailabilityEngine;
use OCA\Appointments\Service\AppointmentPolicy;
use OCA\Appointments\Service\AuthorizationService;
use OCA\Appointments\Service\FormAnswerValidator;
use OCA\Appointments\Service\InputValidator;
use OCA\Appointments\Service\ReminderService;
use OCA\Appointments\Service\TokenService;

require dirname(__DIR__, 2) . '/nextcloud-apps/appointments/lib/Service/AvailabilityEngine.php';
require dirname(__DIR__, 2) . '/nextcloud-apps/appointments/lib/Service/AppointmentPolicy.php';
require dirname(__DIR__, 2) . '/nextcloud-apps/appointments/lib/Service/AuthorizationService.php';
require dirname(__DIR__, 2) . '/nextcloud-apps/appointments/lib/Service/FormAnswerValidator.php';
require dirname(__DIR__, 2) . '/nextcloud-apps/appointments/lib/Service/InputValidator.php';
require dirname(__DIR__, 2) . '/nextcloud-apps/appointments/lib/Service/ReminderService.php';
require dirname(__DIR__, 2) . '/nextcloud-apps/appointments/lib/Service/TokenService.php';

function fail(string $message): never {
    fwrite(STDERR, "appointments-unit: {$message}\n");
    exit(1);
}

function check(bool $condition, string $message): void {
    if (!$condition) {
        fail($message);
    }
}

/** @param callable():mixed $operation */
function rejectsInvalidArgument(callable $operation): bool {
    try {
        $operation();
        return false;
    } catch (InvalidArgumentException) {
        return true;
    }
}

function timestamp(string $local, string $timezone = 'Europe/Berlin'): int {
    return (new DateTimeImmutable($local, new DateTimeZone($timezone)))->getTimestamp();
}

/** @return array<string, mixed> */
function ruleSubject(string $id, string $timezone, array $rules, array $busy = [], array $exceptions = []): array {
    return [
        'id' => $id,
        'timezone' => $timezone,
        'rules' => $rules,
        'busy' => $busy,
        'exceptions' => $exceptions,
    ];
}

/** @return array<string, mixed> */
function weekly(int $weekday, int $startMinute, int $endMinute, string $type = 'available'): array {
    return [
        'weekday' => $weekday,
        'startMinute' => $startMinute,
        'endMinute' => $endMinute,
        'type' => $type,
        'validFrom' => '',
        'validUntil' => '',
    ];
}

/** @param list<array<string, mixed>> $staff
 *  @param list<array<string, mixed>> $locations
 *  @param list<array<string, mixed>> $resources
 *  @return array<string, mixed>
 */
function calculation(
    int $from,
    int $to,
    array $staff,
    array $locations = [],
    array $resources = [],
    int $duration = 30,
    int $bufferBefore = 0,
    int $bufferAfter = 0,
    string $timezone = 'Europe/Berlin',
    int $slotInterval = 30,
): array {
    return [
        'now' => $from - 86400,
        'rangeStart' => $from,
        'rangeEnd' => $to,
        'timezone' => $timezone,
        'slotInterval' => $slotInterval,
        'durationMinutes' => $duration,
        'bufferBeforeMinutes' => $bufferBefore,
        'bufferAfterMinutes' => $bufferAfter,
        'minimumNoticeMinutes' => 0,
        'maximumHorizonDays' => 365,
        'staff' => $staff,
        'locations' => $locations,
        'resources' => $resources,
    ];
}

/** @param list<array<string, mixed>> $slots */
function hasSlot(array $slots, int $start): bool {
    foreach ($slots as $slot) {
        if ((int)$slot['start'] === $start) {
            return true;
        }
    }
    return false;
}

$engine = new AvailabilityEngine();
$policy = new AppointmentPolicy();

// Ordinary weekly hours.
$mondayStart = timestamp('2026-01-12 00:00');
$mondayEnd = timestamp('2026-01-13 00:00');
$staff = ruleSubject('staff-a', 'Europe/Berlin', [weekly(1, 9 * 60, 17 * 60)]);
$slots = $engine->calculate(calculation($mondayStart, $mondayEnd, [$staff]));
check(hasSlot($slots, timestamp('2026-01-12 09:00')), 'regular weekly opening did not produce a slot');
check(!hasSlot($slots, timestamp('2026-01-12 08:30')), 'slot escaped regular weekly opening');

// A weekly interval may cross midnight.
$overnightStaff = ruleSubject('staff-a', 'Europe/Berlin', [weekly(1, 22 * 60, 2 * 60)]);
$overnight = $engine->calculate(calculation($mondayStart, timestamp('2026-01-13 04:00'), [$overnightStaff], [], [], 120));
check(hasSlot($overnight, timestamp('2026-01-12 23:00')), 'appointment crossing midnight was rejected');

// An on-site service cannot silently degrade to a remote slot.
$missingLocation = calculation($mondayStart, $mondayEnd, [$staff]);
$missingLocation['locationRequired'] = true;
check($engine->calculate($missingLocation) === [], 'required missing location produced a remote slot');

// Buffers participate in conflict and working-time checks.
$bufferStaff = ruleSubject('staff-a', 'Europe/Berlin', [weekly(1, 9 * 60, 17 * 60)], [[
    'startsAt' => timestamp('2026-01-12 10:00'),
    'endsAt' => timestamp('2026-01-12 10:30'),
]]);
$buffered = $engine->calculate(calculation($mondayStart, $mondayEnd, [$bufferStaff], [], [], 30, 15, 0));
check(!hasSlot($buffered, timestamp('2026-01-12 10:30')), 'buffer did not create a staff conflict');
check(hasSlot($buffered, timestamp('2026-01-12 11:00')), 'buffer blocked a later non-overlapping slot');

// Leave and manual blocks override regular work.
$vacationStaff = ruleSubject('staff-a', 'Europe/Berlin', [weekly(1, 9 * 60, 17 * 60)], [], [[
    'startsAt' => $mondayStart,
    'endsAt' => $mondayEnd,
    'type' => 'vacation',
]]);
check($engine->calculate(calculation($mondayStart, $mondayEnd, [$vacationStaff])) === [], 'vacation did not override weekly hours');
$blockedStaff = ruleSubject('staff-a', 'Europe/Berlin', [weekly(1, 9 * 60, 17 * 60)], [], [[
    'startsAt' => timestamp('2026-01-12 12:00'),
    'endsAt' => timestamp('2026-01-12 13:00'),
    'type' => 'blocked',
]]);
$blocked = $engine->calculate(calculation($mondayStart, $mondayEnd, [$blockedStaff]));
check(!hasSlot($blocked, timestamp('2026-01-12 12:00')), 'manual block did not remove a slot');
check(hasSlot($blocked, timestamp('2026-01-12 13:00')), 'manual block included its exclusive end');

// Staff availability is insufficient when the selected room is occupied.
$location = ruleSubject('location-a', 'Europe/Berlin', [weekly(1, 9 * 60, 17 * 60)], [[
    'startsAt' => timestamp('2026-01-12 10:00'),
    'endsAt' => timestamp('2026-01-12 11:00'),
]]);
$roomSlots = $engine->calculate(calculation($mondayStart, $mondayEnd, [$staff], [$location]));
check(!hasSlot($roomSlots, timestamp('2026-01-12 10:00')), 'occupied room was offered while staff was free');

// Resource capacity and cancellation release.
$resource = ruleSubject('room-a', 'Europe/Berlin', [weekly(1, 9 * 60, 17 * 60)]);
$resource['capacity'] = 1;
$resource['requiredQuantity'] = 1;
$resource['allocations'] = [[
    'startsAt' => timestamp('2026-01-12 10:00'),
    'endsAt' => timestamp('2026-01-12 11:00'),
    'quantity' => 1,
]];
$resourceSlots = $engine->calculate(calculation($mondayStart, $mondayEnd, [$staff], [], [$resource]));
check(!hasSlot($resourceSlots, timestamp('2026-01-12 10:00')), 'resource capacity overbooking was offered');
$resource['allocations'] = [];
$releasedSlots = $engine->calculate(calculation($mondayStart, $mondayEnd, [$staff], [], [$resource]));
check(hasSlot($releasedSlots, timestamp('2026-01-12 10:00')), 'cancelled resource allocation did not release its slot');
$resource['capacity'] = 2;
$resource['allocations'] = [[
    'startsAt' => timestamp('2026-01-12 10:00'),
    'endsAt' => timestamp('2026-01-12 11:00'),
    'quantity' => 1,
]];
check(hasSlot($engine->calculate(calculation($mondayStart, $mondayEnd, [$staff], [], [$resource])), timestamp('2026-01-12 10:00')), 'parallel resource capacity was ignored');

// A location-bound room is not usable at a different location.
$otherLocation = ruleSubject('location-b', 'Europe/Berlin', [weekly(1, 9 * 60, 17 * 60)]);
$resource['locationId'] = 'location-a';
check(
    $engine->calculate(calculation($mondayStart, $mondayEnd, [$staff], [$otherLocation], [$resource])) === [],
    'location-bound resource was offered at a different location',
);

// Recurring breaks override otherwise available weekly hours.
$staffWithBreak = ruleSubject('staff-a', 'Europe/Berlin', [
    weekly(1, 9 * 60, 17 * 60),
    weekly(1, 12 * 60, 13 * 60, 'break'),
]);
$breakSlots = $engine->calculate(calculation($mondayStart, $mondayEnd, [$staffWithBreak]));
check(!hasSlot($breakSlots, timestamp('2026-01-12 12:00')), 'recurring break did not remove a slot');
check(hasSlot($breakSlots, timestamp('2026-01-12 13:00')), 'recurring break included its exclusive end');

// Different subject zones must intersect in UTC.
$newYorkStaff = ruleSubject('staff-ny', 'America/New_York', [weekly(1, 9 * 60, 17 * 60)]);
$berlinLocation = ruleSubject('location-berlin', 'Europe/Berlin', [weekly(1, 9 * 60, 17 * 60)]);
$zoned = $engine->calculate(calculation($mondayStart, $mondayEnd, [$newYorkStaff], [$berlinLocation]));
check(!hasSlot($zoned, timestamp('2026-01-12 09:00')), 'New York staff was offered outside local working time');
check(hasSlot($zoned, timestamp('2026-01-12 16:00')), 'UTC intersection of Berlin and New York working time was lost');

// DST spring-forward contains no imaginary 02:xx local slots.
$springStart = timestamp('2026-03-29 00:00');
$springEnd = timestamp('2026-03-29 05:00');
$springStaff = ruleSubject('staff-a', 'Europe/Berlin', [weekly(7, 0, 5 * 60)]);
$spring = $engine->calculate(calculation($springStart, $springEnd, [$springStaff]));
check(count($spring) === 8, 'spring-forward produced the wrong number of real half-hour slots');
foreach ($spring as $slot) {
    $localHour = (new DateTimeImmutable('@' . $slot['start']))->setTimezone(new DateTimeZone('Europe/Berlin'))->format('H');
    check($localHour !== '02', 'spring-forward produced an imaginary local time');
}

// DST fall-back produces distinct UTC slots for both real 02:xx occurrences.
$fallStart = timestamp('2026-10-25 00:00');
$fallEnd = timestamp('2026-10-25 05:00');
$fallStaff = ruleSubject('staff-a', 'Europe/Berlin', [weekly(7, 0, 5 * 60)]);
$fall = $engine->calculate(calculation($fallStart, $fallEnd, [$fallStaff]));
$utcStarts = array_map(static fn (array $slot): int => (int)$slot['start'], $fall);
check(count($fall) === 12, 'fall-back did not preserve both real repeated-hour intervals');
check(count($utcStarts) === count(array_unique($utcStarts)), 'fall-back emitted duplicate UTC instants');

// Lifecycle transitions and customer notice deadlines are stable policy.
check($policy->canTransition('pending', 'confirmed'), 'pending appointment could not be confirmed');
check($policy->canTransition('confirmed', 'completed'), 'confirmed appointment could not be completed');
check(!$policy->canTransition('completed', 'confirmed'), 'terminal appointment was reopened');
check($policy->canTransition('confirmed', 'cancelled_by_customer', true), 'customer cancellation transition was rejected');
check(!$policy->canTransition('confirmed', 'completed', true), 'customer was allowed to complete an appointment');
check($policy->cancellationAllowed(10_000, 1_000, 150), 'valid cancellation notice was rejected');
check(!$policy->cancellationAllowed(10_000, 1_001, 150), 'late cancellation notice was accepted');
check($policy->rescheduleAllowed(20_000, 2_000, 300), 'valid rescheduling notice was rejected');
check(!$policy->isKnownStatus('deleted'), 'unknown status was accepted');

// Role permissions are explicit and least-privilege by default.
$administratorPermissions = AuthorizationService::permissionsForRole(true, false, false, false);
check(in_array(AuthorizationService::MANAGE_SETTINGS, $administratorPermissions, true), 'administrator settings permission is missing');
$managerPermissions = AuthorizationService::permissionsForRole(false, true, false, false);
check(in_array(AuthorizationService::MANAGE_APPOINTMENTS, $managerPermissions, true), 'manager appointment permission is missing');
check(!in_array(AuthorizationService::MANAGE_CATALOG, $managerPermissions, true), 'manager unexpectedly received catalog administration');
$staffPermissions = AuthorizationService::permissionsForRole(false, false, false, true);
check(in_array(AuthorizationService::UPDATE_OWN, $staffPermissions, true), 'staff own-update permission is missing');
check(!in_array(AuthorizationService::MANAGE_APPOINTMENTS, $staffPermissions, true), 'staff unexpectedly received all-appointment management');
check(AuthorizationService::permissionsForRole(false, false, false, false) === [], 'unassigned user received appointment permissions');

// Management-token format, expiry, and revocation fail closed.
check(TokenService::structurallyValid(str_repeat('A', 43)), 'valid minimum-length token was rejected');
check(!TokenService::structurallyValid(str_repeat('A', 42)), 'short token was accepted');
check(!TokenService::structurallyValid(str_repeat('A', 42) . '-'), 'non-alphanumeric token was accepted');
check(TokenService::stateUsable(null, 1_000, 1_000), 'token was expired at its inclusive validity boundary');
check(!TokenService::stateUsable(999, 2_000, 1_000), 'revoked token remained usable');
check(!TokenService::stateUsable(null, 999, 1_000), 'expired token remained usable');

// Reminder calculation omits offsets that are already due and remains deterministic.
$planned = ReminderService::plannedReminders(200_000, 10_000);
check(count($planned) === 2, 'future appointment did not receive both default reminders');
check($planned[0] === ['type' => '24_hours', 'scheduledAt' => 113_600], '24-hour reminder time is incorrect');
check($planned[1] === ['type' => '2_hours', 'scheduledAt' => 192_800], '2-hour reminder time is incorrect');
check(ReminderService::plannedReminders(17_200, 10_000) === [], 'already-due reminder was scheduled');

// Custom booking values enforce type, range, option, date, and pattern rules.
$emailField = ['type' => 'email', 'required' => true, 'validation' => []];
check(FormAnswerValidator::validateValueRules($emailField, 'customer@example.test') === 'customer@example.test', 'valid email answer changed');
check(rejectsInvalidArgument(static fn () => FormAnswerValidator::validateValueRules($emailField, 'not-an-email')), 'invalid email answer was accepted');
$numberField = ['type' => 'number', 'required' => false, 'validation' => ['min' => 1, 'max' => 5]];
check(FormAnswerValidator::validateValueRules($numberField, '3.5') === 3.5, 'valid numeric answer was not normalized');
check(rejectsInvalidArgument(static fn () => FormAnswerValidator::validateValueRules($numberField, INF)), 'non-finite numeric answer was accepted');
$multiField = ['type' => 'multi_select', 'required' => false, 'validation' => ['options' => ['A', 'B']]];
check(FormAnswerValidator::validateValueRules($multiField, ['A', 'A']) === ['A'], 'multi-select answer was not normalized');
check(rejectsInvalidArgument(static fn () => FormAnswerValidator::validateValueRules($multiField, ['C'])), 'unknown multi-select option was accepted');
$requiredMultiField = ['type' => 'multi_select', 'required' => true, 'validation' => ['options' => ['A', 'B']]];
check(rejectsInvalidArgument(static fn () => FormAnswerValidator::validateValueRules($requiredMultiField, [])), 'empty required multi-select answer was accepted');
$optionalEmailField = ['type' => 'email', 'required' => false, 'validation' => []];
check(FormAnswerValidator::validateValueRules($optionalEmailField, '') === '', 'blank optional email answer was rejected');
$dateField = ['type' => 'date', 'required' => false, 'validation' => []];
check(rejectsInvalidArgument(static fn () => FormAnswerValidator::validateValueRules($dateField, '2026-02-30')), 'impossible date answer was accepted');
$patternField = ['type' => 'text', 'required' => true, 'validation' => ['pattern' => '[A-Z]{2}[0-9]{2}']];
check(rejectsInvalidArgument(static fn () => FormAnswerValidator::validateValueRules($patternField, 'aa11')), 'pattern-mismatching answer was accepted');

// Local wall times fail closed when daylight-saving transitions make them missing or ambiguous.
check(count(InputValidator::localDateTimeCandidates('2026-03-29T02:30', 'Europe/Berlin')) === 0, 'nonexistent spring-transition time was accepted');
check(count(InputValidator::localDateTimeCandidates('2026-10-25T02:30', 'Europe/Berlin')) === 2, 'ambiguous fall-transition time was silently resolved');
check(count(InputValidator::localDateTimeCandidates('2026-10-25T03:30', 'Europe/Berlin')) === 1, 'unambiguous local time was rejected');

fwrite(STDOUT, "appointments-unit: availability, time zones, lifecycle, permissions, tokens, reminders, and form validation passed\n");
