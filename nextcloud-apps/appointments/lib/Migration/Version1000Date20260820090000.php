<?php

declare(strict_types=1);

namespace OCA\Appointments\Migration;

use Closure;
use OCP\DB\ISchemaWrapper;
use OCP\DB\Types;
use OCP\Migration\IOutput;
use OCP\Migration\SimpleMigrationStep;

final class Version1000Date20260820090000 extends SimpleMigrationStep {
    public function changeSchema(IOutput $output, Closure $schemaClosure, array $options): ?ISchemaWrapper {
        /** @var ISchemaWrapper $schema */
        $schema = $schemaClosure();

        if (!$schema->hasTable('appt_org')) {
            $table = $schema->createTable('appt_org');
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('slug', Types::STRING, ['notnull' => true, 'length' => 80]);
            $table->addColumn('name', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('description', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('contact_info', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('timezone', Types::STRING, ['notnull' => true, 'length' => 64, 'default' => 'Europe/Berlin']);
            $table->addColumn('locale', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'de']);
            $table->addColumn('admin_group', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('manager_group', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('readonly_group', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('public_enabled', Types::BOOLEAN, ['notnull' => true, 'default' => false]);
            $table->addColumn('active', Types::BOOLEAN, ['notnull' => true, 'default' => true]);
            $table->addColumn('slot_interval', Types::SMALLINT, ['notnull' => true, 'default' => 15]);
            $table->addColumn('min_form_seconds', Types::SMALLINT, ['notnull' => true, 'default' => 3]);
            $table->addColumn('retention_days', Types::INTEGER, ['notnull' => true, 'default' => 730]);
            $table->addColumn('privacy_url', Types::STRING, ['notnull' => true, 'length' => 1024, 'default' => '']);
            $table->addColumn('imprint_url', Types::STRING, ['notnull' => true, 'length' => 1024, 'default' => '']);
            $table->addColumn('confirmation_text', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('accent_color', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => '#00679e']);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['organization_id']);
            $table->addUniqueIndex(['slug'], 'appt_org_slug_uq');
        }

        if (!$schema->hasTable('appt_services')) {
            $table = $schema->createTable('appt_services');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('public_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('slug', Types::STRING, ['notnull' => true, 'length' => 80]);
            $table->addColumn('name', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('short_name', Types::STRING, ['notnull' => true, 'length' => 80, 'default' => '']);
            $table->addColumn('description', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('duration_min', Types::SMALLINT, ['notnull' => true]);
            $table->addColumn('buffer_before', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('buffer_after', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('price_min', Types::INTEGER, ['notnull' => false]);
            $table->addColumn('price_max', Types::INTEGER, ['notnull' => false]);
            $table->addColumn('currency', Types::STRING, ['notnull' => true, 'length' => 3, 'default' => 'EUR']);
            $table->addColumn('confirmation_mode', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'automatic']);
            $table->addColumn('min_notice_min', Types::INTEGER, ['notnull' => true, 'default' => 60]);
            $table->addColumn('max_horizon_days', Types::INTEGER, ['notnull' => true, 'default' => 90]);
            $table->addColumn('cancel_notice_min', Types::INTEGER, ['notnull' => true, 'default' => 1440]);
            $table->addColumn('resched_notice_min', Types::INTEGER, ['notnull' => true, 'default' => 1440]);
            $table->addColumn('visibility', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'public']);
            $table->addColumn('active', Types::BOOLEAN, ['notnull' => true, 'default' => true]);
            $table->addColumn('color', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => '#00679e']);
            $table->addColumn('booking_notes', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('preparation', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('appointment_type', Types::STRING, ['notnull' => true, 'length' => 32, 'default' => 'on_site']);
            $table->addColumn('phone_required', Types::BOOLEAN, ['notnull' => true, 'default' => false]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'public_id'], 'appt_service_public_uq');
            $table->addUniqueIndex(['organization_id', 'slug'], 'appt_service_slug_uq');
            $table->addIndex(['organization_id', 'active'], 'appt_service_active_ix');
        }

        if (!$schema->hasTable('appt_staff')) {
            $table = $schema->createTable('appt_staff');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('public_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('slug', Types::STRING, ['notnull' => true, 'length' => 80]);
            $table->addColumn('user_uid', Types::STRING, ['notnull' => false, 'length' => 255]);
            $table->addColumn('display_name', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('description', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('qualifications', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('timezone', Types::STRING, ['notnull' => true, 'length' => 64, 'default' => 'Europe/Berlin']);
            $table->addColumn('public_booking', Types::BOOLEAN, ['notnull' => true, 'default' => true]);
            $table->addColumn('active', Types::BOOLEAN, ['notnull' => true, 'default' => true]);
            $table->addColumn('calendar_uri', Types::STRING, ['notnull' => true, 'length' => 255, 'default' => '']);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'public_id'], 'appt_staff_public_uq');
            $table->addUniqueIndex(['organization_id', 'slug'], 'appt_staff_slug_uq');
            $table->addUniqueIndex(['organization_id', 'user_uid'], 'appt_staff_user_uq');
        }

        if (!$schema->hasTable('appt_locations')) {
            $table = $schema->createTable('appt_locations');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('public_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('slug', Types::STRING, ['notnull' => true, 'length' => 80]);
            $table->addColumn('name', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('kind', Types::STRING, ['notnull' => true, 'length' => 32, 'default' => 'on_site']);
            $table->addColumn('address', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('room', Types::STRING, ['notnull' => true, 'length' => 255, 'default' => '']);
            $table->addColumn('timezone', Types::STRING, ['notnull' => true, 'length' => 64, 'default' => 'Europe/Berlin']);
            $table->addColumn('public_notes', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('directions', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('accessibility', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('active', Types::BOOLEAN, ['notnull' => true, 'default' => true]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'public_id'], 'appt_location_public_uq');
            $table->addUniqueIndex(['organization_id', 'slug'], 'appt_location_slug_uq');
        }

        if (!$schema->hasTable('appt_resources')) {
            $table = $schema->createTable('appt_resources');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('public_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('location_id', Types::BIGINT, ['notnull' => false, 'unsigned' => true]);
            $table->addColumn('name', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('resource_type', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('capacity', Types::SMALLINT, ['notnull' => true, 'default' => 1]);
            $table->addColumn('active', Types::BOOLEAN, ['notnull' => true, 'default' => true]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'public_id'], 'appt_resource_public_uq');
            $table->addIndex(['organization_id', 'location_id'], 'appt_resource_loc_ix');
        }

        if (!$schema->hasTable('appt_service_staff')) {
            $table = $schema->createTable('appt_service_staff');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('service_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('staff_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'service_id', 'staff_id'], 'appt_service_staff_uq');
        }

        if (!$schema->hasTable('appt_service_loc')) {
            $table = $schema->createTable('appt_service_loc');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('service_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('location_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'service_id', 'location_id'], 'appt_service_loc_uq');
        }

        if (!$schema->hasTable('appt_staff_loc')) {
            $table = $schema->createTable('appt_staff_loc');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('staff_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('location_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'staff_id', 'location_id'], 'appt_staff_loc_uq');
        }

        if (!$schema->hasTable('appt_resource_req')) {
            $table = $schema->createTable('appt_resource_req');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('service_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('resource_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('quantity', Types::SMALLINT, ['notnull' => true, 'default' => 1]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'service_id', 'resource_id'], 'appt_resource_req_uq');
        }

        if (!$schema->hasTable('appt_avail_rules')) {
            $table = $schema->createTable('appt_avail_rules');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('subject_type', Types::STRING, ['notnull' => true, 'length' => 16]);
            $table->addColumn('subject_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('weekday', Types::SMALLINT, ['notnull' => true]);
            $table->addColumn('start_minute', Types::SMALLINT, ['notnull' => true]);
            $table->addColumn('end_minute', Types::SMALLINT, ['notnull' => true]);
            $table->addColumn('rule_type', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'available']);
            $table->addColumn('valid_from', Types::STRING, ['notnull' => true, 'length' => 10, 'default' => '']);
            $table->addColumn('valid_until', Types::STRING, ['notnull' => true, 'length' => 10, 'default' => '']);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['organization_id', 'subject_type', 'subject_id', 'weekday'], 'appt_avail_rule_ix');
        }

        if (!$schema->hasTable('appt_avail_except')) {
            $table = $schema->createTable('appt_avail_except');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('subject_type', Types::STRING, ['notnull' => true, 'length' => 16]);
            $table->addColumn('subject_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('starts_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('ends_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('exception_type', Types::STRING, ['notnull' => true, 'length' => 24]);
            $table->addColumn('reason', Types::STRING, ['notnull' => true, 'length' => 255, 'default' => '']);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['organization_id', 'subject_type', 'subject_id', 'starts_at'], 'appt_avail_except_ix');
        }

        if (!$schema->hasTable('appt_form_fields')) {
            $table = $schema->createTable('appt_form_fields');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('public_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('service_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('field_type', Types::STRING, ['notnull' => true, 'length' => 24]);
            $table->addColumn('label', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('help_text', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('required', Types::BOOLEAN, ['notnull' => true, 'default' => false]);
            $table->addColumn('sort_order', Types::INTEGER, ['notnull' => true, 'default' => 0]);
            $table->addColumn('visibility', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'public']);
            $table->addColumn('validation_json', Types::TEXT, ['notnull' => true, 'default' => '{}']);
            $table->addColumn('active', Types::BOOLEAN, ['notnull' => true, 'default' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'public_id'], 'appt_form_field_public_uq');
            $table->addIndex(['organization_id', 'service_id', 'sort_order'], 'appt_form_field_ix');
        }

        if (!$schema->hasTable('appt_appointments')) {
            $table = $schema->createTable('appt_appointments');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('public_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('booking_number', Types::STRING, ['notnull' => true, 'length' => 32]);
            $table->addColumn('service_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('staff_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('location_id', Types::BIGINT, ['notnull' => false, 'unsigned' => true]);
            $table->addColumn('starts_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('ends_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('busy_starts_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('busy_ends_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('timezone', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('status', Types::STRING, ['notnull' => true, 'length' => 32]);
            $table->addColumn('first_name', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('last_name', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('email', Types::STRING, ['notnull' => true, 'length' => 320]);
            $table->addColumn('phone', Types::STRING, ['notnull' => true, 'length' => 64, 'default' => '']);
            $table->addColumn('customer_message', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('internal_note', Types::TEXT, ['notnull' => true, 'default' => '']);
            $table->addColumn('privacy_accepted_at', Types::BIGINT, ['notnull' => false]);
            $table->addColumn('created_by_uid', Types::STRING, ['notnull' => true, 'length' => 255, 'default' => '']);
            $table->addColumn('meeting_ref', Types::STRING, ['notnull' => true, 'length' => 255, 'default' => '']);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('cancelled_at', Types::BIGINT, ['notnull' => false]);
            $table->addColumn('anonymized_at', Types::BIGINT, ['notnull' => false]);
            $table->addColumn('revision', Types::INTEGER, ['notnull' => true, 'default' => 1]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'public_id'], 'appt_appointment_public_uq');
            $table->addUniqueIndex(['organization_id', 'booking_number'], 'appt_booking_number_uq');
            $table->addIndex(['organization_id', 'starts_at', 'status'], 'appt_appointment_time_ix');
            $table->addIndex(['organization_id', 'staff_id', 'busy_starts_at'], 'appt_appointment_staff_ix');
            $table->addIndex(['organization_id', 'location_id', 'busy_starts_at'], 'appt_appointment_loc_ix');
        }

        if (!$schema->hasTable('appt_resource_alloc')) {
            $table = $schema->createTable('appt_resource_alloc');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('appointment_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('resource_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('quantity', Types::SMALLINT, ['notnull' => true, 'default' => 1]);
            $table->addColumn('busy_starts_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('busy_ends_at', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'appointment_id', 'resource_id'], 'appt_resource_alloc_uq');
            $table->addIndex(['organization_id', 'resource_id', 'busy_starts_at'], 'appt_resource_busy_ix');
        }

        if (!$schema->hasTable('appt_status_history')) {
            $table = $schema->createTable('appt_status_history');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('appointment_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('from_status', Types::STRING, ['notnull' => true, 'length' => 32, 'default' => '']);
            $table->addColumn('to_status', Types::STRING, ['notnull' => true, 'length' => 32]);
            $table->addColumn('actor_type', Types::STRING, ['notnull' => true, 'length' => 16]);
            $table->addColumn('actor_ref', Types::STRING, ['notnull' => true, 'length' => 255, 'default' => '']);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['organization_id', 'appointment_id', 'created_at'], 'appt_status_history_ix');
        }

        if (!$schema->hasTable('appt_form_answers')) {
            $table = $schema->createTable('appt_form_answers');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('appointment_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('field_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('value_json', Types::TEXT, ['notnull' => true, 'default' => 'null']);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'appointment_id', 'field_id'], 'appt_form_answer_uq');
        }

        if (!$schema->hasTable('appt_tokens')) {
            $table = $schema->createTable('appt_tokens');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('appointment_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('token_hash', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('token_type', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'manage']);
            $table->addColumn('expires_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('revoked_at', Types::BIGINT, ['notnull' => false]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['token_hash'], 'appt_token_hash_uq');
            $table->addIndex(['organization_id', 'appointment_id'], 'appt_token_appointment_ix');
        }

        if (!$schema->hasTable('appt_reminders')) {
            $table = $schema->createTable('appt_reminders');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('appointment_id', Types::BIGINT, ['notnull' => true, 'unsigned' => true]);
            $table->addColumn('reminder_type', Types::STRING, ['notnull' => true, 'length' => 32]);
            $table->addColumn('scheduled_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('state', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'pending']);
            $table->addColumn('attempts', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('sent_at', Types::BIGINT, ['notnull' => false]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['organization_id', 'appointment_id', 'reminder_type', 'scheduled_at'], 'appt_reminder_uq');
            $table->addIndex(['state', 'scheduled_at'], 'appt_reminder_due_ix');
        }

        if (!$schema->hasTable('appt_mail_outbox')) {
            $table = $schema->createTable('appt_mail_outbox');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('appointment_id', Types::BIGINT, ['notnull' => false, 'unsigned' => true]);
            $table->addColumn('event_type', Types::STRING, ['notnull' => true, 'length' => 32]);
            $table->addColumn('idempotency_key', Types::STRING, ['notnull' => true, 'length' => 128]);
            $table->addColumn('recipient_cipher', Types::TEXT, ['notnull' => true]);
            $table->addColumn('payload_cipher', Types::TEXT, ['notnull' => true]);
            $table->addColumn('locale', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'de']);
            $table->addColumn('state', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'pending']);
            $table->addColumn('available_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('attempts', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('last_error_code', Types::STRING, ['notnull' => true, 'length' => 64, 'default' => '']);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('sent_at', Types::BIGINT, ['notnull' => false]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['idempotency_key'], 'appt_mail_idempotency_uq');
            $table->addIndex(['state', 'available_at'], 'appt_mail_due_ix');
        }

        if (!$schema->hasTable('appt_audit')) {
            $table = $schema->createTable('appt_audit');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true, 'unsigned' => true]);
            $table->addColumn('organization_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('action', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('actor_type', Types::STRING, ['notnull' => true, 'length' => 16]);
            $table->addColumn('subject_type', Types::STRING, ['notnull' => true, 'length' => 32]);
            $table->addColumn('subject_public_id', Types::STRING, ['notnull' => true, 'length' => 64, 'default' => '']);
            $table->addColumn('outcome', Types::STRING, ['notnull' => true, 'length' => 16]);
            $table->addColumn('metadata_json', Types::TEXT, ['notnull' => true, 'default' => '{}']);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['organization_id', 'created_at'], 'appt_audit_org_time_ix');
        }

        return $schema;
    }
}
