<?php

declare(strict_types=1);

namespace OCA\EssentialsPlus\Controller;

use OCA\EssentialsPlus\Service\ModuleService;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IRequest;
use OCP\IUserSession;
use Throwable;

final class ApiController extends Controller {
    public function __construct(
        string $appName,
        IRequest $request,
        private ModuleService $moduleService,
        private IUserSession $userSession,
    ) {
        parent::__construct($appName, $request);
    }

    public function list(): JSONResponse {
        return new JSONResponse($this->moduleService->catalog());
    }

    public function audit(int $limit = 50): JSONResponse {
        return new JSONResponse(['entries' => $this->moduleService->audit($limit)]);
    }

    public function enable(string $id): JSONResponse {
        return $this->mutate(fn (): array => $this->moduleService->enable($id, $this->actor()));
    }

    public function disable(string $id): JSONResponse {
        return $this->mutate(fn (): array => $this->moduleService->disable($id, $this->actor()));
    }

    public function doctor(string $id): JSONResponse {
        return $this->mutate(fn (): array => $this->moduleService->doctor($id, $this->actor()));
    }

    /** @param list<string> $groups */
    public function visibility(string $id, array $groups = []): JSONResponse {
        return $this->mutate(fn (): array => $this->moduleService->setVisibility($id, $groups, $this->actor()));
    }

    /** @param callable(): array<string, mixed> $operation */
    private function mutate(callable $operation): JSONResponse {
        try {
            return new JSONResponse(['module' => $operation()]);
        } catch (Throwable $exception) {
            return new JSONResponse(['error' => $this->safeMessage($exception)], 400);
        }
    }

    private function actor(): string {
        return $this->userSession->getUser()?->getUID() ?? 'unknown-admin';
    }

    private function safeMessage(Throwable $exception): string {
        return mb_substr(preg_replace('~https?://[^[:space:]]+~', '[URL]', $exception->getMessage()) ?? 'Operation failed.', 0, 256);
    }
}
