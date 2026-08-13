<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Command;

use OCA\EssentialsPlus\Service\ModuleService;
use OCA\EssentialsPlus\Service\StateStore;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

final class Metrics extends BaseModuleCommand {
    public function __construct(ModuleService $moduleService, private StateStore $stateStore) {
        parent::__construct($moduleService);
    }

    protected function configure(): void {
        $this->setName('essentialsplus:metrics')
            ->setDescription('Export secret-free Prometheus text metrics for module and recovery state.');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        $output->writeln('# HELP essentialsplus_module_state Current module state as a one-hot gauge.');
        $output->writeln('# TYPE essentialsplus_module_state gauge');
        foreach ($this->moduleService->listForAdmin() as $module) {
            foreach (['not_installed', 'needs_configuration', 'disabled', 'enabled', 'degraded'] as $state) {
                $value = $module['state'] === $state ? 1 : 0;
                $output->writeln(sprintf('essentialsplus_module_state{module="%s",state="%s"} %d', $module['id'], $state, $value));
            }
            $output->writeln(sprintf('essentialsplus_module_health_checked_timestamp_seconds{module="%s"} %d', $module['id'], $module['health']['checkedAt']));
        }
        $output->writeln('# HELP essentialsplus_backup_timestamp_seconds Timestamp of the last recorded backup.');
        $output->writeln('# TYPE essentialsplus_backup_timestamp_seconds gauge');
        $output->writeln('essentialsplus_backup_timestamp_seconds ' . $this->stateStore->evidenceTimestamp('backup'));
        $output->writeln('# HELP essentialsplus_restore_test_timestamp_seconds Timestamp of the last recorded restore test.');
        $output->writeln('# TYPE essentialsplus_restore_test_timestamp_seconds gauge');
        $output->writeln('essentialsplus_restore_test_timestamp_seconds ' . $this->stateStore->evidenceTimestamp('restore_test'));
        return self::SUCCESS;
    }
}
