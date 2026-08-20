#!/usr/bin/env python3
"""Raw-WebDriver acceptance for the Appointments Nextcloud app."""

from __future__ import annotations

import datetime as dt
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
from zoneinfo import ZoneInfo

from admin_center import WebDriver, fail, login, read_env, wait_for


ORGANIZATION_SLUG = "physiotherapie-beispiel"
TIMEZONE = "Europe/Berlin"


class AppointmentsDriver(WebDriver):
    def execute(self, script: str, args: list[object] | None = None) -> object:
        return self.request(
            "POST",
            f"/session/{self.session_id}/execute/sync",
            {"script": script, "args": args or []},
        )

    def execute_async(self, script: str, args: list[object] | None = None) -> object:
        return self.request(
            "POST",
            f"/session/{self.session_id}/execute/async",
            {"script": script, "args": args or []},
        )

    def set_value(self, selector: str, value: str, event_name: str = "input") -> None:
        result = self.execute(
            """
            const control = document.querySelector(arguments[0]);
            if (!control) return false;
            control.value = arguments[1];
            control.dispatchEvent(new Event(arguments[2], {bubbles: true}));
            return true;
            """,
            [selector, value, event_name],
        )
        if result is not True:
            fail(f"browser control not found: {selector}")


def browser_fetch(
    driver: AppointmentsDriver,
    url: str,
    method: str = "GET",
    body: object | None = None,
) -> dict[str, object]:
    value = driver.execute_async(
        """
        const done = arguments[arguments.length - 1];
        const url = arguments[0];
        const method = arguments[1];
        const body = arguments[2];
        const headers = {'Accept': 'application/json'};
        if (body !== null) headers['Content-Type'] = 'application/json';
        if (window.OC && OC.requestToken) headers.requesttoken = OC.requestToken;
        fetch(url, {
            method,
            credentials: 'same-origin',
            headers,
            body: body === null ? undefined : JSON.stringify(body),
        }).then(async (response) => {
            const text = await response.text();
            let payload = null;
            try { payload = text ? JSON.parse(text) : null; } catch (_error) { payload = null; }
            done({status: response.status, payload, cacheControl: response.headers.get('cache-control') || ''});
        }).catch((_error) => done({status: 0, payload: null}));
        """,
        [url, method, body],
    )
    if not isinstance(value, dict) or not isinstance(value.get("status"), int):
        fail("browser API request did not return a status")
    return value


def api_payload(response: dict[str, object], expected_status: int) -> dict[str, object]:
    if response.get("status") != expected_status:
        fail(f"Appointments API returned HTTP {response.get('status')} instead of {expected_status}")
    payload = response.get("payload")
    if not isinstance(payload, dict):
        fail("Appointments API did not return a JSON object")
    return payload


def configure_bookable_service(
    driver: AppointmentsDriver,
    base_url: str,
    user: str,
    password: str,
) -> tuple[str, str, str, str]:
    """Create staff, working hours, and a service through the authenticated API."""
    login(driver, base_url, user, password)
    driver.navigate(f"{base_url}/apps/appointments/")
    wait_for(
        lambda: driver.execute("return Boolean(document.querySelector('[data-testid=\"internal-calendar\"]'))") is True,
        "Appointments administration did not load for setup",
    )
    context = api_payload(browser_fetch(driver, f"{base_url}/apps/appointments/api/v1/context"), 200)
    organizations = context.get("organizations")
    organization = next(
        (
            item
            for item in organizations
            if isinstance(item, dict) and item.get("slug") == ORGANIZATION_SLUG
        ),
        None,
    ) if isinstance(organizations, list) else None
    if not isinstance(organization, dict) or not organization.get("id"):
        fail("demo organization was unavailable for administrator setup")
    organization_id = str(organization["id"])
    organization_api = f"{base_url}/apps/appointments/api/v1/organizations/{urllib.parse.quote(organization_id)}"
    catalog = api_payload(browser_fetch(driver, f"{organization_api}/catalog"), 200)
    locations = catalog.get("locations")
    location = next(
        (item for item in locations if isinstance(item, dict) and item.get("id") and item.get("active") is not False),
        None,
    ) if isinstance(locations, list) else None
    if not isinstance(location, dict):
        fail("demo location was unavailable for administrator setup")
    location_id = str(location["id"])
    suffix = str(int(time.time()))
    staff = api_payload(
        browser_fetch(
            driver,
            f"{organization_api}/staff",
            "POST",
            {
                "slug": f"e2e-staff-{suffix}",
                "displayName": "E2E Booking Staff",
                "description": "Fictional browser-test profile",
                "qualifications": "Acceptance testing",
                "timezone": TIMEZONE,
                "publicBooking": True,
                "active": True,
                "locationIds": [location_id],
            },
        ),
        201,
    )
    staff_id = staff.get("id")
    if not isinstance(staff_id, str) or not staff_id:
        fail("administrator setup did not create a staff profile")
    second_staff = api_payload(
        browser_fetch(
            driver,
            f"{organization_api}/staff",
            "POST",
            {
                "slug": f"e2e-staff-secondary-{suffix}",
                "displayName": "E2E Secondary Staff",
                "description": "Fictional browser-test profile",
                "qualifications": "Acceptance testing",
                "timezone": TIMEZONE,
                "publicBooking": True,
                "active": True,
                "locationIds": [location_id],
            },
        ),
        201,
    )
    second_staff_id = second_staff.get("id")
    if not isinstance(second_staff_id, str) or not second_staff_id:
        fail("administrator setup did not create the secondary staff profile")
    rules = [
        {
            "weekday": weekday,
            "startMinute": 8 * 60,
            "endMinute": 18 * 60,
            "type": "available",
            "validFrom": "",
            "validUntil": "",
        }
        for weekday in range(1, 8)
    ]
    for configured_staff_id in (staff_id, second_staff_id):
        api_payload(
            browser_fetch(
                driver,
                f"{organization_api}/availability/staff/{urllib.parse.quote(configured_staff_id)}",
                "PUT",
                {"rules": rules, "exceptions": []},
            ),
            200,
        )
    service_slug = f"e2e-service-{suffix}"
    service = api_payload(
        browser_fetch(
            driver,
            f"{organization_api}/services",
            "POST",
            {
                "slug": service_slug,
                "name": "E2E Booking Service",
                "shortName": "E2E",
                "description": "Fictional browser-test service",
                "durationMinutes": 30,
                "bufferBeforeMinutes": 5,
                "bufferAfterMinutes": 5,
                "currency": "EUR",
                "confirmationMode": "automatic",
                "minimumNoticeMinutes": 0,
                "maximumHorizonDays": 60,
                "cancellationNoticeMinutes": 0,
                "rescheduleNoticeMinutes": 0,
                "visibility": "public",
                "active": True,
                "color": "#00679e",
                "appointmentType": "on_site",
                "phoneRequired": False,
                "staffIds": [staff_id, second_staff_id],
                "locationIds": [location_id],
                "resourceRequirements": [],
                "formFields": [
                    {
                        "type": "text",
                        "label": "Public booking reference",
                        "helpText": "Fictional public acceptance-test value",
                        "required": False,
                        "order": 0,
                        "visibility": "public",
                        "validation": {"max": 80},
                    },
                    {
                        "type": "text",
                        "label": "Internal handling reference",
                        "helpText": "Must never be exposed through a customer token",
                        "required": False,
                        "order": 1,
                        "visibility": "internal",
                        "validation": {"max": 80},
                    },
                ],
            },
        ),
        201,
    )
    service_id = service.get("id")
    assigned_staff = service.get("staffIds")
    if not isinstance(service_id, str) or not service_id or set(assigned_staff or []) != {staff_id, second_staff_id}:
        fail("administrator setup did not assign the new service to its staff profile")
    fields = service.get("formFields")
    public_field = next(
        (field for field in fields if isinstance(field, dict) and field.get("visibility") == "public"),
        None,
    ) if isinstance(fields, list) else None
    internal_field = next(
        (field for field in fields if isinstance(field, dict) and field.get("visibility") == "internal"),
        None,
    ) if isinstance(fields, list) else None
    if not isinstance(public_field, dict) or not isinstance(public_field.get("id"), str):
        fail("administrator setup did not create the public booking field")
    if not isinstance(internal_field, dict) or not isinstance(internal_field.get("id"), str):
        fail("administrator setup did not create the internal booking field")
    return service_id, service_slug, str(public_field["id"]), str(internal_field["id"])


def selected_form_value(driver: AppointmentsDriver, name: str) -> str:
    value = driver.execute(
        """
        const value = new FormData(document.querySelector('#appointments-public-form')).get(arguments[0]);
        return value === null ? '' : String(value);
        """,
        [name],
    )
    return value if isinstance(value, str) else ""


def find_bookable_date(
    driver: AppointmentsDriver,
    base_url: str,
    service_id: str,
    location_id: str,
) -> tuple[str, dict[str, object]]:
    today = dt.datetime.now(ZoneInfo(TIMEZONE)).date()
    public_base = f"{base_url}/apps/appointments/public/v1/{ORGANIZATION_SLUG}/slots"
    for offset in range(3, 18):
        date = (today + dt.timedelta(days=offset)).isoformat()
        parameters = {"serviceId": service_id, "date": date, "timezone": TIMEZONE}
        if location_id:
            parameters["locationId"] = location_id
        response = browser_fetch(driver, public_base + "?" + urllib.parse.urlencode(parameters))
        if response.get("status") != 200:
            continue
        payload = response.get("payload")
        slots = payload.get("slots") if isinstance(payload, dict) else None
        if isinstance(slots, list) and slots and isinstance(slots[0], dict):
            return date, slots[0]
    fail("no public appointment slot was available in the next 17 days")


def create_public_booking(
    driver: AppointmentsDriver,
    base_url: str,
    service_id: str,
    service_slug: str,
    public_field_id: str,
) -> dict[str, object]:
    started = time.monotonic()
    driver.navigate(
        f"{base_url}/apps/appointments/book/{ORGANIZATION_SLUG}?"
        + urllib.parse.urlencode({"service": service_slug})
    )
    wait_for(
        lambda: driver.execute("return document.querySelectorAll('[data-testid=\"public-service\"]').length") > 0,
        "public booking services did not load",
    )
    selected = driver.execute(
        """
        const input = Array.from(document.querySelectorAll('[data-testid="public-service"]'))
            .find((candidate) => candidate.value === arguments[0]);
        if (!input) return false;
        input.click();
        return true;
        """,
        [service_id],
    )
    if selected is not True:
        fail("administrator-created service was missing from public booking")
    selected_service_id = selected_form_value(driver, "serviceId")
    location_id = selected_form_value(driver, "locationId")
    if selected_service_id != service_id:
        fail("public booking did not select the administrator-created service")
    date, _slot = find_bookable_date(driver, base_url, selected_service_id, location_id)

    driver.click("#appointments-public-next")
    wait_for(
        lambda: driver.execute("return !document.querySelector('[data-booking-step=\"2\"]').hidden") is True,
        "public booking did not advance to time selection",
    )
    driver.set_value('[data-testid="public-date"]', date, "change")
    wait_for(
        lambda: driver.execute("return document.querySelectorAll('[data-testid=\"public-slot\"]').length") > 0,
        "public booking slots did not render",
    )
    driver.click('[data-testid="public-slot"]')
    selected_start = selected_form_value(driver, "slot")
    driver.click("#appointments-public-next")
    wait_for(
        lambda: driver.execute("return !document.querySelector('[data-booking-step=\"3\"]').hidden") is True,
        "public booking did not advance to contact details",
    )

    suffix = str(int(time.time()))
    first_name = "Browser"
    last_name = "Appointment" + suffix
    driver.type('[name="firstName"]', first_name)
    driver.type('[name="lastName"]', last_name)
    driver.type('[name="email"]', f"browser-appointment-{suffix}@example.invalid")
    public_answer = f"public-{suffix}"
    driver.type(f'[name="custom-{public_field_id}"]', public_answer)
    driver.click("#appointments-public-next")
    wait_for(
        lambda: driver.execute("return !document.querySelector('[data-booking-step=\"4\"]').hidden") is True,
        "public booking did not advance to review",
    )
    driver.click('[name="privacyAccepted"]')
    minimum_elapsed = 4.0 - (time.monotonic() - started)
    if minimum_elapsed > 0:
        time.sleep(minimum_elapsed)
    driver.click('[data-testid="public-submit"]')
    wait_for(
        lambda: driver.execute("return !document.querySelector('[data-testid=\"booking-confirmation\"]').hidden") is True,
        "public booking confirmation did not appear",
    )
    evidence = driver.execute(
        """
        const manage = document.querySelector('#appointments-confirmation-manage');
        const details = document.querySelectorAll('#appointments-confirmation-details dd');
        return {
            bookingNumber: details.length ? details[0].textContent.trim() : '',
            manageHref: manage ? manage.href : '',
        };
        """
    )
    if not isinstance(evidence, dict):
        fail("booking confirmation evidence is missing")
    booking_number = evidence.get("bookingNumber")
    manage_href = evidence.get("manageHref")
    if not isinstance(booking_number, str) or not booking_number:
        fail("booking confirmation did not expose a booking number")
    if not isinstance(manage_href, str) or not manage_href:
        fail("booking confirmation did not expose a management link")
    parsed = urllib.parse.urlsplit(manage_href)
    if parsed.query or not parsed.fragment or not parsed.path.endswith("/apps/appointments/manage"):
        fail("management token was not confined to the URL fragment")
    token = urllib.parse.unquote(parsed.fragment)
    return {
        "bookingNumber": booking_number,
        "firstName": first_name,
        "lastName": last_name,
        "token": token,
        "serviceId": selected_service_id,
        "locationId": location_id,
        "date": date,
        "selectedStart": selected_start,
        "publicFieldId": public_field_id,
        "publicAnswer": public_answer,
    }


def cancel_and_release_slot(
    driver: AppointmentsDriver,
    base_url: str,
    booking: dict[str, object],
) -> dict[str, object]:
    token = str(booking["token"])
    manage_url = f"{base_url}/apps/appointments/manage#{urllib.parse.quote(token, safe='')}"
    driver.navigate(manage_url)
    wait_for(
        lambda: driver.execute("return !document.querySelector('#appointments-manage-content').hidden") is True,
        "secure appointment management did not load",
    )
    if driver.execute("return window.location.hash") != "":
        fail("management token remained in the browser address after initial parsing")

    manage_payload = api_payload(
        browser_fetch(
            driver,
            f"{base_url}/apps/appointments/public/v1/manage/view",
            "POST",
            {"token": token},
        ),
        200,
    )
    appointment = manage_payload.get("appointment")
    if not isinstance(appointment, dict):
        fail("management view did not return the appointment")
    if appointment.get("internalNote") is not None:
        fail("management view exposed an internal note")
    service = appointment.get("service")
    staff = appointment.get("staff")
    location = appointment.get("location")
    if not isinstance(service, dict) or not isinstance(staff, dict):
        fail("management view did not expose scheduling identifiers")
    management_slots = api_payload(
        browser_fetch(
            driver,
            f"{base_url}/apps/appointments/public/v1/manage/slots",
            "POST",
            {
                "token": token,
                "date": booking["date"],
                "staffId": "unauthorized-staff-selection",
                "locationId": "unauthorized-location-selection",
            },
        ),
        200,
    ).get("slots")
    expected_location_id = str(location["id"]) if isinstance(location, dict) and location.get("id") else None
    if not isinstance(management_slots, list) or not management_slots:
        fail("customer management did not return slots for the existing assignment")
    if any(
        not isinstance(slot, dict)
        or str(slot.get("staffId", "")) != str(staff.get("id", ""))
        or slot.get("locationId") != expected_location_id
        for slot in management_slots
    ):
        fail("customer management exposed slots outside the existing staff or location assignment")

    driver.click('[data-testid="manage-cancel"]')
    wait_for(
        lambda: driver.execute("return document.querySelector('#appointments-cancel-dialog').open") is True,
        "cancellation confirmation did not open",
    )
    driver.click('#appointments-cancel-form button[type="submit"]')
    wait_for(
        lambda: "state-cancelled_by_customer"
        in str(driver.execute("return document.querySelector('#appointments-manage-state').className")),
        "customer cancellation did not update the appointment status",
    )

    parameters = {
        "serviceId": str(service.get("id", "")),
        "staffId": str(staff.get("id", "")),
        "date": str(booking["date"]),
        "timezone": TIMEZONE,
    }
    if isinstance(location, dict) and location.get("id"):
        parameters["locationId"] = str(location["id"])
    slots_payload = api_payload(
        browser_fetch(
            driver,
            f"{base_url}/apps/appointments/public/v1/{ORGANIZATION_SLUG}/slots?"
            + urllib.parse.urlencode(parameters),
        ),
        200,
    )
    slots = slots_payload.get("slots")
    original_timestamp = appointment.get("startTimestamp")
    released = next(
        (
            slot
            for slot in slots if isinstance(slot, dict) and slot.get("startTimestamp") == original_timestamp
        ),
        None,
    ) if isinstance(slots, list) else None
    if not isinstance(released, dict):
        fail("cancelled appointment slot was not released")
    return {
        "serviceId": str(service["id"]),
        "staffId": str(staff["id"]),
        "locationId": parameters.get("locationId"),
        "startsAt": released.get("startsAt"),
    }


def assert_same_slot_race(
    driver: AppointmentsDriver,
    base_url: str,
    released: dict[str, object],
) -> None:
    suffix = str(int(time.time()))
    base_payload: dict[str, object] = {
        "serviceId": released["serviceId"],
        "staffId": released["staffId"],
        "locationId": released.get("locationId"),
        "startsAt": released["startsAt"],
        "timezone": TIMEZONE,
        "privacyAccepted": True,
        "message": "",
        "formAnswers": {},
        "antiSpam": {"website": "", "bookingStartedAt": int(time.time()) - 5},
    }
    payloads = []
    for index in range(2):
        payload = dict(base_payload)
        payload["contact"] = {
            "firstName": "Race",
            "lastName": f"Request{index}",
            "email": f"appointment-race-{suffix}-{index}@example.invalid",
            "phone": "",
        }
        payloads.append(payload)
    statuses = driver.execute_async(
        """
        const done = arguments[arguments.length - 1];
        const url = arguments[0];
        const payloads = arguments[1];
        const headers = {'Accept': 'application/json', 'Content-Type': 'application/json'};
        if (window.OC && OC.requestToken) headers.requesttoken = OC.requestToken;
        Promise.all(payloads.map((payload) => fetch(url, {
            method: 'POST', credentials: 'same-origin', headers, body: JSON.stringify(payload),
        }).then((response) => response.status).catch(() => 0))).then(done);
        """,
        [f"{base_url}/apps/appointments/public/v1/{ORGANIZATION_SLUG}/book", payloads],
    )
    if not isinstance(statuses, list) or sorted(statuses) != [201, 409]:
        fail(f"same-slot race returned unexpected HTTP statuses: {statuses!r}")


def compose_command(project_dir: str, *arguments: str) -> list[str]:
    return ["docker", "compose", "--project-directory", project_dir, *arguments]


def assert_outbox_created(project_dir: str, core: dict[str, str]) -> None:
    prefix_result = subprocess.run(
        compose_command(
            project_dir,
            "exec",
            "-T",
            "-u",
            "www-data",
            "app",
            "php",
            "occ",
            "config:system:get",
            "dbtableprefix",
        ),
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    table_prefix = prefix_result.stdout.strip()
    if prefix_result.returncode != 0 or not re.fullmatch(r"[A-Za-z0-9_]+", table_prefix):
        fail("could not resolve a safe Nextcloud database table prefix")
    result = subprocess.run(
        compose_command(
            project_dir,
            "exec",
            "-T",
            "db",
            "psql",
            "-U",
            core.get("POSTGRES_USER", "nextcloud"),
            "-d",
            core.get("POSTGRES_DB", "nextcloud"),
            "-Atc",
            f"SELECT count(*) FROM {table_prefix}appt_mail_outbox",
        ),
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        fail("could not verify the appointment mail outbox")
    try:
        count = int(result.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        fail("appointment mail outbox count was not numeric")
    if count < 1:
        fail("public booking did not create a mail outbox entry")


def add_user_to_group(project_dir: str, user: str, group: str) -> None:
    result = subprocess.run(
        compose_command(
            project_dir,
            "exec",
            "-T",
            "-u",
            "www-data",
            "app",
            "php",
            "occ",
            "group:adduser",
            group,
            user,
        ),
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        fail("could not add the tenant-isolation user to its organization role group")


def internal_evidence_and_second_tenant(
    driver: AppointmentsDriver,
    base_url: str,
    user: str,
    password: str,
    booking: dict[str, object],
    project_dir: str,
    tenant_user: str,
    public_field_id: str,
    internal_field_id: str,
) -> tuple[str, str, str]:
    login(driver, base_url, user, password)
    driver.navigate(f"{base_url}/apps/appointments/")
    wait_for(
        lambda: driver.execute("return Boolean(document.querySelector('[data-testid=\"internal-calendar\"]'))") is True,
        "internal appointment calendar did not load",
    )
    driver.type("#appointments-search", str(booking["bookingNumber"]))
    wait_for(
        lambda: str(booking["bookingNumber"]) in driver.source()
        and str(booking["lastName"]) in driver.source(),
        "public booking did not become visible in the internal calendar",
    )
    current_url = str(driver.execute("return window.location.href"))
    if str(booking["bookingNumber"]) in current_url:
        fail("appointment search data leaked into the browser URL")

    context_response = browser_fetch(driver, f"{base_url}/apps/appointments/api/v1/context")
    if "no-store" not in str(context_response.get("cacheControl", "")).lower():
        fail("internal appointment context was cacheable")
    context = api_payload(context_response, 200)
    organizations = context.get("organizations")
    if not isinstance(organizations, list):
        fail("internal appointment context did not contain organizations")
    organization = next(
        (
            item
            for item in organizations
            if isinstance(item, dict) and item.get("slug") == ORGANIZATION_SLUG
        ),
        None,
    )
    if not isinstance(organization, dict) or not organization.get("id"):
        fail("demo appointment organization was missing from internal context")
    organization_id = str(organization["id"])
    search = api_payload(
        browser_fetch(
            driver,
            f"{base_url}/apps/appointments/api/v1/organizations/{urllib.parse.quote(organization_id)}/appointments/search",
            "POST",
            {"search": booking["bookingNumber"]},
        ),
        200,
    )
    appointments = search.get("appointments")
    if not isinstance(appointments, list) or len(appointments) != 1:
        fail("internal booking-number search did not return exactly one appointment")
    appointment = appointments[0]
    if not isinstance(appointment, dict) or not appointment.get("id"):
        fail("internal search did not expose the tenant-scoped appointment ID")
    appointment_id = str(appointment["id"])
    internal_answer = f"internal-{int(time.time())}"
    updated = api_payload(
        browser_fetch(
            driver,
            f"{base_url}/apps/appointments/api/v1/organizations/{urllib.parse.quote(organization_id)}/appointments/{urllib.parse.quote(appointment_id)}",
            "PUT",
            {
                "formAnswers": {
                    public_field_id: booking["publicAnswer"],
                    internal_field_id: internal_answer,
                },
            },
        ),
        200,
    )
    internal_answers = updated.get("formAnswers")
    answer_map = {
        str(answer.get("fieldId")): answer.get("value")
        for answer in internal_answers
        if isinstance(answer, dict) and answer.get("fieldId")
    } if isinstance(internal_answers, list) else {}
    if answer_map.get(public_field_id) != booking["publicAnswer"] or answer_map.get(internal_field_id) != internal_answer:
        fail("internal appointment update did not preserve public and internal form answers")
    customer_export = api_payload(
        browser_fetch(
            driver,
            f"{base_url}/apps/appointments/public/v1/manage/export",
            "POST",
            {"token": booking["token"]},
        ),
        200,
    )
    exported_answers = customer_export.get("formAnswers")
    exported_map = {
        str(answer.get("fieldId")): answer.get("value")
        for answer in exported_answers
        if isinstance(answer, dict) and answer.get("fieldId")
    } if isinstance(exported_answers, list) else {}
    if exported_map != {public_field_id: booking["publicAnswer"]}:
        fail("customer data export omitted a public answer or exposed an internal answer")

    tenant_slug = f"appointments-e2e-{int(time.time())}"
    tenant = api_payload(
        browser_fetch(
            driver,
            f"{base_url}/apps/appointments/api/v1/organizations",
            "POST",
            {
                "name": "Appointments E2E Tenant",
                "slug": tenant_slug,
                "timezone": TIMEZONE,
                "locale": "en",
            },
        ),
        201,
    )
    tenant_organization = tenant.get("organization")
    if not isinstance(tenant_organization, dict) or not tenant_organization.get("id"):
        fail("second appointment organization was not created")
    tenant_id = str(tenant_organization["id"])
    api_payload(
        browser_fetch(
            driver,
            f"{base_url}/apps/appointments/api/v1/organizations/{urllib.parse.quote(tenant_id)}/staff",
            "POST",
            {
                "slug": f"tenant-private-staff-{int(time.time())}",
                "userUid": user,
                "displayName": "Tenant Private Staff",
                "timezone": TIMEZONE,
                "publicBooking": False,
                "active": True,
                "calendarUri": "private-calendar-uri",
                "locationIds": [],
            },
        ),
        201,
    )
    add_user_to_group(project_dir, tenant_user, f"appointments-{tenant_slug}-manager")
    return organization_id, appointment_id, tenant_id


def assert_tenant_isolation(
    endpoint: str,
    chromium: str,
    base_url: str,
    user: str,
    password: str,
    first_organization_id: str,
    appointment_id: str,
    second_organization_id: str,
) -> None:
    driver = AppointmentsDriver(endpoint)
    try:
        driver.start(chromium)
        login(driver, base_url, user, password)
        context_response = browser_fetch(driver, f"{base_url}/apps/appointments/api/v1/context")
        if "no-store" not in str(context_response.get("cacheControl", "")).lower():
            fail("tenant-scoped appointment context was cacheable")
        context = api_payload(context_response, 200)
        if context.get("users") not in ([], None):
            fail("non-administrator appointment context exposed the Nextcloud user directory")
        organizations = context.get("organizations")
        visible_ids = (
            {str(item["id"]) for item in organizations if isinstance(item, dict) and item.get("id")}
            if isinstance(organizations, list)
            else set()
        )
        if first_organization_id in visible_ids or second_organization_id not in visible_ids:
            fail("organization context violated tenant isolation")
        detail = browser_fetch(
            driver,
            f"{base_url}/apps/appointments/api/v1/organizations/{urllib.parse.quote(first_organization_id)}/appointments/{urllib.parse.quote(appointment_id)}",
        )
        listing = browser_fetch(
            driver,
            f"{base_url}/apps/appointments/api/v1/organizations/{urllib.parse.quote(first_organization_id)}/appointments",
        )
        if detail.get("status") not in (403, 404) or listing.get("status") not in (403, 404):
            fail("a user from another tenant could read appointment data")
        own_catalog_response = browser_fetch(
            driver,
            f"{base_url}/apps/appointments/api/v1/organizations/{urllib.parse.quote(second_organization_id)}/catalog",
        )
        if own_catalog_response.get("status") != 200:
            fail("tenant-isolation user could not access its own organization")
        own_catalog = api_payload(own_catalog_response, 200)
        if "operations" in own_catalog:
            fail("tenant manager received settings-only operation diagnostics")
        own_staff = own_catalog.get("staff")
        if not isinstance(own_staff, list) or not own_staff:
            fail("tenant manager catalog did not contain its configured staff profile")
        if any(
            isinstance(staff, dict) and ("userUid" in staff or "calendarUri" in staff)
            for staff in own_staff
        ):
            fail("tenant manager catalog exposed staff account or calendar bindings")
    finally:
        driver.stop()


def main() -> int:
    base_url = os.environ.get("BROWSER_BASE_URL", "").rstrip("/")
    core_env = os.environ.get("BROWSER_CORE_ENV_FILE", "")
    user_env = os.environ.get("BROWSER_USER_ENV_FILE", "")
    project_dir = os.environ.get("BROWSER_PROJECT_DIR", "")
    chromium = os.environ.get("CHROMIUM_BIN", "")
    endpoint = os.environ.get("WEBDRIVER_ENDPOINT", "http://127.0.0.1:9515")
    if not base_url or not core_env or not user_env or not project_dir or not chromium:
        fail("appointments browser test requires URL, protected env files, project directory, and Chromium")
    core = read_env(pathlib.Path(core_env))
    ordinary = read_env(pathlib.Path(user_env))
    setup_driver = AppointmentsDriver(endpoint)
    try:
        setup_driver.start(chromium)
        service_id, service_slug, public_field_id, internal_field_id = configure_bookable_service(
            setup_driver,
            base_url,
            core["NEXTCLOUD_ADMIN_USER"],
            core["NEXTCLOUD_ADMIN_PASSWORD"],
        )
    finally:
        setup_driver.stop()
    driver = AppointmentsDriver(endpoint)
    try:
        driver.start(chromium)
        booking = create_public_booking(driver, base_url, service_id, service_slug, public_field_id)
        first_organization, appointment, second_organization = internal_evidence_and_second_tenant(
            driver,
            base_url,
            core["NEXTCLOUD_ADMIN_USER"],
            core["NEXTCLOUD_ADMIN_PASSWORD"],
            booking,
            project_dir,
            ordinary["BROWSER_USER"],
            public_field_id,
            internal_field_id,
        )
        assert_outbox_created(project_dir, core)
    finally:
        driver.stop()
    management_driver = AppointmentsDriver(endpoint)
    try:
        management_driver.start(chromium)
        released = cancel_and_release_slot(management_driver, base_url, booking)
        assert_same_slot_race(management_driver, base_url, released)
    finally:
        management_driver.stop()
    assert_tenant_isolation(
        endpoint,
        chromium,
        base_url,
        ordinary["BROWSER_USER"],
        ordinary["BROWSER_PASSWORD"],
        first_organization,
        appointment,
        second_organization,
    )
    print("appointments-browser-e2e: booking, private-field export filtering, assignment pinning, outbox, cancellation, release, race, RBAC, and tenant isolation passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exception:
        print(f"appointments-browser-e2e: {exception}", file=sys.stderr)
        sys.exit(1)
