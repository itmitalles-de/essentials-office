<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;
use Throwable;

final class Database {
    public function __construct(private IDBConnection $connection) {
    }

    public function query(): IQueryBuilder {
        return $this->connection->getQueryBuilder();
    }

    /** @return list<array<string, mixed>> */
    public function fetchAll(IQueryBuilder $query): array {
        $result = $query->executeQuery();
        $rows = [];
        while ($row = $result->fetch()) {
            $rows[] = $row;
        }
        $result->closeCursor();
        return $rows;
    }

    /** @return array<string, mixed>|null */
    public function fetchOne(IQueryBuilder $query): ?array {
        $result = $query->executeQuery();
        $row = $result->fetch();
        $result->closeCursor();
        return is_array($row) ? $row : null;
    }

    public function lastInsertId(string $table): int {
        return $this->connection->lastInsertId($table);
    }

    public function escapeLike(string $value): string {
        return $this->connection->escapeLikeParameter($value);
    }

    /** @template T
     *  @param callable(): T $operation
     *  @return T
     */
    public function transaction(callable $operation): mixed {
        $this->connection->beginTransaction();
        try {
            $value = $operation();
            $this->connection->commit();
            return $value;
        } catch (Throwable $exception) {
            if ($this->connection->inTransaction()) {
                $this->connection->rollBack();
            }
            throw $exception;
        }
    }

    public static function bool(mixed $value): bool {
        return in_array($value, [true, 1, '1', 't', 'true'], true);
    }
}
