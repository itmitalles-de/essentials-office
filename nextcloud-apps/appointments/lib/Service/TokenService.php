<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\Exception\NotFoundException;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IL10N;

final class TokenService {
    public function __construct(
        private Database $database,
        private AppointmentRepository $appointments,
        private Identifiers $identifiers,
        private IL10N $l10n,
    ) {
    }

    public function create(string $organizationId, int $appointmentId, int $expiresAt): string {
        $token = $this->identifiers->managementToken();
        $query = $this->database->query();
        $query->insert('appt_tokens')->values([
            'organization_id' => $query->createNamedParameter($organizationId),
            'appointment_id' => $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT),
            'token_hash' => $query->createNamedParameter($this->identifiers->tokenHash($token)),
            'token_type' => $query->createNamedParameter('manage'),
            'expires_at' => $query->createNamedParameter($expiresAt, IQueryBuilder::PARAM_INT),
            'created_at' => $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT),
        ])->executeStatement();
        return $token;
    }

    /** @return array<string,mixed> */
    public function resolve(string $token): array {
        if (!self::structurallyValid($token)) {
            throw $this->invalid();
        }
        $query = $this->database->query();
        $query->select('organization_id', 'appointment_id', 'expires_at', 'revoked_at')->from('appt_tokens')
            ->where($query->expr()->eq('token_hash', $query->createNamedParameter($this->identifiers->tokenHash($token))));
        $row = $this->database->fetchOne($query);
        if ($row === null || !self::stateUsable($row['revoked_at'], (int)$row['expires_at'], time())) {
            throw $this->invalid();
        }
        $appointment = $this->appointments->requireInternal((string)$row['organization_id'], (int)$row['appointment_id']);
        if ($appointment['anonymized_at'] !== null) {
            throw $this->invalid();
        }
        return $appointment;
    }

    public static function structurallyValid(string $token): bool {
        return strlen($token) >= 43 && strlen($token) <= 128 && ctype_alnum($token);
    }

    public static function stateUsable(mixed $revokedAt, int $expiresAt, int $now): bool {
        return $revokedAt === null && $expiresAt >= $now;
    }

    public function revokeForAppointment(string $organizationId, int $appointmentId): void {
        $query = $this->database->query();
        $query->update('appt_tokens')
            ->set('revoked_at', $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT))
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->eq('appointment_id', $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->isNull('revoked_at'))
            ->executeStatement();
    }

    private function invalid(): NotFoundException {
        return new NotFoundException($this->l10n->t('The management link is invalid or has expired.'));
    }
}
