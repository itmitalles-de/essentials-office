<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Command;

use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Throwable;

final class ModuleConfigure extends BaseModuleCommand {
    protected function configure(): void {
        $this->setName('essentialsplus:module:configure')
            ->setDescription('Record a non-secret module configuration value or readiness attestation.')
            ->addArgument('id', InputArgument::REQUIRED, 'Module ID')
            ->addArgument('key', InputArgument::REQUIRED, 'Manifest configuration key or secretReady')
            ->addArgument('value', InputArgument::REQUIRED, 'Non-secret value; never pass credentials');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        try {
            $key = (string)$input->getArgument('key');
            // ModuleService accepts only manifest-declared, typed non-secret
            // values (plus the boolean secretReady attestation). This permits
            // declarations such as sipCredentialStorageReady without ever
            // accepting an actual credential value.
            $status = $this->moduleService->configure(
                (string)$input->getArgument('id'),
                $key,
                (string)$input->getArgument('value'),
                'occ',
            );
            $this->writeJson($output, $status);
            return self::SUCCESS;
        } catch (Throwable $exception) {
            $output->writeln('<error>' . $exception->getMessage() . '</error>');
            return self::FAILURE;
        }
    }
}
