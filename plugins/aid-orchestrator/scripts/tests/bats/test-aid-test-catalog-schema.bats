#!/usr/bin/env bats
# aid-tier: t2
# test-aid-test-catalog-schema.bats — P066 Step 1.
#
# Validates the five schemas every later P066 step reads/writes against:
# test-catalog and test-audit-inventory (the audit's other schemas left with it on 2026-09-21).
#
# JSON-Schema tests use python3 + jsonschema (Draft 2020-12); they skip cleanly when the
# jsonschema package is unavailable rather than false-failing.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CATALOG_SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/test-catalog.schema.json"
  INVENTORY_SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/test-audit-inventory.schema.json"
}

teardown() {
  teardown_test_evidence_dir
}

_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

# _schema_validate <schema_file> <instance_file> — exit 0 valid, 1 invalid.
_schema_validate() {
  python3 - "$1" "$2" <<'PY'
import sys, json
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
inst = json.load(open(sys.argv[2]))
sys.exit(1 if list(Draft202012Validator(schema).iter_errors(inst)) else 0)
PY
}

_minimal_run_unit() {
  cat <<'JSON'
{
  "run_unit_id": "bats:scripts/tests/bats/test-example",
  "runner": "bats",
  "source_paths": ["scripts/lib/example.sh"],
  "production_surfaces": ["scripts/lib/example.sh"],
  "test_level": "suite",
  "risk_tags": [],
  "profiles": ["default"],
  "behavior_claims": [],
  "confidence": "medium",
  "command": {"type": "argv", "argv": ["bats", "scripts/tests/bats/test-example.bats"]},
  "runtime": {"fingerprint": "sha256:0123456789ab"},
  "isolation": {"temp_workspace": "unknown", "fixed_ports": [], "shared_paths": [], "lock_usage": [], "adapter_confidence": "static_parse"},
  "recommendation": "keep",
  "test_cases": [{"test_case_id": "t1", "name": "example works", "filter_expression": "example works"}]
}
JSON
}

@test "test-catalog.schema.json: minimal-valid document validates" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/catalog-valid.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "generated_at": "2026-07-29T00:00:00Z",
  "status": "proposed",
  "run_units": [$(_minimal_run_unit)],
  "source_pattern_mappings": [
    {"match_type": "prefix", "path_pattern": "scripts/lib/", "target_run_unit_ids": ["bats:scripts/tests/bats/test-example"], "classification": "production", "precedence": 1, "status": "proposed"}
  ],
  "mapping_approval": {"status": "proposed"}
}
JSON
  run _schema_validate "$CATALOG_SCHEMA" "$fixture"
  [ "$status" -eq 0 ]
}

@test "test-catalog.schema.json: command union rejects a bare scalar" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/catalog-bare-command.json"
  local unit
  unit="$(_minimal_run_unit | python3 -c 'import json,sys; d=json.load(sys.stdin); d["command"]="bats file.bats"; print(json.dumps(d))')"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "generated_at": "2026-07-29T00:00:00Z",
  "status": "proposed",
  "run_units": [$unit],
  "source_pattern_mappings": [],
  "mapping_approval": {"status": "proposed"}
}
JSON
  run _schema_validate "$CATALOG_SCHEMA" "$fixture"
  [ "$status" -eq 1 ]
}

@test "test-catalog.schema.json: mapping_approval approved requires approved_by/approved_at/reviewed_diff_hash" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/catalog-bad-mapping-approval.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "generated_at": "2026-07-29T00:00:00Z",
  "status": "approved",
  "run_units": [$(_minimal_run_unit)],
  "source_pattern_mappings": [],
  "mapping_approval": {"status": "approved"}
}
JSON
  run _schema_validate "$CATALOG_SCHEMA" "$fixture"
  [ "$status" -eq 1 ]
}

@test "test-catalog.schema.json: rejects an approved mapping row when the root mapping_approval is still proposed" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/catalog-premature-row-approval.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "generated_at": "2026-07-29T00:00:00Z",
  "status": "proposed",
  "run_units": [$(_minimal_run_unit)],
  "source_pattern_mappings": [
    {"match_type": "prefix", "path_pattern": "scripts/lib/", "target_run_unit_ids": ["bats:scripts/tests/bats/test-example"], "classification": "production", "precedence": 1, "status": "approved"}
  ],
  "mapping_approval": {"status": "proposed"}
}
JSON
  run _schema_validate "$CATALOG_SCHEMA" "$fixture"
  [ "$status" -eq 1 ]
}

@test "test-audit-inventory.schema.json: minimal-valid document validates" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/inventory-valid.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "generated_at": "2026-07-29T00:00:00Z",
  "runner_families": ["bats"],
  "entries": [{"run_unit_id": "bats:foo", "runner": "bats", "adapter": "bats", "confidence": "medium"}]
}
JSON
  run _schema_validate "$INVENTORY_SCHEMA" "$fixture"
  [ "$status" -eq 0 ]
}

