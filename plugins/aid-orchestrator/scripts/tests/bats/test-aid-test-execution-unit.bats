#!/usr/bin/env bats
# test-aid-test-execution-unit.bats — P069 Step 1.
#
# Proves aid-test-execution-unit.sh's execution-unit-shaped wrapper over
# aid-job.sh:
#   - a hung fixture reaches state:timed_out with zero orphaned descendants
#   - the streamed log is readable WHILE the unit is still running
#   - aid-job.sh itself is never modified (asserted via git diff, not prose)
#   - `command` argv|shell dispatch matches P066's exact discriminated union
#   - the normalized receipt shape (unit_id, job_id, state, duration_ms,
#     stdout_path, exit_code) is correct for both terminal_pass and the
#     non-terminal (in-flight) case
#
# Synthetic jobs only (sleep 1-3, deadline 1-2s for the timeout case).

setup() {
  export TZ=UTC
  LIB="${BATS_TEST_DIRNAME}/../../lib/aid-test-execution-unit.sh"
  JOB_SH="${BATS_TEST_DIRNAME}/../../aid-job.sh"
  # shellcheck source=/dev/null
  source "$LIB"
  TMP="$(mktemp -d)"
  REPO="$TMP/project"
  JOBS="$REPO/.aid-o/work/jobs"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b main
  git config user.email test@test.local
  git config user.name Test
  echo seed > file.txt
  git add file.txt
  git commit -q -m initial
}

teardown() {
  if [[ -d "$JOBS" ]]; then
    for d in "$JOBS"/*/; do
      [[ -f "$d/job.json" ]] || continue
      local id; id="$(jq -r '.id' "$d/job.json" 2>/dev/null || true)"
      [[ -n "$id" ]] && bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id "$id" >/dev/null 2>&1 || true
    done
  fi
  cd /
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

_await_terminal_receipt() {
  local job_id="$1" max="${2:-60}" i
  for ((i = 0; i < max; i++)); do
    [[ -f "$JOBS/$job_id/result.json" ]] && return 0
    sleep 0.2
  done
  return 1
}

# -- 1. aid-job.sh is never modified by this step --------------------------
@test "aid-job.sh has zero diff (staged or unstaged) against HEAD after this step's changes" {
  run bash -c "cd '${BATS_TEST_DIRNAME}/../..' && git diff HEAD --quiet -- aid-job.sh"
  [ "$status" -eq 0 ]
}

# -- 2. argv-type command dispatch, happy path ------------------------------
@test "execution_unit_run dispatches an argv command and reaches terminal_pass" {
  unit_json='{"unit_id":"bats:foo/bar.bats","command":{"type":"argv","argv":["bash","-c","echo hi; exit 0"]},"deadline_seconds":10,"resource_locks":[],"parallel_eligible":false,"membership_verified":false,"dedup":false}'
  job_id="$(execution_unit_run "$unit_json" "$JOBS")"
  [ -n "$job_id" ]
  _await_terminal_receipt "$job_id"
  run execution_unit_receipt "$JOBS" "$job_id" "bats:foo/bar.bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.unit_id == "bats:foo/bar.bats" and .job_id == "'"$job_id"'" and .state == "terminal_pass" and .exit_code == 0 and (.duration_ms >= 0) and (.stdout_path | length > 0)'
}

# -- 3. shell-type command dispatch -----------------------------------------
@test "execution_unit_run dispatches a shell command" {
  unit_json='{"unit_id":"bats:shell-unit","command":{"type":"shell","shell":"echo shelled; exit 3"},"deadline_seconds":10,"resource_locks":[],"parallel_eligible":false,"membership_verified":false,"dedup":false}'
  job_id="$(execution_unit_run "$unit_json" "$JOBS")"
  _await_terminal_receipt "$job_id"
  run execution_unit_receipt "$JOBS" "$job_id" "bats:shell-unit"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.state == "terminal_fail" and .exit_code == 3'
  grep -q shelled "$JOBS/$job_id/stdout.log"
}

# -- 4. unsupported command.type is rejected --------------------------------
@test "execution_unit_run rejects a third command.type" {
  unit_json='{"unit_id":"bad-unit","command":{"type":"weird","foo":"bar"},"deadline_seconds":10,"resource_locks":[],"parallel_eligible":false,"membership_verified":false,"dedup":false}'
  run execution_unit_run "$unit_json" "$JOBS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported command.type"* ]]
}

# -- 5. unit_id is sanitized deterministically into a valid job_id ----------
@test "unit_id with ':' and '/' is sanitized into a valid, deterministic job_id" {
  unit_json='{"unit_id":"bats:scripts/tests/bats/foo.bats","command":{"type":"argv","argv":["bash","-c","exit 0"]},"deadline_seconds":10,"resource_locks":[],"parallel_eligible":false,"membership_verified":false,"dedup":false}'
  job_id1="$(execution_unit_run "$unit_json" "$JOBS")"
  _await_terminal_receipt "$job_id1"
  [[ "$job_id1" != *:* && "$job_id1" != */* ]]
  [ -d "$JOBS/$job_id1" ]
}

# -- 6. hung fixture reaches state:timed_out with zero orphaned descendants -
@test "a hung unit past its deadline reaches timed_out with no orphaned descendants" {
  unit_json='{"unit_id":"hung-unit","command":{"type":"shell","shell":"sleep 60 & echo $! > '"$TMP"'/child.pid; wait"},"deadline_seconds":1,"resource_locks":[],"parallel_eligible":false,"membership_verified":false,"dedup":false}'
  job_id="$(execution_unit_run "$unit_json" "$JOBS")"
  _await_terminal_receipt "$job_id" 100
  run execution_unit_receipt "$JOBS" "$job_id" "hung-unit"
  echo "$output" | jq -e '.state == "timed_out"'
  # The grandchild recorded its own pid; after termination it must be gone.
  if [[ -f "$TMP/child.pid" ]]; then
    child_pid="$(cat "$TMP/child.pid")"
    run kill -0 "$child_pid"
    [ "$status" -ne 0 ]
  fi
}

# -- 7b. argv element with an embedded newline is preserved as ONE argument -
@test "an argv element containing an embedded newline is passed through as a single argument (Codex regression)" {
  unit_json='{"unit_id":"newline-arg-unit","command":{"type":"argv","argv":["bash","-c","printf %s\\\\n \"$1\" > out.txt","_","line-one\nline-two"]},"deadline_seconds":10,"resource_locks":[],"parallel_eligible":false,"membership_verified":false,"dedup":false}'
  job_id="$(execution_unit_run "$unit_json" "$JOBS")"
  _await_terminal_receipt "$job_id"
  # job.json's persisted command array must still have exactly 5 elements —
  # a line-based decode would have split the newline into a 6th element.
  count="$(jq '.command | length' "$JOBS/$job_id/job.json")"
  [ "$count" -eq 5 ]
  last="$(jq -r '.command[4]' "$JOBS/$job_id/job.json")"
  [ "$last" = $'line-one\nline-two' ]
}

# -- 7c. distinct unit_ids sanitizing to the same charset-mapped prefix -----
# never collide on the final job_id (Codex regression: "a:b" and "a/b" both
# mapped to "a-b" under the earlier prefix-only sanitizer).
@test "distinct unit_ids do not collide on the sanitized job_id" {
  id1="$(_execution_unit_sanitize_id 'a:b')"
  id2="$(_execution_unit_sanitize_id 'a/b')"
  [ "$id1" != "$id2" ]
}

# -- 7d. a pre-exec-handshake cancelled result (no ended_epoch) never crashes
# the receipt normalizer (Codex regression: an unconditional
# .ended_epoch-$se subtraction fails on a valid result record missing the
# field entirely). Deterministic reproduction via aid-job.sh's own IMP-262
# pre-PID handshake shape (same technique as test-aid-job.bats's own
# "cancel in the pre-PID window" tests) rather than racing a live cancel.
@test "a cancelled-before-exec result (no ended_epoch) yields a valid receipt with duration_ms null" {
  job_id="preexec-cancel-unit"
  job_dir="$JOBS/$job_id"
  mkdir -p "$job_dir"
  jq -n --arg id "$job_id" --arg sh "$(git -C "$REPO" rev-parse HEAD)" '{
    schema:"aid-job/1", id:$id, repo:"'"$REPO"'", state:"started",
    command_fingerprint:"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
    start_head:$sh, start_tree:"x", deadline_sec:0, polarity:"", expect:"", filter:"",
    started_at:"2026-07-24T00:00:00Z", started_epoch:0,
    stdout_path:($ENV.job_dir + "/stdout.log"), result_path:($ENV.job_dir + "/result.json"),
    pid:null, pgid:null, proc_starttime:null, cookie:null,
    command:["bash","-c","exit 0"]
  }' > "$job_dir/job.json"
  : > "$job_dir/.cancel_requested"
  job_dir="$job_dir" bash "$JOB_SH" __wrap "$job_dir"
  run execution_unit_receipt "$JOBS" "$job_id" "$job_id"
  echo "$output" | jq -e '.state == "cancelled" and .duration_ms == null'
}

# -- 7. streamed log is readable WHILE the unit is still running ------------
@test "stdout is readable via stdout_path while the unit is still in-flight" {
  unit_json='{"unit_id":"streaming-unit","command":{"type":"shell","shell":"echo first; sleep 3; echo second"},"deadline_seconds":10,"resource_locks":[],"parallel_eligible":false,"membership_verified":false,"dedup":false}'
  job_id="$(execution_unit_run "$unit_json" "$JOBS")"
  # Poll briefly for the first line to appear while the unit is still running.
  for ((i = 0; i < 50; i++)); do
    grep -q first "$JOBS/$job_id/stdout.log" 2>/dev/null && break
    sleep 0.1
  done
  grep -q first "$JOBS/$job_id/stdout.log"
  run execution_unit_receipt "$JOBS" "$job_id" "streaming-unit"
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.duration_ms == null and .exit_code == null and (.state == "running" or .state == "started")'
}
