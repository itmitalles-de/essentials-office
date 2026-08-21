<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use DateTimeImmutable;
use DateTimeZone;
use OCA\Appointments\Exception\ValidationException;
use OCP\IL10N;

final class InputValidator {
    private const MAX_TIMESTAMP = 4102444800;

    public function __construct(private IL10N $l10n) {
    }

    public function string(array $data, string $key, int $max, bool $required = true): string {
        $value = trim((string)($data[$key] ?? ''));
        if ($required && $value === '') {
            throw new ValidationException($this->l10n->t('A required field is missing.'));
        }
        if (mb_strlen($value) > $max) {
            throw new ValidationException($this->l10n->t('A field exceeds its maximum length.'));
        }
        return $value;
    }

    public function integer(array $data, string $key, int $minimum, int $maximum, ?int $default = null): int {
        $value = $data[$key] ?? $default;
        if (filter_var($value, FILTER_VALIDATE_INT) === false) {
            throw new ValidationException($this->l10n->t('An integer field is invalid.'));
        }
        $value = (int)$value;
        if ($value < $minimum || $value > $maximum) {
            throw new ValidationException($this->l10n->t('An integer field is outside the allowed range.'));
        }
        return $value;
    }

    public function boolean(array $data, string $key, bool $default = false): bool {
        $value = $data[$key] ?? $default;
        if (is_bool($value)) {
            return $value;
        }
        if ($value === 1 || $value === '1' || $value === 'true') {
            return true;
        }
        if ($value === 0 || $value === '0' || $value === 'false') {
            return false;
        }
        throw new ValidationException($this->l10n->t('A boolean field is invalid.'));
    }

    /** @param list<string> $allowed */
    public function enum(array $data, string $key, array $allowed, string $default): string {
        $value = (string)($data[$key] ?? $default);
        if (!in_array($value, $allowed, true)) {
            throw new ValidationException($this->l10n->t('A field contains an unsupported value.'));
        }
        return $value;
    }

    public function timezone(array $data, string $key, string $default = 'Europe/Berlin'): string {
        $value = (string)($data[$key] ?? $default);
        try {
            new DateTimeZone($value);
        } catch (\Exception) {
            throw new ValidationException($this->l10n->t('The time zone is invalid.'));
        }
        return $value;
    }

    public function timestamp(array $data, string $key): int {
        $value = $data[$key] ?? null;
        if (is_int($value) || (is_string($value) && ctype_digit($value))) {
            $timestamp = filter_var($value, FILTER_VALIDATE_INT);
            if ($timestamp === false || $timestamp < 0 || $timestamp > self::MAX_TIMESTAMP) {
                throw new ValidationException($this->l10n->t('The date and time are invalid.'));
            }
            return (int)$timestamp;
        }
        if (!is_string($value) || !preg_match(
            '/^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})T(?<hour>\d{2}):(?<minute>\d{2})(?::(?<second>\d{2})(?:\.\d{1,6})?)?(?<offset>Z|[+-](?<offsetHour>\d{2}):(?<offsetMinute>\d{2}))$/D',
            $value,
            $parts,
        )) {
            throw new ValidationException($this->l10n->t('The date and time are required.'));
        }
        $second = isset($parts['second']) && $parts['second'] !== '' ? (int)$parts['second'] : 0;
        $offsetHour = isset($parts['offsetHour']) && $parts['offsetHour'] !== '' ? (int)$parts['offsetHour'] : 0;
        $offsetMinute = isset($parts['offsetMinute']) && $parts['offsetMinute'] !== '' ? (int)$parts['offsetMinute'] : 0;
        if (!checkdate((int)$parts['month'], (int)$parts['day'], (int)$parts['year'])
            || (int)$parts['hour'] > 23 || (int)$parts['minute'] > 59 || $second > 59
            || $offsetHour > 14 || $offsetMinute > 59 || ($offsetHour === 14 && $offsetMinute !== 0)) {
            throw new ValidationException($this->l10n->t('The date and time are invalid.'));
        }
        try {
            $date = new DateTimeImmutable($value);
        } catch (\Exception) {
            throw new ValidationException($this->l10n->t('The date and time are invalid.'));
        }
        $errors = DateTimeImmutable::getLastErrors();
        if (is_array($errors) && ($errors['warning_count'] > 0 || $errors['error_count'] > 0)) {
            throw new ValidationException($this->l10n->t('The date and time are invalid.'));
        }
        $timestamp = $date->getTimestamp();
        if ($timestamp < 0 || $timestamp > self::MAX_TIMESTAMP) {
            throw new ValidationException($this->l10n->t('The date and time are invalid.'));
        }
        return $timestamp;
    }

    public function localDateTime(string $value, string $timezone): int {
        $matches = self::localDateTimeCandidates($value, $timezone);
        if (count($matches) !== 1) {
            throw new ValidationException($this->l10n->t('The local date and time are invalid.'));
        }
        return $matches[0];
    }

    /** @return list<int> */
    public static function localDateTimeCandidates(string $value, string $timezone): array {
        try {
            $zone = new DateTimeZone($timezone);
            $utc = new DateTimeZone('UTC');
            $wallTime = DateTimeImmutable::createFromFormat('!Y-m-d\TH:i', $value, $utc);
        } catch (\Exception) {
            return [];
        }
        if ($wallTime === false || $wallTime->format('Y-m-d\TH:i') !== $value) {
            return [];
        }
        $wallTimestamp = $wallTime->getTimestamp();
        $offsets = [$zone->getOffset($wallTime)];
        $transitions = $zone->getTransitions($wallTimestamp - 172800, $wallTimestamp + 172800);
        if (is_array($transitions)) {
            foreach ($transitions as $transition) {
                $offsets[] = (int)$transition['offset'];
            }
        }
        $matches = [];
        foreach (array_unique($offsets) as $offset) {
            $candidate = $wallTimestamp - (int)$offset;
            if ($candidate < 0 || $candidate > self::MAX_TIMESTAMP) {
                continue;
            }
            $roundTrip = (new DateTimeImmutable('@' . $candidate))->setTimezone($zone)->format('Y-m-d\TH:i');
            if ($roundTrip === $value) {
                $matches[] = $candidate;
            }
        }
        sort($matches);
        return array_values(array_unique($matches));
    }

    /** @return array{from:int,to:int,timezone:string} */
    public function localDayRange(string $date, string $timezone): array {
        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/D', $date)) {
            throw new ValidationException($this->l10n->t('The date is invalid.'));
        }
        try {
            $zone = new DateTimeZone($timezone);
            $start = DateTimeImmutable::createFromFormat('!Y-m-d', $date, $zone);
        } catch (\Exception) {
            $start = false;
        }
        if ($start === false || $start->format('Y-m-d') !== $date) {
            throw new ValidationException($this->l10n->t('The date is invalid.'));
        }
        return ['from' => $start->getTimestamp(), 'to' => $start->modify('+1 day')->getTimestamp(), 'timezone' => $timezone];
    }

    public function slug(string $value): string {
        $slug = strtolower(trim($value));
        if (!preg_match('/^[a-z0-9](?:[a-z0-9-]{0,78}[a-z0-9])?$/D', $slug)) {
            throw new ValidationException($this->l10n->t('The slug is invalid.'));
        }
        return $slug;
    }

    public function email(string $value): string {
        $value = strtolower(trim($value));
        if (filter_var($value, FILTER_VALIDATE_EMAIL) === false || mb_strlen($value) > 320) {
            throw new ValidationException($this->l10n->t('The email address is invalid.'));
        }
        return $value;
    }

    public function httpsUrl(string $value): string {
        $value = trim($value);
        if ($value === '') {
            return '';
        }
        if (preg_match('/[\x00-\x1F\x7F]/', $value)) {
            throw new ValidationException($this->l10n->t('The URL is invalid.'));
        }
        $parts = parse_url($value);
        if (!is_array($parts)
            || ($parts['scheme'] ?? '') !== 'https'
            || !isset($parts['host'])
            || isset($parts['user'])
            || isset($parts['pass'])
            || isset($parts['fragment'])) {
            throw new ValidationException($this->l10n->t('The URL must be an absolute HTTPS URL without credentials or a fragment.'));
        }
        return $value;
    }
}
