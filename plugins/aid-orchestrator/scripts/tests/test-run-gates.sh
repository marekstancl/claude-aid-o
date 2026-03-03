#!/usr/bin/env bats
# Tests for aid-run-gates.sh

setup() {
  TEST_DIR=$(mktemp -d)
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  RUN_GATES="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-run-gates.sh"
  FIXTURES="$REPO_ROOT/plugins/aid-orchestrator/scripts/tests/fixtures"
  TIMELINE="$TEST_DIR/timeline.jsonl"
}

teardown() { rm -rf "$TEST_DIR"; }

# --- run_gate ---

@test "run-gate passing command returns result=pass and exit_code=0" {
  run "$RUN_GATES" run-gate "tests" "exit 0" 10 /dev/null
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.result == \"pass\" and .exit_code == 0'"
  [ "$status" -eq 0 ]
}

@test "run-gate failing command returns result=fail and exit_code=1" {
  run "$RUN_GATES" run-gate "tests" "exit 1" 10 /dev/null
  [ "$status" -eq 1 ]
  run bash -c "echo '$output' | jq -e '.result == \"fail\" and .exit_code == 1'"
  [ "$status" -eq 0 ]
}

@test "run-gate timeout returns exit_code=124" {
  run "$RUN_GATES" run-gate "slow" "sleep 100" 1 /dev/null
  [ "$status" -eq 1 ]
  run bash -c "echo '$output' | jq -e '.exit_code == 124'"
  [ "$status" -eq 0 ]
}

@test "run-gate output has gate name" {
  run "$RUN_GATES" run-gate "my_gate" "exit 0" 10 /dev/null
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.gate == \"my_gate\"'"
  [ "$status" -eq 0 ]
}

@test "run-gate output has duration_ms >= 0" {
  run "$RUN_GATES" run-gate "tests" "exit 0" 10 /dev/null
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.duration_ms >= 0'"
  [ "$status" -eq 0 ]
}

@test "run-gate captures command stdout in output field" {
  run "$RUN_GATES" run-gate "tests" "echo hello_world" 10 /dev/null
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.output | contains(\"hello_world\")'"
  [ "$status" -eq 0 ]
}

@test "run-gate logs to file when log_file is provided" {
  local log_file="$TEST_DIR/gate.log"
  run "$RUN_GATES" run-gate "tests" "exit 0" 10 "$log_file"
  [ -f "$log_file" ]
  run jq -e '.gate == "tests"' "$log_file"
  [ "$status" -eq 0 ]
}

# --- run_all_gates ---

@test "run-all with passing gates returns overall=pass" {
  run "$RUN_GATES" run-all "$FIXTURES/execution-test.yaml" "E-TEST" "R-001" "$TIMELINE"
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.overall == \"pass\"'"
  [ "$status" -eq 0 ]
}

@test "run-all with required failing gate exits 1 and overall=fail" {
  run "$RUN_GATES" run-all "$FIXTURES/execution-failing.yaml" "E-TEST" "R-002" "$TIMELINE"
  [ "$status" -eq 1 ]
  run bash -c "echo '$output' | jq -e '.overall == \"fail\"'"
  [ "$status" -eq 0 ]
}

@test "run-all report has epic_id and run_id" {
  run "$RUN_GATES" run-all "$FIXTURES/execution-test.yaml" "E-MYTEST" "R-999" "$TIMELINE"
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.epic_id == \"E-MYTEST\" and .run_id == \"R-999\"'"
  [ "$status" -eq 0 ]
}

@test "run-all report has gates object with per-gate results" {
  run "$RUN_GATES" run-all "$FIXTURES/execution-test.yaml" "E-TEST" "R-001" "$TIMELINE"
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.gates | has(\"tests_pass\")'"
  [ "$status" -eq 0 ]
}

@test "run-all logs gate_start and gate_complete events to timeline" {
  "$RUN_GATES" run-all "$FIXTURES/execution-test.yaml" "E-TEST" "R-001" "$TIMELINE" >/dev/null
  run grep -c '"event":"gate_start"' "$TIMELINE"
  [ "$output" -ge 1 ]
  run grep -c '"event":"gate_complete"' "$TIMELINE"
  [ "$output" -ge 1 ]
}

@test "run-all logs gates_complete event to timeline" {
  "$RUN_GATES" run-all "$FIXTURES/execution-test.yaml" "E-TEST" "R-001" "$TIMELINE" >/dev/null
  run grep '"event":"gates_complete"' "$TIMELINE"
  [ "$status" -eq 0 ]
}

@test "run-all exits 1 when execution_yaml not found" {
  run "$RUN_GATES" run-all "/nonexistent/execution.yaml" "E-TEST" "R-001" "$TIMELINE"
  [ "$status" -eq 1 ]
}
