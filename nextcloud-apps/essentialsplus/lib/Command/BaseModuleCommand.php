<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Command;

use OCA\EssentialsPlus\Service\ModuleService;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Output\OutputInterface;

abstract class BaseModuleCommand extends Command {
    public function __construct(protected ModuleService $moduleService) {
        parent::__construct();
    }

    /** @param mixed $value */
    protected function writeJson(OutputInterface $output, mixed $value): void {
        $output->writeln(json_encode($value, JSON_THROW_ON_ERROR | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    }
}
