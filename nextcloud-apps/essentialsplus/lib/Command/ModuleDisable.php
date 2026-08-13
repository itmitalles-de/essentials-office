<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Command;

use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Throwable;

final class ModuleDisable extends BaseModuleCommand {
    protected function configure(): void {
        $this->setName('essentialsplus:module:disable')
            ->setDescription('Hide a module and disable unshared Nextcloud apps without deleting data or stopping services.')
            ->addArgument('id', InputArgument::REQUIRED, 'Module ID');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        try {
            $status = $this->moduleService->disable((string)$input->getArgument('id'), 'occ');
            $this->writeJson($output, $status);
            return self::SUCCESS;
        } catch (Throwable $exception) {
            $output->writeln('<error>' . $exception->getMessage() . '</error>');
            return self::FAILURE;
        }
    }
}
