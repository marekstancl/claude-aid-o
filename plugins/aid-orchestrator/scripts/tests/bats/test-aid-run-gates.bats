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

# ─── OBS-20260708-07 F4 — gates runner must never lose a gate and report pass ──
# Three loss paths closed: (a) stdin-consuming gate starving subsequent gates,
# (b) null-command gate leaving no row (bare continue), (c) any other silent row
# loss caught by the defined==processed integrity assert.

@test "run-all F4a: stdin-consuming gate does not starve subsequent gates" {
  # 'eat' runs `cat` which, on the unfixed runner, consumes the driver's
  # here-string stdin (the remaining gate names) so 'beta' is never iterated —
  # yet overall still reports pass. The </dev/null redirect in run_gate fixes it.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  eat:
    command: "cat >/dev/null"
    required: false
  beta:
    command: "exit 0"
    required: false
YAML
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$REPORT" ]
  # Both gates must appear — beta must not be starved out of the report
  run jq -e '.gates | has("eat") and has("beta")' "$REPORT"
  [ "$status" -eq 0 ]
  # No integrity failure, overall stays pass (both gates genuinely ran + passed)
  run jq -e '.gates | has("_integrity") | not' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "pass" ]
}

@test "run-all F4b: null-command gate emits explicit skip row (never bare continue)" {
  # 'nocmd' has no command key. The unfixed runner WARNs + bare `continue`,
  # emitting no row (silent loss). After the fix it must emit an explicit
  # {result:skip, reason:no_command} row so defined==rows holds by construction.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  nocmd:
    required: false
  beta:
    command: "exit 0"
    required: false
YAML
  "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT" >/dev/null 2>&1
  [ -f "$REPORT" ]
  run jq -re '.gates.nocmd.result' "$REPORT"
  [ "$output" == "skip" ]
  run jq -re '.gates.nocmd.reason' "$REPORT"
  [ "$output" == "no_command" ]
  # beta still processed; defined==rows holds so no integrity row, overall pass
  run jq -e '.gates | has("beta")' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -e '.gates | has("_integrity") | not' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -re '.overall' "$REPORT"
  [ "$output" == "pass" ]
}

@test "run-all F4c: silently-lost gate row trips _integrity fail + overall fail + nonzero exit" {
  # Fault injection (AID_TEST_DROP_GATE, honored only under test) drops one
  # gate's row without a corresponding processed++, simulating a silent row
  # loss. The defined==processed assert must catch it: emit an _integrity row,
  # force overall=fail, and exit non-zero.
  cat > "$EXEC_YAML" <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: false
  beta:
    command: "exit 0"
    required: false
YAML
  run env AID_TEST_DROP_GATE=beta "$RUN_GATES" run-all "$EXEC_YAML" "E-X" "R-1" --report-file "$REPORT"
  # Non-zero exit from the runner
  [ "$status" -ne 0 ]
  [ -f "$REPORT" ]
  # Explicit integrity failure row present
  run jq -re '.gates._integrity.result' "$REPORT"
  [ "$output" == "fail" ]
  run jq -re '.gates._integrity.reason' "$REPORT"
  [ "$output" == "gate_count_mismatch" ]
  # defined/processed recorded (2 defined, 1 processed after the drop)
  run jq -re '.gates._integrity.defined' "$REPORT"
  [ "$output" == "2" ]
  run jq -re '.gates._integrity.processed' "$REPORT"
  [ "$output" == "1" ]
  # Overall must be fail — a lost gate can never surface as green
  run jq -re '.overall' "$REPORT"
  [ "$output" == "fail" ]
}
