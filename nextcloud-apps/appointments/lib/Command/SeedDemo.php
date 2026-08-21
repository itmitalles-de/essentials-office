<?php

declare(strict_types=1);

namespace OCA\Appointments\Command;

use OCA\Appointments\Service\DemoSeedService;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

final class SeedDemo extends Command {
    public function __construct(private DemoSeedService $seed) {
        parent::__construct();
    }

    protected function configure(): void {
        $this->setName('appointments:demo:seed')
            ->setDescription('Create explicit fictional appointment demo data for local development.')
            ->addOption('confirm', null, InputOption::VALUE_NONE, 'Confirm creation of local demo data.');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int {
        if (!$input->getOption('confirm')) {
            $output->writeln('<error>Pass --confirm to create fictional development data.</error>');
            return self::INVALID;
        }
        $result = $this->seed->seed();
        $output->writeln(json_encode($result, JSON_THROW_ON_ERROR));
        return self::SUCCESS;
    }
}
