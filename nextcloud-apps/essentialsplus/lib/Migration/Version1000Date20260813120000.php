<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Migration;

use Closure;
use OCP\DB\ISchemaWrapper;
use OCP\DB\Types;
use OCP\Migration\IOutput;
use OCP\Migration\SimpleMigrationStep;

final class Version1000Date20260813120000 extends SimpleMigrationStep {
    public function changeSchema(IOutput $output, Closure $schemaClosure, array $options): ?ISchemaWrapper {
        /** @var ISchemaWrapper $schema */
        $schema = $schemaClosure();
        if ($schema->hasTable('essplus_audit')) {
            return null;
        }

        $table = $schema->createTable('essplus_audit');
        $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
        $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
        $table->addColumn('actor', Types::STRING, ['notnull' => true, 'length' => 255]);
        $table->addColumn('module_id', Types::STRING, ['notnull' => true, 'length' => 64]);
        $table->addColumn('action', Types::STRING, ['notnull' => true, 'length' => 64]);
        $table->addColumn('outcome', Types::STRING, ['notnull' => true, 'length' => 32]);
        $table->addColumn('details', Types::TEXT, ['notnull' => true, 'default' => '{}']);
        $table->setPrimaryKey(['id']);
        $table->addIndex(['created_at'], 'essplus_audit_created');
        $table->addIndex(['module_id'], 'essplus_audit_module');
        return $schema;
    }
}
