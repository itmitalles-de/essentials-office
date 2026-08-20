<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCP\DB\QueryBuilder\IQueryBuilder;

final class AuditService {
    private const ALLOWED_METADATA = [
        'status', 'previous_status', 'source', 'conflict_type', 'count', 'field', 'reason_code', 'revision',
    ];

    public function __construct(private Database $database) {
    }

    /** @param array<string, scalar|null> $metadata */
    public function record(
        string $organizationId,
        string $action,
        string $actorType,
        string $subjectType,
        string $subjectPublicId,
        string $outcome = 'success',
        array $metadata = [],
    ): void {
        $safe = [];
        foreach (self::ALLOWED_METADATA as $key) {
            if (array_key_exists($key, $metadata)) {
                $safe[$key] = $metadata[$key];
            }
        }
        $query = $this->database->query();
        $query->insert('appt_audit')->values([
            'organization_id' => $query->createNamedParameter($organizationId),
            'created_at' => $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT),
            'action' => $query->createNamedParameter(mb_substr($action, 0, 64)),
            'actor_type' => $query->createNamedParameter(mb_substr($actorType, 0, 16)),
            'subject_type' => $query->createNamedParameter(mb_substr($subjectType, 0, 32)),
            'subject_public_id' => $query->createNamedParameter(mb_substr($subjectPublicId, 0, 64)),
            'outcome' => $query->createNamedParameter(mb_substr($outcome, 0, 16)),
            'metadata_json' => $query->createNamedParameter(json_encode($safe, JSON_THROW_ON_ERROR)),
        ])->executeStatement();
    }
}
