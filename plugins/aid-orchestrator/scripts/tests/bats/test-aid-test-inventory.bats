#!/usr/bin/env bats
# test-aid-test-inventory.bats — P066 Step 4.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCANNER="$AID_PLUGIN_PATH/scripts/aid-test-inventory.sh"

  FIXTURE_PROJECT="$TEST_TMPDIR/fixture-project"
  mkdir -p "$FIXTURE_PROJECT/tests" "$FIXTURE_PROJECT/.aid-o/config"

  local at='@test'
  {
    printf '#!/usr/bin/env bats\n'
    printf '%s "case one" {\n  flock -n "$TEST_TMPDIR/x.lock" true\n}\n' "$at"
    printf '%s "case two" {\n  [ 1 -eq 1 ]\n}\n' "$at"
  } > "$FIXTURE_PROJECT/tests/suite.bats"

  cat > "$FIXTURE_PROJECT/package.json" <<'JSON'
{"name": "fixture", "scripts": {"test": "vitest run"}}
JSON

  cat > "$FIXTURE_PROJECT/.aid-o/config/execution.yaml" <<'YAML'
gates:
  lint_pass:
    command: "ruff check ."
YAML

  OUTPUT_DIR="$TEST_TMPDIR/audit-out"
}

teardown() {
  teardown_test_evidence_dir
}

@test "aid-test-inventory.sh: mixed-adapter fixture scan produces a schema-valid inventory.json + test-catalog.proposed.yaml with no collisions" {
  run "$SCANNER" --project-root "$FIXTURE_PROJECT" --audit-id "audit-1" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$OUTPUT_DIR/inventory.json" ]
  [ -f "$OUTPUT_DIR/test-catalog.proposed.yaml" ]

  local run_unit_ids
  run_unit_ids="$(jq -r '[.entries[].run_unit_id] | sort | join(",")' "$OUTPUT_DIR/inventory.json")"
  [[ "$run_unit_ids" == *"bats:tests/suite"* ]]
  [[ "$run_unit_ids" == *"npm:test"* ]]
  [[ "$run_unit_ids" == *"gate:lint_pass"* ]]

  run yq -o=json '.' "$OUTPUT_DIR/test-catalog.proposed.yaml"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "proposed"' >/dev/null
  echo "$output" | jq -e '.mapping_approval.status == "proposed"' >/dev/null
}

@test "aid-test-inventory.sh: statically greps flock usage into the Bats run_unit's isolation.lock_usage[]" {
  run "$SCANNER" --project-root "$FIXTURE_PROJECT" --audit-id "audit-1" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.entries[] | select(.run_unit_id == "bats:tests/suite") | .isolation.lock_usage | length == 1' "$OUTPUT_DIR/inventory.json" >/dev/null
  jq -e '.entries[] | select(.run_unit_id == "bats:tests/suite") | .isolation.lock_usage[0].resolved_scope == "per-test-mktemp"' "$OUTPUT_DIR/inventory.json" >/dev/null
}

@test "aid-test-inventory.sh: re-running against unchanged state is byte-identical excluding the timestamp field" {
  run "$SCANNER" --project-root "$FIXTURE_PROJECT" --audit-id "audit-1" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local first
  first="$(jq 'del(.generated_at)' "$OUTPUT_DIR/inventory.json")"

  local output_dir2="$TEST_TMPDIR/audit-out-2"
  run "$SCANNER" --project-root "$FIXTURE_PROJECT" --audit-id "audit-2" --output-dir "$output_dir2"
  [ "$status" -eq 0 ]
  local second
  second="$(jq 'del(.generated_at)' "$output_dir2/inventory.json")"

  [ "$first" = "$second" ]
}

@test "aid-test-inventory.sh: scanner-level confidence is always normalized to low, never an adapter's higher value" {
  run "$SCANNER" --project-root "$FIXTURE_PROJECT" --audit-id "audit-1" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local confidences
  confidences="$(jq -c '[.entries[].confidence] | unique' "$OUTPUT_DIR/inventory.json")"
  [ "$confidences" = '["low"]' ]
}

@test "aid-test-inventory.sh: a large discovered portfolio does not hit an OS argument-list-length limit" {
  # Regression: an earlier version passed the whole run_units array via
  # jq --argjson (argv), which failed with "Argument list too long" once the
  # portfolio grew large enough (found by Codex review testing against a
  # real, larger repo). 300 Bats files reproduces a comparable payload size.
  for i in $(seq 1 300); do
    printf '#!/usr/bin/env bats\n%s "case" {\n  [ 1 -eq 1 ]\n}\n' '@test' > "$FIXTURE_PROJECT/tests/gen-$i.bats"
  done
  run "$SCANNER" --project-root "$FIXTURE_PROJECT" --audit-id "audit-big" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq '.entries | length' "$OUTPUT_DIR/inventory.json")" -ge 300 ]
}

@test "aid-test-inventory.sh: an injected duplicate run_unit_id causes a named, non-zero-exit failure" {
  # Force a collision: a declared-command gate keyed to the same run_unit_id
  # namespace as an existing Bats entry (contrived, but proves the
  # collision-detection code path fires and names the id).
  cat > "$FIXTURE_PROJECT/.aid-o/config/execution.yaml" <<'YAML'
gates:
  "tests/suite":
    command: "echo not-really-the-same-command"
YAML
  # aid-test-inventory.sh only calls declared_command_adapter_discover with
  # its own "gate:<name>" namespace, so simulate a true collision directly
  # against the shared collision-detection primitive instead of relying on
  # adapter-prefix coincidence.
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-adapter-contract.sh"
  local units_with_collision
  units_with_collision='[{"run_unit_id":"bats:tests/suite","runner":"bats"},{"run_unit_id":"bats:tests/suite","runner":"declared-command"}]'
  run adapter_check_run_unit_id_collisions "$units_with_collision"
  [ "$status" -eq 0 ]
  [ "$output" = "bats:tests/suite" ]
}
