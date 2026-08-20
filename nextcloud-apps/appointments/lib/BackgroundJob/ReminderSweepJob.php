<?php

declare(strict_types=1);

namespace OCA\Appointments\BackgroundJob;

use OCA\Appointments\Service\ReminderService;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\BackgroundJob\TimedJob;

final class ReminderSweepJob extends TimedJob {
    public function __construct(ITimeFactory $time, private ReminderService $reminders) {
        parent::__construct($time);
        $this->setInterval(300);
        $this->setTimeSensitivity(self::TIME_SENSITIVE);
    }

    protected function run(mixed $argument): void {
        $this->reminders->sweep();
    }
}
