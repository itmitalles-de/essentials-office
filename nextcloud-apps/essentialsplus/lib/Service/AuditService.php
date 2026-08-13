<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Service;

use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;
use Psr\Log\LoggerInterface;

final class AuditService {
    private const RETENTION = 1000;

    public function __construct(private IDBConnection $db, private LoggerInterface $logger) {
    }

    /** @param array<string, scalar|null> $details */
    public function record(string $actor, string $moduleId, string $action, string $outcome, array $details = []): void {
        unset($details['secret'], $details['password'], $details['token'], $details['credential']);
        $encoded = json_encode($details, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
        $query = $this->db->getQueryBuilder();
        $query->insert('essplus_audit')->values([
            'created_at' => $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT),
            'actor' => $query->createNamedParameter(mb_substr($actor, 0, 255)),
            'module_id' => $query->createNamedParameter(mb_substr($moduleId, 0, 64)),
            'action' => $query->createNamedParameter(mb_substr($action, 0, 64)),
            'outcome' => $query->createNamedParameter(mb_substr($outcome, 0, 32)),
            'details' => $query->createNamedParameter($encoded),
        ])->executeStatement();
        $this->logger->info('Essentials+ Office module change', [
            'app' => 'essentialsplus',
            'actor' => $actor,
            'module' => $moduleId,
            'action' => $action,
            'outcome' => $outcome,
        ]);
        $this->prune();
    }

    /** @return list<array<string, mixed>> */
    public function recent(int $limit = 50): array {
        $limit = max(1, min($limit, 200));
        $query = $this->db->getQueryBuilder();
        $query->select('id', 'created_at', 'actor', 'module_id', 'action', 'outcome', 'details')
            ->from('essplus_audit')
            ->orderBy('id', 'DESC')
            ->setMaxResults($limit);
        $result = $query->executeQuery();
        $entries = [];
        while ($row = $result->fetch()) {
            try {
                $details = json_decode((string)$row['details'], true, 8, JSON_THROW_ON_ERROR);
            } catch (\JsonException) {
                $details = [];
            }
            $entries[] = [
                'id' => (int)$row['id'],
                'createdAt' => (int)$row['created_at'],
                'actor' => (string)$row['actor'],
                'moduleId' => (string)$row['module_id'],
                'action' => (string)$row['action'],
                'outcome' => (string)$row['outcome'],
                'details' => $details,
            ];
        }
        $result->closeCursor();
        return $entries;
    }

    private function prune(): void {
        $query = $this->db->getQueryBuilder();
        $query->select('id')->from('essplus_audit')->orderBy('id', 'DESC')
            ->setFirstResult(self::RETENTION)->setMaxResults(1);
        $threshold = $query->executeQuery()->fetchOne();
        if ($threshold === false) {
            return;
        }
        $delete = $this->db->getQueryBuilder();
        $delete->delete('essplus_audit')
            ->where($delete->expr()->lte('id', $delete->createNamedParameter((int)$threshold, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
    }
}
