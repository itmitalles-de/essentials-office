<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use DateTimeImmutable;
use OCA\Appointments\Exception\ValidationException;
use OCP\IL10N;

final class FormAnswerValidator {
    public function __construct(private CatalogRepository $catalog, private IL10N $l10n) {
    }

    /** @return list<array{fieldInternalId:int,value:mixed}> */
    public function validate(string $organizationId, int $serviceId, mixed $input, bool $public): array {
        if ($input === null) {
            $input = [];
        }
        if (!is_array($input)) {
            throw new ValidationException($this->l10n->t('Booking form answers are invalid.'));
        }
        if (array_is_list($input)) {
            $mapped = [];
            foreach ($input as $item) {
                if (!is_array($item) || !is_string($item['fieldId'] ?? null) || array_key_exists($item['fieldId'], $mapped)) {
                    throw new ValidationException($this->l10n->t('Booking form answers are invalid.'));
                }
                $mapped[$item['fieldId']] = $item['value'] ?? null;
            }
            $input = $mapped;
        }
        $definitions = $this->catalog->formFieldDefinitions($organizationId, $serviceId, $public);
        $allowedIds = array_map(static fn (array $field): string => (string)$field['id'], $definitions);
        if (array_diff(array_keys($input), $allowedIds) !== []) {
            throw new ValidationException($this->l10n->t('A booking form answer refers to an unavailable field.'));
        }
        $answers = [];
        foreach ($definitions as $field) {
            $exists = array_key_exists($field['id'], $input);
            $value = $exists ? $input[$field['id']] : null;
            if (!$exists && $field['required']) {
                throw new ValidationException($this->l10n->t('A required booking form answer is missing.'));
            }
            if (!$exists) {
                continue;
            }
            $answers[] = ['fieldInternalId' => $field['internalId'], 'value' => $this->validateValue($field, $value)];
        }
        return $answers;
    }

    /** @param array<string,mixed> $field */
    private function validateValue(array $field, mixed $value): mixed {
        try {
            return self::validateValueRules($field, $value);
        } catch (\InvalidArgumentException) {
            throw $this->invalid();
        }
    }

    /** @param array<string,mixed> $field */
    public static function validateValueRules(array $field, mixed $value): mixed {
        $type = (string)$field['type'];
        $rules = $field['validation'];
        if ($type === 'checkbox' || $type === 'boolean') {
            if (!is_bool($value)) {
                throw new \InvalidArgumentException('invalid_boolean');
            }
            if ($type === 'checkbox' && $field['required'] && !$value) {
                throw new \InvalidArgumentException('required_checkbox');
            }
            return $value;
        }
        if ($type === 'multi_select') {
            if (!is_array($value) || count($value) > 50 || count(array_filter($value, 'is_string')) !== count($value)) {
                throw new \InvalidArgumentException('invalid_multi_select');
            }
            $options = $rules['options'] ?? [];
            $values = array_values(array_unique(array_map('trim', $value)));
            if ($field['required'] && $values === []) {
                throw new \InvalidArgumentException('required_multi_select');
            }
            if (array_diff($values, $options) !== []) {
                throw new \InvalidArgumentException('invalid_multi_select_option');
            }
            return $values;
        }
        if (!$field['required'] && $value === '') {
            return $type === 'number' ? null : '';
        }
        if ($type === 'number') {
            if (!is_int($value) && !is_float($value) && !is_numeric($value)) {
                throw new \InvalidArgumentException('invalid_number');
            }
            $number = (float)$value;
            if (!is_finite($number)
                || (isset($rules['min']) && $number < (float)$rules['min'])
                || (isset($rules['max']) && $number > (float)$rules['max'])) {
                throw new \InvalidArgumentException('number_out_of_range');
            }
            return $number;
        }
        if (!is_string($value) || mb_strlen($value) > ($type === 'textarea' ? 5000 : 512)) {
            throw new \InvalidArgumentException('invalid_text');
        }
        $value = trim($value);
        if ($field['required'] && $value === '') {
            throw new \InvalidArgumentException('required_text');
        }
        if ($type === 'email' && filter_var($value, FILTER_VALIDATE_EMAIL) === false) {
            throw new \InvalidArgumentException('invalid_email');
        }
        if ($type === 'phone' && $value !== '' && !preg_match('/^[0-9+() .\/-]{3,64}$/D', $value)) {
            throw new \InvalidArgumentException('invalid_phone');
        }
        if ($type === 'date' && $value !== '') {
            $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $value);
            if ($parsed === false || $parsed->format('Y-m-d') !== $value) {
                throw new \InvalidArgumentException('invalid_date');
            }
        }
        if ($type === 'select' && !in_array($value, $rules['options'] ?? [], true)) {
            throw new \InvalidArgumentException('invalid_select_option');
        }
        $length = mb_strlen($value);
        if ((isset($rules['min']) && $length < (int)$rules['min']) || (isset($rules['max']) && $length > (int)$rules['max'])) {
            throw new \InvalidArgumentException('text_out_of_range');
        }
        if (isset($rules['pattern']) && $value !== '') {
            $pattern = '~(*LIMIT_MATCH=10000)(*LIMIT_DEPTH=100)' . str_replace('~', '\\~', (string)$rules['pattern']) . '~uD';
            if (@preg_match($pattern, $value) !== 1) {
                throw new \InvalidArgumentException('pattern_mismatch');
            }
        }
        return $value;
    }

    private function invalid(): ValidationException {
        return new ValidationException($this->l10n->t('A booking form answer is invalid.'));
    }
}
