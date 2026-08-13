<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Command;

use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Throwable;

final class ModuleStatus extends BaseModuleCommand {
    protected function configure(): void {
        $this->setName('essentialsplus:module:status')
            ->setDescription('Show one Essentials+ Office module as secret-free JSON.')
            ->addArgument('id', InputArgument::REQUIRED, 'Module ID');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        try {
            $this->writeJson($output, $this->moduleService->status((string)$input->getArgument('id')));
            return self::SUCCESS;
        } catch (Throwable $exception) {
            $output->writeln('<error>' . $exception->getMessage() . '</error>');
            return self::FAILURE;
        }
    }
}
