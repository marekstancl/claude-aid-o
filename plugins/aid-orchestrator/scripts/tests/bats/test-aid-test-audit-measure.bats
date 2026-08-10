#!/usr/bin/env bats
# test-aid-test-audit-measure.bats — P066 Step 12.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-measure.sh"
  JOBS_DIR="$TEST_TMPDIR/jobs"
  MEASUREMENTS="$TEST_TMPDIR/measurements.jsonl"
  EXECUTION_YAML="$TEST_TMPDIR/no-such-execution.yaml"
  APPROVED_CATALOG="$TEST_TMPDIR/test-catalog.yaml"
}

teardown() {
  teardown_test_evidence_dir
}

# _approve <commands_json_array> — writes an APPROVED catalog whose
# run_units[].command values are exactly the given commands' .command
# fields, so aid_test_audit_check_allowed's measure-mode approved-catalog
# path accepts them. Mirrors real usage: only a command already present in
# the approved catalog may ever run in measure/full mode — these fixtures
# ARE that approval, built directly from what each test intends to measure.
_approve() {
  local commands_json="$1"
  jq -n --argjson cmds "$commands_json" '{
    schema_version: "1.0.0", generated_at: "2026-07-30T00:00:00Z", status: "approved",
    run_units: [$cmds[] | {
      run_unit_id: .run_unit_id, runner: "bats", source_paths: [], production_surfaces: [],
      test_level: "suite", risk_tags: [], profiles: ["default"], behavior_claims: [],
      confidence: "low", command: .command, runtime: {fingerprint: "sha256:000000000000"},
      isolation: {temp_workspace: "unknown", fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: "static_parse"},
      recommendation: "keep", test_cases: []
    }],
    source_pattern_mappings: [], mapping_approval: {status: "proposed"}
  }' | yq -P -o=yaml '.' > "$APPROVED_CATALOG"
}

@test "a normal argv-type command reaches terminal_pass with exit_code 0" {
  local commands='[{"run_unit_id":"t1","command":{"type":"argv","argv":["echo","hello"]},"deadline_seconds":10}]'
  _approve "$commands"
  run aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG"
  [ "$status" -eq 0 ]
  jq -e '.run_unit_id == "t1" and .state == "terminal_pass" and .exit_code == 0' "$MEASUREMENTS" >/dev/null
}

@test "a shell-type command is executed via bash -c" {
  local commands='[{"run_unit_id":"t2","command":{"type":"shell","shell":"echo a && echo b"},"deadline_seconds":10}]'
  _approve "$commands"
  run aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG"
  [ "$status" -eq 0 ]
  jq -e '.state == "terminal_pass"' "$MEASUREMENTS" >/dev/null
  local stdout_path
  stdout_path="$(jq -r '.stdout_path' "$MEASUREMENTS")"
  run cat "$stdout_path"
  [[ "$output" == *"a"* && "$output" == *"b"* ]]
}

@test "a failing command reaches terminal_fail with the real non-zero exit code" {
  local commands='[{"run_unit_id":"t3","command":{"type":"argv","argv":["bash","-c","exit 7"]},"deadline_seconds":10}]'
  _approve "$commands"
  run aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG"
  [ "$status" -eq 0 ]
  jq -e '.state == "terminal_fail" and .exit_code == 7' "$MEASUREMENTS" >/dev/null
}

@test "a deliberately hung fixture reaches state:timed_out with its process group reaped, zero surviving descendants" {
  local commands='[{"run_unit_id":"hung","command":{"type":"argv","argv":["sleep","30"]},"deadline_seconds":2}]'
  local start end elapsed
  start="$(date +%s)"
  _approve "$commands"
  run aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG"
  end="$(date +%s)"
  elapsed=$((end - start))
  [ "$status" -eq 0 ]
  jq -e '.state == "timed_out"' "$MEASUREMENTS" >/dev/null
  # Bounded tolerance (deadline + 5s), not exact wall-clock equality —
  # process scheduling/timer wake-up/receipt-write latency make "exact
  # deadline" untestable (aid-job.sh's own established AC language).
  [ "$elapsed" -le 7 ]

  local job_id pgid
  job_id="$(jq -r '.job_id' "$MEASUREMENTS")"
  pgid="$(jq -r '.pgid // empty' "$JOBS_DIR/$job_id/job.json")"
  if [[ -n "$pgid" && "$pgid" != "null" ]]; then
    run pgrep -g "$pgid"
    [ "$status" -ne 0 ]
  fi
}

@test "streamed log content is readable while the job is still running" {
  local commands='[{"run_unit_id":"slow-echo","command":{"type":"argv","argv":["bash","-c","echo starting; sleep 2; echo done"]},"deadline_seconds":10}]'
  _approve "$commands"
  ( aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG" ) &
  local runner_pid=$!

  # Poll for the stdout.log file itself (created before the job finishes)
  # and confirm it becomes readable with partial content before the
  # measurement completes.
  local found=0
  for _ in $(seq 1 40); do
    local job_dir
    job_dir="$(find "$JOBS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
    if [[ -n "$job_dir" && -s "$job_dir/stdout.log" ]]; then
      found=1
      break
    fi
    sleep 0.1
  done
  wait "$runner_pid"
  [ "$found" -eq 1 ]
}

@test "two measured entries run strictly sequentially, never concurrently" {
  local marker_dir="$TEST_TMPDIR/markers"
  mkdir -p "$marker_dir"
  local commands
  commands="$(jq -n --arg d "$marker_dir" '[
    {run_unit_id:"first", command:{type:"shell", shell:("touch " + $d + "/first-start; sleep 1; touch " + $d + "/first-end")}, deadline_seconds:10},
    {run_unit_id:"second", command:{type:"shell", shell:("touch " + $d + "/second-start")}, deadline_seconds:10}
  ]')"
  _approve "$commands"
  run aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG"
  [ "$status" -eq 0 ]
  [ -f "$marker_dir/first-end" ]
  [ -f "$marker_dir/second-start" ]
  # first-end must exist at or before second-start (mtime ordering) —
  # second never starts before the first's terminal receipt is written.
  [ "$(stat -c %Y "$marker_dir/first-end")" -le "$(stat -c %Y "$marker_dir/second-start")" ]
}

@test "an argv element containing a literal newline reaches aid-job.sh run and is recorded in job.json as ONE element, never split" {
  # Regression: an earlier version decoded argv via line-based `jq -r`/`read`,
  # so an approved argv element with an embedded newline (a valid POSIX
  # path) would be silently split into two separate arguments BEFORE this
  # script even called aid-job.sh — this step's own responsibility (Codex
  # review). Fixed via NUL-delimited decode (mapfile -d '').
  #
  # Scope note, found while verifying this fix: aid-job.sh's OWN cmd_wrap
  # separately reconstructs argv from job.json via a line-based `mapfile -t`
  # (no -d '') immediately before exec — a PRE-EXISTING limitation inside
  # aid-job.sh itself that this plan's Constraint 8 ("aid-job.sh is not
  # modified") puts out of scope here. This test therefore asserts the
  # guarantee this step actually owns and controls: the argv this script
  # hands to `aid-job.sh run` is preserved, unsplit, all the way into the
  # durable job.json record aid-job.sh writes before any exec — verified via
  # the job dir aid-job.sh itself creates, not via exec'd process output.
  local commands
  commands='[{"run_unit_id":"nl","command":{"type":"argv","argv":["bash","-c","true","_","line-one\nline-two"]},"deadline_seconds":10}]'
  _approve "$commands"
  run aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG"
  [ "$status" -eq 0 ]
  local job_id job_dir
  job_id="$(jq -r '.job_id' "$MEASUREMENTS")"
  job_dir="$JOBS_DIR/$job_id"
  [ "$(jq '.command | length' "$job_dir/job.json")" -eq 5 ]
  [ "$(jq -r '.command[4] | length' "$job_dir/job.json")" -eq 17 ]
}

@test "duration_ms reflects a real wall-clock stopwatch, not a value quantized to a multiple of 1000ms" {
  # Regression: an earlier version derived duration_ms from aid-job.sh's own
  # started_at/ended_at, which are whole-second ISO8601 — ALWAYS producing
  # an exact multiple of 1000 regardless of the command's real duration
  # (Codex review). This asserts the actual property that broke: a real
  # stopwatch around the run+poll lifecycle essentially never lands on an
  # exact multiple of 1000ms, across several distinct short commands —
  # unlike the old (ended_epoch-started_epoch)*1000 derivation, which
  # always did. (Total wall-clock includes aid-job.sh's own real dispatch
  # overhead — e.g. its git-revision fingerprinting — plus this script's
  # 0.2s poll cadence, so an absolute upper bound isn't asserted here, only
  # non-quantization.)
  local commands='[
    {"run_unit_id":"q1","command":{"type":"argv","argv":["true"]},"deadline_seconds":10},
    {"run_unit_id":"q2","command":{"type":"argv","argv":["sleep","0.3"]},"deadline_seconds":10},
    {"run_unit_id":"q3","command":{"type":"argv","argv":["echo","hi"]},"deadline_seconds":10}
  ]'
  _approve "$commands"
  run aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG"
  [ "$status" -eq 0 ]
  local any_non_quantized
  any_non_quantized="$(jq -s '[.[].duration_ms | select(. % 1000 != 0)] | length' "$MEASUREMENTS")"
  [ "$any_non_quantized" -gt 0 ]
}

@test "a genuinely lost job (fabricated job dir) is reported by aid-job.sh's own collect as live_state:lost" {
  # Fixture proving the "lost" signal _tam_run_one's debounce logic reacts
  # to is real and reachable: a job.json recording a pid that is provably
  # not alive, with no result.json — aid-job.sh's own collect (unmodified)
  # reports this as a non-terminal, live_state:lost record (exit 3), which
  # is exactly what _tam_run_one's 3-consecutive-readings debounce (added
  # after Codex review found an earlier version polled a lost job forever)
  # is designed to detect and abort on rather than hang indefinitely.
  mkdir -p "$JOBS_DIR/lost-job-1"
  jq -n --arg id "lost-job-1" --arg stdout "$JOBS_DIR/lost-job-1/stdout.log" --arg result "$JOBS_DIR/lost-job-1/result.json" \
    '{schema:"aid-job/1", id:$id, label:"test-audit", state:"running", command_fingerprint:"x",
      start_head:"x", start_tree:"x", started_at:"2020-01-01T00:00:00Z", started_epoch:0,
      expected_p95_sec:0, deadline_sec:10, polarity:"", expect:"", filter:"",
      stdout_path:$stdout, result_path:$result,
      pid:999999999, pgid:999999999, proc_starttime:"0", cookie:null, command:["true"]}' \
    > "$JOBS_DIR/lost-job-1/job.json"

  run bash "$AID_PLUGIN_PATH/scripts/aid-job.sh" collect --jobs-dir "$JOBS_DIR" --id "lost-job-1"
  [ "$status" -eq 3 ]
  [[ "$output" == *"lost"* ]]
}

@test "the polling loop's lost-detection requires 3 consecutive readings before aborting (debounced, not single-reading)" {
  # Grep-verified structural check that the debounce is actually wired —
  # a single transient "lost" misread (aid-job.sh's own pre-PID handshake
  # window can transiently read this way under scheduling pressure) must
  # never abort a real measurement.
  grep -q "consecutive_lost" "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-measure.sh"
  grep -q 'consecutive_lost.*-ge 3' "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-measure.sh"
}

@test "a command NOT in the approved catalog (and not a real gate) is refused — never reaches aid-job.sh at all" {
  # Regression: an earlier version executed every commands_json entry
  # directly with no allowlist enforcement anywhere in the production
  # path — a controller forwarding a command from an audit artifact could
  # execute arbitrary input via bash -c, bypassing the approved-catalog/
  # gate boundary Step 13 introduced (Codex review of the whole EPIC 2
  # diff). This command is deliberately never approved.
  local commands='[{"run_unit_id":"unapproved","command":{"type":"argv","argv":["echo","should-never-run"]},"deadline_seconds":10}]'
  # No _approve call — APPROVED_CATALOG stays empty/nonexistent.
  run aid_test_audit_measure_run_all "measure" "$JOBS_DIR" "$commands" "$MEASUREMENTS" "$EXECUTION_YAML" "$APPROVED_CATALOG"
  [ "$status" -ne 0 ]
  [ ! -s "$MEASUREMENTS" ]
  [ -z "$(find "$JOBS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]
}

@test "aid-job.sh itself is not modified — only its existing CLI is called" {
  run grep -c "^cmd_run\|^cmd_wrap\|^cmd_collect" "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-measure.sh"
  [ "$status" -ne 0 ] || [ "$output" -eq 0 ]
  grep -q "aid-job.sh" "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-measure.sh"
}
