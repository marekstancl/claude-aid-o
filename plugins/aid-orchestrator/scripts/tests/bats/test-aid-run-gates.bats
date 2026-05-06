#!/usr/bin/env bats
# P032 Step 7 — aid-run-gates.sh provenance fields + framing events (Step 3).
# 3 assertions covering the gate runner's _generated_by/_at/_command_log
# triple and the gate_runner_start / gate_runner_complete timeline events.

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT/.aid-o/work/evidence/E-X/R-1/gates"
  cd "$TEST_PROJECT"

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUN_GATES="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"

  EXEC_YAML="$TEST_PROJECT/exec.yaml"
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
  beta:
    command: "exit 0"
    required: false
YAML

  REPORT="$TEST_PROJECT/.aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  TIMELINE="$TEST_PROJECT/.aid-o/work/evidence/E-X/R-1/timeline.jsonl"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

@test "run-all: gates_report.json carries _generated_by, _generated_at, _command_log" {
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$REPORT" ]
  run jq -e 'has("_generated_by") and has("_generated_at") and has("_command_log")' "$REPORT"
  [ "$status" -eq 0 ]
  # _command_log is a non-empty array of {name, command, exit_code, duration_ms}
  run jq -e '._command_log | length > 0 and all(has("name") and has("command") and has("exit_code") and has("duration_ms"))' "$REPORT"
  [ "$status" -eq 0 ]
  # _generated_by uses the runner@version format
  run jq -re '._generated_by' "$REPORT"
  [[ "$output" =~ ^aid-run-gates\.sh@v ]]
}

@test "run-all: timeline.jsonl has gate_runner_start with report_path + gate_count + command_list" {
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$TIMELINE" ]
  assert_timeline_event "$TIMELINE" "gate_runner_start"
  run jq -se 'first(.[] | select(.event=="gate_runner_start")) | has("report_path") and has("gate_count") and has("command_list")' "$TIMELINE"
  [[ "$output" == *true* ]]
  # gate_count must equal the actual number of gates in execution.yaml (2 here)
  run jq -se 'first(.[] | select(.event=="gate_runner_start")).gate_count' "$TIMELINE"
  [ "$output" == "2" ]
}

@test "run-all: timeline.jsonl has gate_runner_complete with report_path + overall + duration_sec" {
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  assert_timeline_event "$TIMELINE" "gate_runner_complete"
  run jq -se 'first(.[] | select(.event=="gate_runner_complete")) | has("report_path") and has("overall") and has("duration_sec")' "$TIMELINE"
  [[ "$output" == *true* ]]
  # overall=pass for the all-passing fixture
  run jq -se 'first(.[] | select(.event=="gate_runner_complete")).overall' "$TIMELINE"
  [ "$output" == '"pass"' ]
}
