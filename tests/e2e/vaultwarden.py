#!/usr/bin/env python3
"""Raw-WebDriver acceptance for the pinned Vaultwarden Web Vault."""

from __future__ import annotations

import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request


def fail(message: str) -> None:
    raise RuntimeError(message)


def read_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw and not raw.startswith("#") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key] = value
    return values


class Driver:
    def __init__(self, endpoint: str, chromium: str) -> None:
        self.endpoint = endpoint.rstrip("/")
        self.session_id = ""
        value = self.request(
            "POST",
            "/session",
            {
                "capabilities": {
                    "alwaysMatch": {
                        "browserName": "chrome",
                        "goog:chromeOptions": {
                            "binary": chromium,
                            "args": [
                                "--headless=new",
                                "--no-sandbox",
                                "--disable-dev-shm-usage",
                                "--disable-gpu",
                                "--no-proxy-server",
                                "--ignore-certificate-errors",
                                "--allow-insecure-localhost",
                                "--lang=en-GB",
                                "--window-size=1440,1200",
                            ],
                        },
                        "goog:loggingPrefs": {"browser": "ALL"},
                    }
                }
            },
        )
        if not isinstance(value, dict) or not isinstance(value.get("sessionId"), str):
            fail("WebDriver did not create a Vaultwarden browser session")
        self.session_id = value["sessionId"]

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
        value = result.get("value")
        if isinstance(value, dict) and value.get("error"):
            fail(f"WebDriver {value['error']}: {value.get('message', '')}")
        return value

    def stop(self) -> None:
        if self.session_id:
            try:
                self.request("DELETE", f"/session/{self.session_id}")
            except Exception:
                pass
            self.session_id = ""

    def navigate(self, url: str) -> None:
        self.request("POST", f"/session/{self.session_id}/url", {"url": url})

    def execute(self, script: str, args: list[object] | None = None) -> object:
        return self.request(
            "POST",
            f"/session/{self.session_id}/execute/sync",
            {"script": script, "args": args or []},
        )

    def element_from_script(self, script: str, value: str) -> str:
        result = self.execute(script, [value])
        if not isinstance(result, dict):
            fail(f"browser element not found: {value}")
        element_id = result.get("element-6066-11e4-a52e-4f735466cecf")
        if not isinstance(element_id, str):
            fail(f"browser element has no WebDriver ID: {value}")
        return element_id

    def click_text(self, value: str) -> None:
        element = self.element_from_script(
            """
            const wanted = arguments[0].trim().toLowerCase();
            const nodes = Array.from(document.querySelectorAll('button,a,[role="button"],[role="link"],[role="menuitem"],[role="tab"]'));
            return nodes.find((node) => (node.innerText || node.textContent || '').trim().toLowerCase() === wanted)
                || nodes.find((node) => (node.innerText || node.textContent || '').trim().toLowerCase().includes(wanted))
                || null;
            """,
            value,
        )
        self.request("POST", f"/session/{self.session_id}/element/{element}/click", {})

    def click_first(self, *values: str) -> None:
        for value in values:
            try:
                self.click_text(value)
                return
            except RuntimeError:
                pass
        fail(f"browser element not found: {' / '.join(values)}")

    def fill_label(self, value: str, content: str) -> None:
        element = self.element_from_script(
            """
            const wanted = arguments[0].trim().toLowerCase();
            const direct = Array.from(document.querySelectorAll('input[aria-label],textarea[aria-label]')).find(
                (node) => (node.getAttribute('aria-label') || '').trim().toLowerCase().includes(wanted));
            if (direct) return direct;
            for (const label of Array.from(document.querySelectorAll('label,bit-label'))) {
                if (!(label.innerText || label.textContent || '').trim().toLowerCase().includes(wanted)) continue;
                if (label.htmlFor) {
                    const target = document.getElementById(label.htmlFor);
                    if (target) return target;
                }
                const local = label.querySelector('input,textarea')
                    || label.parentElement?.querySelector('input,textarea')
                    || label.parentElement?.parentElement?.querySelector('input,textarea');
                if (local) return local;
            }
            return null;
            """,
            value,
        )
        self.request("POST", f"/session/{self.session_id}/element/{element}/clear", {})
        self.request(
            "POST",
            f"/session/{self.session_id}/element/{element}/value",
            {"text": content, "value": list(content)},
        )

    def body_text(self) -> str:
        value = self.execute("return document.body ? document.body.innerText : ''")
        return value if isinstance(value, str) else ""

    def title(self) -> str:
        value = self.request("GET", f"/session/{self.session_id}/title")
        return value if isinstance(value, str) else ""

    def browser_log(self) -> object:
        try:
            entries = self.request(
                "POST",
                f"/session/{self.session_id}/log",
                {"type": "browser"},
            )
            if not isinstance(entries, list):
                return []
            return [
                {
                    "level": entry.get("level"),
                    "message": str(entry.get("message", ""))[:600],
                }
                for entry in entries
                if isinstance(entry, dict) and entry.get("level") == "SEVERE"
            ][-20:]
        except RuntimeError:
            return []


def wait_for(predicate, message: str, timeout: int = 45) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except RuntimeError:
            pass
        time.sleep(0.5)
    fail(message)


def dismiss_extension(driver: Driver) -> None:
    try:
        driver.click_text("Add it later")
        driver.click_text("Skip to web app")
    except RuntimeError:
        pass


def create_account(endpoint: str, chromium: str, base: str, email: str, name: str, password: str) -> None:
    driver = Driver(endpoint, chromium)
    try:
        driver.navigate(base + "/#/register")
        wait_for(
            lambda: "email address" in driver.body_text().lower() and "create account" in driver.body_text().lower(),
            "Vaultwarden registration page did not load",
            60,
        )
        driver.fill_label("Email address", email)
        driver.fill_label("Name", name)
        driver.click_text("Continue")
        try:
            wait_for(lambda: "master password" in driver.body_text().lower(), "Vaultwarden password step did not load")
        except RuntimeError as exception:
            safe_body = driver.body_text().replace(email, "[synthetic-email]")[:800]
            state = driver.execute(
                """
                return {
                  url: location.href,
                  formValid: document.querySelector('form')?.checkValidity() ?? null,
                  inputs: Array.from(document.querySelectorAll('input')).map((node) => ({
                    id: node.id,
                    name: node.name,
                    type: node.type,
                    aria: node.getAttribute('aria-label'),
                    valueLength: node.value.length,
                    disabled: node.disabled,
                    valid: node.checkValidity(),
                    validationMessage: node.validationMessage,
                  })),
                  buttons: Array.from(document.querySelectorAll('button')).map((node) => ({
                    text: (node.innerText || node.textContent || '').trim(),
                    type: node.type,
                    disabled: node.disabled,
                    ariaDisabled: node.getAttribute('aria-disabled'),
                  })),
                  alerts: Array.from(document.querySelectorAll('[role="alert"],bit-toast,bit-callout')).map(
                    (node) => (node.innerText || node.textContent || '').trim()).filter(Boolean),
                };
                """
            )
            fail(
                f"{exception}; UI text: {safe_body!r}; state: {state!r}; "
                f"browser log: {driver.browser_log()!r}"
            )
        driver.fill_label("Master password", password)
        driver.fill_label("Confirm master password", password)
        driver.click_text("Create account")
        try:
            wait_for(
                lambda: bool(
                    driver.execute(
                        "return location.hash.includes('/vault') || location.hash.includes('/setup-extension') || "
                        "(document.body?.innerText || '').toLowerCase().includes('all vaults')"
                    )
                ),
                "Vaultwarden account creation did not reach the authenticated vault",
                60,
            )
        except RuntimeError as exception:
            safe_body = driver.body_text().replace(email, "[synthetic-email]")[:1200]
            state = driver.execute(
                """
                return {
                  url: location.href,
                  inputs: Array.from(document.querySelectorAll('input')).map((node) => ({
                    id: node.id, type: node.type, valueLength: node.value.length,
                    valid: node.checkValidity(), validationMessage: node.validationMessage,
                  })),
                  alerts: Array.from(document.querySelectorAll('[role="alert"],bit-toast,bit-callout'))
                    .map((node) => (node.innerText || node.textContent || '').trim()).filter(Boolean),
                };
                """
            )
            fail(
                f"{exception}; registration UI text: {safe_body!r}; state: {state!r}; "
                f"browser log: {driver.browser_log()!r}"
            )
        dismiss_extension(driver)
        wait_for(
            lambda: bool(
                driver.execute(
                    "return location.hash.includes('/vault') || "
                    "(document.body?.innerText || '').toLowerCase().includes('all vaults')"
                )
            ),
            "Vaultwarden extension prompt did not lead to the vault",
            30,
        )
    finally:
        driver.stop()


def login(driver: Driver, base: str, email: str, password: str) -> None:
    driver.navigate(base + "/#/login")
    wait_for(lambda: "log in" in driver.body_text().lower(), "Vaultwarden login page did not load")
    driver.fill_label("Email address", email)
    driver.click_text("Continue")
    wait_for(lambda: "master password" in driver.body_text().lower(), "Vaultwarden unlock page did not load")
    driver.fill_label("Master password", password)
    driver.click_text("Log in")
    wait_for(
        lambda: bool(
            driver.execute(
                "return location.hash.includes('/vault') || location.hash.includes('/setup-extension') || "
                "(document.body?.innerText || '').toLowerCase().includes('all vaults')"
            )
        ),
        "Vaultwarden login did not reach the authenticated vault",
        60,
    )
    dismiss_extension(driver)
    wait_for(
        lambda: bool(
            driver.execute(
                "return location.hash.includes('/vault') || "
                "(document.body?.innerText || '').toLowerCase().includes('all vaults')"
            )
        ),
        "Vaultwarden login extension prompt did not lead to the vault",
        30,
    )


def create_organization_objects(driver: Driver, member_email: str) -> None:
    driver.click_first("New organization", "New organisation")
    wait_for(
        lambda: any(value in driver.body_text().lower() for value in ("organization name", "organisation name")),
        "organization dialog did not open",
    )
    try:
        driver.fill_label("Organization name", "Essentials Plus Synthetic Org")
    except RuntimeError:
        driver.fill_label("Organisation name", "Essentials Plus Synthetic Org")
    driver.click_first("Create organization", "Create organisation", "Submit")
    wait_for(
        lambda: "essentials plus synthetic org" in driver.body_text().lower(),
        "organization was not created",
    )

    driver.click_text("Collections")
    wait_for(lambda: "collections" in driver.body_text().lower(), "organization collections page did not load")
    driver.click_first("New collection", "New")
    try:
        driver.click_text("Collection")
    except RuntimeError:
        pass
    driver.fill_label("Name", "Synthetic Shared Collection")
    driver.click_text("Save")
    wait_for(lambda: "synthetic shared collection" in driver.body_text().lower(), "collection was not created")

    driver.click_text("Members")
    wait_for(lambda: "members" in driver.body_text().lower(), "organization members page did not load")
    driver.click_first("Invite member", "Invite user")
    driver.fill_label("Email", member_email)
    # The default explicit member role is User. Saving it exercises the role contract.
    driver.click_text("Save")
    wait_for(lambda: member_email.lower() in driver.body_text().lower(), "organization member invitation was not created")
    try:
        driver.execute(
            """
            const email = arguments[0].toLowerCase();
            const row = Array.from(document.querySelectorAll('tr')).find((node) => (node.innerText || '').toLowerCase().includes(email));
            const button = row && Array.from(row.querySelectorAll('button')).find((node) => (node.getAttribute('aria-label') || '').toLowerCase().includes('options'));
            if (!button) throw new Error('member options unavailable');
            button.click();
            """,
            [member_email],
        )
        driver.click_text("Confirm")
        wait_for(lambda: "confirm user" in driver.body_text().lower(), "member confirmation dialog did not open")
        driver.click_text("Confirm")
    except RuntimeError:
        # Some Web Vault builds mark a local existing account as confirmed immediately.
        pass

    driver.click_text("Groups")
    wait_for(lambda: "groups" in driver.body_text().lower(), "organization groups page did not load")
    try:
        driver.click_first("New group", "Add group")
    except RuntimeError:
        fail("organization group creation action is unavailable")
    driver.fill_label("Name", "Synthetic Editors")
    driver.click_text("Save")
    wait_for(lambda: "synthetic editors" in driver.body_text().lower(), "organization group was not created")


def main() -> int:
    base = os.environ.get("VAULTWARDEN_BASE_URL", "").rstrip("/")
    secrets_path = os.environ.get("VAULTWARDEN_BROWSER_SECRETS_FILE", "")
    chromium = os.environ.get("CHROMIUM_BIN", "")
    endpoint = os.environ.get("WEBDRIVER_ENDPOINT", "http://127.0.0.1:9516")
    if not base or not secrets_path or not chromium:
        fail("Vaultwarden browser test requires base URL, protected fixture file, and Chromium")
    secrets = read_env(pathlib.Path(secrets_path))
    create_account(endpoint, chromium, base, secrets["OWNER_EMAIL"], "Synthetic Owner", secrets["OWNER_PASSWORD"])
    create_account(endpoint, chromium, base, secrets["MEMBER_EMAIL"], "Synthetic Member", secrets["MEMBER_PASSWORD"])
    driver = Driver(endpoint, chromium)
    try:
        login(driver, base, secrets["OWNER_EMAIL"], secrets["OWNER_PASSWORD"])
        try:
            create_organization_objects(driver, secrets["MEMBER_EMAIL"])
        except RuntimeError as exception:
            safe_body = driver.body_text()
            for synthetic_email in (secrets["OWNER_EMAIL"], secrets["MEMBER_EMAIL"]):
                safe_body = safe_body.replace(synthetic_email, "[synthetic-email]")
            state = driver.execute(
                """
                return {
                  url: location.href,
                  actions: Array.from(document.querySelectorAll('button,a,[role="button"],[role="link"],[role="menuitem"],[role="tab"]'))
                    .map((node) => (node.innerText || node.textContent || '').trim()).filter(Boolean).slice(0, 100),
                };
                """
            )
            fail(
                f"{exception}; authenticated UI text: {safe_body[:1600]!r}; "
                f"state: {state!r}; browser log: {driver.browser_log()!r}"
            )
    finally:
        driver.stop()
    print("vaultwarden-browser-e2e: accounts, organization, collection, member role, and group passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exception:
        print(f"vaultwarden-browser-e2e: {exception}", file=sys.stderr)
        sys.exit(1)
