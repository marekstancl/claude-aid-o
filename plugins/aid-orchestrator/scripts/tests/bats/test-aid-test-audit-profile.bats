#!/usr/bin/env bats
# test-aid-test-audit-profile.bats — P072 Step 12.
#
# The profiler's value is in what it REFUSES to claim. A file-level timeout
# tells nobody what to do; a fabricated attribution is worse, because it sends
# someone to split a file whose cost would follow the state into both halves.
# Every case here pins either a refusal or an attribution that cites evidence.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  REPO="$(cd "$PLUGIN_DIR/../.." && pwd)"
  PROFILE="$PLUGIN_DIR/scripts/aid-test-audit-profile.sh"
  CATALOG="$REPO/.aid-o/config/test-catalog.yaml"
  EXEC_YAML="$REPO/.aid-o/config/execution.yaml"
  OUT="$TEST_TMPDIR/out"
}

teardown() { teardown_test_evidence_dir; }

# A disposable clone — the only root the profiler will run against.
_clone() {
  local c="$TEST_TMPDIR/clone"
  [ -d "$c" ] && { echo "$c"; return 0; }
  git clone -q "$REPO" "$c" 2>/dev/null
  mkdir -p "$c/.aid-o/config"
  cp "$CATALOG" "$EXEC_YAML" "$REPO/.aid-o/config/test-audit.yaml" "$c/.aid-o/config/" 2>/dev/null || true
  echo "$c"
}

@test "REFUSAL: profiling the live checkout exits 10" {
  run bash "$PROFILE" --run-unit-id x --catalog "$CATALOG" \
    --output-dir "$OUT" --target-root "$REPO" --project-root "$REPO"
  [ "$status" -eq 10 ]
  [[ "$output" == *"live checkout"* ]]
  [[ "$output" == *"disposable clone"* ]]
}

@test "REFUSAL: a unit that is not in the catalog exits 3 — no command is invented" {
  local c; c="$(_clone)"
  run bash "$PROFILE" --run-unit-id "bats:does/not/exist" --catalog "$CATALOG" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO"
  [ "$status" -eq 3 ]
  [[ "$output" == *"never invents a command"* ]]
}

@test "REFUSAL: a non-numeric budget is rejected before anything runs" {
  local c; c="$(_clone)"
  run bash "$PROFILE" --run-unit-id x --catalog "$CATALOG" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes banana
  [ "$status" -eq 2 ]
  [ ! -d "$OUT/profiles" ]
}

@test "a real profile of a small unit completes and attributes to a cited bucket" {
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  [ -f "$r" ]
  [ "$(jq -r '.complete' "$r")" = "true" ]
  [ "$(jq -r '.lower_bound_ms' "$r")" = "null" ]
  [ "$(jq -r '.timing.cases | length' "$r")" -gt 0 ]
  # a completed run must name a bucket, and the reason must not be empty
  [ -n "$(jq -r '.root_cause.bucket' "$r")" ]
  [ "$(jq -r '.root_cause.reason | length > 20' "$r")" = "true" ]
}

@test "the evidence log is READABLE WHILE THE RUN IS STILL GOING" {
  # A suite that will exceed an hour must be observable long before its
  # deadline; a log that appears only on exit is indistinguishable from a hung
  # process. Asserting this AFTER the run proves nothing — a log written in one
  # shot at the end passes that check — so this reads the live log mid-flight.
  local c; c="$(_clone)"
  bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 5 \
    >"$TEST_TMPDIR/receipt_path" 2>/dev/null &
  local profiler_pid=$!

  # Poll the supervised job's live log while the profiler is still running.
  local live="" waited=0 saw_content=0
  while kill -0 "$profiler_pid" 2>/dev/null && [ "$waited" -lt 120 ]; do
    # Job records live inside the disposable clone now, not under --output-dir:
    # the profiler must not write into the audit's own evidence tree.
    live="$(find "$c/.aid-o/work/profile-jobs" -name 'stdout.log' 2>/dev/null | head -1)"
    if [ -n "$live" ] && [ -s "$live" ]; then saw_content=1; break; fi
    sleep 1; waited=$(( waited + 1 ))
  done

  kill -TERM "$profiler_pid" 2>/dev/null || true
  wait "$profiler_pid" 2>/dev/null || true

  [ "$saw_content" -eq 1 ]
}

@test "the profiled command runs under aid-job.sh, with a terminal receipt" {
  # Not a bare `timeout`. The job supervisor owns the process group, so a
  # profiler that is killed does not strand the suite it was measuring, and
  # every run leaves a durable terminal record rather than an exit code
  # nobody wrote down.
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  [ "$(jq -r '.job.state' "$r")" = "terminal_pass" ]
  # Read the job location from the RECEIPT rather than assuming a layout —
  # assuming one is what broke when job records moved into the clone.
  local jid jdir; jid="$(jq -r '.job.id' "$r")"; jdir="$(jq -r '.job.jobs_dir' "$r")"
  [ -n "$jdir" ] && [ "$jdir" != "null" ]
  [ -f "$jdir/$jid/result.json" ]
  [ "$(jq -r '.schema' "$jdir/$jid/result.json")" = "aid-job-result/1" ]
  # And it is NOT in the audit's output directory.
  [ ! -d "$OUT/profile-jobs" ]
}

@test "the ALLOWLIST approves the exact argv that runs, --timing included" {
  # The check used to happen before `--timing` was inserted, so the approved
  # argv and the executed argv were different strings. The exemption is now
  # explicit and narrow: exactly one known token, over an otherwise approved
  # command.
  local c contains r; c="$(_clone)"
  # A catalog whose command carries an extra flag is a command nobody approved.
  # The unit id is still real, so nothing but the argv comparison can catch it —
  # and the executed argv would be that flag PLUS --timing, which is why the
  # exemption has to be an exact one-token diff rather than "close enough".
  local bad="$TEST_TMPDIR/bad-catalog.yaml"
  yq -o=json '.' "$CATALOG" \
    | jq '(.run_units[] | select(.run_unit_id | test("test-aid-epic-summary")) | .command.argv)
          |= (.[0:1] + ["--jobs=99"] + .[1:])' \
    | yq -P -o=yaml '.' > "$bad"
  run bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$bad" --approved-catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3
  [ "$status" -eq 11 ]
  [[ "$output" == *"not in the approved allowlist"* ]]
  [[ "$output" == *"--jobs=99"* ]]

  # And the honest path still works, with --timing actually applied.
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  [ "$(jq -r '.timing.cases | length' "$r")" -gt 0 ]
}

@test "the receipt is bound to its audit and to the BYTES of its evidence log" {
  # A profiles directory is a directory, not provenance.
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" --audit-id "AUD-XYZ" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  [ "$(jq -r '.audit_id' "$r")" = "AUD-XYZ" ]
  local recorded actual
  recorded="$(jq -r '.evidence_log_sha256' "$r")"
  actual="$(sha256sum "$OUT/profiles/$(jq -r '.evidence_log' "$r")" | cut -d' ' -f1)"
  [ "$recorded" = "$actual" ]
}

@test "an OPERATOR CANCEL is not filed as a deadline" {
  # A deadline kill and a `kill` from a person both arrive as SIGTERM. Reading
  # the exit code alone would file every interrupted run as "this suite is too
  # slow" — a measurement nobody made.
  local c; c="$(_clone)"
  bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 10 \
    >"$TEST_TMPDIR/rp" 2>/dev/null &
  local pid=$!

  # Wait until the job exists, then cancel it the way an operator would.
  local jid="" waited=0
  while [ "$waited" -lt 60 ]; do
    jid="$(find "$c/.aid-o/work/profile-jobs" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
    [ -n "$jid" ] && [ -f "$jid/job.json" ] && break
    sleep 1; waited=$(( waited + 1 ))
  done
  [ -n "$jid" ]
  bash "$PLUGIN_DIR/scripts/aid-job.sh" cancel --jobs-dir "$c/.aid-o/work/profile-jobs" \
    --id "$(basename "$jid")" >/dev/null 2>&1 || true

  wait "$pid" 2>/dev/null || true
  local r; r="$(cat "$TEST_TMPDIR/rp")"
  [ -f "$r" ]
  [ "$(jq -r '.complete' "$r")" = "false" ]
  [ "$(jq -r '.incomplete_reason' "$r")" = "cancelled" ]
  [ "$(jq -r '.cancelled' "$r")" = "true" ]
  # and a cancelled run names no cause at all
  [ "$(jq -r '.root_cause.bucket' "$r")" = "undecidable" ]
  [ "$(jq -r '.root_cause.confidence' "$r")" = "low" ]
}

@test "DEADLINE: an unfinished run reports a lower bound and refuses to name a cause" {
  # The honest shape. `elapsed` becomes `lower_bound_ms`, the timing document
  # says truncated, and the root cause is `undecidable` WITH the probe that
  # would settle it — not a plausible-sounding guess.
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 1 2>/dev/null)"
  [ "$(jq -r '.complete' "$r")" = "false" ]
  [ "$(jq -r '.incomplete_reason' "$r")" = "deadline" ]
  [ "$(jq -r '.lower_bound_ms' "$r")" -ge 60000 ]
  [ "$(jq -r '.timing.truncated' "$r")" = "true" ]
  [ "$(jq -r '.root_cause.next_probe' "$r")" != "null" ]
}

@test "DEADLINE: the cases observed BEFORE the deadline are kept, not discarded" {
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 1 2>/dev/null)"
  [ "$(jq -r '.timing.cases | length' "$r")" -gt 5 ]
  [ "$(jq -r '.timing.planned' "$r")" -gt "$(jq -r '.timing.cases | length' "$r")" ]
}

@test "duplicate membership is read from contains[], and only EXACT membership counts" {
  # A runtime-partitioned candidate set says nothing about whether a unit
  # really ran twice; counting it would report every pooled bats file as
  # duplicated.
  local c contains r; c="$(_clone)"
  contains="$TEST_TMPDIR/contains.json"
  cat > "$contains" <<'JSON'
[{"gate":"gate:a","kind":"direct_invocation","partition":"all","membership":"exact",
  "run_unit_ids":["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"]},
 {"gate":"gate:b","kind":"direct_invocation","partition":"all","membership":"exact",
  "run_unit_ids":["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"]},
 {"gate":"gate:pool","kind":"catalog_pool_runner","partition":"pool","membership":"runtime_partitioned",
  "run_unit_ids":["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"]}]
JSON
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" \
    --budget-minutes 3 --contains "$contains")"
  [ "$(jq -r '.duplicate_membership.duplicated' "$r")" = "true" ]
  [ "$(jq -r '.root_cause.bucket' "$r")" = "duplicate_membership" ]
  # the runtime-partitioned gate must NOT be among the cited gates
  [ "$(jq -r '.duplicate_membership.gates | index("gate:pool")' "$r")" = "null" ]
}

@test "a single exact gate is NOT reported as duplicated" {
  local c contains r; c="$(_clone)"
  contains="$TEST_TMPDIR/one.json"
  cat > "$contains" <<'JSON'
[{"gate":"gate:only","kind":"direct_invocation","partition":"all","membership":"exact",
  "run_unit_ids":["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary"]}]
JSON
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" \
    --budget-minutes 3 --contains "$contains")"
  [ "$(jq -r '.duplicate_membership.duplicated' "$r")" = "false" ]
  [ "$(jq -r '.root_cause.bucket' "$r")" != "duplicate_membership" ]
}

@test "the receipt records the runner version the timing came from" {
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  [[ "$(jq -r '.timing.bats_version' "$r")" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ "$(jq -r '.schema_version' "$r")" = "aid-test-profile-v1" ]
}

@test "the cost curve needs enough timed cases to tell growth from noise" {
  # Declaring accumulation from three data points is how a plausible-sounding
  # cause gets attached to ordinary variance.
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  local n; n="$(jq -r '.timing.cases | length' "$r")"
  if [ "$n" -lt 8 ]; then
    [ "$(jq -r '.cost_curve.detected' "$r")" = "false" ]
    [[ "$(jq -r '.cost_curve.note // ""' "$r")" == *"too few timed cases"* ]]
  fi
}

@test "source signals are recorded as SIGNALS, never as an attributed share of the time" {
  # The runner reports one duration per case and cannot separate waiting from
  # working, so a sleep count is evidence for a probe — not a number of
  # milliseconds anyone may attribute to waiting.
  local c r; c="$(_clone)"
  r="$(bash "$PROFILE" \
    --run-unit-id "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-epic-summary" \
    --catalog "$CATALOG" --execution-yaml "$EXEC_YAML" \
    --output-dir "$OUT" --target-root "$c" --project-root "$REPO" --budget-minutes 3)"
  run jq -e '.source_signals | has("explicit_sleeps") and has("git_invocations")' "$r"
  [ "$status" -eq 0 ]
  # no bucket in the receipt claims a millisecond split the runner cannot make
  run jq -e '.root_cause | has("attributed_ms")' "$r"
  [ "$status" -ne 0 ]
}
