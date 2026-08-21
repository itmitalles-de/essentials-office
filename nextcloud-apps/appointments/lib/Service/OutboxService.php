<?php

declare(strict_types=1);

namespace OCA\Appointments\Service;

use OCA\Appointments\BackgroundJob\MailOutboxJob;
use OCP\BackgroundJob\IJobList;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\L10N\IFactory;
use OCP\Mail\IMailer;
use OCP\Security\ICrypto;
use Throwable;

final class OutboxService {
    private const MAX_ATTEMPTS = 5;

    public function __construct(
        private Database $database,
        private ICrypto $crypto,
        private IMailer $mailer,
        private IFactory $l10nFactory,
        private IJobList $jobList,
    ) {
    }

    /** @param array<string,mixed> $payload */
    public function enqueue(
        string $organizationId,
        ?int $appointmentId,
        string $eventType,
        string $idempotencyKey,
        string $recipient,
        string $locale,
        array $payload,
    ): int {
        $existing = $this->findByIdempotencyKey($idempotencyKey);
        if ($existing !== null) {
            if (in_array((string)$existing['state'], ['cancelled'], true)) {
                $query = $this->database->query();
                $query->update('appt_mail_outbox')
                    ->set('recipient_cipher', $query->createNamedParameter($this->crypto->encrypt($recipient)))
                    ->set('payload_cipher', $query->createNamedParameter($this->crypto->encrypt(json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE))))
                    ->set('locale', $query->createNamedParameter($locale))
                    ->set('state', $query->createNamedParameter('pending'))
                    ->set('available_at', $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT))
                    ->set('attempts', $query->createNamedParameter(0, IQueryBuilder::PARAM_INT))
                    ->set('last_error_code', $query->createNamedParameter(''))
                    ->where($query->expr()->eq('id', $query->createNamedParameter((int)$existing['id'], IQueryBuilder::PARAM_INT)))
                    ->executeStatement();
            }
            return (int)$existing['id'];
        }
        $query = $this->database->query();
        try {
            $query->insert('appt_mail_outbox')->values([
                'organization_id' => $query->createNamedParameter($organizationId),
                'appointment_id' => $appointmentId === null ? $query->createNamedParameter(null, IQueryBuilder::PARAM_NULL) : $query->createNamedParameter($appointmentId, IQueryBuilder::PARAM_INT),
                'event_type' => $query->createNamedParameter($eventType),
                'idempotency_key' => $query->createNamedParameter(mb_substr($idempotencyKey, 0, 128)),
                'recipient_cipher' => $query->createNamedParameter($this->crypto->encrypt($recipient)),
                'payload_cipher' => $query->createNamedParameter($this->crypto->encrypt(json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE))),
                'locale' => $query->createNamedParameter($locale),
                'state' => $query->createNamedParameter('pending'),
                'available_at' => $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT),
                'attempts' => $query->createNamedParameter(0, IQueryBuilder::PARAM_INT),
                'created_at' => $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT),
            ])->executeStatement();
        } catch (Throwable $exception) {
            $existing = $this->findByIdempotencyKey($idempotencyKey);
            if ($existing !== null) {
                return (int)$existing['id'];
            }
            throw $exception;
        }
        return $this->database->lastInsertId('appt_mail_outbox');
    }

    public function schedule(int $outboxId): void {
        $this->jobList->add(MailOutboxJob::class, ['outboxId' => $outboxId]);
    }

    public function deliver(int $outboxId): void {
        $row = $this->claim($outboxId);
        if ($row === null) {
            return;
        }
        try {
            if ((string)$row['event_type'] === 'reminder' && !$this->reminderStillActive((string)$row['idempotency_key'])) {
                $this->cancelDelivery($outboxId);
                return;
            }
            $recipient = $this->crypto->decrypt((string)$row['recipient_cipher']);
            $payload = json_decode($this->crypto->decrypt((string)$row['payload_cipher']), true, 16, JSON_THROW_ON_ERROR);
            if (!is_array($payload) || !$this->mailer->validateMailAddress($recipient)) {
                throw new \RuntimeException('mail_payload_invalid');
            }
            $l10n = $this->l10nFactory->get('appointments', (string)$row['locale']);
            $subject = $l10n->t((string)($payload['subject'] ?? 'Appointment notification'));
            if (isset($payload['organizationName']) && is_string($payload['organizationName']) && $payload['organizationName'] !== '') {
                $subject .= ' · ' . $payload['organizationName'];
            }
            $plain = (string)($payload['plain'] ?? '');
            if (isset($payload['plainTemplate'])) {
                $plain = $l10n->t((string)$payload['plainTemplate']);
                $replacements = [];
                foreach (is_array($payload['parameters'] ?? null) ? $payload['parameters'] : [] as $key => $value) {
                    if (is_scalar($value) || $value === null) {
                        $replacements['{' . $key . '}'] = (string)$value;
                    }
                }
                $plain = strtr($plain, $replacements);
            }
            $html = (string)($payload['html'] ?? nl2br(htmlspecialchars($plain, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8')));
            $message = $this->mailer->createMessage()
                ->setTo([$recipient])
                ->setSubject($subject)
                ->setPlainBody($plain)
                ->setHtmlBody($html)
                ->setAutoSubmitted('auto-generated');
            if (isset($payload['ics']) && is_string($payload['ics']) && $payload['ics'] !== '') {
                $message->attach($this->mailer->createAttachment($payload['ics'], 'appointment.ics', 'text/calendar; charset=utf-8'));
            }
            $this->mailer->send($message);
            $this->finish($outboxId, true, (int)$row['attempts']);
        } catch (Throwable) {
            $this->finish($outboxId, false, (int)$row['attempts']);
            throw new \RuntimeException('Appointment notification delivery failed.');
        }
    }

    /** @return list<int> */
    public function dueIds(int $limit = 100): array {
        $query = $this->database->query();
        $query->select('id')->from('appt_mail_outbox')
            ->where($query->expr()->in('state', $query->createNamedParameter(['pending', 'retry', 'sending'], IQueryBuilder::PARAM_STR_ARRAY)))
            ->andWhere($query->expr()->lte('available_at', $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT)))
            ->orderBy('id', 'ASC')->setMaxResults($limit);
        return array_map(static fn (array $row): int => (int)$row['id'], $this->database->fetchAll($query));
    }

    public function purgeSensitiveForExpired(string $organizationId, int $cutoff): void {
        $query = $this->database->query();
        $query->update('appt_mail_outbox')
            ->set('recipient_cipher', $query->createNamedParameter('[purged]'))
            ->set('payload_cipher', $query->createNamedParameter('[purged]'))
            ->where($query->expr()->eq('organization_id', $query->createNamedParameter($organizationId)))
            ->andWhere($query->expr()->lt('created_at', $query->createNamedParameter($cutoff, IQueryBuilder::PARAM_INT)))
            ->andWhere($query->expr()->neq('recipient_cipher', $query->createNamedParameter('[purged]')))
            ->executeStatement();
    }

    /** @return array<string,mixed>|null */
    private function claim(int $outboxId): ?array {
        return $this->database->transaction(function () use ($outboxId): ?array {
            $query = $this->database->query();
            $query->select('*')->from('appt_mail_outbox')
                ->where($query->expr()->eq('id', $query->createNamedParameter($outboxId, IQueryBuilder::PARAM_INT)))
                ->forUpdate();
            $row = $this->database->fetchOne($query);
            if ($row === null || !in_array((string)$row['state'], ['pending', 'retry', 'sending'], true)
                || (int)$row['available_at'] > time() || (string)$row['recipient_cipher'] === '[purged]') {
                return null;
            }
            $attempts = (int)$row['attempts'] + 1;
            $update = $this->database->query();
            $update->update('appt_mail_outbox')
                ->set('state', $update->createNamedParameter('sending'))
                ->set('attempts', $update->createNamedParameter($attempts, IQueryBuilder::PARAM_INT))
                ->set('available_at', $update->createNamedParameter(time() + 900, IQueryBuilder::PARAM_INT))
                ->where($update->expr()->eq('id', $update->createNamedParameter($outboxId, IQueryBuilder::PARAM_INT)))
                ->executeStatement();
            $row['attempts'] = $attempts;
            return $row;
        });
    }

    private function finish(int $outboxId, bool $success, int $attempts): void {
        $query = $this->database->query();
        $query->update('appt_mail_outbox');
        if ($success) {
            $query->set('state', $query->createNamedParameter('sent'))
                ->set('sent_at', $query->createNamedParameter(time(), IQueryBuilder::PARAM_INT))
                ->set('last_error_code', $query->createNamedParameter(''))
                ->set('recipient_cipher', $query->createNamedParameter('[delivered]'))
                ->set('payload_cipher', $query->createNamedParameter('[delivered]'));
        } elseif ($attempts >= self::MAX_ATTEMPTS) {
            $query->set('state', $query->createNamedParameter('failed'))
                ->set('last_error_code', $query->createNamedParameter('mail_transport'))
                ->set('recipient_cipher', $query->createNamedParameter('[purged]'))
                ->set('payload_cipher', $query->createNamedParameter('[purged]'));
        } else {
            $delay = min(21600, 60 * (2 ** max(0, $attempts - 1)));
            $query->set('state', $query->createNamedParameter('retry'))
                ->set('last_error_code', $query->createNamedParameter('mail_transport'))
                ->set('available_at', $query->createNamedParameter(time() + $delay, IQueryBuilder::PARAM_INT));
        }
        $query->where($query->expr()->eq('id', $query->createNamedParameter($outboxId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
        if ($success || $attempts >= self::MAX_ATTEMPTS) {
            $this->syncReminderState($outboxId, $success ? 'sent' : 'failed');
        }
    }

    /** @return array<string,mixed>|null */
    private function findByIdempotencyKey(string $key): ?array {
        $query = $this->database->query();
        $query->select('id', 'state')->from('appt_mail_outbox')
            ->where($query->expr()->eq('idempotency_key', $query->createNamedParameter(mb_substr($key, 0, 128))));
        return $this->database->fetchOne($query);
    }

    private function syncReminderState(int $outboxId, string $state): void {
        $query = $this->database->query();
        $query->select('event_type', 'idempotency_key')->from('appt_mail_outbox')
            ->where($query->expr()->eq('id', $query->createNamedParameter($outboxId, IQueryBuilder::PARAM_INT)));
        $row = $this->database->fetchOne($query);
        if ($row === null || (string)$row['event_type'] !== 'reminder' || !preg_match('/^reminder:(\d+)$/D', (string)$row['idempotency_key'], $match)) {
            return;
        }
        $update = $this->database->query();
        $update->update('appt_reminders')->set('state', $update->createNamedParameter($state))
            ->set('sent_at', $state === 'sent'
                ? $update->createNamedParameter(time(), IQueryBuilder::PARAM_INT)
                : $update->createNamedParameter(null, IQueryBuilder::PARAM_NULL))
            ->where($update->expr()->eq('id', $update->createNamedParameter((int)$match[1], IQueryBuilder::PARAM_INT)))
            ->executeStatement();
    }

    private function reminderStillActive(string $idempotencyKey): bool {
        if (!preg_match('/^reminder:(\d+)$/D', $idempotencyKey, $match)) {
            return false;
        }
        $query = $this->database->query();
        $query->select('state')->from('appt_reminders')
            ->where($query->expr()->eq('id', $query->createNamedParameter((int)$match[1], IQueryBuilder::PARAM_INT)));
        $row = $this->database->fetchOne($query);
        return $row !== null && (string)$row['state'] === 'queued';
    }

    private function cancelDelivery(int $outboxId): void {
        $query = $this->database->query();
        $query->update('appt_mail_outbox')
            ->set('state', $query->createNamedParameter('cancelled'))
            ->set('last_error_code', $query->createNamedParameter('cancelled'))
            ->set('recipient_cipher', $query->createNamedParameter('[purged]'))
            ->set('payload_cipher', $query->createNamedParameter('[purged]'))
            ->where($query->expr()->eq('id', $query->createNamedParameter($outboxId, IQueryBuilder::PARAM_INT)))
            ->executeStatement();
    }
}
