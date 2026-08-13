<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Command;

use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Throwable;

final class ModuleDoctor extends BaseModuleCommand {
    protected function configure(): void {
        $this->setName('essentialsplus:module:doctor')
            ->setDescription('Run declared health checks and refresh logical activation.')
            ->addArgument('id', InputArgument::OPTIONAL, 'Module ID; omit to check every desired module');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        try {
            $id = (string)($input->getArgument('id') ?? '');
            if ($id !== '') {
                $status = $this->moduleService->doctor($id, 'occ');
                $this->writeJson($output, $status);
                return $status['state'] === 'enabled' || $status['state'] === 'disabled' ? self::SUCCESS : self::FAILURE;
            }
            $statuses = [];
            $failed = false;
            foreach ($this->moduleService->listForAdmin() as $module) {
                if ($module['desired'] !== true) {
                    continue;
                }
                $status = $this->moduleService->doctor($module['id'], 'occ');
                $statuses[] = $status;
                $failed = $failed || $status['state'] !== 'enabled';
            }
            $this->writeJson($output, ['modules' => $statuses]);
            return $failed ? self::FAILURE : self::SUCCESS;
        } catch (Throwable $exception) {
            $output->writeln('<error>' . $exception->getMessage() . '</error>');
            return self::FAILURE;
        }
    }
}
