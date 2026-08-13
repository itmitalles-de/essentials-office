<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Command;

use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

final class ModuleList extends BaseModuleCommand {
    protected function configure(): void {
        $this->setName('essentialsplus:module:list')
            ->setDescription('List every Essentials+ Office module and its logical state.')
            ->addOption('output', null, InputOption::VALUE_REQUIRED, 'table or json', 'table');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        $modules = $this->moduleService->listForAdmin();
        if ($input->getOption('output') === 'json') {
            $this->writeJson($output, ['modules' => $modules]);
            return self::SUCCESS;
        }
        $rows = array_map(static fn (array $module): array => [
            $module['id'], $module['group'], $module['state'], $module['desired'] ? 'yes' : 'no', $module['active'] ? 'yes' : 'no',
        ], $modules);
        (new SymfonyStyle($input, $output))->table(['ID', 'Group', 'State', 'Desired', 'Active'], $rows);
        return self::SUCCESS;
    }
}
