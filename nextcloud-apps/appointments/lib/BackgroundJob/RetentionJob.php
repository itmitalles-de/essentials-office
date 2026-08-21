<?php

declare(strict_types=1);

namespace OCA\Appointments\BackgroundJob;

use OCA\Appointments\Service\RetentionService;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\BackgroundJob\TimedJob;

final class RetentionJob extends TimedJob {
    public function __construct(ITimeFactory $time, private RetentionService $retention) {
        parent::__construct($time);
        $this->setInterval(86400);
        $this->setTimeSensitivity(self::TIME_INSENSITIVE);
    }

    protected function run(mixed $argument): void {
        $this->retention->run();
    }
}
