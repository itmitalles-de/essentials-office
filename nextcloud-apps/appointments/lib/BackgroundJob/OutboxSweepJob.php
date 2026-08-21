<?php

declare(strict_types=1);

namespace OCA\Appointments\BackgroundJob;

use OCA\Appointments\Service\OutboxService;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\BackgroundJob\TimedJob;

final class OutboxSweepJob extends TimedJob {
    public function __construct(ITimeFactory $time, private OutboxService $outbox) {
        parent::__construct($time);
        $this->setInterval(300);
        $this->setAllowParallelRuns(false);
    }

    protected function run($argument): void {
        foreach ($this->outbox->dueIds() as $outboxId) {
            try {
                $this->outbox->schedule($outboxId);
            } catch (\Throwable) {
                // The durable row remains pending/retry for the next sweep.
            }
        }
    }
}
