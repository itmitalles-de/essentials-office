<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\BackgroundJob;

use OCA\EssentialsPlus\Service\ModuleService;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\BackgroundJob\TimedJob;
use Throwable;

final class ModuleHealthJob extends TimedJob {
    public function __construct(ITimeFactory $time, private ModuleService $moduleService) {
        parent::__construct($time);
        $this->setInterval(300);
    }

    protected function run($argument): void {
        foreach ($this->moduleService->listForAdmin() as $module) {
            if ($module['desired'] !== true) {
                continue;
            }
            try {
                $this->moduleService->doctor($module['id'], 'background-job');
            } catch (Throwable) {
                // The module stays non-active/degraded. Doctor records safe detail.
            }
        }
    }
}
