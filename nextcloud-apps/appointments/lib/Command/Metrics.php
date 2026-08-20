<?php

declare(strict_types=1);

namespace OCA\Appointments\Command;

use OCA\Appointments\Service\OperationsService;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

final class Metrics extends Command {
    public function __construct(private OperationsService $operations) {
        parent::__construct();
    }

    protected function configure(): void {
        $this->setName('appointments:metrics')->setDescription('Print PII-free appointment operational metrics in Prometheus format.');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        $metrics = $this->operations->metrics();
        $definitions = [
            'booking_success' => ['essentialsplus_appointments_booking_success_total', 'Successful appointment bookings.', 'counter'],
            'booking_error' => ['essentialsplus_appointments_booking_error_total', 'Failed appointment bookings.', 'counter'],
            'slot_conflict' => ['essentialsplus_appointments_slot_conflict_total', 'Rejected conflicting slot bookings.', 'counter'],
            'reminder_pending' => ['essentialsplus_appointments_reminder_pending', 'Pending appointment reminders.', 'gauge'],
            'reminder_failed' => ['essentialsplus_appointments_reminder_failed', 'Failed appointment reminders.', 'gauge'],
            'outbox_failed' => ['essentialsplus_appointments_outbox_failed', 'Failed appointment mail outbox entries.', 'gauge'],
            'calendar_sync_failed' => ['essentialsplus_appointments_calendar_sync_failed', 'Failed appointment calendar synchronizations.', 'gauge'],
        ];
        foreach ($definitions as $key => [$name, $help, $type]) {
            $output->writeln('# HELP ' . $name . ' ' . $help);
            $output->writeln('# TYPE ' . $name . ' ' . $type);
            $output->writeln($name . ' ' . (int)($metrics[$key] ?? 0));
        }
        return self::SUCCESS;
    }
}
