#!/usr/bin/env bats
# test-aid-test-adapter-declared-command.bats — P066 Step 3.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-adapter-declared-command.sh"

  FIXTURE_YAML="$TEST_TMPDIR/execution.yaml"
  cat > "$FIXTURE_YAML" <<'YAML'
gates:
  tests_pass:
    command: "./run-all-tests.sh"
  lint_pass:
    command: "ruff check ."
  scope_check:
    command: "scripts/gates/scope-check.sh {epic_id}"
YAML
}

teardown() {
  teardown_test_evidence_dir
}

@test "declared_command_adapter_discover: a fixture execution.yaml with 3 gates produces a 1:1 mapping" {
  run declared_command_adapter_discover "$FIXTURE_YAML"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" -eq 3 ]
  echo "$output" | jq -e 'any(.[]; .run_unit_id == "gate:tests_pass")' >/dev/null
  echo "$output" | jq -e 'all(.[]; .command.type == "shell")' >/dev/null
}

@test "declared_command_adapter_discover: dedups against an exact-match existing entry, tagging both provenances, never double-counted" {
  local existing
  existing="$(jq -n '[{
    run_unit_id: "npm:test",
    runner: "package-script",
    source_paths: ["package.json"],
    production_surfaces: ["package.json"],
    test_level: "suite",
    risk_tags: [],
    profiles: ["default"],
    behavior_claims: [],
    confidence: "medium",
    command: {type: "shell", shell: "./run-all-tests.sh"},
    runtime: {fingerprint: "sha256:000000000000"},
    isolation: {temp_workspace: "unknown", fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: "static_parse"},
    recommendation: "keep",
    test_cases: [],
    provenance: ["package-script"]
  }]')"
  run declared_command_adapter_discover "$FIXTURE_YAML" "$existing"
  printf '%s' "$output" > /tmp/bats-actual-output.json
  [ "$status" -eq 0 ]
  # tests_pass's command matches the existing npm:test entry exactly -> merged, not duplicated
  [ "$(echo "$output" | jq 'length')" -eq 3 ]
  echo "$output" | jq -e '.[] | select(.run_unit_id == "npm:test") | (.provenance | sort) == ["declared-command","package-script"]' >/dev/null
  ! echo "$output" | jq -e 'any(.[]; .run_unit_id == "gate:tests_pass")'
}

@test "declared_command_adapter_discover: a gate name containing whitespace is not silently omitted" {
  cat > "$FIXTURE_YAML" <<'YAML'
gates:
  "lint pass":
    command: "echo lint"
  normal:
    command: "echo normal"
YAML
  run declared_command_adapter_discover "$FIXTURE_YAML"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" -eq 2 ]
  echo "$output" | jq -e 'any(.[]; .run_unit_id == "gate:lint pass")' >/dev/null
}

@test "declared_command_adapter_discover: pretty-printed (non-compact) existing JSON does not corrupt the first non-matching gate" {
  # Regression: jq -n's default output is pretty-printed. An earlier bug
  # compared a pretty-printed $existing_json directly against jq -c map()
  # output — always "different" due to formatting alone — causing the first
  # alphabetically-sorted, genuinely non-matching gate to be silently
  # dropped instead of appended as its own run_unit.
  local existing_pretty='[
  {
    "run_unit_id": "npm:test",
    "runner": "package-script",
    "source_paths": ["package.json"],
    "production_surfaces": ["package.json"],
    "test_level": "suite",
    "risk_tags": [],
    "profiles": ["default"],
    "behavior_claims": [],
    "confidence": "medium",
    "command": {"type": "shell", "shell": "./run-all-tests.sh"},
    "runtime": {"fingerprint": "sha256:000000000000"},
    "isolation": {"temp_workspace": "unknown", "fixed_ports": [], "shared_paths": [], "lock_usage": [], "adapter_confidence": "static_parse"},
    "recommendation": "keep",
    "test_cases": [],
    "provenance": ["package-script"]
  }
]'
  run declared_command_adapter_discover "$FIXTURE_YAML" "$existing_pretty"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" -eq 3 ]
  echo "$output" | jq -e 'any(.[]; .run_unit_id == "gate:lint_pass")' >/dev/null
}

@test "declared_command_adapter_discover: preserves the execution.yaml path relative to project_root, never a bare basename" {
  mkdir -p "$TEST_TMPDIR/proj/.aid-o/config"
  cp "$FIXTURE_YAML" "$TEST_TMPDIR/proj/.aid-o/config/execution.yaml"
  run declared_command_adapter_discover "$TEST_TMPDIR/proj/.aid-o/config/execution.yaml" "[]" "$TEST_TMPDIR/proj"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .source_paths == [".aid-o/config/execution.yaml"])' >/dev/null
}

@test "declared_command_adapter_discover: re-running against its own already-tagged output is idempotent (no duplicate run_unit_ids)" {
  run declared_command_adapter_discover "$FIXTURE_YAML" "[]"
  [ "$status" -eq 0 ]
  local first="$output"
  run declared_command_adapter_discover "$FIXTURE_YAML" "$first"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" -eq 3 ]
  [ "$(echo "$output" | jq '[.[].run_unit_id] | unique | length')" -eq 3 ]
}
