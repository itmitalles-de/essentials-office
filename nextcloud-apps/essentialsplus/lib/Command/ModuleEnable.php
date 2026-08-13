<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Command;

use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Throwable;

final class ModuleEnable extends BaseModuleCommand {
    protected function configure(): void {
        $this->setName('essentialsplus:module:enable')
            ->setDescription('Request and reconcile health-gated logical module activation.')
            ->addArgument('id', InputArgument::REQUIRED, 'Module ID');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        try {
            $status = $this->moduleService->enable((string)$input->getArgument('id'), 'occ');
            $this->writeJson($output, $status);
            return self::SUCCESS;
        } catch (Throwable $exception) {
            $output->writeln('<error>' . $exception->getMessage() . '</error>');
            return self::FAILURE;
        }
    }
}
