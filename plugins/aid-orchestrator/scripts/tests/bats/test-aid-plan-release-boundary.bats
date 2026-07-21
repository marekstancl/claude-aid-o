#!/usr/bin/env bats
# test-aid-plan-release-boundary.bats — P064 "Plan Branch Substrate"
# (EPIC E-064-1_2). THE single mandatory integration suite for this plan
# (see .aid-o/plans/P064-plan-branch-substrate.md — this file is named and
# owned by the plan itself, not invented per-step). Every later step in this
# EPIC (and P068's plan-final runner) ADDS test blocks here rather than
# creating a sibling suite — keep new coverage inside the matching
# `# ─── <Library/Command> ───` describe-block below, adding a new block only
# for a genuinely new library/command under test.
#
# Step 1 seeds this file with the bottom-of-stack libraries only:
#   - lib/aid-lock.sh        — generic sidecar flock helper
#   - lib/aid-plan-state.sh  — plan state file + operation record
# Neither library touches Git, so none of these tests need a real
# repository — `setup_test_evidence_dir` is still used (for TEST_PROJECT_ROOT
# and test isolation) but its git-init side effect is incidental here; a
# later step's Git-touching commands (`aid-plan-fsm.sh`) are where a real
# repo starts mattering for this suite.
#
# Step 2 registers the `plan_boundary_manifest` protocol-v2 artifact type
# (envelope + payload-key only) — its own coverage lives in
# scripts/tests/test-protocol-validate.sh, not here.
#
# Step 3 adds:
#   - lib/aid-plan-manifest.sh — the manifest producer/reader/updater +
#     invariant enforcer (plan-boundary-manifest.json, gitignored runtime
#     area — still no real Git needed for THESE tests either).
#   - lib/aid-lifecycle.sh's NEW `aid_lifecycle_plan_mode` /
#     `aid_lifecycle_set_plan_mode` (the git-tracked mode reader/durable
#     writer) — THESE tests DO need a real repo on target_branch, which
#     `setup_test_evidence_dir` already provides (git init + initial commit
#     on main).
#
# This suite is intentionally NOT part of the aggregate `run-all-tests.sh`
# job — see .github/workflows/ci.yml's dedicated `plan-boundary-tests` job
# and run-all-tests.sh's DELEGATED exclusion (both added in this same step).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  LOCK_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-lock.sh"
  PLAN_STATE_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh"
  PLAN_MANIFEST_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh"
  LIFECYCLE_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
  PLAN_FSM_CLI="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  FIXTURES_DIR="$AID_PLUGIN_PATH/scripts/tests/fixtures/protocol-v2/plan_boundary_manifest"
  # Step 5 (E-064-1_2): the EPIC-level FSM entry point itself, now carrying
  # the plan-branch lineage precondition.
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export LOCK_LIB PLAN_STATE_LIB PLAN_MANIFEST_LIB LIFECYCLE_LIB PLAN_FSM_CLI FIXTURES_DIR FSM

  # All three libraries are CWD/env-root-relative, never git-relative — point
  # them at this test's isolated project root (aid-lifecycle.sh's functions
  # instead take an explicit `root` arg, which the lifecycle tests below pass
  # as "." after cd-ing into TEST_PROJECT_ROOT, matching test-lifecycle.bats'
  # own convention).
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"

  # shellcheck disable=SC1090
  source "$PLAN_STATE_LIB"      # also sources $LOCK_LIB (see its own header)
  # shellcheck disable=SC1090
  source "$PLAN_MANIFEST_LIB"   # also sources $LOCK_LIB + aid-gate-profile.sh
  # shellcheck disable=SC1090
  source "$LIFECYCLE_LIB"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixtures ────────────────────────────────────────────────────────────

# _state_file <plan_id> — the canonical state file path, reconstructed
# independently of the library's own (private) path helper, matching this
# repo's existing convention (e.g. test-cp1-ledger.bats's `_ledger_file`).
_state_file() {
  echo "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${1}/plan-state.yaml"
}

# _ops_file <plan_id> — the canonical operation-record path.
_ops_file() {
  echo "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${1}/operations.jsonl"
}

# _init_plan <plan_id> [mode] — convenience wrapper around plan_state_init
# with sane defaults for tests that don't care about mode/branch naming.
_init_plan() {
  local plan_id="$1" mode="${2:-plan_branch}"
  plan_state_init "$plan_id" "$mode" "plan/${plan_id}" "main"
}

# =============================================================================
# ─── lib/aid-lock.sh ─────────────────────────────────────────────────────
# =============================================================================

# ─── AC1: aid_lock_acquire on an already-held lock returns 3 within the
#          stated timeout rather than blocking indefinitely ────────────────
@test "AC1: aid_lock_acquire on an already-held lock returns 3 within the timeout" {
  local lockfile="$TEST_TMPDIR/ac1.lock"

  # A genuinely separate, concurrent process holds the lock for 3s.
  bash "$LOCK_LIB" hold "$lockfile" 3 &
  local hold_pid=$!
  sleep 0.5   # let the holder actually acquire before we contend

  local start end elapsed
  start=$(date +%s)
  run aid_lock_acquire "$lockfile" 1
  end=$(date +%s)
  elapsed=$((end - start))

  [ "$status" -eq 3 ]
  [[ "$output" == *"lock timeout"* ]]
  [[ "$output" == *"$lockfile"* ]]
  # Bounded, not indefinite: must return close to the 1s timeout, well under
  # the holder's full 3s hold.
  [ "$elapsed" -le 2 ]

  wait "$hold_pid" 2>/dev/null || true
}

@test "aid_lock_acquire: lock file exists but holder is dead — next acquire succeeds immediately (Edge Case)" {
  local lockfile="$TEST_TMPDIR/dead-holder.lock"

  # A holder that acquires and exits immediately (no sleep) — by the time we
  # try, its fd is long closed, so the flock is already released even though
  # the sidecar file (with its now-stale pid) still exists on disk.
  bash "$LOCK_LIB" hold "$lockfile" 0
  [ -f "$lockfile" ]

  run aid_lock_acquire "$lockfile" 2
  [ "$status" -eq 0 ]
}

@test "aid_lock_acquire + aid_lock_release: fd is usable and cleanly closed, lock is re-acquirable after release" {
  local lockfile="$TEST_TMPDIR/reacquire.lock"

  aid_lock_acquire "$lockfile" 5
  [ "$?" -eq 0 ]
  [ -n "$AID_LOCK_FD" ]
  local fd="$AID_LOCK_FD"

  aid_lock_release "$fd"
  [ "$?" -eq 0 ]

  # A second acquire on the SAME path must succeed promptly now that the
  # first was released — proves release actually let go of the flock.
  local start end
  start=$(date +%s)
  aid_lock_acquire "$lockfile" 5
  local rc=$?
  end=$(date +%s)
  [ "$rc" -eq 0 ]
  [ $((end - start)) -le 1 ]
  aid_lock_release "$AID_LOCK_FD"
}

@test "aid_lock_release: rejects a non-numeric fd argument" {
  run aid_lock_release "not-a-fd"
  [ "$status" -eq 1 ]
}

# =============================================================================
# ─── lib/aid-plan-state.sh — state file ──────────────────────────────────
# =============================================================================

@test "plan_state_init: seeds a fresh state file at plan_state OPEN" {
  run _init_plan "P064"
  [ "$status" -eq 0 ]
  [ -f "$(_state_file P064)" ]

  run plan_state_get P064 plan_state
  [ "$status" -eq 0 ]
  [ "$output" = "OPEN" ]

  run plan_state_get P064 mode
  [ "$output" = "plan_branch" ]

  run plan_state_get P064 plan_branch
  [ "$output" = "plan/P064" ]

  run plan_state_get P064 target_branch
  [ "$output" = "main" ]
}

@test "plan_state_init: refuses to overwrite an existing state file (never a silent reset)" {
  _init_plan "P064"
  run _init_plan "P064"
  [ "$status" -ne 0 ]
  # Original state must be untouched.
  run plan_state_get P064 plan_state
  [ "$output" = "OPEN" ]
}

@test "plan_state_init: rejects a plan_branch that isn't exactly plan/<plan_id>" {
  run plan_state_init "P064" "plan_branch" "plan/WRONG" "main"
  [ "$status" -ne 0 ]
  [ ! -f "$(_state_file P064)" ]
}

@test "plan_state_get: not_found on stdout + exit 1 when the plan state directory does not exist yet (Edge Case)" {
  run plan_state_get P999 plan_state
  [ "$status" -eq 1 ]
  [ "$output" = "not_found" ]
}

@test "plan_state_get: corrupt state file (unrecognized plan_state) returns 5 and names the offending key" {
  _init_plan "P064"
  sed -i 's/plan_state: OPEN/plan_state: NOT_A_REAL_STATE/' "$(_state_file P064)"

  run plan_state_get P064 plan_state
  [ "$status" -eq 5 ]
  [[ "$output" == *"offending key: plan_state"* ]]
}

@test "plan_state_get: corrupt state file (missing plan_id) returns 5 and names the offending key" {
  _init_plan "P064"
  sed -i '/^plan_id:/d' "$(_state_file P064)"

  run plan_state_get P064 plan_state
  [ "$status" -eq 5 ]
  [[ "$output" == *"offending key: plan_id"* ]]
}

# ─── AC2: plan_state_transition P064 OPEN PLAN_MERGING exits non-zero and
#          leaves plan_state unchanged on disk ─────────────────────────────
@test "AC2: plan_state_transition OPEN -> PLAN_MERGING is rejected and leaves plan_state unchanged" {
  _init_plan "P064"

  run plan_state_transition P064 OPEN PLAN_MERGING
  [ "$status" -ne 0 ]

  run plan_state_get P064 plan_state
  [ "$output" = "OPEN" ]
}

@test "plan_state_transition: a legal transition succeeds and persists" {
  _init_plan "P064"

  run plan_state_transition P064 OPEN EPIC_INTEGRATION
  [ "$status" -eq 0 ]

  run plan_state_get P064 plan_state
  [ "$output" = "EPIC_INTEGRATION" ]
}

@test "plan_state_transition: rejects a transition whose on-disk from-state is stale" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION

  # Caller still believes the plan is OPEN — but it has already moved on.
  run plan_state_transition P064 OPEN ABORTED
  [ "$status" -ne 0 ]

  run plan_state_get P064 plan_state
  [ "$output" = "EPIC_INTEGRATION" ]
}

@test "plan_state_transition: full happy-path chain through to CLOSED is legal end to end" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM PLAN_MERGING
  run plan_state_transition P064 PLAN_MERGING CLOSED
  [ "$status" -eq 0 ]
  run plan_state_get P064 plan_state
  [ "$output" = "CLOSED" ]
}

# =============================================================================
# ─── lib/aid-plan-state.sh — operation record ────────────────────────────
# =============================================================================

# ─── AC6: plan_op_key returns distinct keys for every pair differing in any
#          component, asserted directly over the key builder ──────────────
@test "AC6: plan_op_key produces distinct keys for every input differing in one component" {
  local base cmd_diff plan_diff stage_diff attempt_diff subject_diff
  base="$(plan_op_key "epic-merge-to-plan" "P064" "-" "1" "E-064-1_4")"
  cmd_diff="$(plan_op_key "epic-start" "P064" "-" "1" "E-064-1_4")"
  plan_diff="$(plan_op_key "epic-merge-to-plan" "P065" "-" "1" "E-064-1_4")"
  stage_diff="$(plan_op_key "epic-merge-to-plan" "P064" "freeze" "1" "E-064-1_4")"
  attempt_diff="$(plan_op_key "epic-merge-to-plan" "P064" "-" "2" "E-064-1_4")"
  subject_diff="$(plan_op_key "epic-merge-to-plan" "P064" "-" "1" "E-064-2_4")"

  local -a all=("$base" "$cmd_diff" "$plan_diff" "$stage_diff" "$attempt_diff" "$subject_diff")
  local i j
  for i in "${!all[@]}"; do
    for j in "${!all[@]}"; do
      if [[ "$i" != "$j" ]]; then
        [[ "${all[$i]}" != "${all[$j]}" ]]
      fi
    done
  done

  # And determinism: same inputs, same key, every time.
  local repeat
  repeat="$(plan_op_key "epic-merge-to-plan" "P064" "-" "1" "E-064-1_4")"
  [ "$repeat" = "$base" ]
}

# ─── AC4: a resumed command with no --op-id derives the same op_id as the
#          crashed original and finds its record ───────────────────────────
@test "AC4: a resumed command derives the identical op_id and finds the crashed original's record" {
  _init_plan "P064"

  # "Original" invocation: derive the default key and begin the operation,
  # then crash after intent (no git_applied/commit).
  local op_id
  op_id="$(plan_op_key "epic-merge-to-plan" "P064" "-" "0" "E-064-1_4")"
  plan_op_begin "P064" "$op_id" "epic-merge-to-plan" "E-064-1_4" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  # "Resumed" invocation, later, no --op-id supplied — a real caller would
  # re-derive from the SAME (command, plan_id, stage, attempt, subject)
  # inputs, none of which carry any timestamp/entropy.
  local resumed_op_id
  resumed_op_id="$(plan_op_key "epic-merge-to-plan" "P064" "-" "0" "E-064-1_4")"
  [ "$resumed_op_id" = "$op_id" ]

  run plan_op_reconcile "P064" "$resumed_op_id"
  [ "$status" -eq 0 ]
  [ "$output" = "intent" ]
}

# ─── AC3: plan_op_reconcile returns git_applied for an operation whose
#          git_applied record exists but whose state_committed record does
#          not ─────────────────────────────────────────────────────────────
@test "AC3: plan_op_reconcile returns git_applied when state_committed has not been written yet" {
  _init_plan "P064"
  local op_id="epic-merge-to-plan:P064:-:0:E-064-1_4"

  plan_op_begin "P064" "$op_id" "epic-merge-to-plan" "E-064-1_4" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  plan_op_mark_git_applied "P064" "$op_id" "cafebabecafebabecafebabecafebabecafebabe"

  run plan_op_reconcile "P064" "$op_id"
  [ "$status" -eq 0 ]
  [ "$output" = "git_applied" ]
}

@test "plan_op_reconcile: full cycle reaches state_committed" {
  _init_plan "P064"
  local op_id="epic-merge-to-plan:P064:-:0:E-064-1_4"

  plan_op_begin "P064" "$op_id" "epic-merge-to-plan" "E-064-1_4" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  plan_op_mark_git_applied "P064" "$op_id" "cafebabecafebabecafebabecafebabecafebabe"
  plan_op_commit "P064" "$op_id"

  run plan_op_reconcile "P064" "$op_id"
  [ "$status" -eq 0 ]
  [ "$output" = "state_committed" ]
}

@test "plan_op_reconcile: none when operations.jsonl has no record for the op_id (including no file at all)" {
  _init_plan "P064"
  run plan_op_reconcile "P064" "some-op-id-nobody-wrote"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

# ─── AC5: negative test on key uniqueness — after epic-merge-to-plan for one
#          EPIC records state_committed, the same command for a second EPIC
#          still executes: distinct subjects never share a key ────────────
@test "AC5: distinct subjects never share a key — a second EPIC's op still executes after the first committed" {
  _init_plan "P064"

  local op_id_1 op_id_2
  op_id_1="$(plan_op_key "epic-merge-to-plan" "P064" "-" "0" "E-064-1_4")"
  op_id_2="$(plan_op_key "epic-merge-to-plan" "P064" "-" "0" "E-064-2_4")"
  [ "$op_id_1" != "$op_id_2" ]

  plan_op_begin "P064" "$op_id_1" "epic-merge-to-plan" "E-064-1_4" "1111111111111111111111111111111111111111"
  plan_op_mark_git_applied "P064" "$op_id_1" "2222222222222222222222222222222222222222"
  plan_op_commit "P064" "$op_id_1"
  run plan_op_reconcile "P064" "$op_id_1"
  [ "$output" = "state_committed" ]

  # A second, genuinely distinct EPIC's op: begins clean at "none" first —
  # proving the first EPIC's state_committed record did not leak in.
  run plan_op_reconcile "P064" "$op_id_2"
  [ "$output" = "none" ]

  plan_op_begin "P064" "$op_id_2" "epic-merge-to-plan" "E-064-2_4" "3333333333333333333333333333333333333333"
  run plan_op_reconcile "P064" "$op_id_2"
  [ "$output" = "intent" ]

  # And the first EPIC's record is untouched by the second's activity.
  run plan_op_reconcile "P064" "$op_id_1"
  [ "$output" = "state_committed" ]
}

# ─── AC7: a truncated final line in operations.jsonl produces a non-zero
#          exit that names the line number ─────────────────────────────────
@test "AC7: a truncated final line in operations.jsonl produces a non-zero exit naming the line number" {
  _init_plan "P064"
  local op_id="epic-merge-to-plan:P064:-:0:E-064-1_4"

  plan_op_begin "P064" "$op_id" "epic-merge-to-plan" "E-064-1_4" "1111111111111111111111111111111111111111"
  plan_op_mark_git_applied "P064" "$op_id" "2222222222222222222222222222222222222222"

  # Simulate a crash mid-append: a partial line with NO trailing newline.
  printf '{"op_id":"%s","command":"epic-merge-to-plan","subject":"E-064-1_4","phase":"state_comm' "$op_id" >> "$(_ops_file P064)"

  run plan_op_reconcile "P064" "$op_id"
  [ "$status" -ne 0 ]
  # Line 3 is the truncated one (two complete records precede it).
  [[ "$output" == *"line 3"* ]]

  # Never silently trusted as "nothing happened", and never elevated past
  # the last COMPLETE record (git_applied), per the Edge Case in the spec.
  [[ "$output" == *"git_applied"* ]]
  [[ "$output" != *"state_committed"* ]]
}

@test "operations.jsonl: a line whose command disagrees with an earlier record sharing the same op_id is corrupt (exit 5)" {
  _init_plan "P064"
  local op_id="shared-op-id"

  # Hand-craft a corrupted log: two records, same op_id, DIFFERENT commands
  # — impossible via this library's own functions (which always propagate
  # the first record's command forward), so this simulates external/manual
  # corruption of the file.
  {
    printf '{"op_id":"%s","command":"epic-merge-to-plan","subject":"E-064-1_4","phase":"intent","expected_before_sha":null,"resulting_sha":null,"at":"2026-07-20T00:00:00Z"}\n' "$op_id"
    printf '{"op_id":"%s","command":"epic-start","subject":"E-064-1_4","phase":"intent","expected_before_sha":null,"resulting_sha":null,"at":"2026-07-20T00:00:01Z"}\n' "$op_id"
  } > "$(_ops_file P064)"

  run plan_op_reconcile "P064" "$op_id"
  [ "$status" -eq 5 ]
  [[ "$output" == *"corrupt"* ]]
}

@test "plan_op_mark_git_applied: fails cleanly when no prior plan_op_begin exists for the op_id" {
  _init_plan "P064"
  run plan_op_mark_git_applied "P064" "never-begun" "cafebabecafebabecafebabecafebabecafebabe"
  [ "$status" -ne 0 ]
}

@test "plan_op_commit: fails cleanly when no prior plan_op_begin exists for the op_id" {
  _init_plan "P064"
  run plan_op_commit "P064" "never-begun"
  [ "$status" -ne 0 ]
}

@test "operations.jsonl: a subject operated on twice (merge, conflict/abort, re-merge) accumulates records; reconcile reads the LAST one" {
  _init_plan "P064"
  local op_id="epic-merge-to-plan:P064:-:0:E-064-1_4"

  # First attempt: begins, then aborts (never reaches git_applied/commit in
  # this simulation — just demonstrates several records under one key).
  plan_op_begin "P064" "$op_id" "epic-merge-to-plan" "E-064-1_4" "1111111111111111111111111111111111111111"
  run plan_op_reconcile "P064" "$op_id"
  [ "$output" = "intent" ]

  # Re-merge after conflict resolution: same op_id, moves all the way to
  # state_committed.
  plan_op_mark_git_applied "P064" "$op_id" "2222222222222222222222222222222222222222"
  plan_op_commit "P064" "$op_id"

  run plan_op_reconcile "P064" "$op_id"
  [ "$status" -eq 0 ]
  [ "$output" = "state_committed" ]

  # All records are genuinely still present (append-only, nothing rewritten).
  local n
  n=$(wc -l < "$(_ops_file P064)")
  [ "$n" -eq 3 ]
}

# ─── Corruption isolation: _plan_op_last_command_subject must skip unparseable
#     lines elsewhere in the file, not fail silently ──────────────────────────
@test "Regression: _plan_op_last_command_subject is resilient to corrupt/truncated lines elsewhere in operations.jsonl" {
  _init_plan "P064"

  # Seed the operations log with 3 clean records for an earlier op_id (opA).
  local op_a="epic-merge-to-plan:P064:-:0:E-064-1_4"
  plan_op_begin "P064" "$op_a" "epic-merge-to-plan" "E-064-1_4" "1111111111111111111111111111111111111111"
  plan_op_mark_git_applied "P064" "$op_a" "2222222222222222222222222222222222222222"
  plan_op_commit "P064" "$op_a"

  # Now append a genuinely unparseable line (not valid JSON at all) — this is
  # the actual corruption scenario the bug was about. jq -s (slurp mode, the
  # original implementation) errors out on the WHOLE file if even one line
  # fails to parse, which silently looked like "no record found" to callers.
  printf '{this is not valid json AT ALL, no closing brace\n' >> "$(_ops_file P064)"

  # Begin an unrelated operation (opB). This should succeed and write an
  # intent record despite the corrupt line earlier in the file.
  local op_b="epic-merge-to-plan:P064:-:0:E-064-2_4"
  run plan_op_begin "P064" "$op_b" "epic-merge-to-plan" "E-064-2_4" "3333333333333333333333333333333333333333"
  [ "$status" -eq 0 ]

  # Now try plan_op_mark_git_applied for opB — this MUST succeed and NOT
  # complain "no prior record found" even though a corrupt line exists
  # elsewhere in the file. With the fix, _plan_op_last_command_subject skips
  # the unparseable line (matching plan_op_reconcile's corruption isolation)
  # and finds the valid opB intent record.
  run plan_op_mark_git_applied "P064" "$op_b" "4444444444444444444444444444444444444444"
  [ "$status" -eq 0 ]

  # And plan_op_commit should also succeed for opB.
  run plan_op_commit "P064" "$op_b"
  [ "$status" -eq 0 ]

  # Verify the full cycle for opB completed successfully. plan_op_reconcile
  # still reports rc=5 here (per its own contract: ANY corrupt line in the
  # file, matching this op_id or not, is flagged) but its best-effort status
  # on stdout is unaffected — this is the file-wide corruption signal that
  # _plan_op_last_command_subject intentionally does NOT replicate, since
  # that helper's job is narrowly "find this op_id's record", not "audit the
  # whole file".
  run plan_op_reconcile "P064" "$op_b"
  [ "$status" -eq 5 ]
  [[ "$output" == *"state_committed"* ]]
}

# =============================================================================
# ─── lib/aid-plan-manifest.sh ────────────────────────────────────────────
# =============================================================================

# ─── fixtures ────────────────────────────────────────────────────────────

# _manifest_file <plan_id> — the canonical manifest path, reconstructed
# independently of the library's own (private) path helper (matches
# `_state_file`'s convention above).
_manifest_file() {
  echo "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${1}/plan-boundary-manifest.json"
}

# _init_manifest <plan_id> [mode] — convenience wrapper with sane defaults.
_init_manifest() {
  local plan_id="$1" mode="${2:-plan_branch}"
  plan_manifest_init "$plan_id" "plan/${plan_id}" "main" \
    "1111111111111111111111111111111111111111" \
    "1111111111111111111111111111111111111111" "$mode"
}

# _seed_manifest_from_fixture <plan_id> <fixture_basename.json> — copies a
# fixture from FIXTURES_DIR straight to the canonical runtime path (every
# fixture already carries plan_id=P900, matching the default used below).
_seed_manifest_from_fixture() {
  local plan_id="$1" fixture="$2"
  mkdir -p "$(dirname "$(_manifest_file "$plan_id")")"
  cp "$FIXTURES_DIR/${fixture}" "$(_manifest_file "$plan_id")"
}

# ─── init / path / get ──────────────────────────────────────────────────

@test "plan_manifest_init: seeds a fresh manifest with plan_state OPEN and the given mode" {
  run _init_manifest "P900"
  [ "$status" -eq 0 ]
  [ -f "$(_manifest_file P900)" ]

  run plan_manifest_get P900 '.plan_boundary_manifest.plan_state'
  [ "$output" = "OPEN" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.mode'
  [ "$output" = "plan_branch" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.plan_branch'
  [ "$output" = "plan/P900" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.total_epics'
  [ "$output" = "0" ]
}

@test "plan_manifest_init: refuses to overwrite an existing manifest (never a silent reset)" {
  _init_manifest "P900"
  run _init_manifest "P900"
  [ "$status" -ne 0 ]
  run plan_manifest_get P900 '.plan_boundary_manifest.plan_state'
  [ "$output" = "OPEN" ]
}

@test "plan_manifest_init: rejects a plan_branch that isn't exactly plan/<plan_id>" {
  run plan_manifest_init "P900" "plan/WRONG" "main" \
    "1111111111111111111111111111111111111111" \
    "1111111111111111111111111111111111111111" "plan_branch"
  [ "$status" -ne 0 ]
  [ ! -f "$(_manifest_file P900)" ]
}

@test "plan_manifest_get: not_found on stdout + exit 1 when no manifest exists yet" {
  run plan_manifest_get P999 '.plan_boundary_manifest.plan_state'
  [ "$status" -eq 1 ]
  [ "$output" = "not_found" ]
}

@test "plan_manifest_validate: not_found on stdout + exit 1 when no manifest exists yet" {
  run plan_manifest_validate P999
  [ "$status" -eq 1 ]
  [ "$output" = "not_found" ]
}

@test "plan_manifest_init + plan_manifest_validate: a freshly-initialized manifest is valid" {
  _init_manifest "P900"
  run plan_manifest_validate P900
  [ "$status" -eq 0 ]
}

# ─── AC3: a jq filter producing invalid JSON leaves the manifest untouched ──
@test "AC3: plan_manifest_update with a filter that errors leaves the on-disk manifest byte-identical" {
  _init_manifest "P900"
  local before after
  before="$(cat "$(_manifest_file P900)")"

  run plan_manifest_update P900 '. | error("boom")'
  [ "$status" -ne 0 ]
  [[ "$output" == *"boom"* || "$output" == *"filter"* ]]

  after="$(cat "$(_manifest_file P900)")"
  [ "$before" = "$after" ]
}

@test "plan_manifest_update: a well-formed filter mutates the canonical file atomically" {
  _init_manifest "P900"
  run plan_manifest_update P900 '.plan_boundary_manifest.plan_state = "EPIC_INTEGRATION"'
  [ "$status" -eq 0 ]
  run plan_manifest_get P900 '.plan_boundary_manifest.plan_state'
  [ "$output" = "EPIC_INTEGRATION" ]
}

# ─── add_epic / set_epic_status ─────────────────────────────────────────

@test "plan_manifest_add_epic: adds a new epic_runs entry and keeps epics/total_epics/active_epics in sync" {
  _init_manifest "P900"
  run plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"
  [ "$status" -eq 0 ]

  run plan_manifest_get P900 '.plan_boundary_manifest.total_epics'
  [ "$output" = "1" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.epics | length'
  [ "$output" = "1" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.active_epics | index("E-900-1_2")'
  [ "$output" != "" ]

  run plan_manifest_validate P900
  [ "$status" -eq 0 ]
}

# ─── Edge Case: add_epic called twice for the same epic_id upserts, never
#     duplicates ──────────────────────────────────────────────────────────
@test "Edge Case: plan_manifest_add_epic called twice for the same epic_id updates in place, never duplicates" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  run plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1-retry" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"
  [ "$status" -eq 0 ]

  run plan_manifest_get P900 '.plan_boundary_manifest.epics | length'
  [ "$output" = "1" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs | length'
  [ "$output" = "1" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].run_id'
  [ "$output" = "R-E900-1-retry" ]
}

# ─── Edge Case: merged_to_plan with no merge_commit is rejected ────────────
@test "Edge Case: plan_manifest_set_epic_status merged_to_plan without a merge_commit is rejected, no write" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  local before after
  before="$(cat "$(_manifest_file P900)")"
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "merged_to_plan"
  [ "$status" -ne 0 ]
  after="$(cat "$(_manifest_file P900)")"
  [ "$before" = "$after" ]
}

@test "plan_manifest_set_epic_status: merged_to_plan with a merge_commit succeeds and drops the epic from active_epics" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  run plan_manifest_set_epic_status "P900" "E-900-1_2" "merged_to_plan" "3333333333333333333333333333333333333333"
  [ "$status" -eq 0 ]

  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$output" = "merged_to_plan" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].epic_merge_commit'
  [ "$output" = "3333333333333333333333333333333333333333" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.active_epics | index("E-900-1_2")'
  [ "$status" -ne 0 ]   # no longer active — index() on a miss is null -> plan_manifest_get returns 1

  run plan_manifest_validate P900
  [ "$status" -eq 0 ]
}

@test "plan_manifest_set_epic_status: unknown epic_id is rejected (no prior epic_runs entry)" {
  _init_manifest "P900"
  run plan_manifest_set_epic_status "P900" "E-900-9_9" "running"
  [ "$status" -ne 0 ]
}

# ─── raise_final_profile ─────────────────────────────────────────────────

# ─── AC2: raising to a LOWER profile than current is a documented no-op ────
@test "AC2: plan_manifest_raise_final_profile to a LOWER profile than current is a no-op, current value unchanged" {
  _init_manifest "P900"
  plan_manifest_update P900 '.plan_boundary_manifest.plan_final_required_profile = "standard"'

  run plan_manifest_raise_final_profile "P900" "targeted"
  [ "$status" -eq 0 ]

  run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "standard" ]
}

@test "plan_manifest_raise_final_profile: raising to a HIGHER profile actually raises it" {
  _init_manifest "P900"
  plan_manifest_update P900 '.plan_boundary_manifest.plan_final_required_profile = "standard"'

  run plan_manifest_raise_final_profile "P900" "full"
  [ "$status" -eq 0 ]

  run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]
}

@test "plan_manifest_raise_final_profile: never decreases across two sequential calls (up then down)" {
  _init_manifest "P900"
  plan_manifest_update P900 '.plan_boundary_manifest.plan_final_required_profile = "standard"'

  plan_manifest_raise_final_profile "P900" "full"
  run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]

  # A second call requesting something LOWER than the now-current "full"
  # must leave it at "full" — the rank table never goes backwards.
  run plan_manifest_raise_final_profile "P900" "targeted"
  [ "$status" -eq 0 ]
  run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]
}

# ─── Regression: concurrent raise_final_profile calls must never downgrade ──
@test "Regression: concurrent raise_final_profile calls never downgrade (race-condition test)" {
  # Spawn two concurrent background processes, each raising to a different
  # profile, with NO artificial stagger between them — both start racing
  # from the same instant. The higher-ranked one must win, regardless of
  # which process's lock-free... (there is none anymore) / which process
  # wins the lock first.
  # Rank table: quick=0 < targeted=1 < standard=2 < full=3 < release=4
  # We race: Caller A raises to "full" (rank 3), Caller B raises to
  # "release" (rank 4). Expected result, every time: "release" (the max).
  #
  # A single trial is not reliable evidence on its own: a staggered start
  # (verified empirically against the pre-fix code — the bug this guards
  # against is real, reproduced 3/8 times under true concurrency with no
  # stagger, 0/8 with a naive 50ms stagger between starts, which gives the
  # first caller time to fully complete before the second even begins,
  # eliminating the actual interleaving window) lets the two calls run
  # effectively sequentially and passes even on the buggy pre-fix
  # implementation by luck. This loop runs N truly-concurrent trials,
  # resetting the field to "standard" before each, and requires every single
  # one to land on "release" — a real regression must fail at least one.
  _init_manifest "P900"
  local trial
  for trial in 1 2 3 4 5; do
    plan_manifest_update P900 '.plan_boundary_manifest.plan_final_required_profile = "standard"'

    bash -c "
      source '$PLAN_MANIFEST_LIB'
      export AID_PLAN_MANIFEST_PROJECT_ROOT='$TEST_PROJECT_ROOT'
      plan_manifest_raise_final_profile 'P900' 'full'
    " &
    local pid_a=$!

    bash -c "
      source '$PLAN_MANIFEST_LIB'
      export AID_PLAN_MANIFEST_PROJECT_ROOT='$TEST_PROJECT_ROOT'
      plan_manifest_raise_final_profile 'P900' 'release'
    " &
    local pid_b=$!

    wait "$pid_a" 2>/dev/null || true
    wait "$pid_b" 2>/dev/null || true

    run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
    [ "$status" -eq 0 ]
    [ "$output" = "release" ]
  done
}

# ─── plan_manifest_validate: identity / containment / negative fixtures ──

# ─── AC1: identity mismatch fails validation ────────────────────────────
@test "AC1: a manifest whose payload plan_id differs from identity.plan_id fails plan_manifest_validate" {
  _init_manifest "P900"
  local f; f="$(_manifest_file P900)"
  local tmp; tmp="$(mktemp)"
  jq '.identity.plan_id = "P901"' "$f" > "$tmp" && mv "$tmp" "$f"

  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity"* ]]
}

@test "plan_manifest_validate: plan_branch not equal to plan/<plan_id> fails validation" {
  _init_manifest "P900"
  local f; f="$(_manifest_file P900)"
  local tmp; tmp="$(mktemp)"
  jq '.plan_boundary_manifest.plan_branch = "plan/OTHER"' "$f" > "$tmp" && mv "$tmp" "$f"

  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
}

# ─── AC4: evidence_dir containing ".." is rejected ──────────────────────
@test "AC4: an evidence_dir containing .. is rejected by containment validation" {
  _seed_manifest_from_fixture P900 invalid-path-escape.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"containment"* ]]
}

@test "negative fixture: invalid-missing-field.json fails validation on the missing field" {
  _seed_manifest_from_fixture P900 invalid-missing-field.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* ]]
}

@test "negative fixture: invalid-bad-sha.json fails validation on the malformed sha" {
  _seed_manifest_from_fixture P900 invalid-bad-sha.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"[0-9a-f]{40}"* ]]
}

@test "negative fixture: invalid-duplicate-epic.json fails validation on the duplicate" {
  _seed_manifest_from_fixture P900 invalid-duplicate-epic.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate"* ]]
}

@test "negative fixture: invalid-active-not-subset.json fails validation (active_epics not a subset)" {
  _seed_manifest_from_fixture P900 invalid-active-not-subset.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"subset"* ]]
}

@test "negative fixture: invalid-total-mismatch.json fails validation (total_epics mismatch)" {
  _seed_manifest_from_fixture P900 invalid-total-mismatch.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"total_epics"* ]]
}

@test "negative fixture: invalid-candidate-early-state.json fails validation (candidate_sha too early)" {
  _seed_manifest_from_fixture P900 invalid-candidate-early-state.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate_sha"* ]]
}

@test "negative fixture: invalid-run-id-without-dir.json fails validation (run_id/evidence_dir not paired)" {
  _seed_manifest_from_fixture P900 invalid-run-id-without-dir.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_final_run_id"* ]]
}

@test "negative fixture: invalid-merge-commit-wrong-status.json fails validation (merge_commit without merged_to_plan)" {
  _seed_manifest_from_fixture P900 invalid-merge-commit-wrong-status.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"merged_to_plan"* ]]
}

@test "negative fixture: invalid-path-escape.json fails validation (containment)" {
  _seed_manifest_from_fixture P900 invalid-path-escape.json
  run plan_manifest_validate P900
  [ "$status" -ne 0 ]
  [[ "$output" == *"containment"* ]]
}

@test "sanity: the Step 2 valid.json fixture passes plan_manifest_validate unchanged" {
  _seed_manifest_from_fixture P900 valid.json
  run plan_manifest_validate P900
  [ "$status" -eq 0 ]
}

# ─── Error Handling: aid-protocol-validate.sh missing/non-executable fails
#     CLOSED (exit 5), never treats the manifest as valid ─────────────────
@test "Error Handling: aid-protocol-validate.sh missing fails CLOSED (exit 5), never a false valid" {
  _init_manifest "P900"
  local validator="$AID_PLUGIN_PATH/scripts/aid-protocol-validate.sh"
  local moved="$TEST_TMPDIR/aid-protocol-validate.sh.moved"
  mv "$validator" "$moved"

  run plan_manifest_validate P900
  [ "$status" -eq 5 ]

  mv "$moved" "$validator"
}

# =============================================================================
# ─── lib/aid-lifecycle.sh — aid_lifecycle_plan_mode / aid_lifecycle_set_plan_mode
#     (P064 E-064-1_2 Step 3) ────────────────────────────────────────────
# =============================================================================

# _write_legacy_plan <plan_id> — a minimal strict-grammar plan file so
# aid_lifecycle_ensure_manifest (called internally by
# aid_lifecycle_set_plan_mode) has something to parse.
_write_legacy_plan() {
  local plan_id="$1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  cat > "$TEST_PROJECT_ROOT/.aid-o/plans/${plan_id}-test.md" <<'MD'
**EPIC 1: first**
MD
}

@test "aid_lifecycle_plan_mode: no manifest at all reads back legacy_epic_release_mode (documented default)" {
  run aid_lifecycle_plan_mode "P900" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "legacy_epic_release_mode" ]
}

# ─── AC5 (part 1): a manifest with no `mode` field reads back
#     legacy_epic_release_mode ─────────────────────────────────────────────
@test "AC5: a lifecycle manifest with no mode field reads back legacy_epic_release_mode" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests"
  cat > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml" <<'YML'
schema_version: aid-lifecycle-1.0
repo_id: test-repo-id
plan_id: P900
declared_epics:
  - {id: E-900-1_1, scope: required}
YML

  run aid_lifecycle_plan_mode "P900" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "legacy_epic_release_mode" ]
}

# ─── AC5 (part 2) + AC6: aid_lifecycle_set_plan_mode durably writes mode,
#     the round-trip reads it back, and the amended schema (still
#     additionalProperties:false) accepts it ────────────────────────────────
@test "AC5+AC6: aid_lifecycle_set_plan_mode durably persists mode=plan_branch; round-trips via aid_lifecycle_plan_mode; passes the amended schema" {
  _write_legacy_plan "P900"

  run aid_lifecycle_set_plan_mode "P900" "plan_branch" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Durably committed on target_branch (main) — not just written to the
  # worktree.
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:.aid-lifecycle/manifests/P900.yaml"
  [ "$status" -eq 0 ]

  run aid_lifecycle_plan_mode "P900" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "plan_branch" ]

  # AC6: the manifest (now carrying `mode`) validates against
  # plan-lifecycle-manifest.schema.json despite additionalProperties:false.
  run bash "$AID_PLUGIN_PATH/scripts/aid-lifecycle.sh" validate \
    "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml" plan-lifecycle-manifest.schema.json
  [ "$status" -eq 0 ]
}

@test "aid_lifecycle_set_plan_mode: idempotent no-op when the manifest already carries the requested mode (no new commit)" {
  _write_legacy_plan "P900"
  aid_lifecycle_set_plan_mode "P900" "plan_branch" "$TEST_PROJECT_ROOT"
  local before; before="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"

  run aid_lifecycle_set_plan_mode "P900" "plan_branch" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local after; after="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  [ "$before" = "$after" ]
}

@test "aid_lifecycle_set_plan_mode: rejects an unknown mode value, no write, no commit" {
  _write_legacy_plan "P900"
  local before_head; before_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"

  run aid_lifecycle_set_plan_mode "P900" "not_a_real_mode" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml" ]

  local after_head; after_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  [ "$before_head" = "$after_head" ]
}

# =============================================================================
# ─── scripts/aid-plan-fsm.sh — plan-start / epic-start / plan-state
#     (P064 E-064-1_2 Step 4) ────────────────────────────────────────────────
# =============================================================================

# _pfsm_bootstrap_plan <plan_id> [mode] — writes a minimal legacy plan file
# and runs a REAL plan-start through the CLI (never a parallel "test mode"
# shortcut — matches build_default_init_args's own convention of always
# exercising the production signature). Asserts plan-start itself succeeded,
# so a bootstrap failure can never masquerade as a lineage-check failure in
# the test that calls it.
_pfsm_bootstrap_plan() {
  local plan_id="$1" mode="${2:-plan_branch}"
  _write_legacy_plan "$plan_id"
  run bash "$PLAN_FSM_CLI" plan-start "$plan_id" --mode "$mode" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "AC1: plan-start creates plan/<plan_id> at exactly the recorded target SHA and is a no-op on re-run" {
  _write_legacy_plan "P064"
  local target_sha; target_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  run bash "$PLAN_FSM_CLI" plan-start P064 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "plan/P064" ]
  local branch_sha; branch_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  [ "$branch_sha" = "$target_sha" ]

  # Re-run: idempotent no-op — same SHA, no error.
  run bash "$PLAN_FSM_CLI" plan-start P064 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local branch_sha2; branch_sha2="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  [ "$branch_sha2" = "$target_sha" ]
}

@test "AC2: after plan-start, the lifecycle manifest carries the requested mode, is schema-valid, committed on target_branch, and the mode survives deleting .aid-o/" {
  _write_legacy_plan "P064"
  run bash "$PLAN_FSM_CLI" plan-start P064 --mode plan_branch --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:.aid-lifecycle/manifests/P064.yaml"
  [ "$status" -eq 0 ]

  run bash "$AID_PLUGIN_PATH/scripts/aid-lifecycle.sh" validate \
    "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml" plan-lifecycle-manifest.schema.json
  [ "$status" -eq 0 ]

  run yq -r '.mode' "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  [ "$output" = "plan_branch" ]

  # Delete the ENTIRE gitignored .aid-o/ tree — the mode lives in
  # .aid-lifecycle/ (a sibling, git-tracked tree), so it must survive.
  rm -rf "$TEST_PROJECT_ROOT/.aid-o"
  [ ! -d "$TEST_PROJECT_ROOT/.aid-o" ]

  run aid_lifecycle_plan_mode "P064" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "plan_branch" ]
}

@test "AC3: epic-start records epic_base_commit equal to the plan head observed at that moment and creates the task branch from that SHA" {
  _pfsm_bootstrap_plan "P064"
  local plan_head; plan_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "task/E-064-1_1/main" ]

  local branch_sha; branch_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse task/E-064-1_1/main)"
  [ "$branch_sha" = "$plan_head" ]

  local recorded_base
  recorded_base="$(plan_manifest_get "P064" '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .epic_base_commit')"
  [ "$recorded_base" = "$plan_head" ]

  # epic-start is idempotent on immediate re-run too.
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "AC4: a task branch created from main (not the plan head) is rejected — no manifest mutation" {
  _pfsm_bootstrap_plan "P064"
  # Advance main past the plan head so main != plan/P064.
  echo more >> "$TEST_PROJECT_ROOT/.gitkeep"
  git -C "$TEST_PROJECT_ROOT" add .gitkeep
  git -C "$TEST_PROJECT_ROOT" commit -qm "advance main past the plan head"

  local mp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"
  local manifest_before; manifest_before="$(cat "$mp")"

  git -C "$TEST_PROJECT_ROOT" branch task/E-064-1_1/main main
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]

  local manifest_after; manifest_after="$(cat "$mp")"
  [ "$manifest_before" = "$manifest_after" ]
}

@test "AC4: a task branch whose ACTUAL base does not match its RECORDED epic_base_commit (stale) is rejected — no manifest mutation" {
  # Root commit predates the plan base by construction — a genuine ancestor
  # to reset the branch onto later.
  local root_sha; root_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  echo "advance main before plan-start" >> "$TEST_PROJECT_ROOT/.gitkeep"
  git -C "$TEST_PROJECT_ROOT" add .gitkeep
  git -C "$TEST_PROJECT_ROOT" commit -qm "advance to the plan base"

  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local mp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"
  local manifest_before; manifest_before="$(cat "$mp")"

  # Force the branch onto the EARLIER root commit — an ancestor of, but not
  # equal to, its recorded base — so merge-base with plan/P064 now resolves
  # to that earlier commit, not the one epic-start actually recorded.
  git -C "$TEST_PROJECT_ROOT" branch -f task/E-064-1_1/main "$root_sha"

  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lineage broken"* ]]

  local manifest_after; manifest_after="$(cat "$mp")"
  [ "$manifest_before" = "$manifest_after" ]
}

@test "AC4: a task branch belonging to a DIFFERENT plan has no manifest entry in the NAMED plan and is rejected" {
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot prove lineage"* ]]
}

@test "Edge Case: first EPIC of a plan where plan/Pxxx and target_branch share a SHA — a manually created branch at that SAME SHA is still rejected (check is on the manifest entry, not SHA)" {
  _write_legacy_plan "P064"
  local target_sha; target_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  # Construct the exact "plan/Pxxx and target_branch share a SHA" moment
  # directly via the libraries, bypassing the full plan-start CLI: a real
  # plan-start's OWN lifecycle-mode commit (aid_lifecycle_set_plan_mode)
  # would advance main past plan/P064 immediately afterward, making this
  # moment unobservable as an external post-condition of a single
  # plan-start invocation.
  git -C "$TEST_PROJECT_ROOT" branch plan/P064 "$target_sha"
  plan_state_init "P064" "plan_branch" "plan/P064" "main"
  plan_manifest_init "P064" "plan/P064" "main" "$target_sha" "$target_sha" "plan_branch"
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" ]

  git -C "$TEST_PROJECT_ROOT" branch task/E-064-1_1/main "$target_sha"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no manifest entry"* ]]
}

@test "AC5: the same lineage checks fail identically inside a linked worktree" {
  _pfsm_bootstrap_plan "P064"

  # mock_git_worktree creates a REAL linked worktree and cd's into it.
  # plan/P064 and .aid-lifecycle/ are git-tracked and so ARE visible there;
  # .aid-o/work/plan-state/ is gitignored and would NOT be checked out into
  # a fresh worktree by Git — exactly why aid-plan-fsm.sh resolves its
  # runtime root via git's shared common-dir rather than the worktree's own
  # toplevel (see aid-plan-fsm.sh's own header comment on
  # _pfsm_resolve_project_root).
  mock_git_worktree
  local wt_dir; wt_dir="$(pwd)"

  # A manually created branch is rejected identically inside the worktree.
  git -C "$wt_dir" branch task/E-064-1_1/main main
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$wt_dir"
  [ "$status" -ne 0 ]

  # A legitimate epic-start still succeeds from inside the worktree.
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_2 --project-root "$wt_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "task/E-064-1_2/main" ]
}

@test "AC6: a crash between branch creation and manifest write converges on re-run without creating a second branch" {
  _pfsm_bootstrap_plan "P064"
  local plan_head; plan_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  local op_id; op_id="$(plan_op_key "epic-start" "P064" "-" "0" "E-064-1_1")"

  # Simulate the crash: intent + git_applied recorded, branch physically
  # created, but the manifest write (state_committed) never ran.
  plan_op_begin "P064" "$op_id" "epic-start" "E-064-1_1" ""
  git -C "$TEST_PROJECT_ROOT" branch task/E-064-1_1/main "$plan_head"
  plan_op_mark_git_applied "P064" "$op_id" "$plan_head"

  run plan_op_reconcile "P064" "$op_id"
  [ "$output" = "git_applied" ]

  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "task/E-064-1_1/main" ]

  # No second branch — exactly one ref by that name, at the SAME sha.
  local ref_count
  ref_count="$(git -C "$TEST_PROJECT_ROOT" for-each-ref --format='%(objectname)' refs/heads/task/E-064-1_1/main | wc -l | tr -d ' ')"
  [ "$ref_count" -eq 1 ]
  local final_sha; final_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse task/E-064-1_1/main)"
  [ "$final_sha" = "$plan_head" ]

  run plan_op_reconcile "P064" "$op_id"
  [ "$output" = "state_committed" ]

  local recorded_base
  recorded_base="$(plan_manifest_get "P064" '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .epic_base_commit')"
  [ "$recorded_base" = "$plan_head" ]
}

@test "AC7: plan-state --repair rebuilds a pruned workspace — merged EPICs restored merged_to_plan, unprovable EPICs marked unproven" {
  _pfsm_bootstrap_plan "P064"

  # Declare a second EPIC on the (git-tracked, prune-survivng) lifecycle
  # manifest, mirroring a PM adding a declared EPIC after plan-start.
  local lm="$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  yq -i '.declared_epics += [{"id": "E-064-1_2", "scope": "required"}]' "$lm"
  git -C "$TEST_PROJECT_ROOT" add "$lm"
  git -C "$TEST_PROJECT_ROOT" commit -qm "declare E-064-1_2"

  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Give E-064-1_1's task branch a real commit, then merge it into
  # plan/P064 for real — git's own default merge-commit message embeds the
  # branch name, which is the heuristic repair relies on.
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main
  echo work > "$TEST_PROJECT_ROOT/epic-1.txt"
  git -C "$TEST_PROJECT_ROOT" add epic-1.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "epic 1 work"
  git -C "$TEST_PROJECT_ROOT" checkout -q plan/P064
  git -C "$TEST_PROJECT_ROOT" merge --no-ff -q task/E-064-1_1/main -m "Merge branch 'task/E-064-1_1/main' into plan/P064"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  # E-064-1_2: a live, unmerged branch that was never actually run through
  # epic-start (no manifest entry ever existed for it) — its origin is not
  # provable from Git alone.
  git -C "$TEST_PROJECT_ROOT" branch task/E-064-1_2/main main

  # Prune: delete the entire runtime tree (simulates a fresh checkout).
  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"

  run bash "$PLAN_FSM_CLI" plan-state P064 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local mp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"
  [ -f "$mp" ]

  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .status' "$mp"
  [ "$output" = "merged_to_plan" ]
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .lineage' "$mp"
  [ "$output" = "proven" ]
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .epic_merge_commit' "$mp"
  [ "$output" != "null" ]

  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_2") | .epic_source_ref' "$mp"
  [ "$output" = "null" ]
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_2") | .lineage' "$mp"
  [ "$output" = "unproven" ]

  # The repaired manifest still passes the full invariant validator.
  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

@test "plan-state --repair refuses to run once the plan is past PLAN_SYNC" {
  _pfsm_bootstrap_plan "P064"
  plan_state_transition "P064" "OPEN" "EPIC_INTEGRATION"
  plan_state_transition "P064" "EPIC_INTEGRATION" "PLAN_SYNC"
  plan_state_transition "P064" "PLAN_SYNC" "PLAN_GATES"

  run bash "$PLAN_FSM_CLI" plan-state P064 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"past PLAN_SYNC"* ]]
}

@test "AC8: --attest-source-ref promotes ONE unproven entry to proven, records the attestation in the op log, and is the only way to do so" {
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Manually flip E-064-1_1 to unproven (as --repair would for an
  # unprovable EPIC) so there is something legitimate to attest.
  plan_manifest_update "P064" \
    '.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == "E-064-1_1" then (.lineage = "unproven" | .epic_source_ref = null) else . end]'

  run bash "$PLAN_FSM_CLI" plan-state P064 --attest-source-ref "plan/P064" --reason "manually verified from git log" --epic E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local mp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .lineage' "$mp"
  [ "$output" = "proven" ]
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .epic_source_ref' "$mp"
  [ "$output" = "plan/P064" ]

  # Recorded in the operation log.
  local ops="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/operations.jsonl"
  run bash -c "jq -s '[.[] | select(.command == \"plan-state-attest\")] | length' '$ops'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  # The ONLY way: re-attesting an already-proven entry is refused, never a
  # silent no-op.
  run bash "$PLAN_FSM_CLI" plan-state P064 --attest-source-ref "plan/P064" --reason "second attempt" --epic E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
}

@test "plan-start on a plan whose state is already CLOSED exits 1; a closed plan is not reopened" {
  _pfsm_bootstrap_plan "P064"
  local sp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-state.yaml"
  yq -i '.plan_state = "CLOSED"' "$sp"

  run bash "$PLAN_FSM_CLI" plan-start P064 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CLOSED"* ]]
}

@test "Error Handling: a dirty worktree at epic-start exits 1 before creating anything" {
  _pfsm_bootstrap_plan "P064"
  echo dirty >> "$TEST_PROJECT_ROOT/.gitkeep"

  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  local branch_sha
  branch_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse --verify --quiet refs/heads/task/E-064-1_1/main 2>/dev/null || true)"
  [ -z "$branch_sha" ]
}

@test "Error Handling: a detached HEAD at plan-start exits 1 and prints the resolved SHA" {
  _write_legacy_plan "P064"
  local head_sha; head_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q --detach "$head_sha"

  run bash "$PLAN_FSM_CLI" plan-start P064 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached HEAD"* ]]
  [[ "$output" == *"$head_sha"* ]]
}

# =============================================================================
# ─── aid-fsm.sh init — plan-branch lineage precondition (P064 E-064-1_2 Step 5)
# =============================================================================
# The EPIC-level FSM entry point (aid-fsm.sh, NOT aid-plan-fsm.sh) now refuses
# a `plan_branch` EPIC's `init` when its task branch does not match the
# runtime plan-boundary-manifest.json entry Step 4's epic-start recorded.
# `_pfsm_bootstrap_plan`/`_write_legacy_plan` (above) are reused verbatim —
# this section only adds the aid-fsm.sh `init` side of the same lineage
# story Step 4 already covers on the aid-plan-fsm.sh side.

@test "AC1: aid-fsm.sh init for a plan_branch EPIC whose actual base does not match the manifest exits non-zero and writes NO state file" {
  # Same construction as the aid-plan-fsm.sh AC4 "stale base" test above: an
  # earlier ancestor commit the branch gets force-reset onto after a
  # legitimate epic-start already recorded a LATER base.
  local root_sha; root_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  echo "advance main before plan-start" >> "$TEST_PROJECT_ROOT/.gitkeep"
  git -C "$TEST_PROJECT_ROOT" add .gitkeep
  git -C "$TEST_PROJECT_ROOT" commit -qm "advance to the plan base"

  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Force the task branch onto the EARLIER root commit — an ancestor of, but
  # not equal to, its recorded epic_base_commit.
  git -C "$TEST_PROJECT_ROOT" branch -f task/E-064-1_1/main "$root_sha"

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_branch_mismatch"* ]]
  [ ! -f "$state_file" ]
}

@test "AC2: aid-fsm.sh init for a plan in legacy_epic_release_mode succeeds unchanged" {
  _pfsm_bootstrap_plan "P064" "legacy_epic_release_mode"

  local args; args="$(build_default_init_args E-064-1_1)"
  run "$FSM" init $args
  [ "$status" -eq 0 ]
  local current_branch; current_branch="$(git -C "$TEST_PROJECT_ROOT" rev-parse --abbrev-ref HEAD)"
  [ "$current_branch" = "task/E-064-1_1/main" ]
}

@test "AC3: deleting the runtime plan-boundary-manifest.json does NOT downgrade to legacy — fails closed with plan_manifest_missing, mode still reads plan_branch from the lifecycle manifest" {
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  rm -f "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_manifest_missing"* ]]
  [[ "$output" == *"aid-plan-fsm.sh plan-state P064 --repair"* ]]
  [ ! -f "$state_file" ]

  # The MODE ITSELF survives the deletion — it lives in the separate,
  # git-tracked lifecycle manifest, never in the deleted runtime file.
  run aid_lifecycle_plan_mode "P064" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "plan_branch" ]
}

@test "AC3b: a manifest present but with no epic_runs entry for this EPIC is ALSO plan_manifest_missing (never epic-started under this plan)" {
  _pfsm_bootstrap_plan "P064"
  # No epic-start call — the runtime manifest exists (plan-start always
  # writes it) but carries no epic_runs[] entry for E-064-1_1.

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_manifest_missing"* ]]
  [ ! -f "$state_file" ]
}

@test "Regression: mktemp failure while reading the lifecycle mode fails CLOSED (plan_mode_unavailable), never silently falls back to legacy" {
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Shadow mktemp with a wrapper that always fails, simulating an
  # unwritable/exhausted TMPDIR — the exact scenario the mode-read's
  # throwaway-root construction depends on succeeding.
  local fakebin="$TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/mktemp" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$fakebin/mktemp"

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run env PATH="$fakebin:$PATH" "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unavailable"* ]]
  [ ! -f "$state_file" ]

  # Confirm this is NOT the same as a genuine legacy-mode no-op: the real
  # mode is still plan_branch (mktemp works normally here, outside the
  # shadowed PATH), so a real init call succeeds once mktemp works again.
  run "$FSM" init $args
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]
}

@test "AC4: the lineage check fires on a RESUMED run (state file already present), caught before the generic duplicate-init guard" {
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]

  # Edge Case: the EPIC gets abandoned after work started.
  run bash "$PLAN_MANIFEST_LIB" set-epic-status P064 E-064-1_1 abandoned
  [ "$status" -eq 0 ]

  # Re-invoking init with the SAME args (state file already exists) must be
  # caught by the NEW block's epic_abandoned reason, not by the pre-existing
  # generic "prevent duplicate init" guard further down.
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_abandoned"* ]]
  [[ "$output" != *"prevent duplicate init"* ]]
}

@test "AC4: the lineage check fires inside a linked worktree too (is_worktree() short-circuits PRE-FLIGHT branch enforcement, but not this block)" {
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  run bash "$PLAN_MANIFEST_LIB" set-epic-status P064 E-064-1_1 abandoned
  [ "$status" -eq 0 ]

  mock_git_worktree
  # build_default_init_args is not worktree-aware for non-"E-test" epic ids
  # (it always resolves state_file under $TEST_PROJECT_ROOT, the MAIN
  # worktree) — construct the state_file the same way aid-fsm.sh itself does
  # internally (relative to CWD, which mock_git_worktree already cd'd into
  # the linked worktree).
  local run_id="R-064-1_1-wt" state_file
  state_file="$(pwd)/.aid-o/work/evidence/E-064-1_1/${run_id}/fsm-state.yaml"
  mkdir -p "$(dirname "$state_file")"

  run "$FSM" init E-064-1_1 "$run_id" 3 manual main HEAD "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_abandoned"* ]]
  [ ! -f "$state_file" ]
}

@test "AC5: --force --reason overrides the new block and records the override in the timeline" {
  local root_sha; root_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  echo "advance main before plan-start" >> "$TEST_PROJECT_ROOT/.gitkeep"
  git -C "$TEST_PROJECT_ROOT" add .gitkeep
  git -C "$TEST_PROJECT_ROOT" commit -qm "advance to the plan base"

  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  git -C "$TEST_PROJECT_ROOT" branch -f task/E-064-1_1/main "$root_sha"

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args --force --reason "manually verified override for legitimate re-init after epic base reset"
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]

  local timeline="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-064-1_1/R-064-1_1-test/timeline.jsonl"
  [ -f "$timeline" ]
  run jq -s '[.[] | select(.event=="fsm_init_blocked" and .reason=="plan_branch_mismatch" and .overridden==true)] | length' "$timeline"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "Edge Case: an EPIC id that derives no plan id (ad-hoc EPIC) is a no-op, init succeeds normally" {
  local args; args="$(build_default_init_args E-test)"
  run "$FSM" init $args
  [ "$status" -eq 0 ]
}

@test "Error Handling: lib/aid-plan-manifest.sh cannot be sourced -> fails CLOSED for a declared plan_branch plan (plan_manifest_unavailable), never a silent legacy fallback" {
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # A copy of aid-fsm.sh + lib/ with aid-plan-manifest.sh removed — proves
  # the fail-closed path without mutating the real plugin install (which
  # every other test in this suite, and the whole repo's test run, shares).
  local dest="$TEST_TMPDIR/fsm-no-manifest-lib"
  mkdir -p "$dest/lib"
  cp "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" "$dest/aid-fsm.sh"
  local f
  for f in "$AID_PLUGIN_PATH/scripts/lib/"*.sh; do
    [[ "$(basename "$f")" == "aid-plan-manifest.sh" ]] && continue
    cp "$f" "$dest/lib/"
  done

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run bash "$dest/aid-fsm.sh" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_manifest_unavailable"* ]]
  [ ! -f "$state_file" ]
}

@test "Error Handling: lib/aid-plan-manifest.sh missing does NOT affect a legacy_epic_release_mode plan (stays a no-op)" {
  _pfsm_bootstrap_plan "P064" "legacy_epic_release_mode"

  local dest="$TEST_TMPDIR/fsm-no-manifest-lib-legacy"
  mkdir -p "$dest/lib"
  cp "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" "$dest/aid-fsm.sh"
  local f
  for f in "$AID_PLUGIN_PATH/scripts/lib/"*.sh; do
    [[ "$(basename "$f")" == "aid-plan-manifest.sh" ]] && continue
    cp "$f" "$dest/lib/"
  done

  local args; args="$(build_default_init_args E-064-1_1)"
  run bash "$dest/aid-fsm.sh" init $args
  [ "$status" -eq 0 ]
}
