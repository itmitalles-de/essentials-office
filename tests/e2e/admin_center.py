#!/usr/bin/env python3
"""Minimal raw-WebDriver acceptance for a disposable Essentials+ Office instance."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request


def fail(message: str) -> None:
    raise RuntimeError(message)


def read_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


class WebDriver:
    def __init__(self, endpoint: str) -> None:
        self.endpoint = endpoint.rstrip("/")
        self.session_id = ""

    def request(self, method: str, path: str, payload: object | None = None) -> object:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            self.endpoint + path,
            data=body,
            method=method,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                result = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            fail(f"WebDriver HTTP {error.code}: {detail[:300]}")
        except (TimeoutError, urllib.error.URLError, OSError) as error:
            fail(f"WebDriver transport failed for {method} {path}: {error}")
        value = result.get("value")
        if isinstance(value, dict) and value.get("error"):
            fail(f"WebDriver {value['error']}: {value.get('message', '')}")
        return value

    def start(self, chromium: str) -> None:
        value = self.request(
            "POST",
            "/session",
            {
                "capabilities": {
                    "alwaysMatch": {
                        "browserName": "chrome",
                        "pageLoadStrategy": "none",
                        "timeouts": {"implicit": 0, "pageLoad": 90000, "script": 30000},
                        "goog:chromeOptions": {
                            "binary": chromium,
                            "args": [
                                "--headless=new",
                                "--no-sandbox",
                                "--disable-dev-shm-usage",
                                "--disable-gpu",
                                "--no-proxy-server",
                                "--window-size=1440,1200",
                                "--host-resolver-rules=MAP deploy-test.invalid 127.0.0.1",
                            ],
                        },
                    }
                }
            },
        )
        if not isinstance(value, dict) or not isinstance(value.get("sessionId"), str):
            fail("WebDriver did not create a session")
        self.session_id = value["sessionId"]

    def stop(self) -> None:
        if self.session_id:
            try:
                self.request("DELETE", f"/session/{self.session_id}")
            except Exception:
                pass
            self.session_id = ""

    def navigate(self, url: str) -> None:
        self.request("POST", f"/session/{self.session_id}/url", {"url": url})

    def find(self, selector: str) -> str:
        value = self.request(
            "POST",
            f"/session/{self.session_id}/element",
            {"using": "css selector", "value": selector},
        )
        if not isinstance(value, dict):
            fail(f"element not found: {selector}")
        element_id = value.get("element-6066-11e4-a52e-4f735466cecf")
        if not isinstance(element_id, str):
            fail(f"element has no WebDriver ID: {selector}")
        return element_id

    def type(self, selector: str, value: str) -> None:
        element = self.find(selector)
        self.request(
            "POST",
            f"/session/{self.session_id}/element/{element}/value",
            {"text": value, "value": list(value)},
        )

    def click(self, selector: str) -> None:
        element = self.find(selector)
        self.request("POST", f"/session/{self.session_id}/element/{element}/click", {})

    def execute(self, script: str) -> object:
        return self.request(
            "POST",
            f"/session/{self.session_id}/execute/sync",
            {"script": script, "args": []},
        )

    def source(self) -> str:
        value = self.request("GET", f"/session/{self.session_id}/source")
        return value if isinstance(value, str) else ""

    def diagnostic(self) -> str:
        if not self.session_id:
            return "session=not-created"
        try:
            value = self.execute(
                "return {path: window.location.pathname, title: document.title, readyState: document.readyState}"
            )
            return json.dumps(value, sort_keys=True)
        except Exception as error:
            return f"diagnostic-unavailable={error}"


def wait_for(predicate, message: str, timeout: int = 90) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except RuntimeError:
            pass
        time.sleep(0.5)
    fail(message)


def login(driver: WebDriver, base_url: str, user: str, password: str) -> None:
    driver.navigate(base_url + "/login")
    wait_for(lambda: bool(driver.find("#user")), "Nextcloud login form did not load")
    driver.type("#user", user)
    driver.type("#password", password)
    driver.click("[data-login-form-submit]")
    wait_for(
        lambda: "/login" not in str(driver.execute("return window.location.pathname")),
        "Nextcloud browser login did not complete",
    )


def run_session(
    endpoint: str,
    chromium: str,
    base_url: str,
    user: str,
    password: str,
    admin: bool,
    expected_modules: set[str],
) -> None:
    driver = WebDriver(endpoint)
    try:
        driver.start(chromium)
        login(driver, base_url, user, password)
        if admin:
            driver.navigate(base_url + "/settings/admin/essentialsplus")
            wait_for(
                lambda: driver.execute("return document.querySelectorAll('[data-module-id]').length") == 8,
                "Admin Center did not render all eight module manifests",
            )
            group_count = driver.execute("return document.querySelectorAll('[data-group-id]').length")
            if group_count != 8:
                fail(f"administrator saw {group_count} catalog groups instead of eight")
            source = driver.source()
            for heading in (
                "Dateien und Groupware",
                "Intranet und Wissen",
                "Dokumente",
                "Kommunikation",
                "Sicherheit",
                "People und HR",
                "Integrationen",
                "Kundenspezifisch",
            ):
                if heading not in source:
                    fail(f"administrator catalog is missing group: {heading}")
        else:
            driver.navigate(base_url + "/apps/essentialsplus/")
            wait_for(
                lambda: driver.execute("return Boolean(document.querySelector('.essentialsplus-portal'))"),
                "ordinary user module portal did not load",
            )
            module_ids = driver.execute(
                "return Array.from(document.querySelectorAll('[data-module-id]')).map((node) => node.dataset.moduleId).sort()"
            )
            if module_ids != sorted(expected_modules):
                fail(
                    f"ordinary user module catalog differs: expected {sorted(expected_modules)!r}, "
                    f"observed {module_ids!r}"
                )
            driver.navigate(base_url + "/settings/admin/essentialsplus")
            time.sleep(1)
            if "Essentials+ Office Admin-Center" in driver.source():
                fail("ordinary user reached the administrator settings page")
            driver.navigate(base_url + "/apps/essentialsplus/api/v1/modules")
            time.sleep(1)
            if '"contractVersion"' in driver.source():
                fail("ordinary user reached the administrator module API")
    except Exception as error:
        role = "administrator" if admin else "ordinary-user"
        fail(f"{role} flow failed: {error}; {driver.diagnostic()}")
    finally:
        driver.stop()


def main() -> int:
    base_url = os.environ.get("BROWSER_BASE_URL", "").rstrip("/")
    core_env = os.environ.get("BROWSER_CORE_ENV_FILE", "")
    user_env = os.environ.get("BROWSER_USER_ENV_FILE", "")
    chromium = os.environ.get("CHROMIUM_BIN", "")
    webdriver_endpoint = os.environ.get("WEBDRIVER_ENDPOINT", "http://127.0.0.1:9515")
    expected_modules = {
        value for value in os.environ.get("BROWSER_EXPECTED_MODULES", "nextcloud-core").split(",") if value
    }
    if not base_url or not core_env or not user_env or not chromium:
        fail("browser test requires base URL, protected env files, and Chromium path")
    core = read_env(pathlib.Path(core_env))
    user = read_env(pathlib.Path(user_env))
    run_session(
        webdriver_endpoint,
        chromium,
        base_url,
        core["NEXTCLOUD_ADMIN_USER"],
        core["NEXTCLOUD_ADMIN_PASSWORD"],
        True,
        expected_modules,
    )
    run_session(
        webdriver_endpoint,
        chromium,
        base_url,
        user["BROWSER_USER"],
        user["BROWSER_PASSWORD"],
        False,
        expected_modules,
    )
    print("admin-center-browser-e2e: admin catalog and ordinary-user visibility passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exception:
        print(f"admin-center-browser-e2e: {exception}", file=sys.stderr)
        sys.exit(1)
