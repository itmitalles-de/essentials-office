#!/usr/bin/env bash
# Verify security- and deployment-critical Appointments app invariants without a running Nextcloud.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_DIR/nextcloud-apps/appointments"

die() {
  printf 'appointments-contract: %s\n' "$*" >&2
  exit 1
}

for command in find python3 rg; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done

for relative in \
  appinfo/info.xml \
  appinfo/routes.php \
  lib/AppInfo/Application.php \
  lib/Migration/Version1000Date20260820090000.php \
  templates/index.php \
  templates/public-booking.php \
  templates/manage.php \
  js/internal.js \
  js/public-booking.js \
  js/manage.js \
  l10n/de.js \
  l10n/de.json \
  l10n/en.js \
  l10n/en.json; do
  [ -f "$APP_DIR/$relative" ] || die "missing app file: $relative"
done

routes="$APP_DIR/appinfo/routes.php"
migration="$APP_DIR/lib/Migration/Version1000Date20260820090000.php"

rg -q "'url' => '/manage'" "$routes" || die 'customer management page is not fragment-token compatible'
if rg -n "\{(token|managementToken)\}|/manage/\{" "$routes"; then
  die 'raw management tokens must never be URL path parameters'
fi
for endpoint in view slots cancel reschedule contact export ics; do
  rg -q "'/public/v1/manage/$endpoint'.*'verb' => 'POST'" "$routes" ||
    die "management endpoint is missing or not POST-only: $endpoint"
done

mapfile -t domain_tables < <(sed -n "s/.*createTable('\([^']*\)').*/\1/p" "$migration")
[ "${#domain_tables[@]}" -ge 15 ] || die 'migration does not contain the expected relational domain model'
for table in "${domain_tables[@]}"; do
  case "$table" in
    appt_org) continue ;;
  esac
  block=$(sed -n "/createTable('$table')/,/^        }/p" "$migration")
  rg -q "addColumn\('organization_id'" <<<"$block" || die "tenant key missing from table: $table"
done

duplicate_indexes=$(sed -n "s/.*add\(Unique\)\?Index(.*'\([^']*\)').*/\2/p" "$migration" | sort | uniq -d)
[ -z "$duplicate_indexes" ] || die "duplicate migration index name: $duplicate_indexes"

rg -q "addUniqueIndex\(\['token_hash'\]" "$migration" || die 'management token hashes are not uniquely constrained'
rg -q "addUniqueIndex\(\['idempotency_key'\]" "$migration" || die 'mail outbox is not idempotently constrained'
rg -q "addUniqueIndex\(\['organization_id', 'booking_number'\]" "$migration" || die 'booking numbers are not tenant-scoped and unique'

appointment_service="$APP_DIR/lib/Service/AppointmentService.php"
appointment_repository="$APP_DIR/lib/Service/AppointmentRepository.php"
availability_service="$APP_DIR/lib/Service/AvailabilityService.php"
catalog_service="$APP_DIR/lib/Service/CatalogService.php"
internal_controller="$APP_DIR/lib/Controller/InternalApiController.php"
input_validator="$APP_DIR/lib/Service/InputValidator.php"
rg -q "exportAnswers\(.*true\)" "$appointment_service" || die 'customer export does not request public form answers only'
rg -q "f\.visibility.*public" "$appointment_repository" || die 'form-answer export lacks a public-visibility database filter'
rg -q 'bool \$exactSelection = false' "$availability_service" || die 'customer rescheduling lacks exact assignment validation'
rg -q 'unset\(\$staff.*userUid.*calendarUri' "$catalog_service" || die 'staff account and calendar bindings are not permission-filtered'
rg -q 'unset\(\$result.*operations' "$catalog_service" || die 'operation diagnostics are not permission-filtered'
if rg -n 'respond\(.*false' "$internal_controller"; then
  die 'internal appointment API responses must not be cacheable'
fi
rg -q 'localDateTimeCandidates' "$input_validator" || die 'ambiguous local wall times are not rejected explicitly'

if rg -n --glob '*.js' --glob '*.php' '\.innerHTML\s*=|insertAdjacentHTML\s*\(' "$APP_DIR"; then
  die 'unsafe dynamic HTML insertion is forbidden in Appointments'
fi
if rg -n --glob '*.php' --glob '*.js' '(error_log|console\.log|logger->(debug|info|notice|warning|error)).*(email|phone|firstName|lastName|token)' "$APP_DIR"; then
  die 'possible personal data or token logging detected'
fi

python3 - "$APP_DIR" <<'PY'
import json
import pathlib
import re
import sys

app = pathlib.Path(sys.argv[1])
messages: set[str] = set()
patterns = (
    re.compile(r"(?:->t|(?:UI\.)?translate)\(\s*'((?:\\.|[^'\\])*)'"),
    re.compile(r'(?:->t|(?:UI\.)?translate)\(\s*"((?:\\.|[^"\\])*)"'),
)
for suffix in ("*.php", "*.js"):
    for source in app.rglob(suffix):
        if source.parent.name == "l10n":
            continue
        text = source.read_text(encoding="utf-8")
        for pattern in patterns:
            for match in pattern.finditer(text):
                value = match.group(1).replace(r"\'", "'").replace(r'\"', '"').replace(r"\\", "\\")
                messages.add(value)

for locale in ("de", "en"):
    payload = json.loads((app / "l10n" / f"{locale}.json").read_text(encoding="utf-8"))
    translated = payload.get("translations", {})
    missing = sorted(message for message in messages if message not in translated)
    if missing:
        raise SystemExit(f"appointments-contract: {locale} translations missing: {missing[:8]!r}")
PY

printf 'appointments-contract: routes, tenant keys, token handling, idempotency, assets, and DOM safety passed\n'
