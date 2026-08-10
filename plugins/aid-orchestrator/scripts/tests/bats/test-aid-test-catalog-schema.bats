#!/usr/bin/env bats
# test-aid-test-catalog-schema.bats — P066 Step 1.
#
# Validates the five schemas every later P066 step reads/writes against:
# test-catalog, test-audit-state, test-audit-inventory,
# test-audit-consolidated-findings, test-audit-wave-artifact.
#
# JSON-Schema tests use python3 + jsonschema (Draft 2020-12) — the same idiom
# established in test-aid-c3-dispatch.bats; they skip cleanly when the
# jsonschema package is unavailable rather than false-failing.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CATALOG_SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/test-catalog.schema.json"
  STATE_SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/test-audit-state.schema.json"
  INVENTORY_SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/test-audit-inventory.schema.json"
  FINDINGS_SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/test-audit-consolidated-findings.schema.json"
  WAVE_SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/test-audit-wave-artifact.schema.json"
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

@test "test-audit-state.schema.json: minimal-valid discovering document validates" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/state-valid.json"
  cat > "$fixture" <<JSON
{"schema_version": "1.0.0", "audit_id": "a1", "scope": "repo", "mode": "static", "status": "discovering", "budget": {"minutes": 30}, "waves_completed": 0, "resume_token": null}
JSON
  run _schema_validate "$STATE_SCHEMA" "$fixture"
  [ "$status" -eq 0 ]
}

@test "test-audit-state.schema.json: rejects status:done with wrong waves_completed for its mode" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/state-invalid-waves.json"
  cat > "$fixture" <<JSON
{"schema_version": "1.0.0", "audit_id": "a1", "scope": "repo", "mode": "static", "status": "done", "budget": {"minutes": 30}, "waves_completed": 5, "resume_token": null}
JSON
  run _schema_validate "$STATE_SCHEMA" "$fixture"
  [ "$status" -eq 1 ]
}

@test "test-audit-state.schema.json: accepts correct waves_completed per mode (static=4, measure=5, full=6)" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  for pair in "static:4" "measure:5" "full:6"; do
    local mode="${pair%%:*}" waves="${pair##*:}"
    local fixture="$TEST_TMPDIR/state-valid-$mode.json"
    cat > "$fixture" <<JSON
{"schema_version": "1.0.0", "audit_id": "a1", "scope": "repo", "mode": "$mode", "status": "done", "budget": {"minutes": 30}, "waves_completed": $waves, "resume_token": null}
JSON
    run _schema_validate "$STATE_SCHEMA" "$fixture"
    [ "$status" -eq 0 ]
  done
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

@test "test-audit-consolidated-findings.schema.json: minimal-valid document validates" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/findings-valid.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "audit_id": "a1",
  "generated_at": "2026-07-29T00:00:00Z",
  "findings": [{"finding_id": "f1", "run_unit_id": "bats:foo", "category": "flake", "severity": "low", "evidence_refs": ["ref1"], "recommendation": "keep", "confidence": "medium", "falsification_check": "n/a"}]
}
JSON
  run _schema_validate "$FINDINGS_SCHEMA" "$fixture"
  [ "$status" -eq 0 ]
}

@test "test-audit-consolidated-findings.schema.json: rejects a quarantine recommendation with empty falsification_check" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/findings-bad-quarantine.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "audit_id": "a1",
  "generated_at": "2026-07-29T00:00:00Z",
  "findings": [{"finding_id": "f1", "run_unit_id": "bats:foo", "category": "flake", "severity": "high", "evidence_refs": ["ref1"], "recommendation": "quarantine", "confidence": "medium", "falsification_check": ""}]
}
JSON
  run _schema_validate "$FINDINGS_SCHEMA" "$fixture"
  [ "$status" -eq 1 ]
}

@test "test-audit-wave-artifact.schema.json: minimal-valid document validates" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/wave-valid.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "focus": "shard_portfolio",
  "wave": 1,
  "shard_id": "shard-0",
  "findings": [],
  "produced_at": "2026-07-29T00:00:00Z",
  "producer_agent_dispatch_id": "dispatch-1"
}
JSON
  run _schema_validate "$WAVE_SCHEMA" "$fixture"
  [ "$status" -eq 0 ]
}

@test "test-audit-wave-artifact.schema.json: shard_portfolio focus requires a non-null shard_id" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/wave-shard-portfolio-null-shard.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "focus": "shard_portfolio",
  "wave": 1,
  "shard_id": null,
  "findings": [],
  "produced_at": "2026-07-29T00:00:00Z",
  "producer_agent_dispatch_id": "dispatch-1"
}
JSON
  run _schema_validate "$WAVE_SCHEMA" "$fixture"
  [ "$status" -eq 1 ]
}

@test "test-audit-wave-artifact.schema.json: non-shard_portfolio focus rejects a non-null shard_id" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/wave-non-shard-nonnull-shard.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "focus": "adversarial_review",
  "wave": 3,
  "shard_id": "shard-0",
  "findings": [],
  "produced_at": "2026-07-29T00:00:00Z",
  "producer_agent_dispatch_id": "dispatch-1"
}
JSON
  run _schema_validate "$WAVE_SCHEMA" "$fixture"
  [ "$status" -eq 1 ]
}

@test "test-audit-wave-artifact.schema.json: missing producer_agent_dispatch_id fails validation" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local fixture="$TEST_TMPDIR/wave-invalid.json"
  cat > "$fixture" <<JSON
{
  "schema_version": "1.0.0",
  "focus": "shard_portfolio",
  "wave": 1,
  "shard_id": "shard-0",
  "findings": [],
  "produced_at": "2026-07-29T00:00:00Z"
}
JSON
  run _schema_validate "$WAVE_SCHEMA" "$fixture"
  [ "$status" -eq 1 ]
}
