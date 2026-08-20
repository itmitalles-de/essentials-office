#!/usr/bin/env bash
# Validate the Essentials+ Office module contract, schema, and hard boundaries.
set -Eeuo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
CONTRACT=${OFFICE_MODULE_CONTRACT:-"$PROJECT_DIR/office-modules.json"}
SCHEMA=${OFFICE_MODULE_SCHEMA:-"$PROJECT_DIR/schemas/office-modules.schema.json"}

die() {
  printf 'office-modules-contract-test: %s\n' "$*" >&2
  exit 1
}

for command in docker jq rg sort; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
for file in "$CONTRACT" "$SCHEMA"; do
  [ -f "$file" ] || die "missing contract artifact: $file"
  jq empty "$file"
done

if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1; then
  python3 - "$SCHEMA" "$CONTRACT" <<'PY'
import json
import sys
from jsonschema import Draft202012Validator

with open(sys.argv[1], encoding="utf-8") as source:
    schema = json.load(source)
with open(sys.argv[2], encoding="utf-8") as source:
    contract = json.load(source)
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema).validate(contract)
PY
else
  docker run --rm --network none --entrypoint python \
    -v "$PROJECT_DIR:/repo:ro" python:3.13-alpine \
    -c 'import json; contract=json.load(open("/repo/office-modules.json")); assert contract["schemaVersion"] == "1.0.0"' ||
    die 'minimal schema fallback failed'
fi

jq -e '
  .contractVersion == "2.1.0" and
  .product.displayName == "Essentials+ Office" and
  .product.brand == "Essentials Plus" and
  .states == ["not_installed", "needs_configuration", "disabled", "enabled", "degraded"] and
  ([.groups[].displayName] | sort) == ([
    "Dateien und Groupware", "Intranet und Wissen", "Dokumente", "Kommunikation",
    "Sicherheit", "People und HR", "Integrationen", "Kundenspezifisch"
  ] | sort) and
  ([.groups[].id] | length == (unique | length)) and
  ([.modules[].id] | length == (unique | length)) and
  ([.modules[] | select(.id != "nextcloud-core") | .required] | all(. == false)) and
  ([.modules[] | select(.id == "nextcloud-core" and .required == true and .defaultState == "enabled")] | length == 1) and
  ([.modules[] | select(.id != "nextcloud-core") | .defaultState] | all(. == "disabled" or . == "not_installed")) and
  ([.modules[].group] - [.groups[].id] | length == 0) and
  ([.modules[].dependencies[]] - [.modules[].id] | length == 0) and
  ([.modules[].conflicts[]] - [.modules[].id] | length == 0) and
  ([.modules[] | .dataOwnership.sharedDatabase] | all(. == false)) and
  ([.modules[] | .deactivation.deletesData] | all(. == false)) and
  ([.modules[] | .deactivation.stopsService] | all(. == false)) and
  ([.modules[] | .activation.hostControl] | all(. == false)) and
  ([.modules[] | select(.id == "intranet-lite") | .nextcloudApps[] |
    select(.visibilityMode == "platform-global") | .id] | sort) ==
    (["announcementcenter", "circles", "collectives", "forms"] | sort) and
  ([.modules[] | select(.id == "hr-lite") | .nextcloudApps[] |
    select(.visibilityMode == "platform-global") | .id] | sort) ==
    (["collectives", "forms"] | sort) and
  ([.modules[] | select(.id == "collabora") | .nextcloudApps[] |
    select(.visibilityMode == "platform-global") | .id] == ["richdocuments"]) and
  ([.modules[] | select(.id == "talk") | .nextcloudApps[] |
    select(.visibilityMode == "platform-global") | .id] == ["spreed"]) and
  ([.modules[] | select(.id == "appointments") | .nextcloudApps[] |
    select(.source == "repository" and .visibilityMode == "platform-global") | .id] == ["appointments"]) and
  ([.modules[] | select(.id == "appointments") | .defaultState] == ["disabled"]) and
  ([.modules[] | select(.id == "vaultwarden") | .composeServices] == [["vaultwarden"]]) and
  ([.modules[] | select(.id == "essentials-calls") | .externalServices[0].repository] == ["itmitalles-de/visual-pbx"])
' "$CONTRACT" >/dev/null || die 'module contract violates an Essentials+ Office invariant'

compose_services=$(jq -r '.services | keys[]' < <(
  POSTGRES_PASSWORD=placeholder NEXTCLOUD_ADMIN_PASSWORD=placeholder REDIS_PASSWORD=placeholder \
  POSTGRES_DB=nextcloud POSTGRES_USER=nextcloud NEXTCLOUD_ADMIN_USER=admin \
  NEXTCLOUD_TRUSTED_DOMAINS=cloud.itmitalles.de TRUSTED_PROXIES=172.18.0.0/16 \
  docker compose -f "$PROJECT_DIR/compose.yaml" config --format json
))
if printf '%s\n' "$compose_services" | grep -Eiq 'vaultwarden|collabora|turn|mailcow|visual.?pbx|calls'; then
  die 'the base Compose model unexpectedly contains an optional service'
fi
if rg -n 'reverse_proxy[[:space:]].*(visual-pbx|essentials-calls|\bpbx\b)' \
  "$PROJECT_DIR"/Caddyfile*.example "$PROJECT_DIR"/caddy/*.example >/dev/null 2>&1; then
  die 'the repository must not proxy Visual PBX or Essentials+ Calls'
fi

printf 'office-modules-contract-test: schema, states, groups, inactive defaults, and service boundaries passed\n'
