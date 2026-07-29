#!/usr/bin/env bats
# test-aid-test-audit-state.bats — P066 Step 6.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-state.sh"
  OUTPUT_DIR="$TEST_TMPDIR/audit-state-fixture"
  mkdir -p "$OUTPUT_DIR"
}

teardown() {
  teardown_test_evidence_dir
}

@test "audit_state_init: writes a schema-valid discovering document" {
  run audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30
  [ "$status" -eq 0 ]
  jq -e '.status == "discovering" and .waves_completed == 0 and .resume_token == null' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "full transition matrix: measure mode reaches done at exactly 5 waves (Wave 2 repeats the dispatching phase)" {
  # measure mode's fixed count is 5 (Waves 0-4) — one more than static's 4,
  # because Wave 2 (cross-cutting specialists) is skipped only in static
  # mode. The status enum doesn't grow a name for Wave 2; instead the
  # "dispatching" phase is advanced through TWICE (a same-phase repeat is a
  # valid advance_wave call), matching how Step 11's real dispatcher will
  # call this for measure/full.
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null       # Wave 1
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null    # Wave 2 (specialists)
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null    # Wave 2b (adversarial prep) — same-phase repeat
  audit_state_advance_wave "$OUTPUT_DIR" "consolidating" >/dev/null  # Wave 3
  run audit_state_advance_wave "$OUTPUT_DIR" "reporting"             # Wave 4
  [ "$status" -eq 0 ]
  jq -e '.waves_completed == 5 and .status == "reporting"' "$OUTPUT_DIR/audit-state.json" >/dev/null
  run audit_state_mark_done "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.status == "done" and .waves_completed == 5' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "full transition matrix: full mode reaches done at exactly 6 waves" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "full" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "consolidating" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "reporting" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "reporting" >/dev/null
  run audit_state_mark_done "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.status == "done" and .waves_completed == 6' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "audit_state_init rejects an invalid mode before persisting anything" {
  run audit_state_init "$OUTPUT_DIR" "a1" "repo" "bogus" 30
  [ "$status" -ne 0 ]
  [ ! -f "$OUTPUT_DIR/audit-state.json" ]
}

@test "audit_state_init rejects a non-positive budget_minutes before persisting anything" {
  run audit_state_init "$OUTPUT_DIR" "a1" "repo" "static" 0
  [ "$status" -ne 0 ]
  [ ! -f "$OUTPUT_DIR/audit-state.json" ]

  run audit_state_init "$OUTPUT_DIR" "a1" "repo" "static" "not-a-number"
  [ "$status" -ne 0 ]
  [ ! -f "$OUTPUT_DIR/audit-state.json" ]
}

@test "advance_wave refuses once waves_completed already reached the mode's fixed count, even a same-phase repeat" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "static" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "consolidating" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "reporting" >/dev/null
  jq -e '.waves_completed == 4' "$OUTPUT_DIR/audit-state.json" >/dev/null
  run audit_state_advance_wave "$OUTPUT_DIR" "reporting"
  [ "$status" -ne 0 ]
  jq -e '.waves_completed == 4 and .status == "reporting"' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "advance_wave rejects skipping a wave out of order" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "static" 30 >/dev/null
  run audit_state_advance_wave "$OUTPUT_DIR" "dispatching"
  [ "$status" -ne 0 ]
  jq -e '.status == "discovering"' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "mark_done refuses when waves_completed does not match the mode's fixed count (even from status:reporting)" {
  # measure mode needs 5 waves; reaching "reporting" via the shortest path
  # (4 advances, the static-mode count) leaves waves_completed at 4 — one
  # short of measure's fixed 5 — so mark_done must still refuse.
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "consolidating" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "reporting" >/dev/null
  run audit_state_mark_done "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
}

@test "mark_done succeeds once waves_completed matches the mode's fixed count" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "static" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "consolidating" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "reporting" >/dev/null
  run audit_state_mark_done "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.status == "done" and .waves_completed == 4' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "a document with status:\"corrupt\" (unrecognized enum value) is rejected, never silently advanced to discovering" {
  # PM-confirmed blocker: an unvalidated read let advance_wave's index
  # arithmetic (cur_idx=-1 for an unrecognized status, new_idx=0 for
  # "discovering") coincidentally satisfy "new_idx == cur_idx + 1",
  # silently treating a CORRUPT status as a valid predecessor of the first
  # real status. Real schema validation on read must reject this outright.
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "static" 30 >/dev/null
  jq -c '.status = "corrupt"' "$OUTPUT_DIR/audit-state.json" > "$OUTPUT_DIR/audit-state.json.tmp"
  mv "$OUTPUT_DIR/audit-state.json.tmp" "$OUTPUT_DIR/audit-state.json"

  run audit_state_advance_wave "$OUTPUT_DIR" "discovering"
  [ "$status" -ne 0 ]
  jq -e '.status == "corrupt"' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "_tas_write_locked refuses to persist a schema-invalid document (e.g. a bad enum value), even mid-transition" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "static" 30 >/dev/null
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-adapter-contract.sh"
  local file="$OUTPUT_DIR/audit-state.json"
  local bad_json
  bad_json="$(jq -c '.status = "not-a-real-status"' "$file")"
  run _tas_write_locked "$file" "$bad_json"
  [ "$status" -ne 0 ]
  jq -e '.status == "discovering"' "$file" >/dev/null
}

@test "mark_done rejects an interrupted document even if its wave count matches the mode's fixed total" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "static" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "consolidating" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "reporting" >/dev/null
  audit_state_mark_interrupted "$OUTPUT_DIR" >/dev/null
  run audit_state_mark_done "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  jq -e '.status == "interrupted"' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "concurrent advance_wave and mark_interrupted never lose or tear a completed transition" {
  # Regression: an earlier version's advance_wave/mark_interrupted read the
  # current state BEFORE acquiring the write lock, so a concurrent pair
  # could both read "discovering" and race their writes — the interrupt
  # could silently discard an advance that had already durably succeeded.
  # Now every mutator holds the lock across its entire read-modify-write, so
  # exactly one of these two well-defined outcomes must hold, never a third,
  # inconsistent one.
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null

  # Each side may legitimately lose the race (advance_wave/mark_interrupted
  # both fail loudly against a state they no longer recognize) — only the
  # FINAL ON-DISK STATE is asserted below, never these background exit codes.
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null 2>&1 &
  local advance_pid=$!
  audit_state_mark_interrupted "$OUTPUT_DIR" >/dev/null 2>&1 &
  local interrupt_pid=$!
  wait "$advance_pid" || true
  wait "$interrupt_pid" || true

  # Whichever ran first, the OTHER either failed outright (status document
  # was already interrupted/gone) or the final state is one of the two
  # internally-consistent outcomes below — never waves_completed==1 with
  # status=="discovering" (a torn update), nor resume_token pointing at a
  # status that was never actually reached.
  run jq -e '
    (.status == "interrupted" and .resume_token == "discovering" and .waves_completed == 0)
    or (.status == "interrupted" and .resume_token == "sharding" and .waves_completed == 1)
    or (.status == "sharding" and .waves_completed == 1)
  ' "$OUTPUT_DIR/audit-state.json"
  [ "$status" -eq 0 ]
}

@test "interrupt-then-resume: idempotent, restores exact pre-interrupt status, never touches waves_completed" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "dispatching" >/dev/null
  run audit_state_mark_interrupted "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.status == "interrupted" and .resume_token == "dispatching"' "$OUTPUT_DIR/audit-state.json" >/dev/null

  run audit_state_resume "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.status == "dispatching" and .waves_completed == 2 and .resume_token == null' "$OUTPUT_DIR/audit-state.json" >/dev/null

  # Double-resume: second call is idempotent — same final state, no
  # duplicate wave processing (waves_completed unchanged).
  run audit_state_resume "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  jq -e '.status == "dispatching" and .waves_completed == 2' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "resume refuses a status:failed document without an explicit override" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  jq -c '.status = "failed"' "$OUTPUT_DIR/audit-state.json" > "$OUTPUT_DIR/audit-state.json.tmp"
  mv "$OUTPUT_DIR/audit-state.json.tmp" "$OUTPUT_DIR/audit-state.json"
  run audit_state_resume "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
}

@test "corrupt/version-mismatched state fails closed with a named diagnostic" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  echo 'not valid json at all {{{' > "$OUTPUT_DIR/audit-state.json"
  run audit_state_advance_wave "$OUTPUT_DIR" "sharding"
  [ "$status" -ne 0 ]

  jq -n '{schema_version: "9.9.9", audit_id: "a1", scope: "repo", mode: "measure", status: "interrupted", budget: {minutes: 30}, waves_completed: 1, resume_token: "sharding"}' > "$OUTPUT_DIR/audit-state.json"
  run audit_state_resume "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
}

@test "resume never reports success (or prints a resumed state) if the durable write itself fails" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_mark_interrupted "$OUTPUT_DIR" >/dev/null

  # Force the write to fail: make the directory read-only so mv/tmp-write
  # cannot succeed, without touching the already-written audit-state.json's
  # own readability.
  chmod 555 "$OUTPUT_DIR"
  run audit_state_resume "$OUTPUT_DIR"
  chmod 755 "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" != *"\"status\":\"sharding\""* ]]
  jq -e '.status == "interrupted"' "$OUTPUT_DIR/audit-state.json" >/dev/null
}

@test "two concurrent resume calls on the same audit-id: the second fails loudly instead of queuing" {
  audit_state_init "$OUTPUT_DIR" "a1" "repo" "measure" 30 >/dev/null
  audit_state_advance_wave "$OUTPUT_DIR" "sharding" >/dev/null
  audit_state_mark_interrupted "$OUTPUT_DIR" >/dev/null

  local lockfile="$OUTPUT_DIR/.audit-state.lock"
  # Hold the lock artificially in a background subshell to simulate a
  # concurrent in-flight resume.
  (
    exec 200>"$lockfile"
    flock 200
    sleep 2
  ) &
  local holder_pid=$!
  sleep 0.3

  run audit_state_resume "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already in progress"* ]]

  wait "$holder_pid"
}
