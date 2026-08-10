#!/usr/bin/env bats
# test-aid-select-tests-emit-units.bats — P069 Step 9.
#
# Proves aid-select-tests.sh's --emit-units flag:
#   - the default (no-flag) path is unaffected (covered exhaustively by
#     test-aid-select-tests.bats already; not re-verified here)
#   - --emit-units produces membership-verified execution units matching
#     the identical selection a normal run would have made
#   - exit codes 0/3/10 are preserved: a D-selector-1 unverifiable path
#     still exits 3 and writes NO units file even with --emit-units given
#   - --emit-units with zero selected tests writes an empty, schema-valid
#     units file, not an error
#   - a run_unit_id with no catalog entry fails loudly, never silently

load test-helpers.bash

setup() {
  export TZ=UTC
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"
  git init -q -b main
  git config user.email "test@test.local"
  git config user.name "Test"
  mkdir -p plugins/aid-orchestrator/scripts \
           plugins/aid-orchestrator/defaults/schemas \
           .aid-o/config
  echo "base" > README.md
  git add -A
  git commit -q -m "base"
  BASE_SHA="$(git rev-parse HEAD)"
  export BASE_SHA

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SELECTOR="$AID_PLUGIN_PATH/scripts/aid-select-tests.sh"
  export SELECTOR
  SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/execution-unit.schema.json"
  export SCHEMA
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

commit_change() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  echo "changed" >> "$file"
  git add -A
  git commit -q -m "touch $file"
}

_write_catalog() {
  local status="${1:-unknown}"
  jq -n --arg s "$status" '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved",
    run_units: [
      {run_unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm", runner:"bats",
       source_paths:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"],
       production_surfaces:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"]},
       runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' | yq -P '.' > .aid-o/config/test-catalog.yaml
  git add -f .aid-o/config/test-catalog.yaml
  git commit -q -m "add catalog"
}

@test "--emit-units produces a membership-verified execution unit matching the normal selection" {
  _write_catalog "safe"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  local units_file="$TEST_TMPDIR/units.json"
  run "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file"
  [ "$status" -eq 0 ]
  [ -f "$units_file" ]

  run jq -r '.[0].unit_id' "$units_file"
  [ "$output" = "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm" ]
  run jq -r '.[0].membership_verified' "$units_file"
  [ "$output" = "true" ]
  run jq -r '.[0].membership_binding.catalog_fingerprint' "$units_file"
  [ "$output" = "sha256:aaaaaaaaaaaa" ]
  # P078: parallel_eligible was removed with the parallelism machinery —
  # a unit carries only what sequential execution needs, so the field must
  # be ABSENT, not false.
  run jq -r '.[0] | has("parallel_eligible")' "$units_file"
  [ "$output" = "false" ]
  run jq -r '.[0].command.argv | join(",")' "$units_file"
  [ "$output" = "bats,plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats" ]
}

@test "the JSON summary printed to stdout reports the selection and units_file path" {
  _write_catalog "safe"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  local units_file="$TEST_TMPDIR/units.json"
  run "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.exit_status == 0 and (.selected_tests | length) == 1 and .units_file == "'"$units_file"'"'
}

@test "an unverifiable (D-selector-1) changed path still exits 3 with --emit-units, writing no units file" {
  _write_catalog "safe"
  commit_change "plugins/aid-orchestrator/scripts/aid-totally-unmapped-new-script.sh"

  local units_file="$TEST_TMPDIR/units.json"
  run "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file"
  [ "$status" -eq 3 ]
  [ ! -f "$units_file" ]
}

@test "--emit-units with zero selected tests writes an empty, schema-valid units file" {
  _write_catalog "safe"
  commit_change "README.md"

  local units_file="$TEST_TMPDIR/units.json"
  run "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file"
  [ "$status" -eq 0 ]
  [ -f "$units_file" ]
  run jq '. == []' "$units_file"
  [ "$output" = "true" ]
}

@test "a stale units file from a prior successful run is removed on a later exit-3 (Codex regression)" {
  _write_catalog "safe"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"
  local units_file="$TEST_TMPDIR/units.json"
  "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file" >/dev/null
  [ -f "$units_file" ]

  commit_change "plugins/aid-orchestrator/scripts/aid-totally-unmapped-new-script.sh"
  local new_base; new_base="$(git rev-parse HEAD~1)"
  run "$SELECTOR" --base "$new_base" --emit-units "$units_file"
  [ "$status" -eq 3 ]
  [ ! -f "$units_file" ]
}

@test "a bash-mapped selection with no sh: catalog entry fails loudly, naming the known adapter gap (Codex regression)" {
  _write_catalog "safe"
  commit_change "plugins/aid-orchestrator/scripts/aid-plan-diff.sh"
  local units_file="$TEST_TMPDIR/units.json"
  run "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file"
  [ "$status" -ne 0 ]
  [ ! -f "$units_file" ]
  [[ "$output" == *"no shell-suite"* ]]
}

@test "a selected run_unit_id absent from the catalog fails loudly, never silently" {
  # No catalog written at all — aid-fsm.sh's mapped unit_id cannot resolve.
  mkdir -p .aid-o/config
  jq -n '{schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved", run_units:[], source_pattern_mappings:[], mapping_approval:{status:"proposed"}}' \
    | yq -P '.' > .aid-o/config/test-catalog.yaml
  git add -f .aid-o/config/test-catalog.yaml
  git commit -q -m "empty catalog"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  local units_file="$TEST_TMPDIR/units.json"
  run "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file"
  [ "$status" -ne 0 ]
  [ ! -f "$units_file" ]
  [[ "$output" == *"not found in the catalog"* ]]
}

@test "a schema-valid emitted unit validates against execution-unit.schema.json" {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1 || skip "python3+jsonschema unavailable"
  _write_catalog "constrained"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  local units_file="$TEST_TMPDIR/units.json"
  "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file" >/dev/null

  run python3 -c "
import sys, json
from jsonschema.validators import Draft202012Validator
schema = json.load(open('$SCHEMA'))
units = json.load(open('$units_file'))
errs = []
for u in units:
    errs += list(Draft202012Validator(schema).iter_errors(u))
sys.exit(1 if errs else 0)
"
  [ "$status" -eq 0 ]
  # P078: parallel_eligible was removed with the parallelism machinery —
  # a unit carries only what sequential execution needs, so the field must
  # be ABSENT, not false.
  run jq -r '.[0] | has("parallel_eligible")' "$units_file"
  [ "$output" = "false" ]
}
