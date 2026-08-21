<?php

declare(strict_types=1);

namespace OCA\Appointments\BackgroundJob;

use OCA\Appointments\Service\OutboxService;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\BackgroundJob\QueuedJob;

final class MailOutboxJob extends QueuedJob {
    public function __construct(ITimeFactory $time, private OutboxService $outbox) {
        parent::__construct($time);
        $this->setAllowParallelRuns(true);
    }

    protected function run($argument): void {
        if (!is_array($argument) || !isset($argument['outboxId']) || !is_int($argument['outboxId'])) {
            return;
        }
        $this->outbox->deliver($argument['outboxId']);
    }
}
