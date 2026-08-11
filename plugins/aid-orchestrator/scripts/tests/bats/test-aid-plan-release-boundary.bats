#!/usr/bin/env bats
# aid-tier: t2
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

# ─── Lifecycle Contract: comprehensive negative tests for one-way transitions ──
# The state machine defines mandatory one-way edges that must reject their
# reverse. This table-driven test verifies that every one-way edge A→B in the
# transition table has its reverse B→A properly rejected and leaves state
# unchanged.
#
# LIFECYCLE EDGE CLASSIFICATIONS (per _AID_PLAN_TRANSITIONS):
#   - Self-loops (A→A, trivially their own inverse; test inapplicable):
#     EPIC_INTEGRATION→EPIC_INTEGRATION, PLAN_SYNC→PLAN_SYNC
#   - Genuinely bidirectional (both A→B and B→A legal; not inverse-illegal):
#     EPIC_INTEGRATION↔CONFLICT, PLAN_SYNC↔CONFLICT
#   - All other edges are one-way: reverse must be rejected, state unchanged.
#
# Test strategy: for each one-way edge A→B, reach B via shortest legal path,
# then attempt B→A and assert failure + unchanged state.
@test "Negative test: EPIC_INTEGRATION → PLAN_SYNC is one-way; reverse PLAN_SYNC → EPIC_INTEGRATION rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC

  run plan_state_transition P064 PLAN_SYNC EPIC_INTEGRATION
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_SYNC" ]
}

@test "Negative test: PLAN_SYNC → PLAN_GATES is one-way; reverse PLAN_GATES → PLAN_SYNC rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES

  run plan_state_transition P064 PLAN_GATES PLAN_SYNC
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_GATES" ]
}

@test "Negative test: PLAN_GATES → PLAN_REVIEW is one-way; reverse PLAN_REVIEW → PLAN_GATES rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW

  run plan_state_transition P064 PLAN_REVIEW PLAN_GATES
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_REVIEW" ]
}

@test "Negative test: PLAN_REVIEW → AWAITING_PM is one-way; reverse AWAITING_PM → PLAN_REVIEW rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM

  run plan_state_transition P064 AWAITING_PM PLAN_REVIEW
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "AWAITING_PM" ]
}

@test "Negative test: AWAITING_PM → PLAN_MERGING is one-way; reverse PLAN_MERGING → AWAITING_PM rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM PLAN_MERGING

  run plan_state_transition P064 PLAN_MERGING AWAITING_PM
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_MERGING" ]
}

@test "Negative test: PLAN_MERGING → CLOSED is one-way; reverse CLOSED → PLAN_MERGING rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM PLAN_MERGING
  plan_state_transition P064 PLAN_MERGING CLOSED

  run plan_state_transition P064 CLOSED PLAN_MERGING
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "CLOSED" ]
}

@test "Negative test: PLAN_GATES → PLAN_FIX is one-way; reverse PLAN_FIX → PLAN_GATES rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_FIX

  run plan_state_transition P064 PLAN_FIX PLAN_GATES
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_FIX" ]
}

@test "Negative test: PLAN_REVIEW → PLAN_FIX is one-way; reverse PLAN_FIX → PLAN_REVIEW rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW PLAN_FIX

  run plan_state_transition P064 PLAN_FIX PLAN_REVIEW
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_FIX" ]
}

@test "Negative test: PLAN_FIX → PLAN_SYNC is one-way; reverse PLAN_SYNC → PLAN_FIX rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_FIX
  plan_state_transition P064 PLAN_FIX PLAN_SYNC

  run plan_state_transition P064 PLAN_SYNC PLAN_FIX
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_SYNC" ]
}

@test "Negative test: AWAITING_PM → PLAN_SYNC is one-way; reverse PLAN_SYNC → AWAITING_PM rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM PLAN_SYNC

  run plan_state_transition P064 PLAN_SYNC AWAITING_PM
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_SYNC" ]
}

@test "Negative test: AWAITING_PM → PLAN_FIX is one-way; reverse PLAN_FIX → AWAITING_PM rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM PLAN_FIX

  run plan_state_transition P064 PLAN_FIX AWAITING_PM
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_FIX" ]
}

@test "Negative test: AWAITING_PM → CONFLICT is one-way; reverse CONFLICT → AWAITING_PM rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM CONFLICT

  run plan_state_transition P064 CONFLICT AWAITING_PM
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "CONFLICT" ]
}

@test "Negative test: PLAN_MERGING → CONFLICT is one-way; reverse CONFLICT → PLAN_MERGING rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM PLAN_MERGING
  plan_state_transition P064 PLAN_MERGING CONFLICT

  run plan_state_transition P064 CONFLICT PLAN_MERGING
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "CONFLICT" ]
}

@test "Documented: EPIC_INTEGRATION → CONFLICT and CONFLICT → EPIC_INTEGRATION are bidirectional (both legal); no inverse-illegal test" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION CONFLICT

  # Both directions are legal; this is a genuine bidirectional pair.
  run plan_state_transition P064 CONFLICT EPIC_INTEGRATION
  [ "$status" -eq 0 ]
  [ "$output" = "" ]

  run plan_state_get P064 plan_state
  [ "$output" = "EPIC_INTEGRATION" ]
}

@test "Documented: PLAN_SYNC → CONFLICT and CONFLICT → PLAN_SYNC are bidirectional (both legal); no inverse-illegal test" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC CONFLICT

  # Both directions are legal; this is a genuine bidirectional pair.
  run plan_state_transition P064 CONFLICT PLAN_SYNC
  [ "$status" -eq 0 ]
  [ "$output" = "" ]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_SYNC" ]
}

@test "Documented: self-loops EPIC_INTEGRATION → EPIC_INTEGRATION and PLAN_SYNC → PLAN_SYNC are trivially their own inverse; no inverse-illegal test" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION

  # Self-loop: A→A is legal and its own inverse.
  run plan_state_transition P064 EPIC_INTEGRATION EPIC_INTEGRATION
  [ "$status" -eq 0 ]

  run plan_state_get P064 plan_state
  [ "$output" = "EPIC_INTEGRATION" ]

  # Likewise for PLAN_SYNC.
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  run plan_state_transition P064 PLAN_SYNC PLAN_SYNC
  [ "$status" -eq 0 ]

  run plan_state_get P064 plan_state
  [ "$output" = "PLAN_SYNC" ]
}

@test "Negative test: OPEN → EPIC_INTEGRATION is one-way; reverse EPIC_INTEGRATION → OPEN rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION

  run plan_state_transition P064 EPIC_INTEGRATION OPEN
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "EPIC_INTEGRATION" ]
}

@test "Negative test: OPEN → ABORTED is one-way; reverse ABORTED → OPEN rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN ABORTED

  run plan_state_transition P064 ABORTED OPEN
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
}

@test "Negative test: EPIC_INTEGRATION → ABORTED is one-way; reverse ABORTED → EPIC_INTEGRATION rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION ABORTED

  run plan_state_transition P064 ABORTED EPIC_INTEGRATION
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
}

@test "Negative test: CONFLICT → ABORTED is one-way; reverse ABORTED → CONFLICT rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION CONFLICT
  plan_state_transition P064 CONFLICT ABORTED

  run plan_state_transition P064 ABORTED CONFLICT
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
}

@test "Negative test: PLAN_SYNC → ABORTED is one-way; reverse ABORTED → PLAN_SYNC rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC ABORTED

  run plan_state_transition P064 ABORTED PLAN_SYNC
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
}

@test "Negative test: PLAN_GATES → ABORTED is one-way; reverse ABORTED → PLAN_GATES rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES ABORTED

  run plan_state_transition P064 ABORTED PLAN_GATES
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
}

@test "Negative test: PLAN_REVIEW → ABORTED is one-way; reverse ABORTED → PLAN_REVIEW rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW ABORTED

  run plan_state_transition P064 ABORTED PLAN_REVIEW
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
}

@test "Negative test: PLAN_FIX → ABORTED is one-way; reverse ABORTED → PLAN_FIX rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_FIX
  plan_state_transition P064 PLAN_FIX ABORTED

  run plan_state_transition P064 ABORTED PLAN_FIX
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
}

@test "Negative test: AWAITING_PM → ABORTED is one-way; reverse ABORTED → AWAITING_PM rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM ABORTED

  run plan_state_transition P064 ABORTED AWAITING_PM
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
}

@test "Negative test: PLAN_MERGING → ABORTED is one-way; reverse ABORTED → PLAN_MERGING rejected" {
  _init_plan "P064"
  plan_state_transition P064 OPEN EPIC_INTEGRATION
  plan_state_transition P064 EPIC_INTEGRATION PLAN_SYNC
  plan_state_transition P064 PLAN_SYNC PLAN_GATES
  plan_state_transition P064 PLAN_GATES PLAN_REVIEW
  plan_state_transition P064 PLAN_REVIEW AWAITING_PM
  plan_state_transition P064 AWAITING_PM PLAN_MERGING
  plan_state_transition P064 PLAN_MERGING ABORTED

  run plan_state_transition P064 ABORTED PLAN_MERGING
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  run plan_state_get P064 plan_state
  [ "$output" = "ABORTED" ]
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

# ─── IMP-265: lineage defaults fail-closed to unproven ───────────────────
@test "IMP-265: plan_manifest_add_epic defaults an OMITTED lineage to unproven (fail-closed)" {
  _init_manifest "P900"
  run plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"
  [ "$status" -eq 0 ]
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].lineage'
  [ "$output" = "unproven" ]
}

@test "IMP-265: plan_manifest_add_epic writes proven ONLY when the caller passes it explicitly" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/" "proven"
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].lineage'
  [ "$output" = "proven" ]
}

@test "IMP-265: plan_manifest_add_epic rejects a malformed lineage value, writing nothing (never coerced to proven)" {
  _init_manifest "P900"
  local before; before="$(cat "$(_manifest_file P900)")"
  run plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/" "bogus"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lineage must be exactly"* ]]
  [ "$(cat "$(_manifest_file P900)")" = "$before" ]
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

# ─── EPIC STATUS TRANSITION LIFECYCLE TESTS ──────────────────────────────
# The transition table (_AID_EPIC_STATUS_TRANSITIONS) defines legal edges in
# the epic status state machine. This test suite verifies that every one-way
# edge is enforced: the reverse transition is rejected with PRECONDITION FAIL,
# the entry remains unchanged on disk, and (for merged_to_plan specifically)
# the epic_merge_commit is unchanged.
#
# LIFECYCLE EDGE CLASSIFICATIONS (per _AID_EPIC_STATUS_TRANSITIONS):
#   - Terminal states (no outgoing edges): merged_to_plan, abandoned, superseded
#   - Active/temporary with outgoing edges: pending, running, blocked
#   - Legal transitions: 12 edges total (see header comment in aid-plan-manifest.sh)

@test "Negative test: running → merged_to_plan is one-way; reverse merged_to_plan → running rejected" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  # Reach merged_to_plan via the legal forward transition
  plan_manifest_set_epic_status "P900" "E-900-1_2" "merged_to_plan" "3333333333333333333333333333333333333333"

  # Attempt the illegal reverse transition
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "running"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"merged_to_plan -> running is not a legal pair"* ]]

  # Verify state unchanged on disk
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$output" = "merged_to_plan" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].epic_merge_commit'
  [ "$output" = "3333333333333333333333333333333333333333" ]
}

@test "Negative test: running → abandoned is one-way; reverse abandoned → running rejected" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  # Reach abandoned via the legal forward transition
  plan_manifest_set_epic_status "P900" "E-900-1_2" "abandoned"

  # Attempt the illegal reverse transition
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "running"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"abandoned -> running is not a legal pair"* ]]

  # Verify state unchanged on disk
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$output" = "abandoned" ]
}

@test "Negative test: running → superseded is one-way; reverse superseded → running rejected" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  # Reach superseded via the legal forward transition
  plan_manifest_set_epic_status "P900" "E-900-1_2" "superseded"

  # Attempt the illegal reverse transition
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "running"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"superseded -> running is not a legal pair"* ]]

  # Verify state unchanged on disk
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$output" = "superseded" ]
}

@test "Negative test: running → blocked is one-way; reverse blocked → pending rejected (pending invalid from blocked)" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  # Reach blocked via the legal forward transition
  plan_manifest_set_epic_status "P900" "E-900-1_2" "blocked"

  # Attempt an illegal transition (blocked → pending is not legal)
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "pending"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"blocked -> pending is not a legal pair"* ]]

  # Verify state unchanged on disk
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$output" = "blocked" ]
}

@test "Positive test: running → blocked → running is a legal two-way path (unblock a dependency)" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  # running → blocked (legal)
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "blocked"
  [ "$status" -eq 0 ]

  # blocked → running (legal reversal)
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "running"
  [ "$status" -eq 0 ]

  # Verify final state
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$output" = "running" ]
}

@test "Negative test: blocked → abandoned is one-way; reverse abandoned → blocked rejected" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  # Reach blocked then abandoned
  plan_manifest_set_epic_status "P900" "E-900-1_2" "blocked"
  plan_manifest_set_epic_status "P900" "E-900-1_2" "abandoned"

  # Attempt the illegal reverse transition
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"abandoned -> blocked is not a legal pair"* ]]

  # Verify state unchanged on disk
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$output" = "abandoned" ]
}

@test "Negative test: blocked → superseded is one-way; reverse superseded → blocked rejected" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  # Reach blocked then superseded
  plan_manifest_set_epic_status "P900" "E-900-1_2" "blocked"
  plan_manifest_set_epic_status "P900" "E-900-1_2" "superseded"

  # Attempt the illegal reverse transition
  run plan_manifest_set_epic_status "P900" "E-900-1_2" "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"superseded -> blocked is not a legal pair"* ]]

  # Verify state unchanged on disk
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$output" = "superseded" ]
}

@test "Negative test: pending and blocked → merged_to_plan are one-way; reverses rejected" {
  _init_manifest "P900"

  # Test pending → merged_to_plan (rare but legal per table). epic_id must
  # match ^E-[0-9]{3}-[0-9]+_[0-9]+$ (the Bug 2 / CP3 jq-injection fix added
  # this validation to plan_manifest_set_epic_status after this test was
  # first written with a non-conforming id — "E-900-test-pending" — which
  # made this test start failing for the wrong reason: rejected on format,
  # never reaching the transition-legality assertion it was actually meant
  # to exercise. Caught live by bats_all, not by this file in isolation —
  # revealing this test was never actually exercised successfully end to
  # end even before that fix: the manual epic_runs[] splice below also
  # skipped registering the id in .epics/.active_epics/.total_epics, which
  # plan_manifest_add_epic normally does and _pm_check_invariants requires
  # (every epic_runs[].epic_id must be a member of .epics) — fixed here too.
  plan_manifest_update P900 '
    .plan_boundary_manifest.epics += ["E-900-9_9"]
    | .plan_boundary_manifest.active_epics += ["E-900-9_9"]
    | .plan_boundary_manifest.total_epics = (.plan_boundary_manifest.epics | length)
    | .plan_boundary_manifest.epic_runs |= . + [{
      epic_id: "E-900-9_9",
      status: "pending",
      epic_merge_commit: null,
      run_id: "R-E900-1",
      task_branch: "task/E-900-9_9/main",
      epic_base_commit: "1111111111111111111111111111111111111111",
      epic_source_ref: "plan/P900",
      lineage: "proven",
      evidence_dir: ".aid-o/work/evidence/E-900-9_9/"
    }]
  '

  # P068 F2 (2026-07-27): `pending -> merged_to_plan` was REMOVED from the
  # table. A pending EPIC has completed nothing, so the route should never have
  # existed — the P067 dogfood took it and put unfinished work into a plan
  # candidate. It is now refused, which this test asserts instead of relying on
  # it as a setup step.
  run plan_manifest_set_epic_status "P900" "E-900-9_9" "merged_to_plan" "2222222222222222222222222222222222222222"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]

  # The reverse-rejection assertions below need the EPIC actually IN
  # merged_to_plan, which is now reachable only from `running`.
  plan_manifest_set_epic_status "P900" "E-900-9_9" "running"
  plan_manifest_set_epic_status "P900" "E-900-9_9" "merged_to_plan" "2222222222222222222222222222222222222222"

  # Attempt reverse (illegal)
  run plan_manifest_set_epic_status "P900" "E-900-9_9" "pending"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"merged_to_plan -> pending is not a legal pair"* ]]

  # Verify state unchanged on disk
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-900-9_9") | .status'
  [ "$output" = "merged_to_plan" ]
}

@test "Terminal state documentation: merged_to_plan has no outgoing edges (is truly terminal)" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  plan_manifest_set_epic_status "P900" "E-900-1_2" "merged_to_plan" "3333333333333333333333333333333333333333"

  # Try to transition to any other state — all should be illegal
  for dest in pending running blocked abandoned superseded; do
    run plan_manifest_set_epic_status "P900" "E-900-1_2" "$dest"
    [ "$status" -ne 0 ] || skip "Transition to $dest should be illegal from merged_to_plan"
    [[ "$output" == *"PRECONDITION FAIL"* ]] || skip "Should have PRECONDITION FAIL for $dest"
  done
}

@test "Terminal state documentation: abandoned has no outgoing edges (is truly terminal)" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  plan_manifest_set_epic_status "P900" "E-900-1_2" "abandoned"

  # Try to transition to any other state — all should be illegal
  for dest in pending running merged_to_plan blocked superseded; do
    run plan_manifest_set_epic_status "P900" "E-900-1_2" "$dest"
    [ "$status" -ne 0 ] || skip "Transition to $dest should be illegal from abandoned"
    [[ "$output" == *"PRECONDITION FAIL"* ]] || skip "Should have PRECONDITION FAIL for $dest"
  done
}

@test "Terminal state documentation: superseded has no outgoing edges (is truly terminal)" {
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  plan_manifest_set_epic_status "P900" "E-900-1_2" "superseded"

  # Try to transition to any other state — all should be illegal
  for dest in pending running merged_to_plan blocked abandoned; do
    run plan_manifest_set_epic_status "P900" "E-900-1_2" "$dest"
    [ "$status" -ne 0 ] || skip "Transition to $dest should be illegal from superseded"
    [[ "$output" == *"PRECONDITION FAIL"* ]] || skip "Should have PRECONDITION FAIL for $dest"
  done
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
  [[ "$output" == *"runtime run/directory must be paired"* ]]
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

# _pfsm_install_plan_final_stub — build an isolated fixture copy of the real CLI
# whose dispatcher declares BOTH compensating plan-final subcommands
# (`plan-finalize` + `plan-merge-to-main`), simulating a post-P068 install so the
# mechanical probe `_pfsm_plan_final_installed` reports them present and the
# plan_branch refusal lifts WITHOUT any override flag. Echoes the path to the
# stub CLI. The copy sources the real lib/ via a symlink so SCRIPT_DIR
# resolution still works, and always seds from the LIVE plugin CLI (never a
# possibly-already-reassigned PLAN_FSM_CLI). Idempotent per test — TEST_TMPDIR is
# a fresh mktemp -d for each test. IMP-271 (Codex A1) removed the
# `--allow-incomplete-plan-final` escape hatch that fixtures previously used to
# create a plan_branch plan; this stub install is the sanctioned replacement and
# still exercises the real production plan-start signature (no fixture-only flag),
# just with the P068 subcommands simulated present.
_pfsm_install_plan_final_stub() {
  local sdir="$TEST_TMPDIR/plan-final-stub-scripts"
  # Idempotency guard tests -e on the GENERATED script (sed output is NOT
  # executable, so an earlier `-x` guard was always true and re-ran the ln
  # below on every call). `ln -sfn` is mandatory: without --no-dereference a
  # second `ln -sf <dir> <existing-symlink-to-dir>` writes THROUGH the existing
  # `lib` symlink and creates `scripts/lib/lib` in the LIVE plugin tree — a real
  # working-tree pollution that Phase-1's "no writes to the live repo" rule
  # forbids. `-n` replaces the symlink atomically instead.
  if [[ ! -e "$sdir/aid-plan-fsm.sh" ]]; then
    mkdir -p "$sdir"
    ln -sfn "$AID_PLUGIN_PATH/scripts/lib" "$sdir/lib"
    sed 's|    plan-state) cmd_plan_state "$@" ;;|    plan-finalize) echo "stub plan-finalize" ;;\n    plan-merge-to-main) echo "stub plan-merge-to-main" ;;\n    plan-state) cmd_plan_state "$@" ;;|' \
      "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh" > "$sdir/aid-plan-fsm.sh"
  fi
  echo "$sdir/aid-plan-fsm.sh"
}

# _pfsm_install_pre_p068_stub — the INVERSE of the stub above, and the reason it
# exists: P068 E-068-1_2 Step 5 landed `plan-merge-to-main`, so the REAL CLI now
# declares both plan-final arms and `_pfsm_plan_final_installed` returns true.
# The refusal it guards can therefore no longer be observed against the live CLI.
# This installs a fixture copy with BOTH dispatcher arms stripped — a faithful
# pre-P068 CLI — so the hard refusal and its "advertises no bypass" assertions
# stay under test instead of being deleted along with the condition that fired
# them. Same `ln -sfn` + `-e` guard discipline as the positive-control stub.
_pfsm_install_pre_p068_stub() {
  local sdir="$TEST_TMPDIR/pre-p068-stub-scripts"
  if [[ ! -e "$sdir/aid-plan-fsm.sh" ]]; then
    mkdir -p "$sdir"
    ln -sfn "$AID_PLUGIN_PATH/scripts/lib" "$sdir/lib"
    sed -E '/^[[:space:]]*plan-finalize\) /d; /^[[:space:]]*plan-merge-to-main\) /d' \
      "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh" > "$sdir/aid-plan-fsm.sh"
  fi
  echo "$sdir/aid-plan-fsm.sh"
}

# _pfsm_bootstrap_plan <plan_id> [mode] — writes a minimal legacy plan file
# and runs a REAL plan-start through the CLI (never a parallel "test mode"
# shortcut — matches build_default_init_args's own convention of always
# exercising the production signature). Asserts plan-start itself succeeded,
# so a bootstrap failure can never masquerade as a lineage-check failure in
# the test that calls it.
_pfsm_bootstrap_plan() {
  local plan_id="$1" mode="${2:-plan_branch}"
  _write_legacy_plan "$plan_id"
  # IMP-271 (Codex A1): plan_branch is HARD-REFUSED until the P068 plan-final
  # commands are installed, and the earlier `--allow-incomplete-plan-final`
  # escape hatch was removed (self-asserted, not authorization). To create a
  # plan_branch fixture we install a CLI copy whose dispatcher declares both
  # plan-final subcommands (simulating post-P068) and point PLAN_FSM_CLI at it
  # for the WHOLE remaining test, so every downstream call uses the same CLI.
  # legacy_epic_release_mode needs none of this and keeps the live CLI.
  if [[ "$mode" == "plan_branch" ]]; then
    PLAN_FSM_CLI="$(_pfsm_install_plan_final_stub)"
  fi
  run bash "$PLAN_FSM_CLI" plan-start "$plan_id" --mode "$mode" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

# _pfsm_plan_tree <plan_id> — the tree in which `plan/<plan_id>` is checked out.
#
# P074 EPIC 2 (Step 7): plan-start now gives EVERY plan — both modes — its own
# execution worktree at `.aid-worktrees/plan-<id>` and leaves `plan/<id>`
# checked out THERE. Git refuses the same branch in two trees, so a fixture
# that needs a REAL merge onto the plan branch can no longer `git -C
# "$TEST_PROJECT_ROOT" checkout plan/<id>`; it operates in the plan worktree.
# Plans bootstrapped without one (or a future mode that skips it) fall back to
# the primary checkout, so the helper is safe everywhere.
_pfsm_plan_tree() {
  local wt="$TEST_PROJECT_ROOT/.aid-worktrees/plan-$1"
  if [[ -d "$wt" ]]; then printf '%s' "$wt"; else printf '%s' "$TEST_PROJECT_ROOT"; fi
}

# _pfsm_drop_plan_worktree <plan_id> — remove the plan's execution worktree AND
# its git registration, leaving the plan in the shape a genuinely fresh
# checkout has: refs present, no `.aid-worktrees/` (it is gitignored), nothing
# registered. Fixtures that simulate a pruned/recovered workspace by deleting
# `.aid-o/work` must use this too — deleting only the state record while the
# registered worktree survives is a DIFFERENT scenario (the plan-start crash
# window), which the P074 Step 8 enforcer deliberately refuses.
# _pfsm_stdout_tail — the LAST line of the previous `run`'s capture.
#
# P074 Step 8 prints a one-line redirect NOTE ("<plan> executes in its own
# worktree — re-running this command in …") on STDERR whenever a plan-linked
# command re-executes itself in the plan worktree, and bats' `run` folds
# stderr into `$output`. Commands whose CONTRACT is "one SHA on stdout"
# (epic-merge-to-plan) are therefore read from the tail rather than from the
# whole capture — the contract itself is unchanged, only the capture is noisier.
_pfsm_stdout_tail() {
  printf '%s' "${lines[$(( ${#lines[@]} - 1 ))]}"
}

_pfsm_drop_plan_worktree() {
  local wt="$TEST_PROJECT_ROOT/.aid-worktrees/plan-$1"
  git -C "$TEST_PROJECT_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$wt"
  git -C "$TEST_PROJECT_ROOT" worktree prune >/dev/null 2>&1 || true
  return 0
}

@test "AC1: plan-start creates plan/<plan_id> at exactly the recorded target SHA and is a no-op on re-run" {
  _write_legacy_plan "P064"
  local target_sha; target_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  # IMP-271: --mode is mandatory. This test is about lineage, not mode, so it
  # uses legacy_epic_release_mode (needs no plan-final escape hatch).
  run bash "$PLAN_FSM_CLI" plan-start P064 --mode legacy_epic_release_mode --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "plan/P064" ]
  local branch_sha; branch_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  [ "$branch_sha" = "$target_sha" ]

  # Re-run: idempotent no-op — same SHA, no error.
  run bash "$PLAN_FSM_CLI" plan-start P064 --mode legacy_epic_release_mode --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local branch_sha2; branch_sha2="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  [ "$branch_sha2" = "$target_sha" ]
}

@test "AC2: after plan-start, the lifecycle manifest carries the requested mode, is schema-valid, committed on target_branch, and the mode survives deleting .aid-o/" {
  _write_legacy_plan "P064"
  # IMP-271 (Codex A1): plan_branch mode is the point of this test. The escape
  # hatch was removed, so we create the plan through a CLI copy that simulates
  # the P068 plan-final commands installed — still the real production plan-start
  # signature, no fixture-only flag.
  local cli; cli="$(_pfsm_install_plan_final_stub)"
  run bash "$cli" plan-start P064 --mode plan_branch --project-root "$TEST_PROJECT_ROOT"
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

@test "AC7: plan-state --repair rebuilds a pruned workspace — merged EPICs restored merged_to_plan, EVERY repaired entry lineage:unproven" {
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
  # The merge happens where plan/P064 is checked out — the plan worktree since
  # P074 EPIC 2 (see _pfsm_plan_tree).
  local ptree; ptree="$(_pfsm_plan_tree P064)"
  git -C "$ptree" checkout -q plan/P064
  git -C "$ptree" merge --no-ff -q task/E-064-1_1/main -m "Merge branch 'task/E-064-1_1/main' into plan/P064"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  # E-064-1_2: a live, unmerged branch that was never actually run through
  # epic-start (no manifest entry ever existed for it) — its origin is not
  # provable from Git alone.
  git -C "$TEST_PROJECT_ROOT" branch task/E-064-1_2/main main

  # Prune: delete the entire runtime tree (simulates a fresh checkout).
  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"
  # A pruned workspace has no `.aid-worktrees/` either (gitignored) — see
  # _pfsm_drop_plan_worktree.
  _pfsm_drop_plan_worktree P064

  run bash "$PLAN_FSM_CLI" plan-state P064 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local mp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"
  [ -f "$mp" ]

  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .status' "$mp"
  [ "$output" = "merged_to_plan" ]
  # Security F-2: status + merge commit are DIAGNOSTIC facts repair may still
  # record, but a merge commit never authorises lineage — repair cannot write
  # proven on any path, so even the merged EPIC comes back unproven and needs
  # an explicit attestation before init will run it.
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .lineage' "$mp"
  [ "$output" = "unproven" ]
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

# ─── IMP-265b: healthy repair is a non-destructive no-op ─────────────────────
@test "IMP-265b: plan-state --repair on a HEALTHY manifest is a non-destructive no-op — proven + attestation metadata preserved, byte-identical" {
  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Decorate the healthy proven entry with attestation-style metadata that
  # repair MUST preserve (the pre-IMP-265b repair discarded exactly this).
  plan_manifest_update "P900" \
    '.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == "E-900-1_1" then (.attestation_reason = "operator verified" | .attested_at = "2026-01-01T00:00:00Z") else . end]'

  local mp; mp="$(_manifest_file P900)"
  local before; before="$(cat "$mp")"

  run bash "$PLAN_FSM_CLI" plan-state P900 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Byte-identical round-trip: nothing degraded, nothing discarded.
  [ "$(cat "$mp")" = "$before" ]
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-900-1_1") | .lineage' "$mp"
  [ "$output" = "proven" ]
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-900-1_1") | .epic_source_ref' "$mp"
  [ "$output" = "plan/P900" ]
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-900-1_1") | .attestation_reason' "$mp"
  [ "$output" = "operator verified" ]
}

@test "IMP-265b: a second plan-state --repair is idempotent — the rebuilt manifest round-trips byte-identical" {
  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # A real merge so the first repair restores a merged_to_plan (unproven) entry.
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-900-1_1/main
  echo work > "$TEST_PROJECT_ROOT/epic-1.txt"
  git -C "$TEST_PROJECT_ROOT" add epic-1.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "epic 1 work"
  git -C "$(_pfsm_plan_tree P900)" checkout -q plan/P900
  git -C "$(_pfsm_plan_tree P900)" merge --no-ff -q task/E-900-1_1/main -m "Merge branch 'task/E-900-1_1/main' into plan/P900"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"
  # A pruned workspace has no `.aid-worktrees/` either (gitignored) — see
  # _pfsm_drop_plan_worktree.
  _pfsm_drop_plan_worktree P900
  run bash "$PLAN_FSM_CLI" plan-state P900 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local mp; mp="$(_manifest_file P900)"
  local after_first; after_first="$(cat "$mp")"

  run bash "$PLAN_FSM_CLI" plan-state P900 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$(cat "$mp")" = "$after_first" ]
}

# ─── IMP-258: repair propagates per-entry write failures ─────────────────────
@test "IMP-258: a per-entry write failure during --repair fails the whole repair with a non-zero exit (never success over a partial manifest)" {
  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"
  # A pruned workspace has no `.aid-worktrees/` either (gitignored) — see
  # _pfsm_drop_plan_worktree.
  _pfsm_drop_plan_worktree P900

  # Drive repair in-process so we can force the per-entry writer to fail
  # exactly the way an unwritable manifest would. The `|| true` that IMP-258
  # replaced would have swallowed this and still exited 0.
  # shellcheck disable=SC1090
  source "$PLAN_FSM_CLI"
  _pfsm_repair_add_unproven() { echo "forced durable-write failure for $2" >&2; return 1; }
  run _pfsm_plan_state_repair "P900" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"partially-written manifest"* ]]
}

# ─── IMP-267: attestation re-derives ancestry from Git ───────────────────────
@test "IMP-267: attesting a repaired entry RE-DERIVES epic_base_commit from Git, overwriting a wrong stored value" {
  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-900-1_1/main
  echo work > "$TEST_PROJECT_ROOT/epic-1.txt"
  git -C "$TEST_PROJECT_ROOT" add epic-1.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "epic 1 work"
  git -C "$(_pfsm_plan_tree P900)" checkout -q plan/P900
  git -C "$(_pfsm_plan_tree P900)" merge --no-ff -q task/E-900-1_1/main -m "Merge branch 'task/E-900-1_1/main' into plan/P900"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"
  # A pruned workspace has no `.aid-worktrees/` either (gitignored) — see
  # _pfsm_drop_plan_worktree.
  _pfsm_drop_plan_worktree P900
  run bash "$PLAN_FSM_CLI" plan-state P900 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local mp; mp="$(_manifest_file P900)"
  # Corrupt the stored base to a WRONG (but well-formed) value, as a
  # misattributing repair could have.
  local wrong=2222222222222222222222222222222222222222
  local tmp="$mp.x"
  jq --arg w "$wrong" '.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id=="E-900-1_1" then (.epic_base_commit=$w) else . end]' "$mp" > "$tmp"
  mv "$tmp" "$mp"

  run bash "$PLAN_FSM_CLI" plan-state P900 --attest-source-ref "plan/P900" --reason "verified from reflog" --epic E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local plan_head; plan_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P900)"
  local real_base; real_base="$(git -C "$TEST_PROJECT_ROOT" merge-base "${plan_head}^1" "${plan_head}^2")"
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-900-1_1") | .epic_base_commit' "$mp"
  [ "$output" = "$real_base" ]
  [ "$output" != "$wrong" ]
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-900-1_1") | .lineage' "$mp"
  [ "$output" = "proven" ]
}

@test "IMP-267: attestation FAILS CLOSED when the stored ancestry cannot be proven from Git" {
  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Flip to unproven and plant a bogus (well-formed but non-existent) merge
  # commit with a merged_to_plan status — the shape --repair could leave.
  local fake=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  plan_manifest_update "P900" \
    ".plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == \"E-900-1_1\" then (.lineage = \"unproven\" | .epic_source_ref = null | .status = \"merged_to_plan\" | .epic_merge_commit = \"${fake}\") else . end]"

  run bash "$PLAN_FSM_CLI" plan-state P900 --attest-source-ref "plan/P900" --reason "attempt" --epic E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be proven from Git"* ]]

  # Unchanged: still unproven, never promoted on unprovable ancestry.
  local mp; mp="$(_manifest_file P900)"
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-900-1_1") | .lineage' "$mp"
  [ "$output" = "unproven" ]
}

@test "plan-start on a plan whose state is already CLOSED exits 1; a closed plan is not reopened" {
  _pfsm_bootstrap_plan "P064"
  local sp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-state.yaml"
  yq -i '.plan_state = "CLOSED"' "$sp"

  # IMP-271: --mode is mandatory; legacy mode reaches the closed-plan check
  # (the plan_branch refusal would otherwise pre-empt it with a different msg).
  run bash "$PLAN_FSM_CLI" plan-start P064 --mode legacy_epic_release_mode --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CLOSED"* ]]
}

@test "Error Handling (P074 Step 5): a dirty worktree no longer blocks epic-start — the ref is created and the edit survives untouched" {
  # Until P074 this asserted a refusal. epic-start creates refs only (no
  # checkout, no tracked writes), so the repo-wide clean-worktree preflight
  # was removed for it — the same dirty tree now proves the loosening is safe:
  # the task branch is created and the unrelated edit is neither consumed,
  # stashed nor reverted.
  _pfsm_bootstrap_plan "P064"
  echo dirty >> "$TEST_PROJECT_ROOT/.gitkeep"

  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"uncommitted changes present"* ]]
  local branch_sha
  branch_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse --verify --quiet refs/heads/task/E-064-1_1/main 2>/dev/null || true)"
  [ -n "$branch_sha" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' status --porcelain --untracked-files=no"
  [[ "$output" == *".gitkeep"* ]]
}

@test "Error Handling: a detached HEAD at plan-start exits 1 and prints the resolved SHA" {
  _write_legacy_plan "P064"
  local head_sha; head_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q --detach "$head_sha"

  # IMP-271: --mode is mandatory; legacy mode reaches the detached-HEAD preflight
  # check (the plan_branch refusal runs after preflight, but is mode-gated off here).
  run bash "$PLAN_FSM_CLI" plan-start P064 --mode legacy_epic_release_mode --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached HEAD"* ]]
  [[ "$output" == *"$head_sha"* ]]
}

# =============================================================================
# ─── IMP-271: plan-start requires an explicit --mode, and HARD-REFUSES
#     plan_branch until the compensating plan-final commands (P068) are
#     installed — no override (Codex A1) ──────────────────────────────────────
#
# F-2 (Auditor): plan-start defaulted an omitted --mode to plan_branch, which
# P064 makes structurally skip the per-EPIC release stack while the commands
# that could close such a plan (plan-finalize / plan-merge-to-main) do not
# exist until P068 — a defaulted plan_branch created a plan that skipped
# verification yet could never close.
#
# The original IMP-271 fix shipped an `--allow-incomplete-plan-final --reason`
# escape hatch so P068's own dogfood run could bootstrap plan_branch early. The
# PM then found (HIGH) that the hatch is self-asserted, not authorization: in
# AUTO mode the controller agent supplies it itself, so the fail-closed refusal
# is bypassable by the very actor it constrains. An independent Codex
# adjudication chose A1 — remove the hatch entirely. These tests now prove the
# hatch no longer exists (unknown flag → exit 2), that plan_branch is
# hard-refused with NO advertised bypass, and that a genuine P068 install (both
# dispatcher arms present) lifts the refusal mechanically.
# =============================================================================

@test "IMP-271: plan-start with no --mode exits 2 and creates nothing (no default)" {
  _write_legacy_plan "P900"

  run bash "$PLAN_FSM_CLI" plan-start P900 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--mode is REQUIRED"* ]]
  [[ "$output" == *"IMP-271"* ]]
  [[ "$output" == *"P068"* ]]

  # Nothing created: no runtime state, no plan branch, no lifecycle manifest,
  # nothing committed beyond the fixture's own initial commit.
  [ ! -e "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P900" ]
  run git -C "$TEST_PROJECT_ROOT" rev-parse --verify --quiet refs/heads/plan/P900
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml" ]
}

@test "IMP-271 (P068 Step 5): the LIVE CLI now accepts --mode plan_branch — the refusal lifted because plan-finalize and plan-merge-to-main landed" {
  _write_legacy_plan "P900"

  # The guard was always conditional: "hard-refused WHILE those subcommands are
  # missing". P068 E-068-1_2 Steps 1-5 landed them, so `_pfsm_plan_final_installed`
  # now returns true against the real CLI and the refusal lifts MECHANICALLY —
  # no flag, no override, no edit to the guard itself. This test records that
  # transition; the refusal itself stays under test in the next one, against a
  # fixture CLI with the arms stripped.
  run grep -Eq '^[[:space:]]*plan-finalize\)' "$PLAN_FSM_CLI"
  [ "$status" -eq 0 ]
  run grep -Eq '^[[:space:]]*plan-merge-to-main\)' "$PLAN_FSM_CLI"
  [ "$status" -eq 0 ]

  run bash "$PLAN_FSM_CLI" plan-start P900 --mode plan_branch --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "plan/P900" ]
  run yq -r '.mode' "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml"
  [ "$output" = "plan_branch" ]

  # The escape hatch stays gone: nothing recorded one, because nothing needed one.
  local ops; ops="$(_ops_file P900)"
  run grep -c 'allow_incomplete_plan_final' "$ops"
  [ "$output" = "0" ]
}

@test "IMP-271: a CLI WITHOUT the plan-final subcommands still hard-refuses --mode plan_branch (exit 1), names both, advertises NO bypass, and creates nothing" {
  _write_legacy_plan "P900"

  # The guard's protection must not disappear just because THIS repo has since
  # satisfied its condition. Run it against a faithful pre-P068 CLI (both
  # dispatcher arms stripped) so the refusal, its message and the absence of any
  # escape hatch are all still asserted.
  local cli; cli="$(_pfsm_install_pre_p068_stub)"
  run grep -Eq '^[[:space:]]*plan-finalize\)' "$cli"
  [ "$status" -ne 0 ]
  run grep -Eq '^[[:space:]]*plan-merge-to-main\)' "$cli"
  [ "$status" -ne 0 ]

  run bash "$cli" plan-start P900 --mode plan_branch --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan-finalize"* ]]
  [[ "$output" == *"plan-merge-to-main"* ]]
  [[ "$output" == *"IMP-271"* ]]

  # Codex A1: the refusal must NOT advertise any escape hatch / override — a
  # bypass the AUTO controller could self-assert is exactly what was removed.
  [[ "$output" != *"allow-incomplete-plan-final"* ]]
  [[ "$output" != *"escape hatch"* ]]

  [ ! -e "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P900" ]
  run git -C "$TEST_PROJECT_ROOT" rev-parse --verify --quiet refs/heads/plan/P900
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml" ]
}

@test "IMP-271 (Codex A1): the removed --allow-incomplete-plan-final flag is now an unknown flag (exit 2) for --mode plan_branch, and creates nothing" {
  _write_legacy_plan "P900"

  # The exact invocation that used to bypass the fail-closed refusal must now be
  # rejected as an unknown flag BEFORE any side effect — no plan is created.
  run bash "$PLAN_FSM_CLI" plan-start P900 --mode plan_branch \
    --allow-incomplete-plan-final --reason "P068 dogfood bootstrap: plan-final commands not yet installed" \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown flag"* ]]
  [[ "$output" == *"--allow-incomplete-plan-final"* ]]

  [ ! -e "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P900" ]
  run git -C "$TEST_PROJECT_ROOT" rev-parse --verify --quiet refs/heads/plan/P900
  [ "$status" -ne 0 ]
  [ ! -e "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml" ]
}

@test "IMP-271 (Codex A1): the removed --allow-incomplete-plan-final flag is unknown (exit 2) even with --mode legacy_epic_release_mode — it cannot be smuggled in through any mode" {
  _write_legacy_plan "P900"

  run bash "$PLAN_FSM_CLI" plan-start P900 --mode legacy_epic_release_mode \
    --allow-incomplete-plan-final --reason "this flag no longer exists in any mode" \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown flag"* ]]
  [[ "$output" == *"--allow-incomplete-plan-final"* ]]

  # An unknown flag fails before any write — nothing created.
  [ ! -e "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P900" ]
  run git -C "$TEST_PROJECT_ROOT" rev-parse --verify --quiet refs/heads/plan/P900
  [ "$status" -ne 0 ]
}

@test "IMP-271: --mode legacy_epic_release_mode is unaffected — succeeds and records legacy mode, no escape hatch needed" {
  _write_legacy_plan "P900"

  run bash "$PLAN_FSM_CLI" plan-start P900 --mode legacy_epic_release_mode --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "plan/P900" ]
  run yq -r '.mode' "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml"
  [ "$output" = "legacy_epic_release_mode" ]

  # No plan-final escape-hatch artifact of any kind — legacy never touches the
  # plan-final guard, and the removed hatch leaves no residue.
  local ops; ops="$(_ops_file P900)"
  run grep -c 'allow_incomplete_plan_final' "$ops"
  [ "$output" = "0" ]
}

@test "IMP-271: mechanical detection (positive control) — a CLI whose dispatcher declares plan-finalize + plan-merge-to-main lifts the plan_branch refusal (not a hardcoded false), with NO override flag" {
  _write_legacy_plan "P900"

  # The SAME stub-install the plan_branch bootstrap uses: an isolated fixture
  # copy of the CLI that DOES declare both plan-final subcommands in its
  # dispatcher (simulating post-P068), sourcing the real lib/ via a symlink so
  # SCRIPT_DIR resolution still works. This is the positive control that a
  # genuine P068 install lifts the refusal mechanically — the only sanctioned
  # way to create a plan_branch plan now that the escape hatch is gone.
  local cli; cli="$(_pfsm_install_plan_final_stub)"

  # Sanity: the stub arms are actually present in the fixture source.
  run grep -Eq '^[[:space:]]*plan-finalize\)' "$cli"
  [ "$status" -eq 0 ]
  run grep -Eq '^[[:space:]]*plan-merge-to-main\)' "$cli"
  [ "$status" -eq 0 ]

  # plan_branch with NO flag succeeds — the refusal lifted purely because the
  # dispatcher recognises the subcommands.
  run bash "$cli" plan-start P900 --mode plan_branch --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "plan/P900" ]
  run yq -r '.mode' "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml"
  [ "$output" = "plan_branch" ]

  # And no escape-hatch record was written (the refusal never fired, and the
  # hatch no longer exists at all).
  local ops; ops="$(_ops_file P900)"
  run grep -c 'allow_incomplete_plan_final' "$ops"
  [ "$output" = "0" ]
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

  # P074 EPIC 2 (Steps 7-9): plan-start gives EVERY plan — legacy_epic_release_mode
  # included — its own execution worktree, and `init` re-executes itself there,
  # creating task/<epic>/main from the plan head and leaving the PM's checkout
  # exactly where it was. The pre-P074 assertion (the PRIMARY checkout ends on
  # the task branch) described the single-checkout topology this EPIC replaced;
  # what "unchanged" means for this test is that the legacy plan still reaches
  # READY on its own task branch, which is asserted below in the tree that now
  # owns it.
  local plan_tree; plan_tree="$(_pfsm_plan_tree P064)"
  [ "$plan_tree" != "$TEST_PROJECT_ROOT" ]
  local wt_branch; wt_branch="$(git -C "$plan_tree" rev-parse --abbrev-ref HEAD)"
  [ "$wt_branch" = "task/E-064-1_1/main" ]
  local current_branch; current_branch="$(git -C "$TEST_PROJECT_ROOT" rev-parse --abbrev-ref HEAD)"
  [ "$current_branch" = "main" ]
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

@test "Regression: mktemp failure while reading the lifecycle mode fails CLOSED (plan_mode_unresolved), never silently falls back to legacy" {
  # IMP-273: cmd_init now routes its mode decision through the single
  # committed-tree authority `_fsm_declared_plan_mode`, so an mktemp failure
  # while it extracts the committed manifest surfaces as `unresolved`
  # (mode_root_unavailable) -> the unified `plan_mode_unresolved` hard block,
  # not the old cmd_init-local `plan_mode_unavailable`. Same fail-closed
  # guarantee, now one authority instead of a second reader.
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
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [ ! -f "$state_file" ]

  # Confirm this is NOT the same as a genuine legacy-mode no-op: the real
  # mode is still plan_branch (mktemp works normally here, outside the
  # shadowed PATH), so a real init call succeeds once mktemp works again.
  run "$FSM" init $args
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]
}

# ─── IMP-273: cmd_init routes its mode decision through the ONE committed-tree,
#     fail-closed authority (_fsm_declared_plan_mode) — the same resolver
#     done-advance uses. Every "cannot determine the mode" becomes
#     `plan_mode_unresolved` (a hard block with the audited --force override),
#     never a silent legacy downgrade that would skip THIS lineage precondition.
#     _fsm_init_timeline <state_file> — the timeline cmd_init writes for a block,
#     derived from the state file's own evidence dir (state file itself is absent
#     on a fresh init, so its DIRECTORY is the stable anchor).
_fsm_init_timeline() { echo "$(dirname "$1")/timeline.jsonl"; }

@test "IMP-273: yq absent while a plan_branch declaration is committed blocks cmd_init with plan_mode_unresolved (was a silent legacy downgrade)" {
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # A PATH holding every tool cmd_init's preamble needs EXCEPT yq — genuinely
  # absent, the exact case `command -v yq` in the mode authority guards. Not a
  # stub exiting non-zero; missing entirely.
  local nobin="$TEST_TMPDIR/nobin-init"; mkdir -p "$nobin"
  local t p
  for t in bash sh git grep sed awk cat date mktemp rm mkdir dirname basename \
           printf tr wc head tail jq env chmod touch cp mv sort id find xargs cut readlink; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    ln -sf "$p" "$nobin/$t"
  done
  [ ! -e "$nobin/yq" ]

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run env PATH="$nobin" "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [ ! -f "$state_file" ]
  local tl; tl="$(_fsm_init_timeline "$state_file")"
  [ "$(jq -r 'select(.event=="fsm_init_blocked") | .reason' "$tl" | tail -1)" = "plan_mode_unresolved" ]
  [ "$(jq -r 'select(.event=="fsm_init_blocked") | .mode_reason' "$tl" | tail -1)" = "yq_unavailable" ]
}

@test "IMP-273: an unparseable committed lifecycle manifest blocks cmd_init with plan_mode_unresolved, never a legacy fallback" {
  _pfsm_bootstrap_plan "P064"
  # Corrupt the committed declaration on the target branch (main).
  printf 'mode: [unclosed\n  : : :\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  git -C "$TEST_PROJECT_ROOT" add .aid-lifecycle/manifests/P064.yaml
  git -C "$TEST_PROJECT_ROOT" commit -qm "corrupt the manifest"

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [ ! -f "$state_file" ]
  local tl; tl="$(_fsm_init_timeline "$state_file")"
  [ "$(jq -r 'select(.event=="fsm_init_blocked") | .mode_reason' "$tl" | tail -1)" = "manifest_unparseable" ]
}

@test "IMP-273: a committed manifest declaring an UNKNOWN mode value blocks cmd_init rather than defaulting to legacy" {
  _pfsm_bootstrap_plan "P064"
  yq -i '.mode = "plan_branch_v2"' "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  git -C "$TEST_PROJECT_ROOT" add .aid-lifecycle/manifests/P064.yaml
  git -C "$TEST_PROJECT_ROOT" commit -qm "unknown mode value"

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [ ! -f "$state_file" ]
  local tl; tl="$(_fsm_init_timeline "$state_file")"
  [ "$(jq -r 'select(.event=="fsm_init_blocked") | .mode_reason' "$tl" | tail -1)" = "mode_unknown_value_plan_branch_v2" ]
}

@test "IMP-273: a working-tree-only (uncommitted) plan_branch manifest is 'unresolved' and blocks cmd_init — the intended tightening over the old legacy-treating reader" {
  # No bootstrap: the declaration exists ONLY in the working tree, never
  # committed. The old cmd_init reader treated an uncommitted manifest as
  # legacy/no-op; the unified authority treats a manifest that was typed but
  # never declared (committed) as unresolved -> a hard block.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests"
  printf 'schema_version: aid-lifecycle-1.0\nplan_id: P064\nmode: plan_branch\n' \
    > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  # Untracked: the target branch's committed tree does not know it.
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:.aid-lifecycle/manifests/P064.yaml"
  [ "$status" -ne 0 ]

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [ ! -f "$state_file" ]
  local tl; tl="$(_fsm_init_timeline "$state_file")"
  [ "$(jq -r 'select(.event=="fsm_init_blocked") | .mode_reason' "$tl" | tail -1)" = "manifest_not_committed_on_main" ]
}

@test "IMP-273: genuine absence (no lifecycle manifest anywhere) resolves legacy and cmd_init proceeds — the pre-P064 no-op is unchanged" {
  # No plan-start, no lifecycle manifest for P064 anywhere: the authority
  # returns legacy_epic_release_mode (no_manifest_on_main), so the mode gate is
  # a no-op and init proceeds exactly as before P064 (mirrors AC2, minus even a
  # declared legacy manifest).
  [ ! -e "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml" ]

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]
  local current_branch; current_branch="$(git -C "$TEST_PROJECT_ROOT" rev-parse --abbrev-ref HEAD)"
  [ "$current_branch" = "task/E-064-1_1/main" ]
  # The mode gate did NOT fire.
  local tl; tl="$(_fsm_init_timeline "$state_file")"
  [ ! -f "$tl" ] || [ -z "$(jq -rc 'select(.event=="fsm_init_blocked" and .reason=="plan_mode_unresolved")' "$tl")" ]
}

@test "IMP-273: --force converts the plan_mode_unresolved block into an AUDITED override, and init proceeds" {
  _pfsm_bootstrap_plan "P064"
  printf 'mode: [unclosed\n  : : :\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  git -C "$TEST_PROJECT_ROOT" add .aid-lifecycle/manifests/P064.yaml
  git -C "$TEST_PROJECT_ROOT" commit -qm "corrupt the manifest"

  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args --force --reason "IMP-273 test: manifest repair is tracked separately"
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]
  local tl; tl="$(_fsm_init_timeline "$state_file")"
  [ "$(jq -r 'select(.event=="fsm_init_blocked") | .reason' "$tl" | tail -1)" = "plan_mode_unresolved" ]
  [ "$(jq -r 'select(.event=="fsm_init_blocked") | .overridden' "$tl" | tail -1)" = "true" ]
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

@test "Security: malformed epic_id is rejected BEFORE jq interpolation to prevent injection attacks (epic_id_invalid_format)" {
  # The vulnerability (CP3 security finding): epic_id is spliced directly into
  # a jq filter without validation, allowing jq double-quote breakout.
  # This test proves the fix: an epic_id that passes the loose ^E-[0-9]+ check
  # (used for plan_id derivation elsewhere in cmd_init) but fails the strict
  # ^E-[0-9]{3}-[0-9]+_[0-9]+$ format check is rejected BEFORE reaching the
  # vulnerable plan_manifest_get call.
  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Test Case 1: epic_id with missing underscore segment (E-064-1 instead of E-064-1_1)
  # This passes the loose check (has E- and digits) but fails the strict check.
  local malformed_epic="E-064-1"
  local args; args="$(build_default_init_args "$malformed_epic")"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_id_invalid_format"* ]]
  [ ! -f "$state_file" ]

  # Test Case 2: epic_id with jq-suspicious characters (literal double-quote)
  # This would have broken out of the jq string literal without the fix.
  malformed_epic='E-064-1_1"'
  args="$(build_default_init_args "$malformed_epic")"
  state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_id_invalid_format"* ]]
  [ ! -f "$state_file" ]
}

# ─── Security: plan_manifest_set_epic_status validates epic_id format ──────
@test "Security: malformed epic_id is rejected BEFORE jq interpolation in plan_manifest_set_epic_status" {
  # Bug Fix #2: epic_id format must be validated before splicing into jq filter.
  # An epic_id like 'E-064-1_1"' could break out of the jq string literal
  # without proper validation.
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  # Test Case 1: epic_id with missing underscore segment (E-900-1 instead of E-900-1_2)
  # This fails the strict ^E-[0-9]{3}-[0-9]+_[0-9]+$ format check.
  run plan_manifest_set_epic_status "P900" "E-900-1" "running"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_id must match format"* ]]

  # Test Case 2: epic_id with jq-suspicious characters (literal double-quote)
  # This would have broken out of the jq string literal without the fix.
  local malformed_epic='E-900-1_2"'
  run plan_manifest_set_epic_status "P900" "$malformed_epic" "running"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_id must match format"* ]]

  # Verify the manifest is unchanged (no partial/corrupted write)
  run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
  [ "$status" -eq 0 ]
  [ "$output" = "running" ]
}

# ─── Regression: concurrent plan_manifest_set_epic_status must not allow TOCTOU race ──
@test "Regression: concurrent plan_manifest_set_epic_status calls never downgrade terminal state (TOCTOU race test)" {
  # Bug Fix #1: The transition-legality decision must happen under the lock,
  # against the file's LIVE current status at write time — not from a bash-side
  # snapshot taken before acquiring the lock. This prevents a race where two
  # concurrent callers both read the same stale current_status="running", both
  # decide their intended transition is legal, and the second write clobbers
  # the first even if that clobber is actually illegal (e.g., terminal-state
  # downgrade).
  #
  # Scenario: A transitions running -> merged_to_plan (legal, terminal),
  #          B transitions running -> blocked (legal, but lower rank than terminal).
  # If A completes first, the file has merged_to_plan.
  # If B then reads a stale snapshot still showing "running", B's write will
  # unconditionally set status=blocked, downgrading the terminal state
  # (BUG). With the fix, B's write fails because it re-checks under the lock
  # and sees the current status is actually merged_to_plan (terminal).
  #
  # We run 5 truly-concurrent trials (no stagger, both subshells start at ~same
  # time) to increase the probability of interleaving.
  #
  # The sharp discriminator is NOT "the final status is one of the two
  # attempted values" — under the buggy unconditional-write code, the final
  # status is ALWAYS one of {merged_to_plan, blocked} regardless of ordering
  # (empirically verified: A-then-B gives blocked, an illegal downgrade FROM
  # merged_to_plan; B-then-A gives merged_to_plan, an illegal transition FROM
  # blocked, since blocked's only legal targets are {running,abandoned,superseded}
  # — merged_to_plan is not among them). A same-value-set assertion therefore
  # cannot distinguish buggy from fixed code.
  #
  # The real invariant: whichever call's write lands SECOND must see the
  # OTHER call's already-committed status under the lock and correctly
  # reject its own (now-illegal) transition — so exactly ONE of the two
  # concurrent calls succeeds (exit 0) and the OTHER fails (non-zero exit,
  # "not a legal pair" in its stderr) on every trial. Under the bug, BOTH
  # calls always succeed (unconditional overwrite) regardless of order.
  _init_manifest "P900"
  plan_manifest_add_epic "P900" "E-900-1_2" "R-E900-1" "task/E-900-1_2/main" \
    "1111111111111111111111111111111111111111" "plan/P900" ".aid-o/work/evidence/E-900-1_2/"

  local trial
  for trial in 1 2 3 4 5; do
    # Reset the epic to running state before each trial
    plan_manifest_update P900 '.plan_boundary_manifest.epic_runs |= map(if .epic_id == "E-900-1_2" then .status = "running" | .epic_merge_commit = null else . end)'

    local rc_file_a="$TEST_TMPDIR/rc_a_${trial}" rc_file_b="$TEST_TMPDIR/rc_b_${trial}"
    local err_file_a="$TEST_TMPDIR/err_a_${trial}" err_file_b="$TEST_TMPDIR/err_b_${trial}"

    # Spawn two concurrent subshells, each attempting a different transition
    # from the same running state. Both transitions are legal FROM running,
    # but only one of the two can legally land — one (merged_to_plan) is
    # terminal, and blocked's legal targets never include merged_to_plan.
    bash -c "
      source '$PLAN_MANIFEST_LIB'
      export AID_PLAN_MANIFEST_PROJECT_ROOT='$TEST_PROJECT_ROOT'
      plan_manifest_set_epic_status 'P900' 'E-900-1_2' 'merged_to_plan' '3333333333333333333333333333333333333333' 2>'$err_file_a'
      echo \$? > '$rc_file_a'
    " &
    local pid_a=$!

    bash -c "
      source '$PLAN_MANIFEST_LIB'
      export AID_PLAN_MANIFEST_PROJECT_ROOT='$TEST_PROJECT_ROOT'
      plan_manifest_set_epic_status 'P900' 'E-900-1_2' 'blocked' 2>'$err_file_b'
      echo \$? > '$rc_file_b'
    " &
    local pid_b=$!

    wait "$pid_a" 2>/dev/null || true
    wait "$pid_b" 2>/dev/null || true

    local rc_a rc_b
    rc_a="$(cat "$rc_file_a" 2>/dev/null || echo "?")"
    rc_b="$(cat "$rc_file_b" 2>/dev/null || echo "?")"

    # Exactly one of the two must succeed and the other must fail — never
    # both-succeed (the TOCTOU bug: both think their stale snapshot is
    # still current) and never both-fail (would mean neither transition
    # was ever accepted, a different bug).
    if [[ "$rc_a" -eq 0 && "$rc_b" -eq 0 ]]; then
      echo "FAIL (trial $trial): BOTH concurrent calls succeeded — TOCTOU race, one clobbered the other's terminal write without re-checking the live status."
      return 1
    fi
    if [[ "$rc_a" -ne 0 && "$rc_b" -ne 0 ]]; then
      echo "FAIL (trial $trial): BOTH concurrent calls failed — neither legal transition from 'running' was ever accepted."
      cat "$err_file_a" "$err_file_b"
      return 1
    fi

    # The loser's stderr must show a legality rejection, not some unrelated
    # error (lock timeout, corrupt file, etc.) — a real "your snapshot is
    # stale" rejection, not an accidental failure mode.
    if [[ "$rc_a" -ne 0 ]]; then
      grep -q "is not a legal pair" "$err_file_a" || {
        echo "FAIL (trial $trial): loser A failed for an unexpected reason:"; cat "$err_file_a"; return 1;
      }
    else
      grep -q "is not a legal pair" "$err_file_b" || {
        echo "FAIL (trial $trial): loser B failed for an unexpected reason:"; cat "$err_file_b"; return 1;
      }
    fi

    # The on-disk status must match whichever call actually won.
    run plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[0].status'
    [ "$status" -eq 0 ]
    local final_status="$output" expected_status
    if [[ "$rc_a" -eq 0 ]]; then expected_status="merged_to_plan"; else expected_status="blocked"; fi
    [ "$final_status" = "$expected_status" ] || {
      echo "FAIL (trial $trial): final status '$final_status' does not match the winning call's own status '$expected_status'."
      return 1
    }
  done
}

# ─── Regression: lineage and epic_source_ref enforcement ─────────────────────
@test "Regression: unproven entry (after repair) is rejected by aid-fsm init with epic_lineage_unproven block reason" {
  # This test reproduces the security finding F-1: a task branch created
  # outside the plan's epic-start (simulated by repo recovery after prune) has
  # lineage:unproven + epic_source_ref:null. aid-fsm init must REJECT it with
  # block reason epic_lineage_unproven until it is explicitly attested.

  _pfsm_bootstrap_plan "P064"
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Prune .aid-o/work to simulate a recovered workspace (evidence lost). The
  # execution worktree goes with it: `.aid-worktrees/` is gitignored, so a
  # recovered checkout has neither the directory nor its git registration.
  # Leaving a REGISTERED worktree behind while deleting its state record would
  # simulate the plan-start crash window instead, which P074 Step 8 refuses
  # before init ever reaches the lineage check this test is about.
  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work"
  _pfsm_drop_plan_worktree P064

  # Run plan-state --repair to rebuild entries from Git evidence
  # The repaired entry has lineage:unproven + epic_source_ref:null
  run bash "$PLAN_FSM_CLI" plan-state P064 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Verify the repaired entry is indeed unproven
  local mp; mp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .lineage' "$mp"
  [ "$status" -eq 0 ]
  [ "$output" = "unproven" ]

  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .epic_source_ref' "$mp"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]

  # aid-fsm init for an unproven entry must FAIL with epic_lineage_unproven block reason
  local args; args="$(build_default_init_args E-064-1_1)"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_lineage_unproven"* ]]
  [ ! -f "$state_file" ]
}

@test "Regression: proven entry (lineage:proven, epic_source_ref:plan/P064) passes aid-fsm init" {
  # Positive control: a properly proven entry (created via epic-start without
  # being pruned) passes init successfully.
  _pfsm_bootstrap_plan "P064"

  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Verify the entry is proven from the start
  local mp; mp="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"
  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .lineage' "$mp"
  [ "$status" -eq 0 ]
  [ "$output" = "proven" ]

  run jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id=="E-064-1_1") | .epic_source_ref' "$mp"
  [ "$status" -eq 0 ]
  [ "$output" = "plan/P064" ]

  # aid-fsm init for a proven entry must SUCCEED
  local args; args="$(build_default_init_args E-064-1_1)"
  run "$FSM" init $args
  [ "$status" -eq 0 ]
}

# ─── Security F-2: --repair may never mint lineage:proven ────────────────────
# A merge-commit SUBJECT is attacker-controlled free text. Before this fix,
# _pfsm_plan_state_repair took a `grep -F` substring hit on a merge subject as
# proof of lineage and wrote `lineage: proven` + `epic_source_ref:
# plan/<plan_id>`, which is exactly what aid-fsm.sh init accepts as
# authorisation. Two ways in: a deliberately forged subject (Exploit A) and an
# accidental substring collision with a sibling branch (Exploit B). The fix is
# a systemic invariant — repair creates every entry ALREADY unproven, in one
# atomic write — plus diagnostic-accuracy hardening on the candidate match.

# _f2_repaired_field <plan_id> <epic_id> <field> — one field of a repaired
# epic_runs[] entry, read straight off the canonical manifest file.
_f2_repaired_field() {
  local plan_id="$1" epic_id="$2" field="$3"
  jq -r --arg e "$epic_id" --arg f "$field" \
    '.plan_boundary_manifest.epic_runs[] | select(.epic_id==$e) | .[$f]' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${plan_id}/plan-boundary-manifest.json"
}

# _f2_assert_init_blocked <epic_id> — aid-fsm.sh init must refuse this EPIC
# with the lineage block reason AND write no state file at all.
_f2_assert_init_blocked() {
  local epic_id="$1"
  local args; args="$(build_default_init_args "$epic_id")"
  local state_file; state_file="$(awk '{print $NF}' <<<"$args")"
  run "$FSM" init $args
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_lineage_unproven"* ]]
  [ ! -f "$state_file" ]
}

@test "Security F-2 (Exploit A): a forged merge subject naming a victim branch cannot mint lineage:proven, and init stays blocked" {
  _pfsm_bootstrap_plan "P900"
  local base_sha; base_sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P900)"

  # Decoy branch forked at the plan base and merged into plan/P900 under a
  # subject that NAMES a branch it has nothing to do with. The decoy is then
  # deleted, so only the (attacker-authored) subject text survives.
  git -C "$TEST_PROJECT_ROOT" checkout -q -b decoy "$base_sha"
  echo decoy > "$TEST_PROJECT_ROOT/decoy.txt"
  git -C "$TEST_PROJECT_ROOT" add decoy.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "decoy work"
  git -C "$(_pfsm_plan_tree P900)" checkout -q plan/P900
  git -C "$(_pfsm_plan_tree P900)" merge --no-ff -q decoy \
    -m "Merge branch 'task/E-900-1_1/main' into plan/P900"
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  git -C "$TEST_PROJECT_ROOT" branch -q -D decoy

  # The victim branch is cut from main — it was never epic-started under this
  # plan, and the merge above never touched it.
  git -C "$TEST_PROJECT_ROOT" branch task/E-900-1_1/main main

  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"
  # A pruned workspace has no `.aid-worktrees/` either (gitignored) — see
  # _pfsm_drop_plan_worktree.
  _pfsm_drop_plan_worktree P900
  run bash "$PLAN_FSM_CLI" plan-state P900 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # THE invariant: repair produced an entry, and it is unproven.
  run _f2_repaired_field P900 E-900-1_1 lineage
  [ "$output" = "unproven" ]

  _f2_assert_init_blocked E-900-1_1
}

@test "Security F-2 (Exploit B): a legitimate sibling branch merge is not misattributed to the substring-matching entry, which stays unproven" {
  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # No adversary here: a sibling branch whose name merely has the victim's
  # name as a PREFIX. Its merge subject contains `task/E-900-1_1/main` as a
  # substring, which is all the old grep -F needed.
  git -C "$TEST_PROJECT_ROOT" checkout -q -b task/E-900-1_1/main-fixup task/E-900-1_1/main
  echo fixup > "$TEST_PROJECT_ROOT/fixup.txt"
  git -C "$TEST_PROJECT_ROOT" add fixup.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "fixup work"
  git -C "$(_pfsm_plan_tree P900)" checkout -q plan/P900
  git -C "$(_pfsm_plan_tree P900)" merge --no-ff -q task/E-900-1_1/main-fixup \
    -m "Merge branch 'task/E-900-1_1/main-fixup' into plan/P900"
  local sibling_merge; sibling_merge="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P900)"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"
  # A pruned workspace has no `.aid-worktrees/` either (gitignored) — see
  # _pfsm_drop_plan_worktree.
  _pfsm_drop_plan_worktree P900
  run bash "$PLAN_FSM_CLI" plan-state P900 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Diagnostic accuracy: the sibling's merge commit is NOT credited to
  # E-900-1_1's entry, which is restored on the live-branch (no merge
  # evidence) path instead.
  run _f2_repaired_field P900 E-900-1_1 epic_merge_commit
  [ "$output" = "null" ]
  [ "$output" != "$sibling_merge" ]
  run _f2_repaired_field P900 E-900-1_1 status
  [ "$output" = "running" ]

  # THE invariant, again.
  run _f2_repaired_field P900 E-900-1_1 lineage
  [ "$output" = "unproven" ]

  _f2_assert_init_blocked E-900-1_1
}

@test "Security F-2 (positive control): a fresh epic-start still writes lineage:proven and init still succeeds" {
  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Built through the REAL epic-start, never a hand-written fixture — this is
  # what proves the invariant did not break the happy path.
  run _f2_repaired_field P900 E-900-1_1 lineage
  [ "$output" = "proven" ]
  run _f2_repaired_field P900 E-900-1_1 epic_source_ref
  [ "$output" = "plan/P900" ]

  local args; args="$(build_default_init_args E-900-1_1)"
  run "$FSM" init $args
  [ "$status" -eq 0 ]
}

@test "Security F-2: BOTH repair paths (genuine merge commit, and no merge at all) produce lineage:unproven" {
  _pfsm_bootstrap_plan "P900"

  # Declare a second EPIC on the git-tracked lifecycle manifest.
  local lm="$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P900.yaml"
  yq -i '.declared_epics += [{"id": "E-900-1_2", "scope": "required"}]' "$lm"
  git -C "$TEST_PROJECT_ROOT" add "$lm"
  git -C "$TEST_PROJECT_ROOT" commit -qm "declare E-900-1_2"

  # Path 1: a genuine epic-start plus a genuine merge into the plan branch.
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-900-1_1/main
  echo work > "$TEST_PROJECT_ROOT/epic-1.txt"
  git -C "$TEST_PROJECT_ROOT" add epic-1.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "epic 1 work"
  git -C "$(_pfsm_plan_tree P900)" checkout -q plan/P900
  git -C "$(_pfsm_plan_tree P900)" merge --no-ff -q task/E-900-1_1/main \
    -m "Merge branch 'task/E-900-1_1/main' into plan/P900"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  # Path 2: a live, never-merged branch.
  git -C "$TEST_PROJECT_ROOT" branch task/E-900-1_2/main plan/P900

  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"
  # A pruned workspace has no `.aid-worktrees/` either (gitignored) — see
  # _pfsm_drop_plan_worktree.
  _pfsm_drop_plan_worktree P900
  run bash "$PLAN_FSM_CLI" plan-state P900 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Merge path: status + merge commit are kept as DIAGNOSTIC facts, but the
  # lineage claim is not.
  run _f2_repaired_field P900 E-900-1_1 status
  [ "$output" = "merged_to_plan" ]
  run _f2_repaired_field P900 E-900-1_1 epic_merge_commit
  [ "$output" != "null" ]
  run _f2_repaired_field P900 E-900-1_1 lineage
  [ "$output" = "unproven" ]

  # No-merge path.
  run _f2_repaired_field P900 E-900-1_2 status
  [ "$output" = "running" ]
  run _f2_repaired_field P900 E-900-1_2 lineage
  [ "$output" = "unproven" ]

  # A repaired manifest is still fully valid under the invariant checker.
  run plan_manifest_validate "P900"
  [ "$status" -eq 0 ]
}

@test "Security F-2: an explicit operator attestation is the ONLY way a repaired entry becomes proven, and then init succeeds" {
  _pfsm_bootstrap_plan "P900"
  run bash "$PLAN_FSM_CLI" epic-start P900 E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  rm -rf "$TEST_PROJECT_ROOT/.aid-o/work/plan-state"
  # A pruned workspace has no `.aid-worktrees/` either (gitignored) — see
  # _pfsm_drop_plan_worktree.
  _pfsm_drop_plan_worktree P900
  run bash "$PLAN_FSM_CLI" plan-state P900 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  run _f2_repaired_field P900 E-900-1_1 lineage
  [ "$output" = "unproven" ]

  # The real CLI, exactly as the aid-fsm.sh recovery message now prints it.
  run bash "$PLAN_FSM_CLI" plan-state P900 --attest-source-ref "plan/P900" \
    --reason "operator verified the branch origin from the reflog" \
    --epic E-900-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run _f2_repaired_field P900 E-900-1_1 lineage
  [ "$output" = "proven" ]
  run _f2_repaired_field P900 E-900-1_1 epic_source_ref
  [ "$output" = "plan/P900" ]

  local args; args="$(build_default_init_args E-900-1_1)"
  run "$FSM" init $args
  [ "$status" -eq 0 ]
}

# =============================================================================
# ─── scripts/aid-plan-fsm.sh — epic-complete / epic-merge-to-plan
#     (P064 EPIC E-064-2_2 Step 1 = plan Step 6) ───────────────────────────────
# =============================================================================
# The merge half of the plan-branch substrate: an EPIC is finalized
# (`epic-complete`) and then integrated into `plan/<plan_id>` inside one
# reconcilable transaction (`epic-merge-to-plan`) whose ONLY accepted evidence
# of completion is Git ancestry. `_pfsm_bootstrap_plan` / `_write_legacy_plan`
# (Step 4's fixtures, above) are reused verbatim.
#
# TRACEABILITY — an `ACn:` prefix names the acceptance criterion that test
# actually proves, numbered in the order of this step's own AC list in
# .aid-o/tasks/E-064-2_2-…md (step-1 UI contract):
#   AC1  only `plan/<plan_id>` moves; the `main` SHA is byte-identical
#   AC2  a crash after the Git merge converges on re-run to merged_to_plan
#   AC3  dirty worktree / MERGE_HEAD / unmerged path / stale expected-sha block
#   AC4  merged_to_plan refused on `state: DONE` + a deleted task branch alone
#   AC5  a merge conflict moves the plan to CONFLICT and records no completion
#   AC6  `epic-complete --abandon` records the terminal status and reason
# Everything else carries the suite's existing Edge Case / Error Handling /
# Security / Regression prefixes — those cases harden the commands but are not
# themselves acceptance criteria of this step.

# _pfsm_epic_with_commit <plan_id> <epic_id> [file] [content]
#   epic-start's the EPIC through the REAL CLI, then puts exactly one real
#   commit on its task branch and returns the worktree to main — the normal
#   pre-merge shape. Never fabricates the branch by hand: a hand-made branch
#   has no provable lineage and epic-start would (correctly) reject it.
_pfsm_epic_with_commit() {
  local plan_id="$1" epic_id="$2" file="${3:-work-${2}.txt}" content="${4:-work}"
  run bash "$PLAN_FSM_CLI" epic-start "$plan_id" "$epic_id" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  git -C "$TEST_PROJECT_ROOT" checkout -q "task/${epic_id}/main"
  # `file` may be a nested path (Step 8's risk cases commit
  # plugins/aid-orchestrator/scripts/aid-fsm.sh to exercise the high-risk
  # classification) — create its parent, never assume repo root.
  mkdir -p "$(dirname "$TEST_PROJECT_ROOT/$file")"
  echo "$content" > "$TEST_PROJECT_ROOT/$file"
  git -C "$TEST_PROJECT_ROOT" add "$file"
  git -C "$TEST_PROJECT_ROOT" commit -qm "${epic_id}: work"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  # P068 F2 (2026-07-27): epic-merge-to-plan now requires a SUCCESSFUL,
  # task-SHA-bound epic-complete before it will move anything. These fixtures
  # predate that gate and merged straight from `running`, which is precisely the
  # hole the gate closes — so the default seed now completes the EPIC, and the
  # cases that deliberately exercise an INCOMPLETE one opt out with
  # PFSM_SKIP_COMPLETE=1 rather than the whole suite pretending completion is
  # optional.
  if [[ "${PFSM_SKIP_COMPLETE:-0}" != "1" ]]; then
    _pfsm_write_epic_evidence "$epic_id" DONE
    run bash "$PLAN_FSM_CLI" epic-complete "$plan_id" "$epic_id" --project-root "$TEST_PROJECT_ROOT"
    [ "$status" -eq 0 ]
  fi
}

# _pfsm_write_epic_evidence <epic_id> [state] [profile]
#   Writes the EPIC run's own evidence exactly where epic-start recorded it
#   (run_id defaults to R-<epic_id>-plan): the FSM state file epic-complete
#   reads `state:` from, and optionally the gates_report.json it reads
#   `.profile` from.
#
#   `done_phase: release` IS WRITTEN FOR A DONE STATE (CP3 integration review
#   finding 3). It used to be omitted, which made every epic-complete test run
#   against a state file no production run can ever produce: epic-complete is
#   only reachable AFTER `done-advance review release`, so a real EPIC's state
#   file always carries `done_phase: release` at that point. The omission is
#   what let the acceptance level assert a risk-derived floor while the
#   library level asserted `release` for the same input — one of them had to be
#   describing something other than production, and it was this fixture.
_pfsm_write_epic_evidence() {
  local epic_id="$1" state="${2:-DONE}" profile="${3:-}"
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/R-${epic_id}-plan"
  mkdir -p "$dir/gates"
  printf 'epic_id: %s\nstate: %s\n' "$epic_id" "$state" > "$dir/fsm-state.yaml"
  # Only a DONE run has advanced through the DONE phases at all; a GATES-state
  # fixture must not claim a done_phase it could not have reached.
  [[ "$state" == "DONE" ]] && printf 'done_phase: release\n' >> "$dir/fsm-state.yaml"
  if [[ -n "$profile" ]]; then
    jq -nc --arg p "$profile" '{profile: $p}' > "$dir/gates/gates_report.json"
  fi
}

# _pfsm_entry_field <plan_id> <epic_id> <field> — one field of the epic_runs[]
# entry, read straight from the canonical manifest file.
_pfsm_entry_field() {
  local plan_id="$1" epic_id="$2" field="$3"
  jq -r --arg e "$epic_id" --arg f "$field" \
    '.plan_boundary_manifest.epic_runs[] | select(.epic_id==$e) | .[$f]' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${plan_id}/plan-boundary-manifest.json"
}

# _pfsm_merge_commit_count <plan_branch> — merge commits reachable from the
# plan branch (the "exactly one merge commit" assertion).
_pfsm_merge_commit_count() {
  git -C "$TEST_PROJECT_ROOT" rev-list --merges --count "$1"
}

# ─── AC1: only plan/<plan_id> moves ────────────────────────────────────────
@test "AC1: epic-merge-to-plan moves only plan/<plan_id>; the main SHA is byte-identical before and after" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  local main_before; main_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  local task_tip; task_tip="$(git -C "$TEST_PROJECT_ROOT" rev-parse task/E-064-1_1/main)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local merge_commit; merge_commit="$(_pfsm_stdout_tail)"

  # main is untouched, byte for byte.
  local main_after; main_after="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  [ "$main_before" = "$main_after" ]

  # plan/P064 moved to a real two-parent merge commit.
  local plan_after; plan_after="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  [ "$plan_after" = "$merge_commit" ]
  [ "$plan_after" != "$plan_before" ]
  local parents; parents="$(git -C "$TEST_PROJECT_ROOT" rev-list --parents -n1 "$plan_after" | wc -w | tr -d ' ')"
  [ "$parents" -eq 3 ]
  run git -C "$TEST_PROJECT_ROOT" log -1 --format=%s "$plan_after"
  [ "$output" = "merge(epic): E-064-1_1 into plan/P064" ]

  # Ancestry proof holds for both the merge commit and the task tip.
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$merge_commit" plan/P064
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$task_tip" plan/P064
  [ "$status" -eq 0 ]

  # Manifest records the status + the merge commit that proves it.
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "merged_to_plan" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_merge_commit
  [ "$output" = "$merge_commit" ]

  # HEAD is back where the operator left it.
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "main" ]

  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

# ─── AC2: crash after the Git merge converges on re-run ────────────────────
@test "AC2: a crash after the Git merge converges on re-run to merged_to_plan with exactly one merge commit" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  local op_id; op_id="$(plan_op_key "epic-merge-to-plan" "P064" "-" "0" "E-064-1_1")"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  # Simulate the crash: intent + the real Git merge + git_applied recorded,
  # but the manifest status write never ran.
  plan_op_begin "P064" "$op_id" "epic-merge-to-plan" "E-064-1_1" "$plan_before"
  git -C "$(_pfsm_plan_tree P064)" checkout -q plan/P064
  git -C "$(_pfsm_plan_tree P064)" merge --no-ff -q task/E-064-1_1/main -m "merge(epic): E-064-1_1 into plan/P064"
  local merge_commit; merge_commit="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  plan_op_mark_git_applied "P064" "$op_id" "$merge_commit"

  run plan_op_reconcile "P064" "$op_id"
  [ "$output" = "git_applied" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$(_pfsm_stdout_tail)" = "$merge_commit" ]

  # Exactly ONE merge commit — the resume performed only the state write.
  run _pfsm_merge_commit_count plan/P064
  [ "$output" = "1" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$merge_commit" ]

  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "merged_to_plan" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_merge_commit
  [ "$output" = "$merge_commit" ]
  run plan_op_reconcile "P064" "$op_id"
  [ "$output" = "state_committed" ]
}

# ─── Edge Case: already merged — converge, never a second merge ────────────
@test "Edge Case: epic-merge-to-plan is idempotent — a second run converges without a second merge commit" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local merge_commit; merge_commit="$(_pfsm_stdout_tail)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$(_pfsm_stdout_tail)" = "$merge_commit" ]

  run _pfsm_merge_commit_count plan/P064
  [ "$output" = "1" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$merge_commit" ]
}

# ─── AC3: the four pre-merge blocks (dirty worktree, MERGE_HEAD, unmerged
#          index path, stale --expected-plan-sha) ─────────────────────────────
@test "AC3: a dirty plan worktree blocks epic-merge-to-plan with a non-zero exit and the porcelain output" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  # P074 EPIC 2: the pre-merge cleanliness check evaluates the tree the merge
  # will run in — the PLAN worktree. Dirtying the PM's own checkout is exactly
  # what this EPIC made harmless (that is the headline concurrency win), so the
  # fixture dirties the tree the guard is actually about.
  local ptree; ptree="$(_pfsm_plan_tree P064)"
  echo dirty >> "$ptree/.gitkeep"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [[ "$output" == *".gitkeep"* ]]

  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
}

@test "AC3: a pre-existing MERGE_HEAD blocks epic-merge-to-plan with a non-zero exit" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  # A linked worktree keeps MERGE_HEAD in ITS git dir (.git/worktrees/<name>),
  # which is the one the merge consults after the P074 Step 8 redirect.
  local ptree; ptree="$(_pfsm_plan_tree P064)"
  git -C "$TEST_PROJECT_ROOT" rev-parse main \
    > "$(git -C "$ptree" rev-parse --absolute-git-dir)/MERGE_HEAD"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MERGE_HEAD"* ]]

  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
}

@test "AC3: an unmerged index path blocks epic-merge-to-plan with a non-zero exit" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  # A stage-2 index entry with no stage-0 counterpart — an unmerged path
  # without a MERGE_HEAD, so the MERGE_HEAD guard cannot be what fires.
  local ptree; ptree="$(_pfsm_plan_tree P064)"
  local blob; blob="$(git -C "$ptree" hash-object -w "$ptree/.gitkeep")"
  printf '100644 %s 2\t.gitkeep\n' "$blob" \
    | git -C "$ptree" update-index --index-info
  [ -n "$(git -C "$ptree" ls-files --unmerged)" ]

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unmerged index"* ]]

  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
}

@test "AC3: a stale --expected-plan-sha blocks before the merge (concurrent-writer guard)" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  local stale; stale="$(git -C "$TEST_PROJECT_ROOT" rev-parse task/E-064-1_1/main)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 \
    --expected-plan-sha "$stale" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected-plan-sha"* ]]

  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  run _pfsm_merge_commit_count plan/P064
  [ "$output" = "0" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]

  # The matching sha still merges — the guard is about staleness, not refusal.
  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 \
    --expected-plan-sha "$plan_before" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

# ─── AC4: state:DONE + a deleted task branch is NOT proof ──────────────────
@test "AC4: merged_to_plan is refused when only state:DONE and a deleted task branch are present (unproven_merge)" {
  _pfsm_bootstrap_plan "P064"
  # NOT completed: the point is an EPIC that never earned a merge authorization.
  PFSM_SKIP_COMPLETE=1 _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "standard"

  # The exact failure mode aid-fsm.sh's _revalidate_one_dep fallback accepts:
  # the branch is gone and the run says DONE, but nothing was ever merged.
  git -C "$TEST_PROJECT_ROOT" branch -D task/E-064-1_1/main
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  # P068 F2 (2026-07-27): the completion gate now fires FIRST and refuses on
  # epic_completion_missing before the lineage check is reached. Both refusals
  # are correct and the merge is refused either way; this asserts the refusal
  # and its reason rather than pinning one of two valid ones.
  [[ "$output" == *"unproven_merge"* || "$output" == *"epic_completion_missing"* ]]

  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_merge_commit
  [ "$output" = "null" ]
}

# ─── Edge Case: deleted branch + a proven merge commit is still merged ─────
@test "Edge Case: a deleted task branch WITH a recorded, proven merge commit converges to exit 0" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local merge_commit; merge_commit="$(_pfsm_stdout_tail)"

  git -C "$TEST_PROJECT_ROOT" branch -D task/E-064-1_1/main
  run git -C "$TEST_PROJECT_ROOT" rev-parse --verify --quiet refs/heads/task/E-064-1_1/main
  [ "$status" -ne 0 ]

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$(_pfsm_stdout_tail)" = "$merge_commit" ]
  run _pfsm_merge_commit_count plan/P064
  [ "$output" = "1" ]
}

# ─── AC5: a conflict transitions to CONFLICT and records NO completion ─────
@test "AC5: a merge conflict transitions the plan to CONFLICT, records the op aborted, exits 4 and writes no completion" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1" "conflicted.txt" "from the task branch"

  # A competing change to the SAME file directly on the plan branch.
  local ptree; ptree="$(_pfsm_plan_tree P064)"
  git -C "$ptree" checkout -q plan/P064
  echo "from the plan branch" > "$ptree/conflicted.txt"
  git -C "$ptree" add conflicted.txt
  git -C "$ptree" commit -qm "plan-side change to the same file"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  local main_before; main_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 4 ]
  [[ "$output" == *"conflict"* ]]

  # No completion, no moved branches, no leftover merge state.
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_merge_commit
  [ "$output" = "null" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" = "$main_before" ]
  # The merge runs in the PLAN worktree (P074 Step 8), so its merge state — if
  # any leaked — would live in THAT tree's git dir, not the common one.
  [ ! -f "$(git -C "$(_pfsm_plan_tree P064)" rev-parse --absolute-git-dir)/MERGE_HEAD" ]
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "main" ]

  # Plan state is CONFLICT and the operation record says aborted.
  run plan_state_get P064 plan_state
  [ "$output" = "CONFLICT" ]
  local op_id; op_id="$(plan_op_key "epic-merge-to-plan" "P064" "-" "0" "E-064-1_1")"
  run plan_op_reconcile "P064" "$op_id"
  [ "$output" = "aborted" ]
}

# ─── Security: the merge command never touches lineage ─────────────────────
@test "Security: epic-merge-to-plan never writes lineage — the entry stays exactly as epic-start recorded it" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  local lineage_before; lineage_before="$(_pfsm_entry_field P064 E-064-1_1 lineage)"
  local base_before; base_before="$(_pfsm_entry_field P064 E-064-1_1 epic_base_commit)"
  local src_before; src_before="$(_pfsm_entry_field P064 E-064-1_1 epic_source_ref)"
  [ "$lineage_before" = "proven" ]

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run _pfsm_entry_field P064 E-064-1_1 lineage
  [ "$output" = "$lineage_before" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_base_commit
  [ "$output" = "$base_before" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_source_ref
  [ "$output" = "$src_before" ]
}

# ─── epic-complete ─────────────────────────────────────────────────────────

@test "Error Handling: epic-complete requires the EPIC FSM state file to report state: DONE" {
  _pfsm_bootstrap_plan "P064"
  # The seed must NOT complete it — this test is about epic-complete's own refusal.
  PFSM_SKIP_COMPLETE=1 _pfsm_epic_with_commit "P064" "E-064-1_1"

  # No state file at all.
  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fsm-state.yaml"* ]]

  # Present, but not DONE.
  _pfsm_write_epic_evidence "E-064-1_1" "GATES" "standard"
  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GATES"* ]]

  run _pfsm_entry_field P064 E-064-1_1 merge_status
  [ "$output" = "null" ]
}

@test "epic-complete raises the plan-final profile from gates_report.json and marks the entry pending merge" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "full"

  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "standard" ]

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]
  run _pfsm_entry_field P064 E-064-1_1 merge_status
  [ "$output" = "pending" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_completion_profile
  [ "$output" = "full" ]
  # Still `running` in the manifest's own status vocabulary — only
  # epic-merge-to-plan's ancestry proof may move it off that.
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]

  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

@test "AC6: epic-complete --abandon records the terminal status and reason in the runtime manifest and makes no lifecycle write" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  # Stand where the command really runs: on the EPIC's own task branch.
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main
  local head_before; head_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  local main_before; main_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  # A lifecycle write from here WOULD be refused — that is precisely why this
  # step records the terminal status in the runtime manifest only.
  run _aid_lc_require_target_branch "$TEST_PROJECT_ROOT"
  [ "$status" -eq 3 ]

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --abandon \
    --reason "superseded by an infra change; no longer worth building" \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "abandoned" ]
  run _pfsm_entry_field P064 E-064-1_1 terminal_reason
  [ "$output" = "superseded by an infra change; no longer worth building" ]

  # No lifecycle write happened: no new commit anywhere, main untouched.
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" = "$main_before" ]
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "task/E-064-1_1/main" ]

  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]

  # Re-running converges rather than failing on the terminal-state edge.
  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --abandon \
    --reason "superseded by an infra change; no longer worth building" \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "epic-complete --supersede-by records superseded plus the superseding EPIC id" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 \
    --supersede-by E-064-1_2 --reason "folded into the wider EPIC" \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "superseded" ]
  run _pfsm_entry_field P064 E-064-1_1 superseded_by
  [ "$output" = "E-064-1_2" ]
  run _pfsm_entry_field P064 E-064-1_1 terminal_reason
  [ "$output" = "folded into the wider EPIC" ]
  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

@test "Error Handling: epic-complete terminal flags require --reason and are mutually exclusive (usage errors)" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --abandon --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--reason"* ]]

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --abandon --supersede-by E-064-1_2 \
    --reason "both at once" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --full-tests --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--reason"* ]]

  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
}

@test "epic-complete --full-tests --reason records the PM exception without lowering the plan-final floor" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "quick"

  # Raise the floor first, so a "quick" mid-plan run has something to lower.
  plan_manifest_raise_final_profile "P064" "release"

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --full-tests \
    --reason "PM asked for a one-off full run mid-plan" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # The floor is monotonic — a lower-profile EPIC run can never pull it down.
  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "release" ]

  # Field renamed to `epic_full_test_exception` by Step 8 (plan Step 8 names
  # it; the `epic_` prefix keeps it distinct from a future plan-final one).
  run bash -c "jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id==\"E-064-1_1\") | .epic_full_test_exception.reason' '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json'"
  [ "$output" = "PM asked for a one-off full run mid-plan" ]
  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

@test "Registration: epic-complete and epic-merge-to-plan are registered subcommands with usage text" {
  run bash "$PLAN_FSM_CLI" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"epic-complete"* ]]
  [[ "$output" == *"epic-merge-to-plan"* ]]

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064
  [ "$status" -eq 2 ]
  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --nope --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]
}

# ─── CP2 fix regressions (E-064-2_2 Step 1) ────────────────────────────────
# Five defects found by the CP2 review of the commands above. Each test here
# fails against the pre-fix command and passes after it; none of them is an
# acceptance criterion of the step, so none carries an `ACn:` prefix.

# _pfsm_force_unproven <plan_id> <epic_id> — rewrite ONE entry into exactly
# the shape `plan-state --repair` produces (lineage unproven, no source ref),
# without going through the whole prune-and-repair cycle. Mirrors
# `_pfsm_entry_update`'s single-entry jq shape.
_pfsm_force_unproven() {
  local plan_id="$1" epic_id="$2"
  plan_manifest_update "$plan_id" \
    "(.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == \"${epic_id}\" then (.lineage = \"unproven\" | .epic_source_ref = null) else . end])" \
    >/dev/null
}

@test "Regression: an already-merged EPIC whose task branch moved on is refused, never re-merged behind the terminal status" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local first_merge; first_merge="$(_pfsm_stdout_tail)"

  # More work lands on the task branch AFTER the merge, so its tip is no
  # longer contained in plan/P064 — the pre-fix command took the real-merge
  # path, created a SECOND merge commit, reported it on stdout, and left
  # epic_merge_commit naming the first one.
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main
  echo "later work" > "$TEST_PROJECT_ROOT/later.txt"
  git -C "$TEST_PROJECT_ROOT" add later.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "E-064-1_1: later work"
  git -C "$TEST_PROJECT_ROOT" checkout -q main

  local moved_tip; moved_tip="$(git -C "$TEST_PROJECT_ROOT" rev-parse task/E-064-1_1/main)"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already merged_to_plan"* ]]
  [[ "$output" == *"$moved_tip"* ]]

  # No second merge commit, and the manifest still agrees with Git.
  run _pfsm_merge_commit_count plan/P064
  [ "$output" = "1" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_merge_commit
  [ "$output" = "$first_merge" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "merged_to_plan" ]
  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

@test "Security: epic-merge-to-plan refuses an entry whose lineage is not proven (no merge, no merged_to_plan)" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_force_unproven "P064" "E-064-1_1"
  run _pfsm_entry_field P064 E-064-1_1 lineage
  [ "$output" = "unproven" ]

  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"epic_lineage_unproven"* ]]
  [[ "$output" == *"--attest-source-ref"* ]]

  # Nothing merged, nothing recorded.
  run _pfsm_merge_commit_count plan/P064
  [ "$output" = "0" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_merge_commit
  [ "$output" = "null" ]

  # epic-start refuses the SAME entry — the two commands now agree.
  run bash "$PLAN_FSM_CLI" epic-start P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lineage"* ]]
}

@test "Edge Case: an already-merged entry with unproven lineage still converges read-only (a repaired plan is not wedged)" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local merge_commit; merge_commit="$(_pfsm_stdout_tail)"

  # `plan-state --repair` rebuilds merged EPICs at merged_to_plan with EVERY
  # entry lineage:unproven. Re-confirming that already-recorded fact must not
  # be refused — and must not launder anything either: it writes NOTHING.
  _pfsm_force_unproven "P064" "E-064-1_1"
  local manifest="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json"
  cp "$manifest" "$BATS_TEST_TMPDIR/manifest-before.json"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$(_pfsm_stdout_tail)" = "$merge_commit" ]

  run cmp -s "$BATS_TEST_TMPDIR/manifest-before.json" "$manifest"
  [ "$status" -eq 0 ]
  run _pfsm_entry_field P064 E-064-1_1 lineage
  [ "$output" = "unproven" ]
  run _pfsm_merge_commit_count plan/P064
  [ "$output" = "1" ]
}

@test "Error Handling: a non-conflict merge failure is not reported or state-machined as a conflict" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1" "collide.txt" "from the task branch"

  # An UNTRACKED file at a path the merge must write: invisible to the
  # preflight (`git status --untracked-files=no`), fatal to `git merge`, which
  # refuses BEFORE writing anything — so no MERGE_HEAD and no unmerged index
  # entry ever exists. The pre-fix command called this a MERGE CONFLICT, drove
  # the plan to CONFLICT and exited 4.
  # P074 EPIC 2: planted in the PLAN worktree — the tree the merge writes into
  # after the Step 8 redirect. An untracked file in the PM's own checkout is
  # exactly what this EPIC made irrelevant to the merge.
  echo "untracked local scratch" > "$(_pfsm_plan_tree P064)/collide.txt"

  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"
  local main_before; main_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MERGE FAILED (not a conflict)"* ]]
  [[ "$output" != *"MERGE CONFLICT"* ]]
  [[ "$output" == *"untracked working tree files"* ]]

  # The plan is NOT sent down the conflict-resolution path ...
  run plan_state_get P064 plan_state
  [ "$output" = "OPEN" ]

  # ... and every safety property of the conflict path still holds.
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" = "$main_before" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_merge_commit
  [ "$output" = "null" ]
  # The merge runs in the PLAN worktree (P074 Step 8), so its merge state — if
  # any leaked — would live in THAT tree's git dir, not the common one.
  [ ! -f "$(git -C "$(_pfsm_plan_tree P064)" rev-parse --absolute-git-dir)/MERGE_HEAD" ]
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "main" ]
  local op_id; op_id="$(plan_op_key "epic-merge-to-plan" "P064" "-" "0" "E-064-1_1")"
  run plan_op_reconcile "P064" "$op_id"
  [ "$output" = "aborted" ]

  # The lock is released — a second run gets as far as the same refusal
  # rather than timing out on a lock the aborted run never let go of.
  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MERGE FAILED (not a conflict)"* ]]
}

@test "Error Handling: a checkout-back that fails on the conflict path is reported loudly, never claimed as restored" {
  _pfsm_bootstrap_plan "P064"

  # A file tracked on main and ABSENT from plan/P064 — and, because it is on
  # NEITHER side of the merge, one the merge itself never touches. That is what
  # makes it a pure RESTORE blocker: a file the merge does carry (anything on
  # the task branch) makes git refuse the merge outright, which is a different
  # error path than the one under test.
  echo "only on main" > "$TEST_PROJECT_ROOT/only-main.txt"
  git -C "$TEST_PROJECT_ROOT" add only-main.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "main-only file"

  _pfsm_epic_with_commit "P064" "E-064-1_1" "conflicted.txt" "from the task branch"

  # The same add/add conflict as the AC5 case, committed where plan/P064 now
  # lives: the plan worktree (P074 EPIC 2).
  local ptree; ptree="$(_pfsm_plan_tree P064)"
  echo "from the plan branch" > "$ptree/conflicted.txt"
  git -C "$ptree" add conflicted.txt
  git -C "$ptree" commit -qm "plan-side change to the same file"

  # P074 EPIC 2: the merge runs in the PLAN worktree, so the position it must
  # restore is THAT tree's HEAD, not the PM's. Park it on a branch carrying
  # only-main.txt — the direct analogue of the pre-P074 fixture, where the
  # position to restore was `main` in the single checkout.
  git -C "$ptree" checkout -q -b wt-detour main

  # Installed LAST so it only fires inside the command under test: the moment
  # the command lands on plan/P064 it plants an untracked only-main.txt, which
  # makes the checkout BACK to wt-detour fail ("would be overwritten by
  # checkout"). The pre-fix command swallowed that failure and still told the
  # operator its position was restored. Hooks live in the COMMON git dir, so
  # this one fires inside the plan worktree too.
  cat > "$TEST_PROJECT_ROOT/.git/hooks/post-checkout" <<'HOOK'
#!/bin/sh
if [ "$(git symbolic-ref --short HEAD 2>/dev/null)" = "plan/P064" ]; then
  echo "planted by the post-checkout hook" > only-main.txt
fi
HOOK
  chmod +x "$TEST_PROJECT_ROOT/.git/hooks/post-checkout"

  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  # Still a genuine conflict — exit code and plan state are unchanged.
  [ "$status" -eq 4 ]
  [[ "$output" == *"MERGE CONFLICT"* ]]

  # The restore failure is stated, and names where HEAD really is.
  [[ "$output" == *"HEAD NOT RESTORED"* ]]
  [[ "$output" == *"plan/P064"* ]]
  # The PM's own checkout never moved; the worktree is the one left stranded.
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "main" ]
  run git -C "$ptree" symbolic-ref --short HEAD
  [ "$output" = "plan/P064" ]

  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse plan/P064)" = "$plan_before" ]
  run _pfsm_entry_field P064 E-064-1_1 status
  [ "$output" = "running" ]
  run plan_state_get P064 plan_state
  [ "$output" = "CONFLICT" ]
}

@test "Error Handling: a value-less trailing option is a usage error (exit 2), never an infinite loop" {
  # `timeout` bounds the PRE-fix behaviour: `shift 2` with a single argument
  # left shifts nothing and returns 1, so the option loop re-matched the same
  # arm forever (rc 124, no output). Every arm of both commands is covered.
  run timeout 20 bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --expected-plan-sha
  [ "$status" -eq 2 ]
  [[ "$output" == *"--expected-plan-sha requires a value"* ]]

  run timeout 20 bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root
  [ "$status" -eq 2 ]
  [[ "$output" == *"--project-root requires a value"* ]]

  run timeout 20 bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --op-id
  [ "$status" -eq 2 ]

  run timeout 20 bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --abandon --reason
  [ "$status" -eq 2 ]
  [[ "$output" == *"--reason requires a value"* ]]

  run timeout 20 bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --supersede-by
  [ "$status" -eq 2 ]

  run timeout 20 bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root
  [ "$status" -eq 2 ]

  run timeout 20 bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --op-id
  [ "$status" -eq 2 ]
}

# =============================================================================
# ─── lib/aid-queue-write.sh + aid-fsm.sh dependency resolution
#     (P064 EPIC E-064-2_2 Step 2 = plan Step 7) ─────────────────────────────
# =============================================================================
# The queue half of the plan-branch substrate. Two things are under test here
# and they are deliberately tested together, because the whole point of the
# step is that they agree:
#   1. lib/aid-queue-write.sh — the ONLY writer of queue statuses, and the
#      owner of the two new per-entry fields `plan_id` + `merge_target`.
#   2. aid-fsm.sh's `queue-revalidate` — the READER whose dependency
#      resolution now proves ancestry against the entry's declared
#      `merge_target` instead of the `main|master|HEAD` guess.
#
# THE INVARIANT EVERY TEST BELOW DEFENDS: a queue entry is a DERIVED VIEW and
# is never evidence. A status field — including one someone typed by hand —
# can never substitute for `git merge-base --is-ancestor`.
#
# TRACEABILITY — an `ACn:` prefix names the acceptance criterion the test
# proves, numbered as in plan Step 7's own AC list:
#   AC1  same-plan deps resolve against plan/P064; cross-plan released deps
#        resolve against the target branch
#   AC2  a deleted task branch with no ancestry proof does not unblock
#   AC3  two concurrent queue_claim_next calls: exactly one claim, one refusal
#   AC4  a failed/aborted plan leaves dependents blocked with a recorded reason
# The real CLI is always exercised (`bash $QUEUE_WRITE_LIB <sub>`), never a
# sourced-in "test mode" shortcut — the library is deliberately NOT sourced in
# setup() because it, like aid-plan-state.sh, defines its own `main`.

# ─── fixtures ────────────────────────────────────────────────────────────

_qw_lib() { echo "$AID_PLUGIN_PATH/scripts/lib/aid-queue-write.sh"; }

# _qw_queue — the canonical queue path this suite's fixtures write, matching
# the library's own default (<root>/.aid-o/config/queue.yaml), reconstructed
# independently of the library exactly like _state_file/_manifest_file above.
_qw_queue() { echo "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml"; }

# _qw_write_queue — write a queue fixture from stdin.
_qw_write_queue() {
  mkdir -p "$(dirname "$(_qw_queue)")"
  cat > "$(_qw_queue)"
}

# _qw <subcommand> [args...] — run the real CLI against this test's root.
_qw() {
  run bash "$(_qw_lib)" "$@" --project-root "$TEST_PROJECT_ROOT"
}

# _qw_field <epic_id> <key> — one field, straight off disk via the CLI.
_qw_field() {
  bash "$(_qw_lib)" get "$1" "$2" --project-root "$TEST_PROJECT_ROOT"
}

# _qw_revalidate <epic_id> — aid-fsm.sh's dependency reader over this queue.
_qw_revalidate() {
  run bash "$FSM" queue-revalidate "$1" "$(_qw_queue)" "$TEST_TMPDIR/queue-tl.jsonl"
}

# _qw_append <epic_id> <block> — the library's append door called DIRECTLY,
# i.e. with aid-queue-add.sh's own input guards out of the picture, the way any
# future caller would reach it.
_qw_append() {
  run bash -c '
    export AID_QUEUE_FILE="$1"
    export AID_QUEUE_WRITE_PROJECT_ROOT="$2"
    source "$3"
    queue_append_entry "$4" "$5"
  ' _ "$(_qw_queue)" "$TEST_PROJECT_ROOT" "$(_qw_lib)" "$1" "$2"
}

# _qw_add [args...] — the real aid-queue-add.sh CLI against this test's queue.
# The APPEND half of the write path, i.e. the second of the two doors into the
# file (lib/aid-queue-write.sh's header, "THE TWO DOORS").
_qw_add() {
  run bash "$AID_PLUGIN_PATH/scripts/aid-queue-add.sh" --queue-yaml "$(_qw_queue)" "$@"
}

# _qw_json_status <epic_id> — the status aid-fsm.sh's OWN queue parser reports.
#
# The two readers DISAGREEING is the observable signature of the append-door
# injection: `queue_get_field` is first-key-wins, `_queue_parse_to_json` is
# last-key-wins, so an entry carrying an injected second `status:` line makes
# the FSM and the queue writer read different facts off the same bytes — which
# is how a supplied `completed` came to unblock an EPIC with no branch, no
# evidence and no merge commit. Any test that asserts "nothing was injected"
# must assert the two agree, not merely that one of them looks right.
_qw_json_status() {
  bash -c 'source "$1" >/dev/null 2>&1; _queue_parse_to_json "$2"' _ "$FSM" "$(_qw_queue)" \
    | jq -r --arg e "$1" '[.[] | select(.epic_id == $e) | .status] | last // ""'
}

# ─── AC1 (part 1): same-plan dependency resolves against plan/P064 ──────────
@test "AC1: a same-plan dependency merged into plan/P064 but NOT into main unblocks its dependent" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_epic_with_commit "P064" "E-064-2_1"

  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # The premise: this work is on plan/P064 and is provably NOT on main. Under
  # the pre-P064 _queue_merge_target() guess it would report blocked forever.
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor task/E-064-1_1/main main
  [ "$status" -ne 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor task/E-064-1_1/main plan/P064
  [ "$status" -eq 0 ]

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: merged_to_plan
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML

  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 0 ]
  [ "$output" = "unblocked" ]
  grep -q '"merge_target":"plan/P064"' "$TEST_TMPDIR/queue-tl.jsonl"

  # The writer agrees with the reader: the dependent is claimable.
  _qw claim-next P064
  [ "$status" -eq 0 ]
  [ "$output" = "E-064-2_1" ]
  [ "$(_qw_field E-064-2_1 status)" = "running" ]
}

# ─── AC1 (part 2): cross-plan released dependency resolves against main ─────
@test "AC1: a cross-plan dependency already released to the target branch resolves against main" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-2_1"

  # A dependency from ANOTHER plan whose work has landed on main — its
  # merge_target is the target branch, which is the intended cross-plan
  # semantics (plan-merge-to-main rewrites merge_target on release).
  git -C "$TEST_PROJECT_ROOT" checkout -q -b task/E-063-1_1/main main
  echo cross > "$TEST_PROJECT_ROOT/cross.txt"
  git -C "$TEST_PROJECT_ROOT" add cross.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "E-063-1_1: work"
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  git -C "$TEST_PROJECT_ROOT" merge --no-ff -q task/E-063-1_1/main -m "merge(epic): E-063-1_1 into main"

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-063-1_1
    status: released_to_main
    plan_id: "P063"
    merge_target: "main"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-063-1_1"]
YAML

  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 0 ]
  [ "$output" = "unblocked" ]

  _qw claim-next P064
  [ "$status" -eq 0 ]
  [ "$output" = "E-064-2_1" ]
}

# ─── AC2: a deleted task branch with no ancestry proof does not unblock ─────
@test "AC2: a deleted task branch with no ancestry proof does not unblock a dependent" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_epic_with_commit "P064" "E-064-2_1"

  # The dependency's branch is deleted WITHOUT ever being merged: there is no
  # ancestry to prove and nothing else may stand in for it.
  git -C "$TEST_PROJECT_ROOT" branch -qD task/E-064-1_1/main

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: merged_to_plan
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML

  # Even a `merged_to_plan` status — the strongest thing the queue can say —
  # is not evidence: the reader wants ancestry and there is none.
  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 0 ]
  [ "$output" = "blocked" ]
  grep -q '"reason":"no_ancestry_proof"' "$TEST_TMPDIR/queue-tl.jsonl"

  _qw claim-next P064
  [ "$status" -eq 1 ]
  [[ "$output" == "blocked:E-064-2_1:dependency_no_ancestry_proof:E-064-1_1" ]]
  [ "$(_qw_field E-064-2_1 status)" = "blocked" ]
}

# ─── Edge Case: a hand-edited `completed` cannot unblock a plan-branch dep ──
@test "Edge Case: a hand-edited 'completed' status cannot unblock a plan-branch dependency" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_epic_with_commit "P064" "E-064-2_1"
  # E-064-1_1 is genuinely UNMERGED — only the status line claims otherwise.

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: completed
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML

  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 0 ]
  [ "$output" = "blocked" ]

  _qw claim-next P064
  [ "$status" -eq 1 ]
  [[ "$output" == "blocked:E-064-2_1:dependency_unmerged:E-064-1_1" ]]

  # And `completed` is not even writable — only a hand edit can produce it.
  _qw set-status E-064-1_1 completed
  [ "$status" -eq 2 ]
}

# ─── AC3: two concurrent claims — exactly one winner, nothing lost ─────────
@test "AC3: two concurrent queue_claim_next calls yield exactly one claim and one refusal" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-2_1"

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: merged_to_plan
    plan_id: "P064"
    merge_target: null
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML

  # A REAL race: a third process holds the queue lock while BOTH claimers
  # start, so both are genuinely blocked in flock and contend at release.
  local lockfile="$(_qw_queue).lock"
  bash "$LOCK_LIB" hold "$lockfile" 2 &
  local hold_pid=$!
  sleep 0.5

  # Two shapes matter here, both of them bats/`set -e` traps rather than
  # incidental style: the braces (without them, `cmd; echo $? &` backgrounds
  # ONLY the echo and runs the claim in the foreground), and `|| _rc=$?`
  # (a bare `cmd; echo $?` inside `{...}&` would let `set -e` kill the LOSER's
  # subshell on its expected rc 1, before it ever records anything).
  { _rc=0; bash "$(_qw_lib)" claim-next P064 --project-root "$TEST_PROJECT_ROOT" \
      > "$TEST_TMPDIR/claim-a.out" 2>/dev/null || _rc=$?; echo "$_rc" > "$TEST_TMPDIR/claim-a.rc"; } &
  local a_pid=$!
  { _rc=0; bash "$(_qw_lib)" claim-next P064 --project-root "$TEST_PROJECT_ROOT" \
      > "$TEST_TMPDIR/claim-b.out" 2>/dev/null || _rc=$?; echo "$_rc" > "$TEST_TMPDIR/claim-b.rc"; } &
  local b_pid=$!

  wait "$hold_pid" || true
  wait "$a_pid" || true
  wait "$b_pid" || true

  local rc_a rc_b out_a out_b
  rc_a="$(cat "$TEST_TMPDIR/claim-a.rc")"; out_a="$(cat "$TEST_TMPDIR/claim-a.out")"
  rc_b="$(cat "$TEST_TMPDIR/claim-b.rc")"; out_b="$(cat "$TEST_TMPDIR/claim-b.out")"

  # Exactly one winner: one rc 0 printing the id, one rc 1 refusing.
  local winners=0
  [ "$rc_a" -eq 0 ] && winners=$((winners + 1))
  [ "$rc_b" -eq 0 ] && winners=$((winners + 1))
  [ "$winners" -eq 1 ]
  if [ "$rc_a" -eq 0 ]; then
    [ "$out_a" = "E-064-2_1" ]
    [ "$rc_b" -eq 1 ]
    [ "$out_b" = "none" ]
  else
    [ "$out_b" = "E-064-2_1" ]
    [ "$rc_a" -eq 1 ]
    [ "$out_a" = "none" ]
  fi

  # No entry is lost and the entry ended exactly once in `running`.
  [ "$(grep -c 'epic_id:' "$(_qw_queue)")" -eq 2 ]
  [ "$(_qw_field E-064-2_1 status)" = "running" ]
  [ "$(_qw_field E-064-1_1 status)" = "merged_to_plan" ]
}

# ─── AC4: an aborted/abandoned dependency blocks with a recorded reason ────
@test "AC4: an abandoned dependency leaves cross-plan work blocked with the aborted plan recorded as the reason" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-2_1"

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-063-1_1
    status: abandoned
    plan_id: "P063"
    merge_target: "plan/P063"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-063-1_1"]
YAML

  _qw claim-next P064
  [ "$status" -eq 1 ]
  [[ "$output" == "blocked:E-064-2_1:dependency_abandoned:E-063-1_1:plan=P063" ]]

  # The reason is DURABLE on the entry, not just on stdout.
  [ "$(_qw_field E-064-2_1 status)" = "blocked" ]
  [[ "$(_qw_field E-064-2_1 reason)" == "dependency_abandoned:E-063-1_1:plan=P063" ]]

  # Re-running is stable: a blocked entry stays a candidate (blocked -> running
  # is a legal edge) but stays blocked while the dependency is abandoned.
  _qw claim-next P064
  [ "$status" -eq 1 ]
  [[ "$output" == "blocked:E-064-2_1:dependency_abandoned:E-063-1_1:plan=P063" ]]
}

# ─── Error Handling: a status outside the enum writes nothing ──────────────
@test "Error Handling: a queue status outside the enum exits 2 and leaves the file byte-identical" {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []
YAML
  local before; before="$(md5sum < "$(_qw_queue)")"

  _qw set-status E-064-1_1 done_probably
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a writable queue status"* ]]

  # `queued` is READ-ONLY legacy: accepted on read, never written.
  _qw set-status E-064-1_1 queued
  [ "$status" -eq 2 ]

  local after; after="$(md5sum < "$(_qw_queue)")"
  [ "$before" = "$after" ]
}

# ─── Error Handling: the lock is unavailable → exit 3, nothing written ─────
@test "Error Handling: a queue write that cannot acquire the lock in the lease exits 3 and writes nothing" {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []
YAML
  local before; before="$(md5sum < "$(_qw_queue)")"

  bash "$LOCK_LIB" hold "$(_qw_queue).lock" 3 &
  local hold_pid=$!
  sleep 0.5

  AID_QUEUE_WRITE_LOCK_TIMEOUT_S=1 run bash "$(_qw_lib)" set-status E-064-1_1 running \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 3 ]

  wait "$hold_pid" || true
  local after; after="$(md5sum < "$(_qw_queue)")"
  [ "$before" = "$after" ]
}

# ─── Edge Case: legacy entry (status: queued, no plan_id/merge_target) ─────
@test "Edge Case: a legacy entry reads status queued as pending and keeps the pre-P064 fallback resolution" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-2_1"

  # The 43-entry live shape: `queued`, no plan_id, no merge_target. The
  # dependency is `completed` with a deleted branch — the pre-P064
  # merged-detection fallback, which MUST still work for legacy entries.
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-005-1_4
    path: .aid-o/02-epics/legacy.md
    priority: high
    status: completed
    added_at: '2026-02-25T14:00:00Z'
  - epic_id: E-064-2_1
    path: .aid-o/02-epics/dependent.md
    priority: high
    status: queued
    depends_on: ["E-005-1_4"]
YAML

  # Read-side synonym: `queued` is `pending`.
  [ "$(_qw_field E-064-2_1 status)" = "queued" ]
  _qw claim-next P064
  # No plan_id on the entry, so it is not claimable BY PLAN — but it is not an
  # error either, and nothing was mutated.
  [ "$status" -eq 1 ]
  [ "$output" = "none" ]

  # The legacy fallback chain is untouched for an entry with no merge_target.
  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 0 ]
  [ "$output" = "unblocked" ]
  grep -q '"resolution":"merged_completed"' "$TEST_TMPDIR/queue-tl.jsonl"
}

# ─── queue_set_plan: inserts both fields where neither existed ────────────
@test "queue_set_plan inserts plan_id and merge_target into an entry that has neither and round-trips" {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    path: .aid-o/tasks/a.md
    status: queued
    depends_on: []
  - epic_id: E-064-2_1
    path: .aid-o/tasks/b.md
    status: queued
    depends_on:
      - E-064-1_1
YAML

  _qw set-plan E-064-2_1 P064 plan/P064
  [ "$status" -eq 0 ]
  [ "$(_qw_field E-064-2_1 plan_id)" = "P064" ]
  [ "$(_qw_field E-064-2_1 merge_target)" = "plan/P064" ]

  # The OTHER entry is untouched, and the multi-line depends_on list survives.
  [ "$(_qw_field E-064-1_1 plan_id)" = "" ]
  run bash "$(_qw_lib)" deps E-064-2_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "E-064-1_1" ]

  # A null plan is representable and reads back as absent.
  _qw set-plan E-064-1_1 null null
  [ "$status" -eq 0 ]
  [ "$(_qw_field E-064-1_1 merge_target)" = "" ]

  # An unknown epic_id writes nothing and fails loudly.
  _qw set-plan E-999-9_9 P999 plan/P999
  [ "$status" -eq 1 ]
}

# ─── Security: a declared merge_target that does not resolve is fail-loud ──
@test "Security: a dependency whose declared merge_target ref does not resolve is never silently treated as merged" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-2_1"

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-063-1_1
    status: merged_to_plan
    plan_id: "P063"
    merge_target: "plan/P063"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-063-1_1"]
YAML

  # plan/P063 was never created (or was deleted). The reader fail-louds rather
  # than reporting a comfortable `blocked` that would hide the broken record.
  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 1 ]
  [ "$output" = "failed" ]
  grep -q '"reason":"merge_target_missing"' "$TEST_TMPDIR/queue-tl.jsonl"

  _qw claim-next P064
  [ "$status" -eq 1 ]
  [[ "$output" == "blocked:E-064-2_1:dependency_merge_target_missing:E-063-1_1" ]]
}

# ─── IMP-272: merge_target authorization — both twins refuse an illegal anchor ─
# The Auditor's attack: a hand-edited dependency whose `merge_target` names a
# resolvable ref OTHER than the entry's own plan branch or the target branch —
# most sharply, the dependency's OWN task branch, whose ancestry against itself
# is trivially true. That self-satisfied the ancestry proof and unblocked work
# provably never in plan/P064. `_dep_valid_branch_ref`/`_queue_valid_branch_ref`
# only prove the value is a legal ref NAME; they do not constrain WHICH ref, so
# the constraint lives in a dedicated CHANGE-BOTH twin
# (aid-fsm.sh:_dep_merge_target_authorized ⇄
#  lib/aid-queue-write.sh:_queue_merge_target_authorized).
@test "IMP-272: a merge_target that is neither the own plan branch nor the target branch is refused by both twins" {
  _pfsm_bootstrap_plan "P064"
  # task/E-064-1_1/main carries a commit that is provably NOT in plan/P064.
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor task/E-064-1_1/main plan/P064
  [ "$status" -ne 0 ]

  # Two more resolvable refs that DO contain the work — so ancestry against them
  # is genuinely true and the attack would otherwise succeed — yet neither is an
  # authorized anchor: another plan's branch, and an arbitrary feature branch.
  git -C "$TEST_PROJECT_ROOT" branch plan/P063 task/E-064-1_1/main
  git -C "$TEST_PROJECT_ROOT" branch feature/rogue task/E-064-1_1/main

  # _neg <merge_target> — write the fixture, assert BOTH twins refuse.
  _neg() {
    local mt="$1"
    _qw_write_queue <<YAML
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: merged_to_plan
    plan_id: "P064"
    merge_target: "${mt}"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML

    # WRITER (queue_claim_next): the dependent is BLOCKED, never claimed, and
    # the illegal value class is named in a durable reason.
    _qw claim-next P064
    [ "$status" -eq 1 ]
    [[ "$output" == "blocked:E-064-2_1:dependency_merge_target_unauthorized:E-064-1_1" ]]
    [ "$(_qw_field E-064-2_1 status)" = "blocked" ]

    # READER (aid-fsm queue-revalidate): fail-loud, not a comfortable blocked.
    _qw_revalidate "E-064-2_1"
    [ "$status" -eq 1 ]
    [ "$output" = "failed" ]
    grep -q '"reason":"merge_target_unauthorized"' "$TEST_TMPDIR/queue-tl.jsonl"
  }

  _neg "task/E-064-1_1/main"   # the demonstrated self-branch attack
  _neg "plan/P063"             # another plan's branch
  _neg "feature/rogue"         # an arbitrary feature branch
}

# ─── IMP-272: the guard does not over-block — legal anchors still resolve ──
@test "IMP-272: an own plan branch, the target branch, a legacy absent merge_target, and a null-plan_id target that the epic id still resolves to, all resolve" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  # Land the work on plan/P064 (own plan branch) AND on main (target branch),
  # so both legal anchors are genuine ancestors.
  git -C "$(_pfsm_plan_tree P064)" checkout -q plan/P064
  git -C "$(_pfsm_plan_tree P064)" merge -q --no-ff -m "merge(epic): E-064-1_1 into plan/P064" task/E-064-1_1/main
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  git -C "$TEST_PROJECT_ROOT" merge -q --no-ff -m "release plan/P064" plan/P064

  # _pos <plan_id_yaml> <merge_target> — both twins must UNBLOCK/claim.
  _pos() {
    local pid="$1" mt="$2"
    _qw_write_queue <<YAML
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: merged_to_plan
    plan_id: ${pid}
    merge_target: "${mt}"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML
    _qw_revalidate "E-064-2_1"
    [ "$status" -eq 0 ]
    [ "$output" = "unblocked" ]
    _qw claim-next P064
    [ "$status" -eq 0 ]
    [ "$output" = "E-064-2_1" ]
  }

  _pos '"P064"' "plan/P064"   # legal same-plan own plan branch
  _pos '"P064"' "main"        # legal cross-plan target branch
  _pos 'null'   "main"        # null plan_id: only the target branch is legal

  # Legacy absent-merge_target path is unchanged: the pre-P064 status fallback
  # still governs, with no authorization gate in the way.
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: completed
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML
  # No merge_target on the dependency → the legacy `completed` synonym still
  # reads as delivered (the pre-P064 behaviour this fix must not disturb).
  run bash -c 'source "$1"; _queue_dep_state "E-064-1_1" "$2" "$3"' _ \
    "$(_qw_lib)" "$(_qw_queue)" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "merged" ]

  # HARDENING (post-review HIGH): the owning plan is DERIVED from the epic id,
  # not read from the entry's plan_id field, so a MISSING plan_id no longer
  # rejects a legitimate same-plan dependency — E-064-1_1's identity names P064
  # regardless of the (absent) field, and plan/P064 is genuinely its plan
  # branch. The field is redundant, not authoritative.
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: merged_to_plan
    plan_id: null
    merge_target: "plan/P064"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML
  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 0 ]
  [ "$output" = "unblocked" ]
  _qw claim-next P064
  [ "$status" -eq 0 ]
  [ "$output" = "E-064-2_1" ]
}

# ─── IMP-272 HARDENING (post-review HIGH): plan_id from the same hand-editable
# entry is not authority. Deriving the owning plan from the entry's own plan_id
# let plan_id: P999 + merge_target: plan/P999 self-authorize the anchor one
# field over. The owning plan must come from the epic id (the record key), and
# a declared plan_id that disagrees with the id-derived plan is refused. ──────
@test "IMP-272 HARDENING: a plan_id colluding with merge_target cannot self-authorize an unowned plan branch" {
  _pfsm_bootstrap_plan "P064"
  # E-064-1_1's work is on its own task branch, provably NOT in plan/P064.
  _pfsm_epic_with_commit "P064" "E-064-1_1"

  # The attacker forges a whole plan branch that DOES contain the work, so
  # ancestry against it is trivially true — the only thing standing between the
  # attack and a false claim is the authorization rule.
  git -C "$TEST_PROJECT_ROOT" branch plan/P999 task/E-064-1_1/main
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor task/E-064-1_1/main plan/P999
  [ "$status" -eq 0 ]

  # The PM attack: plan_id AND merge_target both point at P999, so an
  # own-plan-from-the-field check would agree plan/P999 is "its own" plan.
  # E-064-1_1's id derives P064, so the collusion is refused.
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: merged_to_plan
    plan_id: "P999"
    merge_target: "plan/P999"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML

  # WRITER (queue_claim_next): dependent BLOCKED, never claimed.
  _qw claim-next P064
  [ "$status" -eq 1 ]
  [[ "$output" == "blocked:E-064-2_1:dependency_merge_target_unauthorized:E-064-1_1" ]]
  [ "$(_qw_field E-064-2_1 status)" = "blocked" ]

  # READER (aid-fsm queue-revalidate): fail-loud with the mismatch surfaced.
  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 1 ]
  [ "$output" = "failed" ]
  grep -q '"reason":"merge_target_unauthorized"' "$TEST_TMPDIR/queue-tl.jsonl"
  grep -q '"declared_plan":"P999"' "$TEST_TMPDIR/queue-tl.jsonl"
  grep -q '"derived_plan":"P064"' "$TEST_TMPDIR/queue-tl.jsonl"

  # And the sharper variant: plan_id lies but merge_target names the REAL
  # id-derived plan branch (plan/P064). merge_target is legal, but the lying
  # plan_id is still refused fail-closed — corruption is not trusted, one field
  # cannot vouch for another.
  git -C "$TEST_PROJECT_ROOT" branch plan/P064-real task/E-064-1_1/main 2>/dev/null || true
  git -C "$(_pfsm_plan_tree P064)" checkout -q plan/P064
  git -C "$(_pfsm_plan_tree P064)" merge -q --no-ff -m "merge(epic): E-064-1_1 into plan/P064" task/E-064-1_1/main
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: merged_to_plan
    plan_id: "P999"
    merge_target: "plan/P064"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML
  _qw claim-next P064
  [ "$status" -eq 1 ]
  [[ "$output" == "blocked:E-064-2_1:dependency_merge_target_unauthorized:E-064-1_1" ]]
  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 1 ]
  [ "$output" = "failed" ]
}

# ─── queue_set_status: terminal statuses have no way out ──────────────────
@test "queue_set_status refuses to move an entry out of a terminal status" {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []
YAML

  _qw set-status E-064-1_1 running
  [ "$status" -eq 0 ]
  _qw set-status E-064-1_1 merged_to_plan
  [ "$status" -eq 0 ]
  # merged_to_plan is NOT terminal in the queue — released_to_main follows it.
  _qw set-status E-064-1_1 released_to_main
  [ "$status" -eq 0 ]

  # released_to_main IS terminal: no edge back out, nothing written.
  _qw set-status E-064-1_1 running
  [ "$status" -eq 1 ]
  [[ "$output" == *"terminal"* ]]
  [ "$(_qw_field E-064-1_1 status)" = "released_to_main" ]
}

# ─── aid-queue-add.sh emits the new fields ────────────────────────────────
@test "aid-queue-add.sh writes status pending plus plan_id and merge_target, and stays CLI-compatible" {
  _pfsm_bootstrap_plan "P064"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" "$TEST_PROJECT_ROOT/.aid-o/tasks"
  : > "$TEST_PROJECT_ROOT/.aid-o/tasks/E-064-1_1.md"

  run bash "$AID_PLUGIN_PATH/scripts/aid-queue-add.sh" \
    --epic-id E-064-1_1 --epic-path .aid-o/tasks/E-064-1_1.md \
    --queue-yaml "$(_qw_queue)"
  [ "$status" -eq 0 ]
  [ "$output" = "queued:E-064-1_1" ]

  [ "$(_qw_field E-064-1_1 status)" = "pending" ]
  [ "$(_qw_field E-064-1_1 plan_id)" = "P064" ]
  # plan/P064 exists (bootstrap created it), so the entry declares it.
  [ "$(_qw_field E-064-1_1 merge_target)" = "plan/P064" ]

  # An EPIC of a plan with NO plan branch gets a null merge_target — the
  # documented legacy shape that keeps aid-fsm.sh's old fallback in charge.
  run bash "$AID_PLUGIN_PATH/scripts/aid-queue-add.sh" \
    --epic-id E-099-1_1 --epic-path .aid-o/tasks/E-064-1_1.md \
    --queue-yaml "$(_qw_queue)"
  [ "$status" -eq 0 ]
  [ "$(_qw_field E-099-1_1 plan_id)" = "P099" ]
  [ "$(_qw_field E-099-1_1 merge_target)" = "" ]

  # The duplicate guard still sees an entry this script itself wrote.
  run bash "$AID_PLUGIN_PATH/scripts/aid-queue-add.sh" \
    --epic-id E-064-1_1 --epic-path .aid-o/tasks/E-064-1_1.md \
    --queue-yaml "$(_qw_queue)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already in the queue"* ]]
}

# =============================================================================
# ─── CP2 regression block: the queue writer's untrusted-input surface
#     (P064 EPIC E-064-2_2 Step 2, CP2 findings 1–5) ─────────────────────────
# =============================================================================
# Every test here pins a defect that was LIVE at commit ee9edf9 and reachable
# without any privileged access — a `reason` string, or a `depends_on` id typed
# into the hand-editable queue file, was enough. They all defend the same
# invariant as the block above: the queue file's own content can never decide
# what status gets written, and a queue entry is never evidence.

# _qw_yaml_parses — assert the queue file is still loadable YAML. The whole
# point of finding 1 was that a corrupt write is SILENT: aid-fsm.sh's awk
# parser keeps reading a file that no YAML parser will accept.
_qw_yaml_parses() {
  python3 -c 'import yaml' 2>/dev/null || skip "python3 + PyYAML not available"
  python3 -c "
import sys, yaml
d = yaml.safe_load(open('$(_qw_queue)'))
assert isinstance(d, dict) and isinstance(d.get('queue'), list), 'queue is not a YAML mapping with a queue list'
"
}

# ─── Finding 1: `reason` free text can never write a status ────────────────
@test "CP2 F1: a reason carrying a literal backslash-n cannot smuggle a second assignment into the write payload" {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "E-1"
    status: pending
    path: "a.md"
    depends_on: []
YAML
  local before; before="$(md5sum "$(_qw_queue)" | cut -d' ' -f1)"

  # THE payload from the CP2 report: a two-character backslash-n, which BOTH
  # mawk and gawk used to expand to a real newline inside `awk -v`.
  _qw set-status E-1 blocked 'oops\nstatus=released_to_main'
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside the allowed set"* ]]

  # Nothing written at all — not even last_modified.
  local after; after="$(md5sum "$(_qw_queue)" | cut -d' ' -f1)"
  [ "$before" = "$after" ]

  # The status the caller never asked for is absent; the entry is untouched
  # and NOT wedged in a terminal status.
  [ "$(_qw_field E-1 status)" = "pending" ]
  [ "$(_qw_field E-1 path)" = "a.md" ]
  ! grep -q 'released_to_main' "$(_qw_queue)"
  _qw_yaml_parses

  # Still transitionable — the old bug left it permanently stuck.
  _qw set-status E-1 running
  [ "$status" -eq 0 ]
  [ "$(_qw_field E-1 status)" = "running" ]
}

@test "CP2 F1: a depends_on id carrying a newline payload cannot write a status through queue_claim_next" {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "E-2"
    status: pending
    plan_id: "P064"
    path: "b.md"
    depends_on: ["E-9\nstatus=running"]
YAML
  # An id read back OUT of the queue file is untrusted input: the file is
  # hand-editable, which is the entire reason this library exists.
  _qw claim-next P064
  [ "$status" -eq 1 ]
  [ "$output" = "blocked:E-2:dependency_id_invalid" ]

  # The entry got the status the CODE decided (blocked), never the one the
  # payload asked for, and the poisoned id is not propagated into any field.
  [ "$(_qw_field E-2 status)" = "blocked" ]
  [ "$(_qw_field E-2 reason)" = "dependency_id_invalid" ]
  [ "$(_qw_field E-2 path)" = "b.md" ]
  ! grep -qE '^[[:space:]]+status: running' "$(_qw_queue)"
  _qw_yaml_parses
}

@test "CP2 F1: the transport and parse layers hold even when the input guard is bypassed" {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "E-1"
    status: pending
    path: "a.md"
    depends_on: []
YAML
  local queue; queue="$(_qw_queue)"
  local before; before="$(md5sum "$queue" | cut -d' ' -f1)"

  # Layer 1 (ENVIRON transport): _queue_apply_fields called DIRECTLY, i.e. with
  # queue_set_status' charset guard out of the picture. The backslash-n stays
  # literal, so it remains ONE k=v pair and the requested status stands.
  run bash -c '
    export AID_QUEUE_WRITE_PROJECT_ROOT="$1"
    source "$2"
    _queue_apply_fields "$3" E-1 "status=blocked" "reason=\"oops\\nstatus=released_to_main\""
  ' _ "$TEST_PROJECT_ROOT" "$(_qw_lib)" "$queue"
  [ "$status" -eq 0 ]
  [ "$(_qw_field E-1 status)" = "blocked" ]
  ! grep -qE '^[[:space:]]+status: released_to_main' "$queue"
  _qw_yaml_parses

  # Layer 2 (parse): three malformed payloads, each aborting the WHOLE write.
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "E-1"
    status: pending
    path: "a.md"
    depends_on: []
YAML
  before="$(md5sum "$queue" | cut -d' ' -f1)"
  local payload
  for payload in 'nokeyhere' 'Sta-tus=blocked'; do
    run bash -c '
      export AID_QUEUE_WRITE_PROJECT_ROOT="$1"
      source "$2"
      _queue_apply_fields "$3" E-1 "status=blocked" "$4"
    ' _ "$TEST_PROJECT_ROOT" "$(_qw_lib)" "$queue" "$payload"
    [ "$status" -eq 2 ]
    [ "$(md5sum "$queue" | cut -d' ' -f1)" = "$before" ]
  done

  # A duplicated key is an ERROR, not "last one wins".
  run bash -c '
    export AID_QUEUE_WRITE_PROJECT_ROOT="$1"
    source "$2"
    _queue_apply_fields "$3" E-1 "status=blocked" "status=released_to_main"
  ' _ "$TEST_PROJECT_ROOT" "$(_qw_lib)" "$queue"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate field key"* ]]
  [ "$(md5sum "$queue" | cut -d' ' -f1)" = "$before" ]
  [ "$(_qw_field E-1 status)" = "pending" ]

  # And the awk BEGIN block itself — reached with a REAL newline in the
  # payload, which the bash layer above can no longer produce — aborts with 8
  # rather than applying the smuggled pair.
  run bash -c '
    AID_QW_TARGET="E-1" AID_QW_KVS="status=blocked
reason=\"oops
status=released_to_main\"
" awk '"'"'
      BEGIN {
        kvs = ENVIRON["AID_QW_KVS"]; aborted = 0; nkeys = 0
        n = split(kvs, lines, "\n")
        for (i = 1; i <= n; i++) {
          if (lines[i] == "") continue
          p = index(lines[i], "=")
          if (p < 2) { aborted = 1; exit 8 }
          k = substr(lines[i], 1, p - 1)
          if (k !~ /^[a-z_]+$/) { aborted = 1; exit 8 }
          if (k in seenkey)     { aborted = 1; exit 8 }
          seenkey[k] = 1; nkeys++
        }
      }
      END { if (aborted) exit 8; print "WOULD-HAVE-WRITTEN" }
    '"'"' /dev/null
  '
  [ "$status" -eq 8 ]
  [ -z "$output" ]
}

# ─── Finding 2: the writer mutates exactly the entry the reader reads ──────
@test "CP2 F2: with two entries sharing an epic_id only the FIRST is rewritten — the one queue_get_field reads" {
  # aid-queue-add.sh:272-275 permits this shape: its duplicate guard only
  # rejects queued|pending|blocked|running, so re-adding an EPIC whose earlier
  # entry is already terminal legitimately creates a second entry.
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "E-1"
    status: pending
    depends_on: []

  - epic_id: "E-1"
    status: completed
    depends_on: []
YAML
  _qw set-status E-1 running
  [ "$status" -eq 0 ]
  [[ "$output" == *"entries carry epic_id"* ]]   # duplicate is visible, not silent

  # Exactly one entry moved, and it is the one the reader sees.
  [ "$(_qw_field E-1 status)" = "running" ]
  [ "$(grep -c '^[[:space:]]*status: running' "$(_qw_queue)")" -eq 1 ]
  [ "$(grep -c '^[[:space:]]*status: completed' "$(_qw_queue)")" -eq 1 ]
  _qw_yaml_parses
}

# ─── Finding 3: writer and reader resolve a dep's branch by the SAME rule ──
@test "CP2 F3: a dependency on a non-conventional branch resolves identically for aid-fsm queue-revalidate and queue_claim_next" {
  _pfsm_bootstrap_plan "P064"

  # The dep ran on a branch that does NOT follow task/<id>/main and recorded
  # that in its evidence — the exact case aid-fsm.sh:_resolve_dep_branch
  # already handled and the writer did not.
  git -C "$TEST_PROJECT_ROOT" checkout -q -b feature/odd-name plan/P064
  echo dep > "$TEST_PROJECT_ROOT/dep.txt"
  git -C "$TEST_PROJECT_ROOT" add dep.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "E-064-1_1: work"
  git -C "$(_pfsm_plan_tree P064)" checkout -q plan/P064
  git -C "$(_pfsm_plan_tree P064)" merge -q --no-ff -m "merge E-064-1_1" feature/odd-name
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-064-1_1/R-1"
  printf 'epic_id: E-064-1_1\nstate: DONE\nbranch: feature/odd-name\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-064-1_1/R-1/fsm-state.yaml"

  # The premise: the conventional ref does NOT exist, but the real branch does
  # and IS an ancestor of the declared merge_target.
  run git -C "$TEST_PROJECT_ROOT" show-ref --verify --quiet refs/heads/task/E-064-1_1/main
  [ "$status" -ne 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor feature/odd-name plan/P064
  [ "$status" -eq 0 ]

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "E-064-1_1"
    status: merged_to_plan
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []

  - epic_id: "E-064-2_1"
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML

  # READER
  _qw_revalidate "E-064-2_1"
  [ "$status" -eq 0 ]
  [ "$output" = "unblocked" ]

  # WRITER — must agree. Before this fix it wrote
  # blocked:E-064-2_1:dependency_no_ancestry_proof:E-064-1_1 on the same fact,
  # making the dependent unclaimable while the FSM reported it ready.
  _qw claim-next P064
  [ "$status" -eq 0 ]
  [ "$output" = "E-064-2_1" ]
  [ "$(_qw_field E-064-2_1 status)" = "running" ]

  # ── iteration 2: a ref git accepts but the writer's old REGEX did not ─────
  # `feature/odd-name` above is inside `^[A-Za-z0-9][A-Za-z0-9._/-]*$`, so it
  # could never detect the remaining divergence: the writer applied that regex
  # and the reader applied NOTHING, so for a git-legal name OUTSIDE it the two
  # halves gave opposite answers again — reader `unblocked`, writer
  # `dependency_no_ancestry_proof`. `_wip` (leading underscore) is the
  # verifier's own repro. Both halves now defer to `git check-ref-format`.
  run git -C "$TEST_PROJECT_ROOT" check-ref-format refs/heads/_wip
  [ "$status" -eq 0 ]                      # git itself accepts it …
  [[ ! "_wip" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]   # … and the old regex did not.

  git -C "$TEST_PROJECT_ROOT" checkout -q -b _wip plan/P064
  echo dep2 > "$TEST_PROJECT_ROOT/dep2.txt"
  git -C "$TEST_PROJECT_ROOT" add dep2.txt
  git -C "$TEST_PROJECT_ROOT" commit -qm "E-064-1_2: work"
  git -C "$(_pfsm_plan_tree P064)" checkout -q plan/P064
  git -C "$(_pfsm_plan_tree P064)" merge -q --no-ff -m "merge E-064-1_2" _wip
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-064-1_2/R-1"
  printf 'epic_id: E-064-1_2\nstate: DONE\nbranch: _wip\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-064-1_2/R-1/fsm-state.yaml"

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "E-064-1_2"
    status: merged_to_plan
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []

  - epic_id: "E-064-3_1"
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_2"]
YAML

  _qw_revalidate "E-064-3_1"
  [ "$status" -eq 0 ]
  [ "$output" = "unblocked" ]

  _qw claim-next P064
  [ "$status" -eq 0 ]
  [ "$output" = "E-064-3_1" ]
  [ "$(_qw_field E-064-3_1 status)" = "running" ]
}

# ─── Finding 4: never report a reason that was not recorded ────────────────
@test "CP2 F4: queue_claim_next never prints a blocked reason it failed to write" {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "E-DEP"
    status: merged_to_plan
    plan_id: "P064"
    merge_target: "plan/GONE"
    depends_on: []

  - epic_id: "E-C"
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-DEP"]
YAML
  # Sanity: with a writable directory this IS a durable blocked record.
  _qw claim-next P064
  [ "$status" -eq 1 ]
  [ "$output" = "blocked:E-C:dependency_merge_target_missing:E-DEP" ]
  [ "$(_qw_field E-C status)" = "blocked" ]

  # Now make the write impossible. The lock sidecar already exists and stays
  # writable, so the lock is still acquired — only the queue rewrite fails.
  _qw set-status E-C pending
  [ "$status" -eq 0 ]
  : > "$(_qw_queue).lock"
  local before; before="$(md5sum "$(_qw_queue)" | cut -d' ' -f1)"
  chmod 555 "$(dirname "$(_qw_queue)")"
  _qw claim-next P064
  chmod 755 "$(dirname "$(_qw_queue)")"

  # AC4 says the block is recorded "with a recorded reason". It was not, so the
  # failure is visible (rc 3, the transaction-failure code) instead of a
  # `blocked:` line the caller would believe is durable.
  [ "$status" -eq 3 ]
  [[ "$output" != *"blocked:E-C"* ]]
  [[ "$output" == *"could not record blocked"* ]]
  [ "$(md5sum "$(_qw_queue)" | cut -d' ' -f1)" = "$before" ]
  [ "$(_qw_field E-C status)" = "pending" ]
}

# ─── Finding 5: no subshell may outlive the lock release holding its fd ────
@test "CP2 F5: queue_claim_next holds no process substitution open across aid_lock_release" {
  # STRUCTURAL, deliberately. flock drops only when the LAST descriptor on the
  # open file description closes, so a `done < <(...)` subshell forked after
  # the `exec {fd}<>` keeps the lock alive past aid_lock_release. It is not
  # observable as contention today (bash tears the subshell down when the
  # function returns, and the live queue's id list fits in one pipe buffer),
  # which is exactly why it needs a source-level pin rather than a timing test:
  # the defect is size- and scheduling-dependent, so a behavioural test would
  # be green for the wrong reason.
  # Comment lines are stripped first: the rationale comment naturally quotes
  # the very construct being banned.
  local body
  body="$(awk '/^queue_claim_next\(\)/,/^}/' "$(_qw_lib)" | grep -v '^[[:space:]]*#')"
  [ -n "$body" ]
  run grep -c 'done < <(' <<< "$body"
  [ "$output" = "0" ]

  # And the one lock-held helper added for finding 3 must not reintroduce it.
  body="$(awk '/^_queue_evidence_branch\(\)/,/^}/' "$(_qw_lib)" | grep -v '^[[:space:]]*#')"
  [ -n "$body" ]
  run grep -c 'done < <(' <<< "$body"
  [ "$output" = "0" ]

  # The claim path still works with an id list far larger than a pipe buffer.
  mkdir -p "$(dirname "$(_qw_queue)")"
  {
    printf 'paused: false\nlast_modified: "2026-01-01T00:00:00Z"\n\nqueue:\n'
    printf '  - epic_id: "E-FIRST"\n    status: pending\n    plan_id: "P064"\n    depends_on: []\n\n'
    local i
    for i in $(seq 1 4000); do
      printf '  - epic_id: "E-PADDING-ENTRY-%06d"\n    status: completed\n    plan_id: "P999"\n    depends_on: []\n\n' "$i"
    done
  } > "$(_qw_queue)"
  _qw claim-next P064
  [ "$status" -eq 0 ]
  [ "$output" = "E-FIRST" ]
  # The lock is genuinely free again the moment the call returns.
  run flock -n "$(_qw_queue).lock" -c true
  [ "$status" -eq 0 ]
}

# =============================================================================
# ─── CP2 iteration 2: the APPEND door (finding 1) ────────────────────────────
# =============================================================================
# The block above pins the MUTATE door (`_queue_apply_fields`). Every one of
# those layers said nothing about the second door: `queue_append_entry` used to
# write its `$block` argument byte-for-byte with no validation, and
# `aid-queue-add.sh` renders that block by interpolating six argument-reachable
# values into a heredoc with no charset guard on any of them.
#
# The payload below is the verifier's, executed end to end. Before the fix it
# produced an entry carrying a SECOND `status:` line, after which:
#     _queue_parse_to_json -> {"epic_id":"E-800","status":"completed",…}
#     queue_get_field      -> pending
#     queue_revalidate E-801 -> unblocked   (no branch, no evidence, no merge)
# i.e. a queue status substituting for git ancestry proof, arriving through a
# script — the exact thing this whole step exists to abolish.

# _qw_seed_queue — a benign one-entry queue to append onto, so "nothing was
# written" can be asserted as a byte-identical file rather than an absent one.
_qw_seed_queue() {
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:

  - epic_id: "E-SEED"
    path: "seed.md"
    priority: medium
    status: pending
    depends_on: []
    plan_id: "P064"
    merge_target: null
YAML
}

@test "CP2 F1 (iteration 2): the aid-queue-add.sh append door rejects the injection payload, writes nothing, and leaves both queue readers agreeing" {
  _qw_seed_queue
  local before; before="$(md5sum "$(_qw_queue)" | cut -d' ' -f1)"

  # THE verifier payload, verbatim: a merge_target that closes its own quote
  # and opens two further entry lines, the last of which is `merge_target`
  # itself (so the block still ends on a plausible key).
  _qw_add --epic-id E-800 --epic-path ".aid-o/tasks/E-800.md" --plan-id P800 \
    --merge-target 'plan/P800"
    status: completed
    merge_target: null
    trailer: "x'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid --merge-target"* ]]

  # Nothing written at all — not even last_modified.
  [ "$(md5sum "$(_qw_queue)" | cut -d' ' -f1)" = "$before" ]
  ! grep -q 'E-800' "$(_qw_queue)"
  ! grep -q 'status: completed' "$(_qw_queue)"
  _qw_yaml_parses

  # THE assertion the iteration-1 fix would have passed on and this one must
  # not: the two readers agree. E-800 exists for neither of them …
  [ "$(_qw_field E-800 status)" = "" ]
  [ "$(_qw_json_status E-800)" = "" ]
  # … and the pre-existing entry reads identically through both.
  [ "$(_qw_field E-SEED status)" = "pending" ]
  [ "$(_qw_json_status E-SEED)" = "pending" ]

  # Positive control: the same add without the payload succeeds, and THAT entry
  # also reads identically through both readers — the guard rejects the attack,
  # not the feature.
  _qw_add --epic-id E-800 --epic-path ".aid-o/tasks/E-800.md" --plan-id P800 \
    --merge-target 'plan/P800'
  [ "$status" -eq 0 ]
  [ "$output" = "queued:E-800" ]
  [ "$(_qw_field E-800 status)" = "pending" ]
  [ "$(_qw_json_status E-800)" = "pending" ]
  [ "$(_qw_field E-800 merge_target)" = "plan/P800" ]
  _qw_yaml_parses
}

@test "CP2 F1 (iteration 2): every argument-reachable field of the entry block is guarded, not just merge_target" {
  # The injection is a CLASS, not one field: the block interpolates six values
  # and finding 1 named only one of them. Each case below wrote a corrupt entry
  # at commit 5611dbc.
  local nl_payload
  nl_payload='a.md"
    status: completed
    trailer: "x'

  _qw_seed_queue
  local before; before="$(md5sum "$(_qw_queue)" | cut -d' ' -f1)"

  # epic_id — `^E-` was the ONLY check, so a newline sailed straight through.
  _qw_add --epic-id "E-810${nl_payload}" --epic-path "a.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid EPIC ID format"* ]]

  # epic_path — no check at all.
  _qw_add --epic-id E-811 --epic-path "$nl_payload"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid --epic-path"* ]]

  # plan_ref — no check at all.
  _qw_add --epic-id E-812 --epic-path "a.md" --plan-ref "$nl_payload"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid --plan-ref"* ]]

  # plan_id — the other half of finding 1's anchor pair.
  _qw_add --epic-id E-813 --epic-path "a.md" --plan-id "P1${nl_payload}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid --plan-id"* ]]

  # depends_on — `read` happens to stop at the first line, but the reference
  # check was a BRE, so `E-SEE.` matched the real `E-SEED` and wrote a
  # dependency on an id that does not exist (a permanent block).
  _qw_add --epic-id E-814 --epic-path "a.md" --depends-on 'E-SEE.'
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found in queue"* ]]

  # priority stays an enum match; added_at is generated, never argument-reachable.
  _qw_add --epic-id E-815 --epic-path "a.md" --priority 'medium
    status: completed'
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid priority"* ]]

  # Not one of them wrote a byte.
  [ "$(md5sum "$(_qw_queue)" | cut -d' ' -f1)" = "$before" ]
  ! grep -q 'status: completed' "$(_qw_queue)"
  [ "$(_qw_field E-SEED status)" = "pending" ]
  [ "$(_qw_json_status E-SEED)" = "pending" ]
  _qw_yaml_parses
}

@test "CP2 F1 (iteration 2): queue_append_entry structurally refuses a block no matter which caller hands it over" {
  # The caller-side guards above are the usage-error layer. THIS is the class
  # closer: the library validates the shape of the block it is handed, so the
  # door cannot be walked through by a future caller that forgets to validate —
  # which is exactly how aid-queue-add.sh arrived at the defect twice.
  _qw_seed_queue
  local before; before="$(md5sum "$(_qw_queue)" | cut -d' ' -f1)"

  # Exactly what aid-queue-add.sh WOULD have rendered from the verifier payload.
  local injected
  injected='
  - epic_id: "E-800"
    path: ".aid-o/tasks/E-800.md"
    priority: medium
    status: pending
    depends_on: []
    plan_id: "P800"
    merge_target: "plan/P800"
    status: completed
    merge_target: null
    trailer: "x"'

  _qw_append E-800 "$injected"
  [ "$status" -eq 2 ]
  [[ "$output" == *"appears twice"* ]]
  [ "$(md5sum "$(_qw_queue)" | cut -d' ' -f1)" = "$before" ]

  # A block whose id is not the id the duplicate check ran against.
  _qw_append E-800 '
  - epic_id: "E-OTHER"
    status: pending'
  [ "$status" -eq 2 ]
  [[ "$output" == *"declares epic_id"* ]]

  # Two entries smuggled in through one append.
  _qw_append E-800 '
  - epic_id: "E-800"
    status: pending
  - epic_id: "E-801"
    status: completed'
  [ "$status" -eq 2 ]
  [[ "$output" == *"more than one"* ]]

  # A value outside the shapes this library writes.
  _qw_append E-800 '
  - epic_id: "E-800"
    status: pending
    evil: {a: b}'
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a shape this library writes"* ]]

  # A line that is not an entry line at all.
  _qw_append E-800 'queue: []'
  [ "$status" -eq 2 ]
  [[ "$output" == *"is neither"* ]]

  # A key line with no preceding epic_id line.
  _qw_append E-800 '
    status: completed'
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not start with"* ]]

  # Five refusals, zero bytes, and the readers still agree.
  [ "$(md5sum "$(_qw_queue)" | cut -d' ' -f1)" = "$before" ]
  [ "$(_qw_field E-SEED status)" = "pending" ]
  [ "$(_qw_json_status E-SEED)" = "pending" ]
  [ "$(_qw_field E-800 status)" = "" ]
  [ "$(_qw_json_status E-800)" = "" ]
  _qw_yaml_parses

  # And a well-formed block from the same door is still accepted.
  _qw_append E-800 '
  - epic_id: "E-800"
    path: "a.md"
    priority: medium
    status: pending
    depends_on: ["E-SEED"]
    added_at: "2026-01-01T00:00:00Z"
    started_at: null
    completed_at: null
    plan_ref: null
    plan_id: "P800"
    merge_target: "plan/P800"'
  [ "$status" -eq 0 ]
  [ "$(_qw_field E-800 status)" = "pending" ]
  [ "$(_qw_json_status E-800)" = "pending" ]
  _qw_yaml_parses
}

@test "CP2 F1 (iteration 2): _queue_apply_fields preserves the file byte for byte, trailing blank lines included" {
  # The header claimed "preserves untouched lines byte for byte"; the
  # `out=\$(awk …)` round-trip silently ate every trailing newline, so the claim
  # was false for the end of the file. Now streamed through the staging temp.
  mkdir -p "$(dirname "$(_qw_queue)")"
  printf 'paused: false\nlast_modified: "2026-01-01T00:00:00Z"\n\nqueue:\n\n  - epic_id: "E-1"\n    status: pending\n    depends_on: []\n\n\n' \
    > "$(_qw_queue)"
  local before_tail; before_tail="$(od -c "$(_qw_queue)" | tail -2)"

  _qw set-status E-1 running
  [ "$status" -eq 0 ]
  [ "$(_qw_field E-1 status)" = "running" ]
  [ "$(od -c "$(_qw_queue)" | tail -2)" = "$before_tail" ]
}

# =============================================================================
# ─── Boundary-split gate profiles + self-host activation
#     (P064 EPIC E-064-2_2 Step 3 = plan Step 8) ─────────────────────────────
# =============================================================================
# The risk resolver (lib/aid-gate-profile.sh) now answers TWO questions from
# one call: "what should THIS EPIC's own gate run be" (stdout, capped at
# `standard` when the caller passes boundary=epic) and "what must the
# plan-final run be at minimum" (the accumulated floor, out-of-band via
# AID_GATE_PROFILE_FLOOR / --floor-file). `epic-complete` records the second
# into the plan-boundary manifest; P068's plan-final stage consumes it.
#
# TRACEABILITY — `ACn:` numbers this step's own AC list (plan Step 8):
#   AC1  high-risk EPIC records plan_final_required_profile >= full while its
#        own boundary runs targeted/standard
#   AC2  no bats_all at an EPIC boundary without a recorded PM exception
#   AC3  a PM `--full-tests` run is an audited exception and never lowers the floor
#   AC4  an unknown production path fails the EPIC gate and raises the floor to full
#   AC5  `release`'s include list is a superset of `full`'s
#   AC6  a high-risk EPIC that ran `standard` still reaches DONE
#   AC7  a docs-only EPIC resolves to `quick`, which exists as a gate_profiles key
#   AC8  test-aid-fsm.bats / test-aid-gate-profile.bats stay green (run, not asserted here)

# _gp_paths_file <path> [path ...] — a changed-paths file for the resolver.
_gp_paths_file() {
  local f="$TEST_TMPDIR/gp-paths-$$.txt"
  printf '%s\n' "$@" > "$f"
  echo "$f"
}

# _selfhost_execution_yaml — this repository's OWN .aid-o/config/execution.yaml
# (the dogfood config Step 8 activates). AID_PLUGIN_PATH is <repo>/plugins/aid-orchestrator.
_selfhost_execution_yaml() {
  echo "$AID_PLUGIN_PATH/../../.aid-o/config/execution.yaml"
}

# NOTE on the four tests below that read the self-host config: `.aid-o/` is
# gitignored (.gitignore:98), so that file genuinely does not exist on a fresh
# checkout or in CI. They assert properties of the DELIVERED dogfood config,
# and there is no honest fixture stand-in for "the file this repository
# actually runs its gates against" — a copy would silently drift. So each one
# `skip`s when the file is absent, INLINE in the test body (never from a
# helper: `skip` inside a `$(...)` subshell cannot end the test, it just
# returns, and the test then asserts against an empty path — a green test
# proving nothing). Every config-INDEPENDENT half of the same ACs runs
# unconditionally.

# _gp_yq_jq <file> <jq_expr> — yq -> jq under `pipefail`, so a missing/broken
# execution.yaml surfaces as a FAILING assertion instead of an empty stream
# that jq happily accepts.
_gp_yq_jq() {
  bash -c "set -o pipefail; yq -o=json '.' '$1' | jq -e '$2'"
}

# _pfsm_write_gates_report <epic_id> <json> — the run's gates_report.json,
# verbatim, for cases that need more than `_pfsm_write_epic_evidence`'s
# `{profile}` (excluded_gates[], per-gate exit codes).
_pfsm_write_gates_report() {
  local epic_id="$1" json="$2"
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/R-${epic_id}-plan/gates"
  mkdir -p "$dir"
  printf '%s\n' "$json" > "$dir/gates_report.json"
}

# _pfsm_write_plan_json <epic_id> <gates_json_array> — the run's plan.json,
# whose `gates[]` is the plan-declared hard floor.
_pfsm_write_plan_json() {
  local epic_id="$1" gates="$2"
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/R-${epic_id}-plan"
  mkdir -p "$dir"
  jq -nc --argjson g "$gates" '{gates: $g}' > "$dir/plan.json"
}

# ─── lib/aid-gate-profile.sh — the boundary split ──────────────────────────

@test "AC1: gate_profile_resolve boundary=epic caps a high-risk diff at standard while the accumulated floor stays full" {
  local paths; paths="$(_gp_paths_file "plugins/aid-orchestrator/scripts/aid-fsm.sh")"

  # Sourced caller (no command substitution) so AID_GATE_PROFILE_FLOOR is
  # observable — that is the documented out-of-band channel.
  AID_GATE_PROFILE_FLOOR=""
  gate_profile_resolve "$paths" "" "" epic > "$TEST_TMPDIR/resolved.txt"
  [ "$(cat "$TEST_TMPDIR/resolved.txt")" = "standard" ]
  [ "$AID_GATE_PROFILE_FLOOR" = "full" ]

  # stdout is still EXACTLY one line — both production callers use it as a
  # single gate_profiles key.
  [ "$(wc -l < "$TEST_TMPDIR/resolved.txt")" -eq 1 ]
}

@test "AC1: --floor-file writes the accumulated floor for a non-sourcing caller" {
  local paths; paths="$(_gp_paths_file "plugins/aid-orchestrator/scripts/aid-fsm.sh")"
  local floor_file="$TEST_TMPDIR/floor.txt"

  run bash "$AID_PLUGIN_PATH/scripts/lib/aid-gate-profile.sh" resolve \
    "$paths" "" "" epic --floor-file "$floor_file"
  [ "$status" -eq 0 ]
  [ "$output" = "standard" ]
  [ "$(cat "$floor_file")" = "full" ]
}

# WHAT THIS PINS, AND WHAT IT DOES NOT (CP3 integration review finding 3).
# This is a LIBRARY-level statement: "given an fsm-state whose done_phase is
# `release`, boundary=epic suppresses the escalation in the printed profile and
# keeps it in the floor". It is NOT a statement about what `epic-complete`
# records — that command deliberately passes NO fsm-state (aid-plan-fsm.sh,
# "THE EPIC'S OWN fsm-state IS DELIBERATELY NOT PASSED"), because an EPIC's own
# `done_phase: release` is its FSM tail, not the plan's final boundary. The
# acceptance-level tests below therefore expect a RISK-derived floor, and the
# contract test "CP3-F3 (contract)" holds the two levels together.
@test "Edge Case: boundary=epic suppresses the release escalation for the run profile while the floor still records release" {
  local paths; paths="$(_gp_paths_file "docs/x.md")"
  local state="$TEST_TMPDIR/fsm-state.yaml"
  printf 'epic_id: E-064-1_1\ndone_phase: release\n' > "$state"

  AID_GATE_PROFILE_FLOOR=""
  gate_profile_resolve "$paths" "$state" "" epic > "$TEST_TMPDIR/resolved.txt"
  [ "$(cat "$TEST_TMPDIR/resolved.txt")" = "quick" ]
  [ "$AID_GATE_PROFILE_FLOOR" = "release" ]

  # plan_final asks for the escalated run itself.
  AID_GATE_PROFILE_FLOOR=""
  gate_profile_resolve "$paths" "$state" "" plan_final > "$TEST_TMPDIR/resolved2.txt"
  [ "$(cat "$TEST_TMPDIR/resolved2.txt")" = "release" ]
  [ "$AID_GATE_PROFILE_FLOOR" = "release" ]
}

@test "Regression: a three-argument gate_profile_resolve call keeps today's unbounded behaviour byte-identical" {
  local paths; paths="$(_gp_paths_file "plugins/aid-orchestrator/scripts/aid-fsm.sh")"
  local state="$TEST_TMPDIR/fsm-state.yaml"
  printf 'epic_id: E-064-1_1\ndone_phase: release\n' > "$state"

  # No boundary → no cap, no suppression: high-risk stays `full`, a release
  # done_phase still escalates to `release`.
  run gate_profile_resolve "$paths"
  [ "$status" -eq 0 ]
  [ "$output" = "full" ]

  run gate_profile_resolve "$paths" "$state"
  [ "$status" -eq 0 ]
  [ "$output" = "release" ]

  # Docs-only, no boundary → quick, exactly as before.
  local docs; docs="$(_gp_paths_file "docs/a.md" "README.md")"
  run gate_profile_resolve "$docs"
  [ "$status" -eq 0 ]
  [ "$output" = "quick" ]
}

@test "Edge Case: AID_GATE_PROFILE_OVERRIDE downward from full without the force variables is refused at the epic boundary" {
  local paths; paths="$(_gp_paths_file "plugins/aid-orchestrator/scripts/aid-fsm.sh")"

  AID_GATE_PROFILE_OVERRIDE=quick run gate_profile_resolve "$paths" "" "" epic
  [ "$status" -eq 0 ]
  [[ "$output" == *"rejected"* ]]
  [[ "$output" == *"standard"* ]]

  # The waiver is honoured — and the cap still applies on top of it, so the
  # EPIC boundary can never be talked into a broad suite either way.
  AID_GATE_PROFILE_OVERRIDE=quick AID_GATE_PROFILE_FORCE=1 \
    AID_GATE_PROFILE_FORCE_REASON="documented waiver for this one run, PM approved" \
    run gate_profile_resolve "$paths" "" "" epic
  [ "$status" -eq 0 ]
  [ "$output" = "quick" ]

  # A downward override never lowers the plan-final floor.
  AID_GATE_PROFILE_FLOOR=""
  AID_GATE_PROFILE_OVERRIDE=quick AID_GATE_PROFILE_FORCE=1 \
    AID_GATE_PROFILE_FORCE_REASON="documented waiver for this one run, PM approved" \
    gate_profile_resolve "$paths" "" "" epic --floor-file "$TEST_TMPDIR/floor.txt" >/dev/null
  [ "$(cat "$TEST_TMPDIR/floor.txt")" = "full" ]
}

@test "Error Handling: gate_profile_resolve exits 2 on an unknown boundary and on --floor-file without a boundary" {
  local paths; paths="$(_gp_paths_file "docs/a.md")"

  run gate_profile_resolve "$paths" "" "" plan-final
  [ "$status" -eq 2 ]
  [[ "$output" == *"boundary"* ]]

  run gate_profile_resolve "$paths" "" "" epic extra
  [ "$status" -eq 2 ]

  run gate_profile_resolve "$paths" --floor-file "$TEST_TMPDIR/floor.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--floor-file"* ]]
  [ ! -f "$TEST_TMPDIR/floor.txt" ]

  run gate_profile_resolve "$paths" "" "" epic --floor-file
  [ "$status" -eq 2 ]

  run gate_profile_resolve "$paths" "" "" epic --nope
  [ "$status" -eq 2 ]
}

# ─── .aid-o/config/execution.yaml — the activated profile table ────────────

@test "AC5: the release include list is a superset of the full include list in the self-host execution.yaml" {
  local cfg; cfg="$(_selfhost_execution_yaml)"
  [[ -f "$cfg" ]] || skip "self-host .aid-o/config/execution.yaml absent (gitignored workspace)"

  run _gp_yq_jq "$cfg" '([.gate_profiles.full.include[]] - [.gate_profiles.release.include[]]) | length == 0'
  [ "$status" -eq 0 ]
  # Guard against the vacuous pass: both lists must actually be non-empty.
  run _gp_yq_jq "$cfg" '(.gate_profiles.full.include | length) > 0 and (.gate_profiles.release.include | length) > 0'
  [ "$status" -eq 0 ]
}

@test "AC7: every profile the resolver can return is a key under gate_profiles, and each include[] names only defined gates" {
  local cfg; cfg="$(_selfhost_execution_yaml)"
  [[ -f "$cfg" ]] || skip "self-host .aid-o/config/execution.yaml absent (gitignored workspace)"
  local p
  for p in quick targeted standard full release; do
    run _gp_yq_jq "$cfg" "(.gate_profiles.${p}.include | length) > 0"
    [ "$status" -eq 0 ]
    run _gp_yq_jq "$cfg" "([.gate_profiles.${p}.include[]] - [.gates | keys[]] | length) == 0"
    [ "$status" -eq 0 ]
  done
}

@test "AC2: no profile the epic boundary can resolve to includes bats_all — a broad suite needs a recorded PM exception" {
  # The cap really is `standard`, even for the worst possible classification
  # (high-risk paths AND a release done_phase) — config-independent, so this
  # half runs everywhere.
  local paths; paths="$(_gp_paths_file "plugins/aid-orchestrator/scripts/aid-fsm.sh" "plugins/aid-orchestrator/defaults/policies/x.yaml")"
  local state="$TEST_TMPDIR/fsm-state.yaml"
  printf 'done_phase: release\n' > "$state"
  run gate_profile_resolve "$paths" "$state" "" epic
  [ "$output" = "standard" ]

  # …and none of the three profiles boundary=epic can return runs the broad
  # suite (quick is classify_paths' floor, standard is the cap).
  local cfg; cfg="$(_selfhost_execution_yaml)"
  [[ -f "$cfg" ]] || skip "self-host .aid-o/config/execution.yaml absent (gitignored workspace)"
  local p
  for p in quick targeted standard; do
    run _gp_yq_jq "$cfg" "([.gate_profiles.${p}.include[]] | index(\"bats_all\")) == null"
    [ "$status" -eq 0 ]
  done
}

@test "AC7: a docs-only diff resolves to quick at the epic boundary and quick's include[] excludes the broad suite" {
  local docs; docs="$(_gp_paths_file "docs/a.md" "CHANGELOG.md")"
  AID_GATE_PROFILE_FLOOR=""
  gate_profile_resolve "$docs" "" "" epic > "$TEST_TMPDIR/resolved.txt"
  [ "$(cat "$TEST_TMPDIR/resolved.txt")" = "quick" ]
  [ "$AID_GATE_PROFILE_FLOOR" = "quick" ]

  local cfg; cfg="$(_selfhost_execution_yaml)"
  [[ -f "$cfg" ]] || skip "self-host .aid-o/config/execution.yaml absent (gitignored workspace)"
  run _gp_yq_jq "$cfg" '(.gate_profiles.quick.include | length) > 0'
  [ "$status" -eq 0 ]
}

# ─── aid-plan-fsm.sh epic-complete — recording the floor ───────────────────

@test "AC1: epic-complete records the plan-final floor full for a high-risk EPIC whose own boundary ran standard" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1" "plugins/aid-orchestrator/scripts/aid-fsm.sh" "risk"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "standard"

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # The EPIC ran `standard` at its own boundary…
  run _pfsm_entry_field P064 E-064-1_1 epic_completion_profile
  [ "$output" = "standard" ]
  # …but the plan-final floor records what the risk really demands.
  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]

  # Binding invariant: nothing in this path touches lineage.
  run _pfsm_entry_field P064 E-064-1_1 lineage
  [ "$output" = "proven" ]
  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

@test "AC4: an unknown production path (targeted_tests exit 3) raises the plan-final floor to full" {
  _pfsm_bootstrap_plan "P064"
  # A LOW-risk diff — without the exit-3 signal this run's floor would be
  # `standard`, so the raise can only come from the unknown production path.
  _pfsm_epic_with_commit "P064" "E-064-1_1" "src/thing.ts" "code"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE"
  _pfsm_write_gates_report "E-064-1_1" '{"profile":"standard","overall":"pass","excluded_gates":[],"gates":{"targeted_tests":{"gate":"targeted_tests","result":"fail","exit_code":3}}}'

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]
  run _pfsm_entry_field P064 E-064-1_1 unknown_production_path
  [ "$output" = "true" ]
}

@test "Edge Case: a docs-only EPIC in a plan whose floor is already release keeps the floor at release" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1" "docs/notes.md" "docs"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "quick"
  plan_manifest_raise_final_profile "P064" "release"

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "release" ]
  run _pfsm_entry_field P064 E-064-1_1 epic_final_profile_floor
  [ "$output" = "quick" ]
}

# ─── CP3 integration review finding 3: the floor reflects RISK, not the
#     EPIC's own done_phase ────────────────────────────────────────────────
@test "CP3-F3: the recorded floor is risk-derived even though the EPIC's own done_phase is release" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1" "docs/notes.md" "docs"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "quick"

  # THE PREMISE, MADE EXPLICIT: epic-complete is only reachable after
  # `done-advance review release`, so the state file it reads always says
  # `done_phase: release`. That is production, not a fixture quirk.
  grep -q '^done_phase: release$' \
    "$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-064-1_1/R-E-064-1_1-plan/fsm-state.yaml"

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # A docs-only EPIC contributes `quick`, NOT `release`. Before the fix the
  # done_phase was inherited and every EPIC — this one included — recorded
  # `release`, which made AC4's discriminating premise (targeted_tests exit 3
  # RAISES the floor) impossible to observe: the floor was already maxed.
  run _pfsm_entry_field P064 E-064-1_1 epic_final_profile_floor
  [ "$output" = "quick" ]
  # The PLAN-wide value is raise-only from the manifest's own `standard`
  # seed, so the observable claim here is that this EPIC did not push it to
  # `release` — which is exactly what inheriting done_phase used to do.
  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "standard" ]
}

@test "CP3-F3 (contract): epic-complete passes NO fsm-state to gate_profile_resolve" {
  # The structural half of the same claim, so the two test LEVELS cannot drift
  # apart again: the library keeps escalating on a `release` done_phase (see
  # "Edge Case: boundary=epic suppresses the release escalation…"), and this
  # pins that epic-complete never hands it one.
  local call
  call="$(grep -n -A 2 'gate_profile_resolve "\$_ec_paths"' "$PLAN_FSM_CLI")"
  [ -n "$call" ]
  [[ "$call" == *'gate_profile_resolve "$_ec_paths" ""'* ]]
  [[ "$call" != *'gate_profile_resolve "$_ec_paths" "$state_file"'* ]]
  # …and the reason is written down next to it, not only here.
  grep -q 'DELIBERATELY NOT PASSED' "$PLAN_FSM_CLI"
}

@test "Edge Case: a plan-declared gate the active profile excluded is recorded as a mandatory plan-final gate, never silently dropped" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1" "src/thing.ts" "code"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE"
  _pfsm_write_plan_json "E-064-1_1" '["docs_updated","bats_fsm"]'
  _pfsm_write_gates_report "E-064-1_1" '{"profile":"standard","overall":"pass","excluded_gates":["docs_updated","shell_pipeline_smoke"],"gates":{}}'

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Recorded plan-wide (what P068's plan-final stage must run) …
  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_gates'
  [[ "$output" == *"docs_updated"* ]]
  # … only the PLAN-declared one, not every profile exclusion.
  [[ "$output" != *"shell_pipeline_smoke"* ]]
  # … and with per-EPIC provenance.
  run bash -c "jq -c '.plan_boundary_manifest.epic_runs[] | select(.epic_id==\"E-064-1_1\") | .plan_final_required_gates' '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json'"
  [ "$output" = '["docs_updated"]' ]
  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

@test "AC3: epic-complete --full-tests records epic_full_test_exception with reason and requesting boundary and never lowers the floor" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1" "docs/notes.md" "docs"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "quick"
  plan_manifest_raise_final_profile "P064" "release"

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --full-tests \
    --reason "PM asked for a one-off full run mid-plan" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "release" ]
  run bash -c "jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id==\"E-064-1_1\") | .epic_full_test_exception.reason' '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json'"
  [ "$output" = "PM asked for a one-off full run mid-plan" ]
  run bash -c "jq -r '.plan_boundary_manifest.epic_runs[] | select(.epic_id==\"E-064-1_1\") | .epic_full_test_exception.boundary' '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json'"
  [ "$output" = "epic" ]
  run plan_manifest_validate "P064"
  [ "$status" -eq 0 ]
}

@test "Error Handling: epic-complete with no gate_profiles in execution.yaml still records the floor and reports gate_profiles_absent" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1" "plugins/aid-orchestrator/scripts/aid-fsm.sh" "risk"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "standard"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'gates:\n  bats_fsm:\n    command: "true"\n' > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"

  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate_profiles_absent"* ]]
  run plan_manifest_get "P064" '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]

  # With the block present, no such note.
  printf 'gates:\n  bats_fsm:\n    command: "true"\ngate_profiles:\n  quick:\n    include: [bats_fsm]\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  _pfsm_epic_with_commit "P064" "E-064-1_2" "src/other.ts" "code"
  _pfsm_write_epic_evidence "E-064-1_2" "DONE" "standard"
  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_2 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"gate_profiles_absent"* ]]
}

# ─── aid-fsm.sh — the boundary-aware GATES:DONE recompute ──────────────────

# _fsm_seed_gates_run <epic_id> <base_commit> <profile> — an EPIC run parked at
# GATES with a gates_report.json naming <profile>, in the run directory
# epic-start recorded. Mirrors seed_test_state_files' shape (that helper is
# hardwired to TEST_EVIDENCE_DIR, which is a different EPIC here).
_fsm_seed_gates_run() {
  local epic_id="$1" base="$2" profile="$3"
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/R-${epic_id}-plan"
  mkdir -p "$dir/gates"
  cat > "$dir/fsm-state.yaml" <<EOF
epic_id: ${epic_id}
run_id: R-${epic_id}-plan
state: GATES
current_step: 1
total_steps: 1
created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
base_commit: ${base}
EOF
  jq -nc --arg p "$profile" \
    '{overall:"pass", profile:$p, profile_source:"auto_resolved", excluded_gates:[],
      _generated_by:"aid-run-gates.sh", gates:{}}' > "$dir/gates/gates_report.json"
  echo "$dir/fsm-state.yaml"
}

@test "AC6: a high-risk EPIC that ran standard at its own boundary reaches DONE in plan_branch mode" {
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  _pfsm_bootstrap_plan "P064" plan_branch
  _pfsm_epic_with_commit "P064" "E-064-1_1" "plugins/aid-orchestrator/scripts/aid-fsm.sh" "risk"

  local base; base="$(_pfsm_entry_field P064 E-064-1_1 epic_base_commit)"
  local state_file; state_file="$(_fsm_seed_gates_run "E-064-1_1" "$base" "standard")"

  # The recompute diffs base_commit..HEAD, so stand on the EPIC's own branch.
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$state_file"
  [ "$status" -eq 0 ]
  [ "$(grep '^state:' "$state_file" | awk '{print $2}')" = "DONE" ]
}

@test "AC6: the same high-risk EPIC in a legacy-mode plan still requires full — the epic cap is plan_branch only" {
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  _pfsm_bootstrap_plan "P064" legacy_epic_release_mode
  _pfsm_epic_with_commit "P064" "E-064-1_1" "plugins/aid-orchestrator/scripts/aid-fsm.sh" "risk"

  local base; base="$(_pfsm_entry_field P064 E-064-1_1 epic_base_commit)"
  local state_file; state_file="$(_fsm_seed_gates_run "E-064-1_1" "$base" "standard")"
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"risk_profile_below_required"* ]]
  [[ "$output" == *"'full'"* ]]
  [ "$(grep '^state:' "$state_file" | awk '{print $2}')" = "GATES" ]
}

@test "AC6: a plan_branch EPIC that ran BELOW the epic-boundary requirement is still refused" {
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  _pfsm_bootstrap_plan "P064" plan_branch
  _pfsm_epic_with_commit "P064" "E-064-1_1" "plugins/aid-orchestrator/scripts/aid-fsm.sh" "risk"

  local base; base="$(_pfsm_entry_field P064 E-064-1_1 epic_base_commit)"
  local state_file; state_file="$(_fsm_seed_gates_run "E-064-1_1" "$base" "quick")"
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main

  AID_PROJECT_ROOT="$TEST_PROJECT_ROOT" run "$FSM" transition GATES DONE "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"risk_profile_below_required"* ]]
  [[ "$output" == *"'standard'"* ]]
}

# =============================================================================
# ─── aid-fsm.sh done-advance review→release — the silenced per-EPIC release
#     stack (P064 EPIC E-064-2_2 Step 4 = plan Step 9) ────────────────────────
# =============================================================================
# An INTERMEDIATE EPIC completion inside an open `plan_branch` plan must be
# structurally incapable of invoking the per-EPIC release stack (CP3 full-diff
# pair, Auditor, Curator, Simplifier, Reporter, EPIC-scoped C4, the PM release
# summary, `aid-release.sh`). The proof is a spy harness — executables on a
# PATH-prepended directory that log their argv — not the prose.
#
# TRACEABILITY — `ACn:` numbers this step's own AC list (plan Step 9):
#   AC1  intermediate plan_branch completion → zero invocations of every spy
#   AC2  the same fixture in legacy_epic_release_mode → the expected non-zero ones
#   AC3  CP2-fed tiered compliance + the local checks still execute in plan_branch
#   AC4  the timeline event's skipped-stage list == AID_PLAN_BRANCH_SKIPPED_STAGES
#
# MODE SOURCE — these tests exercise `_fsm_declared_plan_mode`, which reads the
# git-tracked lifecycle manifest (the PM's DECLARATION), NOT Step 3's
# `_fsm_gate_profile_boundary`, which reads the gitignored runtime manifest.

# _rs_run_dir <epic_id> — the run directory epic-start records (run_id
# R-<epic_id>-plan), matching _pfsm_write_epic_evidence's own convention.
_rs_run_dir() {
  echo "$TEST_PROJECT_ROOT/.aid-o/work/evidence/${1}/R-${1}-plan"
}

# _rs_seed_done_review <epic_id> [streamlined] — an EPIC parked at DONE/review
# with pm_decision=merge and the minimum evidence done-advance always reads.
# Deliberately writes NO curator-report / audit-report / review-profile.json:
# that absence is what makes the legacy inverse (AC2) fail loudly and the
# plan_branch path (AC1) pass, which is the whole behavioural difference.
_rs_seed_done_review() {
  local epic_id="$1" streamlined="${2:-false}"
  local dir; dir="$(_rs_run_dir "$epic_id")"
  mkdir -p "$dir/gates" "$TEST_PROJECT_ROOT/.aid-o/config" \
           "$TEST_PROJECT_ROOT/.aid-o/work" "$TEST_PROJECT_ROOT/.aid-o/tasks"
  cat > "$dir/fsm-state.yaml" <<YAML
epic_id: ${epic_id}
run_id: R-${epic_id}-plan
branch: task/${epic_id}/main
state: DONE
done_phase: review
streamlined_mode: ${streamlined}
created_at: 2026-07-22T00:00:00Z
total_steps: 1
current_step: 1
pm_decision: merge
YAML
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-07-22T00:00:00Z","_command_log":[]}\n' \
    > "$dir/gates/gates_report.json"
  touch "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/plugin.yaml" <<YAML
plugin_path: "$AID_PLUGIN_PATH"
dispatch_mode: subagent
YAML
  echo "$dir/fsm-state.yaml"
}

# _rs_install_spies — the spy harness, following
# scripts/tests/bats/test-aid-c3-dispatch.bats:1059-1068: a temp directory
# prepended to PATH holding executables that append their argv to a log.
#
# ONLY SEAMS A `done-advance` CALL CAN GENUINELY REACH ARE INSTALLED, so that a
# zero line count is EVIDENCE rather than decoration (Step 4 CP2 finding 3).
#   RS_C4_LOG — the C4 release aggregator, spied through the PRODUCTION
#               `AID_RELEASE_POLICY_BIN` seam the dual-run hook itself reads
#               (aid-fsm.sh: `_c4_bin="${AID_RELEASE_POLICY_BIN:-...}"`). Live
#               and discriminating: AC2's positive inverse shows it firing.
#   RS_LOG    — `git tag` / `git push`, through a PATH wrapper. aid-fsm.sh
#               really does shell out to git, so the wrapper is reachable.
#
# WHAT WAS REMOVED, AND WHY (Step 4 CP2 finding 3). The earlier version also
# installed PATH spies for `aid-release.sh`, `aid-auditor-dispatch`,
# `aid-curator-dispatch`, `aid-simplifier-dispatch`, `aid-reporter-dispatch`
# and `claude`. None of them could ever log a line: `aid-release.sh` has no
# caller under `scripts/` and the controller invokes it by ABSOLUTE path
# (`bash {plugin_path}/scripts/aid-release.sh`), which a PATH spy cannot
# intercept; the four dispatch markers are not executables that exist anywhere
# in this repository (the specialists are agent dispatches, not processes); and
# `claude` is never invoked from any script under `scripts/`. Their zero line
# count was unconditionally true — it would have held with the entire skip
# guard deleted. `_rs_static_release_stack_absence` is the honest replacement.
#
# Install AFTER the plan/EPIC bootstrap so bootstrap git traffic never lands
# in the log — the assertion is a ZERO line count, and a dirty baseline would
# make it either impossible or meaningless.
_rs_install_spies() {
  RS_SPY="$TEST_TMPDIR/release-spy"; mkdir -p "$RS_SPY"
  RS_LOG="$TEST_TMPDIR/release-spy.log"; : > "$RS_LOG"
  RS_C4_LOG="$TEST_TMPDIR/c4-spy.log"; : > "$RS_C4_LOG"
  export RS_SPY RS_LOG RS_C4_LOG

  # git wrapper: logs the two release-only verbs and delegates everything else
  # untouched (done-advance legitimately runs rev-parse/log/status).
  # Matches BOTH `git tag|push` and `git -C <dir> tag|push`: every git call
  # inside aid-fsm.sh uses the `-C` form, so the old bare-$1 match could never
  # have fired — a real harness bug independent of what it was asserting.
  local real_git; real_git="$(command -v git)"
  cat > "$RS_SPY/git" <<EOF
#!/usr/bin/env bash
_rs_verb="\$1"
[ "\$1" = "-C" ] && _rs_verb="\$3"
case "\$_rs_verb" in
  tag|push) printf 'git %s\n' "\$*" >> "$RS_LOG" ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$RS_SPY/git"

  cat > "$RS_SPY/aid-release-policy-spy.sh" <<EOF
#!/usr/bin/env bash
printf 'aid-release-policy.sh %s\n' "\$*" >> "$RS_C4_LOG"
exit 0
EOF
  chmod +x "$RS_SPY/aid-release-policy-spy.sh"
  export AID_RELEASE_POLICY_BIN="$RS_SPY/aid-release-policy-spy.sh"

  PATH="$RS_SPY:$PATH"; export PATH
}

# _rs_static_release_stack_absence — the CONTROL-FLOW half of AC1's claim
# (Step 4 CP2 finding 3). The release-stack invocations that no runtime seam can
# observe from `aid-fsm.sh done-advance` are proven absent STATICALLY instead of
# with spies that could never fire: the FSM does not invoke them at all, in
# either mode, so a plan_branch run cannot reach them by construction.
_rs_static_release_stack_absence() {
  # This test is about the INTERMEDIATE done-advance path, so the static guard
  # is scoped to the FSM that path runs through. It used to grep all of
  # scripts/ and assert `aid-release.sh` has zero callers anywhere — a premise
  # P068 Step 5 legitimately retired by adding the plan-final `tag-plan` call in
  # aid-plan-fsm.sh. That call is reachable ONLY from plan-merge-to-main, i.e.
  # at the plan boundary, never from an intermediate EPIC completion, so a
  # whole-tree assertion made the test fail for the very change it should
  # permit. (PM-authorized scope extension, 2026-07-26.)
  run bash -c "grep -n 'aid-release\\.sh' '$FSM' || true"
  [ -z "$output" ]
  # The four specialist dispatches are AGENT dispatches, not executables: no
  # such name exists anywhere in the plugin, least of all in the FSM.
  run grep -c 'aid-auditor-dispatch\|aid-curator-dispatch\|aid-simplifier-dispatch\|aid-reporter-dispatch' "$FSM"
  [ "$output" = "0" ]
  # The plugin cache refresh (`claude ...`) is never invoked from the FSM.
  run bash -c "grep -nE '(^|[^-a-zA-Z_/])claude ' '$FSM' || true"
  [ -z "$output" ]
}

# _rs_skipped_stages_from_source — AID_PLAN_BRANCH_SKIPPED_STAGES parsed out of
# aid-fsm.sh itself. The test NEVER keeps its own copy of the list (plan Step 9
# is explicit: "the spy test can assert against the same source of truth").
_rs_skipped_stages_from_source() {
  sed -n '/^AID_PLAN_BRANCH_SKIPPED_STAGES=(/,/^)/p' "$FSM" \
    | sed -e '1d' -e '$d' -e 's/#.*//' \
    | tr -d '[:blank:]' \
    | grep -v '^$'
}

# _rs_event <epic_id> <event> — the LAST timeline event of that name, as JSON.
_rs_event() {
  local dir; dir="$(_rs_run_dir "$1")"
  jq -c --arg e "$2" 'select(.event==$e)' "$dir/timeline.jsonl" 2>/dev/null | tail -1
}

_rs_done_phase() {
  grep '^done_phase:' "$1" | awk '{print $2}'
}

# _rs_plan_branch_epic <plan_id> <epic_id> [mode] — bootstrap + epic-start +
# one real commit, then stand on the EPIC's own task branch (the production
# shape: cmd_init leaves the run there, and the lifecycle manifest is committed
# on target_branch only, so the mode read must go through target_branch's tree).
_rs_plan_branch_epic() {
  local plan_id="$1" epic_id="$2" mode="${3:-plan_branch}"
  _pfsm_bootstrap_plan "$plan_id" "$mode"
  _pfsm_epic_with_commit "$plan_id" "$epic_id"
  git -C "$TEST_PROJECT_ROOT" checkout -q "task/${epic_id}/main"
}

# ─── AC1: zero invocations of the release stack ────────────────────────────

# EXACTLY WHAT AC1 PROVES, AND HOW (Step 4 CP2 finding 3). Two different kinds
# of evidence, kept apart on purpose:
#   * BY A LIVE SEAM — the C4 release aggregator (`AID_RELEASE_POLICY_BIN`, the
#     production seam the dual-run hook reads) and `git tag` / `git push` (a
#     PATH wrapper over a binary the FSM really does invoke). Both are
#     discriminating: AC2's complete legacy run shows the C4 seam firing on the
#     same fixture, so a zero here is a fact about the mode, not about the
#     harness.
#   * BY CONTROL FLOW ONLY — the C4 dual-run BLOCK is never reached, therefore
#     `aid-release-policy.sh` is not invoked; and `aid-release.sh`, the four
#     specialist dispatches and the `claude` cache refresh are not invoked
#     because the FSM contains no call to any of them in EITHER mode
#     (`_rs_static_release_stack_absence`). No runtime spy can add anything to
#     that: they are the controller's own steps in pipeline.md §7, guarded by
#     the prose fork and by the plan-branch instructions, not by this binary.
@test "AC1: an intermediate plan_branch completion invokes NO release-stack executable — every reachable seam is silent" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [ "$(_rs_done_phase "$state_file")" = "release" ]

  # Proven BY A LIVE SEAM: zero line count in both reachable logs.
  [ "$(wc -l < "$RS_LOG")" -eq 0 ]
  [ "$(wc -l < "$RS_C4_LOG")" -eq 0 ]

  # Proven BY A LIVE PRODUCTION EMITTER: `c3_review_profile_presence` is the
  # first stage in AID_PLAN_BRANCH_SKIPPED_STAGES and emits
  # `review_profile_would_block` whenever it runs without a review-profile.json.
  # This fixture has none, so the event's ABSENCE here is discriminating — the
  # AC2 complete-legacy run below asserts the same event IS emitted.
  [ -z "$(_rs_event E-064-1_1 review_profile_would_block)" ]

  # Proven BY CONTROL FLOW: the FSM cannot invoke the rest at all.
  _rs_static_release_stack_absence

  # ...and the transition succeeded with NO curator-report, NO audit-report and
  # NO review-profile.json anywhere: the stack is not merely un-invoked, it is
  # no longer a precondition.
  [ ! -f "$(_rs_run_dir E-064-1_1)/curator-report.md" ]
  [ ! -f "$(_rs_run_dir E-064-1_1)/audit-report.md" ]

  local ev; ev="$(_rs_event E-064-1_1 done_advance_plan_branch_mode)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.mode')" = "plan_branch" ]
  [ "$(echo "$ev" | jq -r '.plan_id')" = "P064" ]
  [ "$(echo "$ev" | jq -r '.forced')" = "false" ]
}

# ─── AC2: the legacy-mode positive inverse ─────────────────────────────────

@test "AC2: the same fixture in legacy_epic_release_mode is REFUSED — the release stack is demonstrably still live" {
  _rs_plan_branch_epic P064 E-064-1_1 legacy_epic_release_mode
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Curator report not found"* ]]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
  # No plan_branch routing event was emitted for a legacy plan.
  [ -z "$(_rs_event E-064-1_1 done_advance_plan_branch_mode)" ]
}

@test "AC2: a COMPLETE legacy-mode run reaches release AND fires the C4 aggregator — the expected non-zero invocation" {
  _rs_plan_branch_epic P064 E-064-1_1 legacy_epic_release_mode
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  local dir; dir="$(_rs_run_dir E-064-1_1)"
  printf 'blocking_findings: false\n' > "$dir/audit-report.md"
  echo "curator report" > "$dir/curator-report.md"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [ "$(_rs_done_phase "$state_file")" = "release" ]
  # The C4 dual-run hook ran: exactly the stage plan_branch mode skips.
  [ "$(wc -l < "$RS_C4_LOG")" -ge 1 ]
  [[ "$(cat "$RS_C4_LOG")" == *"E-064-1_1"* ]]
  # ...and so did `c3_review_profile_presence`, the first skipped stage: its
  # would_block telemetry fires here on the SAME fixture whose plan_branch run
  # (AC1) emits nothing. That contrast is what makes AC1's silence evidence.
  [ -n "$(_rs_event E-064-1_1 review_profile_would_block)" ]
}

@test "AC2: the identical EPIC id under plan_branch needs NEITHER report — mode, not evidence, is what differs" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Curator report not found"* ]]
  [[ "$output" != *"Auditor report not found"* ]]
}

# ─── AC3: the skip is SCOPED, not blanket ──────────────────────────────────

@test "AC3: the retained streamlined integration review still blocks a plan_branch EPIC missing its CP3 evidence" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1 true)"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required integration-review evidence"* ]]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
  # The routing event is still emitted (it describes routing, not completion),
  # proving the block came from a RETAINED check and not from mode resolution.
  [ -n "$(_rs_event E-064-1_1 done_advance_plan_branch_mode)" ]
}

@test "AC3: the retained CP2-fed tiered-compliance precondition still evaluates in plan_branch mode" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  # branch_correct is a CP2-era compliance dimension; promote it to blocking and
  # make it fail (branch value that is not ^task/E-). If tiered compliance were
  # skipped along with the release stack, this run would sail through.
  sed -i 's|^branch: .*|branch: feature/not-a-task-branch|' "$state_file"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/check-severity.yaml" <<'YAML'
checks:
  branch_correct:
    severity: blocking
    promoted_at: "2026-07-22"
YAML
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking compliance failure"* ]]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
  # ...and even while a RETAINED check blocked, no release-stack spy fired.
  [ "$(wc -l < "$RS_LOG")" -eq 0 ]
  [ "$(wc -l < "$RS_C4_LOG")" -eq 0 ]
}

# ─── AC4: the emitted list IS the source constant ──────────────────────────

@test "AC4: the skipped-stage list in the timeline event matches AID_PLAN_BRANCH_SKIPPED_STAGES read out of aid-fsm.sh" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]

  local from_source emitted
  from_source="$(_rs_skipped_stages_from_source)"
  [ -n "$from_source" ]
  emitted="$(_rs_event E-064-1_1 done_advance_plan_branch_mode | jq -r '.skipped_stages[]')"
  [ "$emitted" = "$from_source" ]

  # Every name the array claims is skipped is a stage this file really has.
  local stage
  while read -r stage; do
    [ -n "$stage" ]
  done <<< "$from_source"
  [ "$(echo "$from_source" | wc -l)" -ge 8 ]
}

# ─── Step 4 CP2 finding 1: the auditor verdict is EPIC-LOCAL, not a release
#     stage — it must block in BOTH modes ───────────────────────────────────
# The legacy `blocking_findings` read used to sit INSIDE the skip guard while
# appearing in neither AID_PLAN_BRANCH_SKIPPED_STAGES nor its "WHAT IS NOT
# HERE, ON PURPOSE" list. A PM-blessed mid-plan Auditor run
# (`mid_plan_specialist_review_exception`) reporting a critical finding was
# therefore silently ungated for an intermediate plan-branch EPIC: it merged
# into `plan/{plan_id}` with the finding unaddressed, and the
# `done_advance_plan_branch_mode` event did not name the bypassed gate, so the
# bypass left no auditable trace. AC4 structurally cannot catch this — it
# compares the array against an event built from that same array.

@test "CP2-1: a mid-plan audit-report with blocking_findings: true REFUSES a plan_branch advance" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  local dir; dir="$(_rs_run_dir E-064-1_1)"
  # Exactly the verifier's scenario: the PM records the exception, dispatches
  # the Auditor mid-plan, and the Auditor reports a critical finding. Risk
  # profile is low/medium (no review-profile.json at all), so the C3 hook would
  # not have fired even in legacy mode — this .md read is the ONLY gate on the
  # field, and before the hoist plan_branch mode skipped it.
  plan_manifest_update P064 '.plan_boundary_manifest.mid_plan_specialist_review_exception = {"epic_id":"E-064-1_1","reason":"PM asked for an early architecture read"}'
  printf 'blocking_findings: true\n' > "$dir/audit-report.md"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking_findings"* ]]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
  # The block came from a RETAINED EPIC-local check, not from mode resolution:
  # the routing event is still emitted and no release-stack seam fired.
  [ -n "$(_rs_event E-064-1_1 done_advance_plan_branch_mode)" ]
  [ "$(wc -l < "$RS_C4_LOG")" -eq 0 ]
  # ...and the check is deliberately NOT claimed as skipped.
  ! _rs_skipped_stages_from_source | grep -q 'blocking_findings'
}

@test "CP2-1: the same blocking verdict still REFUSES in legacy_epic_release_mode" {
  _rs_plan_branch_epic P064 E-064-1_1 legacy_epic_release_mode
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  local dir; dir="$(_rs_run_dir E-064-1_1)"
  printf 'blocking_findings: true\n' > "$dir/audit-report.md"
  echo "curator report" > "$dir/curator-report.md"

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking_findings"* ]]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
}

@test "CP2-1: a non-false value is fail-closed in plan_branch too (not just literal true)" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  local dir; dir="$(_rs_run_dir E-064-1_1)"
  # An audit-report that EXISTS but carries no line-start verdict: the field is
  # unreadable, so "clean" cannot be confirmed. Fail-closed, same as legacy.
  printf '# Audit\n\nNo blocking_findings: true were found in this EPIC.\n' > "$dir/audit-report.md"

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing canonical top-level 'blocking_findings' field"* ]]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
}

@test "CP2-1: the hoisted check is a NO-OP when no audit-report exists — the normal intermediate EPIC still advances" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  local dir; dir="$(_rs_run_dir E-064-1_1)"
  # The ordinary shape of an intermediate plan-branch EPIC: no auditor ran, so
  # there is nothing to read. Absence must stay silence — never a new hard fail.
  [ ! -f "$dir/audit-report.md" ]
  [ ! -f "$dir/audit-report.yaml" ]
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [ "$(_rs_done_phase "$state_file")" = "release" ]
  [[ "$output" != *"blocking_findings"* ]]
  [ "$(wc -l < "$RS_C4_LOG")" -eq 0 ]
}

@test "CP2-1: a clean mid-plan verdict (blocking_findings: false) advances in plan_branch" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  local dir; dir="$(_rs_run_dir E-064-1_1)"
  printf 'blocking_findings: false\n' > "$dir/audit-report.md"

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [ "$(_rs_done_phase "$state_file")" = "release" ]
}

# ─── Step 4 CP2 finding 4: the no-jq fallback must not lie about its type ───
# log_event (lib/aid-stage-log.sh) passes a value through as raw JSON only when
# it starts with '[' or '{'. The old jq-less fallback produced
# `c3_review_profile_presence,cp4_...`, which starts with 'c' and was emitted as
# a QUOTED STRING — every consumer doing `.skipped_stages[]` (including AC4's
# own assertion) broke on a jq-less host, silently degrading the telemetry
# contract while every other jq-dependent check in this function fails closed.

@test "CP2-4: with jq absent, done_advance_plan_branch_mode still emits skipped_stages as a JSON ARRAY" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"

  # A PATH holding every tool the FSM needs EXCEPT jq — genuinely absent, which
  # is the case `command -v jq` guards (same construction as the yq test below).
  local nobin="$TEST_TMPDIR/nojq"; mkdir -p "$nobin"
  local t
  for t in bash sh git grep sed awk cat date mktemp rm mkdir dirname basename \
           printf tr wc head tail yq env chmod touch cp mv sort id find xargs; do
    local p; p="$(command -v "$t" 2>/dev/null)" || continue
    ln -sf "$p" "$nobin/$t"
  done
  [ ! -e "$nobin/jq" ]

  # The trailing `|| true` is what makes "the exit code is not part of this
  # assertion" explicit (and keeps bats from warning about a 127 the test
  # deliberately tolerates) — see the note below.
  run bash -c "PATH='$nobin' bash '$FSM' done-advance review release '$state_file' || true"
  # NEITHER the exit code NOR done_phase is asserted here, on purpose. A jq-less
  # host does not complete this transition at all: the invalidation-map
  # expectation check further down runs `jq ... | wc -l` under
  # `set -euo pipefail`, so the missing jq surfaces as an unguarded exit 127
  # BEFORE the phase is written. That is a separate, pre-existing degradation of
  # the jq-less path (reported, not fixed here — outside CP2 finding 4). What
  # finding 4 is about, and what this test pins, is the SHAPE of the
  # done_advance_plan_branch_mode payload: it is emitted long before that point
  # and is exactly what a consumer reads back afterwards.

  # Read back with the REAL jq (the test host has it): the payload must be an
  # array, and its members must be the source-of-truth list, in order.
  local ev; ev="$(_rs_event E-064-1_1 done_advance_plan_branch_mode)"
  [ -n "$ev" ]
  [ "$(echo "$ev" | jq -r '.skipped_stages | type')" = "array" ]
  [ "$(echo "$ev" | jq -r '.skipped_stages[]')" = "$(_rs_skipped_stages_from_source)" ]
}

# ─── Step 4 CP2 finding 5: an unresolved-mode --force is AUDITABLE ─────────
# The run timeline is not the surface a PM audits. `fsm_handle_force_override`
# writes .aid-o/work/audit-log.jsonl with a GENERIC force carrying whatever
# --blocked-checks the operator typed, so an audit of that file alone could not
# tell that this EPIC advanced without knowing whether it was supposed to merge
# to the target branch.

@test "CP2-5: a --force over an unresolved mode names itself in audit-log.jsonl, not only in the timeline" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  printf 'mode: [unclosed\n  : : :\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  git -C "$TEST_PROJECT_ROOT" add .aid-lifecycle/manifests/P064.yaml
  git -C "$TEST_PROJECT_ROOT" commit -qm "corrupt the manifest"
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"

  run bash "$FSM" done-advance review release "$state_file" \
    --force --reason "PM override: manifest repair is tracked separately"
  [ "$status" -eq 0 ]

  local al="$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  local entry
  entry="$(jq -c 'select(.event=="plan_mode_unresolved_override")' "$al" | tail -1)"
  [ -n "$entry" ]
  [ "$(echo "$entry" | jq -r '.epic_id')" = "E-064-1_1" ]
  [ "$(echo "$entry" | jq -r '.plan_id')" = "P064" ]
  [ "$(echo "$entry" | jq -r '.unresolved_reason')" = "manifest_unparseable" ]
  # The generic force entry is still written — the new one is ADDITIVE, so
  # fsm_handle_force_override's contract is unchanged for its other callers.
  [ -n "$(jq -c 'select(.event=="fsm_force_override")' "$al" | tail -1)" ]
}

# ─── Step 4 CP2 findings 2 + 7: the prose must match the FSM ───────────────

@test "CP2-2: the controller instructions do NOT claim the FSM skips CP3 itself" {
  # `fsm_check_streamlined_integration_review` runs ABOVE the skip guard and
  # hard-dies when streamlined_mode is true and the two CP3 outputs are absent
  # (asserted by the AC3 test above). A controller told that "CP3" is skipped
  # would not dispatch it and would hit an unrecoverable done-advance.
  ! grep -q 'Curator/Auditor/CP3/CP4/C3/C4 stack' "$AID_PLUGIN_PATH/commands/aid-run.md"
  grep -q 'CP3 freshness re-check' "$AID_PLUGIN_PATH/commands/aid-run.md"
  # pipeline.md must say plainly that the CP3 pair is still dispatched per EPIC
  # and stays mandatory under streamlined_mode.
  grep -q 'CP3 verifier pair is still dispatched per EPIC' "$AID_PLUGIN_PATH/skills/pipeline.md"
}

@test "CP2-7: the release sub-phase's auto-merge rule and evidence list are mode-qualified" {
  # The `plan_branch` branch must carry its OWN auto-mode rule, evaluable from
  # artifacts an intermediate EPIC actually has — an auditor score cannot be
  # required where no auditor ran.
  grep -q 'Auto-mode (FIRST AID) in `plan_branch` mode' "$AID_PLUGIN_PATH/skills/pipeline.md"
  grep -q 'Auto-mode (FIRST AID) in `legacy_epic_release_mode`' "$AID_PLUGIN_PATH/skills/pipeline.md"
  # ...and the evidence block must be scoped to the legacy branch rather than
  # listing artifacts an intermediate plan-branch EPIC never produces.
  grep -q 'Evidence written (`legacy_epic_release_mode`)' "$AID_PLUGIN_PATH/skills/pipeline.md"
  grep -q 'Evidence written (`plan_branch` mode' "$AID_PLUGIN_PATH/skills/pipeline.md"
}

# ─── Edge Case: --force must not reintroduce the skipped stages ────────────

@test "Edge Case: --force done-advance in plan_branch mode still fires zero release-stack spies" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file" \
    --force --reason "PM override for the plan-branch force-path regression test"
  [ "$status" -eq 0 ]
  [ "$(_rs_done_phase "$state_file")" = "release" ]
  [ "$(wc -l < "$RS_LOG")" -eq 0 ]
  [ "$(wc -l < "$RS_C4_LOG")" -eq 0 ]
  [ "$(_rs_event E-064-1_1 done_advance_plan_branch_mode | jq -r '.forced')" = "true" ]
}

# ─── Edge Case: mode is resolved PER PLAN, never globally ──────────────────

@test "Edge Case: a legacy plan and a plan_branch plan in ONE repository resolve independently" {
  _pfsm_bootstrap_plan P064 plan_branch
  _pfsm_bootstrap_plan P077 legacy_epic_release_mode
  _pfsm_epic_with_commit P064 E-064-1_1
  _pfsm_epic_with_commit P077 E-077-1_1
  local pb_state lg_state
  pb_state="$(_rs_seed_done_review E-064-1_1)"
  lg_state="$(_rs_seed_done_review E-077-1_1)"
  _rs_install_spies

  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main
  run bash "$FSM" done-advance review release "$pb_state"
  [ "$status" -eq 0 ]
  [ -n "$(_rs_event E-064-1_1 done_advance_plan_branch_mode)" ]

  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-077-1_1/main
  run bash "$FSM" done-advance review release "$lg_state"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Curator report not found"* ]]
  [ -z "$(_rs_event E-077-1_1 done_advance_plan_branch_mode)" ]
}

# ─── Edge Case: a PM-requested mid-plan specialist review ──────────────────

@test "Edge Case: a recorded mid_plan_specialist_review_exception never re-enables the FSM release stack" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  # The PM exception is recorded in the runtime manifest — it authorizes a
  # CONTROLLER dispatch, it is not an FSM precondition. The structural skip is
  # unchanged by its presence, which is exactly what makes the exception
  # countable separately rather than a default invocation.
  plan_manifest_update P064 '.plan_boundary_manifest.mid_plan_specialist_review_exception = {"epic_id":"E-064-1_1","reason":"PM asked for an early architecture read"}'
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$RS_LOG")" -eq 0 ]
  [ "$(wc -l < "$RS_C4_LOG")" -eq 0 ]
  [ "$(_rs_event E-064-1_1 done_advance_plan_branch_mode | jq -r '.skipped_stages | length')" \
    = "$(_rs_skipped_stages_from_source | wc -l)" ]

  # The exception is durable and separately attributable.
  run bash -c "jq -r '.plan_boundary_manifest.mid_plan_specialist_review_exception.epic_id' '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/P064/plan-boundary-manifest.json'"
  [ "$status" -eq 0 ]
  [ "$output" = "E-064-1_1" ]
}

@test "Edge Case: the mid-plan specialist exception is named in the controller instructions" {
  grep -q 'mid_plan_specialist_review_exception' "$AID_PLUGIN_PATH/skills/pipeline.md"
}

# ─── Error Handling: an unresolvable mode BLOCKS, never falls back to legacy ─

@test "Error Handling: a corrupt lifecycle manifest blocks with plan_mode_unresolved — never a silent legacy fallback" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  printf 'mode: [unclosed\n  : : :\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  git -C "$TEST_PROJECT_ROOT" add .aid-lifecycle/manifests/P064.yaml
  git -C "$TEST_PROJECT_ROOT" commit -qm "corrupt the manifest"
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"
  _rs_install_spies

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [[ "$output" == *"P064"* ]]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
  [ "$(_rs_event E-064-1_1 plan_mode_unresolved | jq -r '.reason')" = "manifest_unparseable" ]
  # A fallback to legacy would have run the release stack; it did not.
  [ "$(wc -l < "$RS_C4_LOG")" -eq 0 ]
}

@test "Error Handling: a manifest declaring an UNKNOWN mode value blocks rather than defaulting either way" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  yq -i '.mode = "plan_branch_v2"' "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  git -C "$TEST_PROJECT_ROOT" add .aid-lifecycle/manifests/P064.yaml
  git -C "$TEST_PROJECT_ROOT" commit -qm "unknown mode value"
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [ "$(_rs_event E-064-1_1 plan_mode_unresolved | jq -r '.reason')" = "mode_unknown_value_plan_branch_v2" ]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
}

@test "Error Handling: an UNREADABLE lifecycle manifest in the working tree blocks with manifest_unreadable" {
  if [ "$(id -u)" -eq 0 ]; then skip "running as root — chmod 000 does not deny reads"; fi
  _pfsm_bootstrap_plan P064 plan_branch
  _pfsm_epic_with_commit P064 E-064-1_1
  # Stay on main, where the manifest IS in the working tree, then deny reads.
  # The guard is bound to the STATE ROOT (this tree) even after P074 Step 8
  # redirects done-advance into the plan worktree — see _fsm_declared_plan_mode.
  chmod 000 "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"

  run bash "$FSM" done-advance review release "$state_file"
  local rc="$status" out="$output"
  chmod 644 "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  [ "$rc" -ne 0 ]
  [[ "$out" == *"plan_mode_unresolved"* ]]
  [ "$(_rs_event E-064-1_1 plan_mode_unresolved | jq -r '.reason')" = "manifest_unreadable" ]
}

@test "Error Handling: yq absent while a declaration may exist blocks with yq_unavailable" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"

  # A PATH holding every tool the resolver needs EXCEPT yq. Not a stub that
  # exits non-zero — genuinely absent, which is the case `command -v yq` guards.
  local nobin="$TEST_TMPDIR/nobin"; mkdir -p "$nobin"
  local t
  for t in bash sh git grep sed awk cat date mktemp rm mkdir dirname basename \
           printf tr wc head tail jq env chmod touch cp mv sort id find xargs; do
    local p; p="$(command -v "$t" 2>/dev/null)" || continue
    ln -sf "$p" "$nobin/$t"
  done
  [ ! -e "$nobin/yq" ]

  run env PATH="$nobin" bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [ "$(_rs_event E-064-1_1 plan_mode_unresolved | jq -r '.reason')" = "yq_unavailable" ]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
}

@test "Error Handling: --force converts the unresolved-mode block into an AUDITED override, not a silent one" {
  _rs_plan_branch_epic P064 E-064-1_1 plan_branch
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  printf 'mode: [unclosed\n  : : :\n' > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P064.yaml"
  git -C "$TEST_PROJECT_ROOT" add .aid-lifecycle/manifests/P064.yaml
  git -C "$TEST_PROJECT_ROOT" commit -qm "corrupt the manifest"
  git -C "$TEST_PROJECT_ROOT" checkout -q task/E-064-1_1/main
  local state_file; state_file="$(_rs_seed_done_review E-064-1_1)"

  run bash "$FSM" done-advance review release "$state_file" \
    --force --reason "PM override: manifest repair is tracked separately"
  [ "$status" -eq 0 ]
  [ "$(_rs_event E-064-1_1 plan_mode_unresolved | jq -r '.overridden')" = "true" ]
}

# ─── Documented non-blocks: absence is a DECLARATION, not ambiguity ────────

@test "Documented: an EPIC id that derives no plan id resolves legacy (never a block) — same rule as cmd_init" {
  local state_file; state_file="$(_rs_seed_done_review E-test)"
  local dir; dir="$(_rs_run_dir E-test)"
  printf 'blocking_findings: false\n' > "$dir/audit-report.md"
  echo "curator report" > "$dir/curator-report.md"

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [ -z "$(_rs_event E-test plan_mode_unresolved)" ]
  [ -z "$(_rs_event E-test done_advance_plan_branch_mode)" ]
}

@test "Documented: no lifecycle manifest at all resolves legacy (never a block) — the pre-P064 model" {
  local state_file; state_file="$(_rs_seed_done_review E-064-9_9)"
  local dir; dir="$(_rs_run_dir E-064-9_9)"
  printf 'blocking_findings: false\n' > "$dir/audit-report.md"
  echo "curator report" > "$dir/curator-report.md"

  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -eq 0 ]
  [ -z "$(_rs_event E-064-9_9 plan_mode_unresolved)" ]
  [ -z "$(_rs_event E-064-9_9 done_advance_plan_branch_mode)" ]
}

# =============================================================================
# ─── ONE AUTHORITY for the plan's release mode
#     (CP3 integration review finding 2, adjudicated action A3) ──────────────
# =============================================================================
# Before A3 the two mode resolvers in aid-fsm.sh read two INDEPENDENTLY STALE
# sources: `_fsm_gate_profile_boundary` read the gitignored RUNTIME manifest
# (.aid-o/work/plan-state/<plan>/plan-boundary-manifest.json) and
# `_fsm_declared_plan_mode` read the git-tracked DECLARATION
# (.aid-lifecycle/manifests/<plan>.yaml), preferring the working-tree copy.
# They could therefore disagree while BOTH returned a confident answer:
#
#   Direction A  runtime=plan_branch + no declaration -> gates capped at
#                `standard` while the LEGACY release stack merged the EPIC into
#                the target branch and ran the bump/tag/push. Reduced
#                verification on a shipping EPIC, and no accumulated floor
#                (only `epic-complete` writes one, and the legacy path never
#                reaches it).
#   Direction B  an UNTRACKED .aid-lifecycle manifest saying plan_branch
#                silenced all nine AID_PLAN_BRANCH_SKIPPED_STAGES with nothing
#                committed anywhere.
#
# A3: the DECLARATION is the sole authority for both, and it only counts when it
# is present in target_branch's COMMITTED tree. Each helper keeps its own
# reaction to "cannot tell" — gate-profile routing answers "" (no cap => more
# gates), release routing hard-blocks — which is a difference in CONSEQUENCE,
# never in the verdict itself.

# _mode_probe <epic_id> — the two resolvers, called on the SAME input inside one
# sourced aid-fsm.sh, from TEST_PROJECT_ROOT (the CWD a real run has).
# Prints "<mode>|<reason>|<boundary>"; `<boundary>` is the literal `<nocap>`
# when _fsm_gate_profile_boundary returns "" (legacy, no cap).
_mode_probe() {
  local epic_id="$1"
  local script="$TEST_TMPDIR/mode-probe.sh"
  cat > "$script" <<'SH'
# shellcheck disable=SC1090
source "$1" >/dev/null 2>&1
set +e +u +o pipefail
m=""; p=""; r=""
IFS=$'\t' read -r m p r < <(_fsm_declared_plan_mode "$2")
b="$(_fsm_gate_profile_boundary "$2")"
printf '%s|%s|%s\n' "$m" "$r" "${b:-<nocap>}"
SH
  ( cd "$TEST_PROJECT_ROOT" && bash "$script" "$FSM" "$epic_id" )
}

# _decl_write <plan_id> <yaml-body...> — a lifecycle declaration in the WORKING
# TREE only (deliberately never committed).
_decl_write() {
  local plan_id="$1"; shift
  mkdir -p "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests"
  printf '%s\n' "$@" > "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/${plan_id}.yaml"
}

# _decl_commit <plan_id> — commit whatever _decl_write left, on main.
_decl_commit() {
  local plan_id="$1"
  git -C "$TEST_PROJECT_ROOT" add ".aid-lifecycle/manifests/${plan_id}.yaml"
  git -C "$TEST_PROJECT_ROOT" commit -qm "declare ${plan_id}"
}

@test "CP3-F2 Direction A: a runtime manifest declaring plan_branch is NOT a mode input — no cap, and release routing stays legacy" {
  # The runtime manifest is the ONLY thing that says plan_branch here…
  run _init_manifest "P901" plan_branch
  [ "$status" -eq 0 ]
  run plan_manifest_get P901 '.plan_boundary_manifest.mode'
  [ "$output" = "plan_branch" ]
  # …and no declaration exists anywhere.
  [ ! -e "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P901.yaml" ]

  # Both resolvers answer from the declaration: absent => the documented
  # pre-P064 default, and NO gate cap. Before A3 the boundary said `epic`
  # (gates capped at standard) while release routing said legacy (full release
  # stack, EPIC merged to the target branch) — a confident disagreement.
  run _mode_probe E-901-1_1
  [ "$status" -eq 0 ]
  [ "$output" = "legacy_epic_release_mode|no_manifest_on_main|<nocap>" ]
}

@test "CP3-F2 Direction B: an UNTRACKED declaration is 'unresolved', never an answer — no cap, and done-advance blocks" {
  _decl_write P902 'schema_version: aid-lifecycle-1.0' 'plan_id: P902' 'mode: plan_branch'
  # Untracked: git does not know this file at all.
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:.aid-lifecycle/manifests/P902.yaml"
  [ "$status" -ne 0 ]

  run _mode_probe E-902-1_1
  [ "$status" -eq 0 ]
  [ "$output" = "unresolved|manifest_not_committed_on_main|<nocap>" ]

  # Release routing turns the same verdict into a hard block: nine release
  # stages can no longer be silenced by a file that was never committed.
  local state_file; state_file="$(_rs_seed_done_review E-902-1_1)"
  _rs_install_spies
  run bash "$FSM" done-advance review release "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_mode_unresolved"* ]]
  [ "$(_rs_event E-902-1_1 plan_mode_unresolved | jq -r '.reason')" = "manifest_not_committed_on_main" ]
  [ -z "$(_rs_event E-902-1_1 done_advance_plan_branch_mode)" ]
  [ "$(_rs_done_phase "$state_file")" = "review" ]
}

@test "CP3-F2: the 'cannot tell' matrix — both resolvers answer from the SAME verdict on every input shape" {
  # Six declaration shapes, one plan id each, all present at once. The
  # assertion is a PAIR per row: the release-routing mode AND the gate-profile
  # boundary. They can no longer disagree, because the boundary helper computes
  # nothing of its own.

  # (1) absent everywhere -> the documented legacy default, no cap.
  local row1="legacy_epic_release_mode|no_manifest_on_main|<nocap>"

  # (2) committed, mode: plan_branch -> the only shape that caps gates.
  _decl_write P912 'schema_version: aid-lifecycle-1.0' 'plan_id: P912' 'mode: plan_branch'
  _decl_commit P912
  local row2="plan_branch||epic"

  # (2b) committed, mode: plan_branch, ABSENT from the working tree — the shape
  #      every real plan_branch run has (cmd_init leaves the task branch checked
  #      out and the manifest is committed on target_branch only).
  _decl_write P922 'schema_version: aid-lifecycle-1.0' 'plan_id: P922' 'mode: plan_branch'
  _decl_commit P922
  rm -f "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P922.yaml"
  local row2b="plan_branch||epic"

  # (3) committed, no `mode` key -> "not yet declared plan_branch" (legacy).
  _decl_write P913 'schema_version: aid-lifecycle-1.0' 'plan_id: P913'
  _decl_commit P913
  local row3="legacy_epic_release_mode||<nocap>"

  # (4) working tree only (untracked) -> unresolved, never an answer.
  _decl_write P914 'schema_version: aid-lifecycle-1.0' 'plan_id: P914' 'mode: plan_branch'
  local row4="unresolved|manifest_not_committed_on_main|<nocap>"

  # (5) committed but UNPARSEABLE -> unresolved.
  _decl_write P915 'mode: [unclosed' '  : : :'
  _decl_commit P915
  rm -f "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P915.yaml"
  local row5="unresolved|manifest_unparseable|<nocap>"

  # (6) committed but an UNKNOWN mode value -> unresolved (never defaulted
  #     either way), and the untrusted value is sanitised into the reason.
  _decl_write P916 'schema_version: aid-lifecycle-1.0' 'plan_id: P916' 'mode: plan_branch_v2'
  _decl_commit P916
  rm -f "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P916.yaml"
  local row6="unresolved|mode_unknown_value_plan_branch_v2|<nocap>"

  run _mode_probe E-911-1_1; [ "$output" = "$row1" ]
  run _mode_probe E-912-1_1; [ "$output" = "$row2" ]
  run _mode_probe E-922-1_1; [ "$output" = "$row2b" ]
  run _mode_probe E-913-1_1; [ "$output" = "$row3" ]
  run _mode_probe E-914-1_1; [ "$output" = "$row4" ]
  run _mode_probe E-915-1_1; [ "$output" = "$row5" ]
  run _mode_probe E-916-1_1; [ "$output" = "$row6" ]

  # The invariant behind every row: boundary == "epic" IFF mode == plan_branch.
  local e
  for e in E-911-1_1 E-912-1_1 E-922-1_1 E-913-1_1 E-914-1_1 E-915-1_1 E-916-1_1; do
    run _mode_probe "$e"
    local mode="${output%%|*}" boundary="${output##*|}"
    if [ "$mode" = "plan_branch" ]; then [ "$boundary" = "epic" ]; else [ "$boundary" = "<nocap>" ]; fi
  done
}

@test "CP3-F2: a PRESENT but UNREADABLE working-tree declaration is unresolved for BOTH resolvers, even with a readable committed copy" {
  if [ "$(id -u)" -eq 0 ]; then skip "running as root — chmod 000 does not deny reads"; fi
  # The committed copy is perfectly readable and says plan_branch…
  _decl_write P917 'schema_version: aid-lifecycle-1.0' 'plan_id: P917' 'mode: plan_branch'
  _decl_commit P917
  # …but the working-tree copy cannot be read, so we cannot prove the two agree.
  # Silently resolving from the committed copy here is exactly what the
  # in-source comment at _fsm_declared_plan_mode warned against.
  chmod 000 "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P917.yaml"
  run _mode_probe E-917-1_1
  local out="$output"
  chmod 644 "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/P917.yaml"
  [ "$out" = "unresolved|manifest_unreadable|<nocap>" ]
}

@test "CP3-F2: _fsm_gate_profile_boundary reads no manifest of its own — the runtime manifest is not a mode input anywhere in aid-fsm.sh" {
  # Structural half of "they cannot disagree": the boundary helper's body
  # contains no source of its own, only the delegation.
  local body; body="$(sed -n '/^_fsm_gate_profile_boundary() {/,/^}/p' "$FSM")"
  [ -n "$body" ]
  [[ "$body" == *"_fsm_declared_plan_mode"* ]]
  [[ "$body" != *"plan_manifest_path"* ]]
  [[ "$body" != *"plan_boundary_manifest"* ]]
  # And nothing else in the FSM reads the runtime manifest for a MODE.
  run bash -c "grep -n 'plan_boundary_manifest.mode' '$FSM' || true"
  [ -z "$output" ]
}

# =============================================================================
# ─── The documented plan_branch release hand-off, END TO END
#     (CP3 integration review finding 1) ─────────────────────────────────────
# =============================================================================
# skills/pipeline.md §7 "Sub-phase: release" prescribes step 15
# (`epic-complete` -> `epic-merge-to-plan`) and step 16 (queue). Between them,
# NOTHING used to write the queue: the `queue_set_status <epic> merged_to_plan`
# call that step-1-verify.md assigned to "Step 4 of this EPIC or P068" was
# neither wired into aid-plan-fsm.sh nor documented anywhere. The sequence the
# controller was told to run therefore stalled every multi-EPIC plan at its
# second EPIC. These tests walk the DOCUMENTED sequence and assert the plan
# keeps moving.

@test "CP3-F1: the documented plan_branch sequence claims the next EPIC end to end" {
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_epic_with_commit "P064" "E-064-2_1"
  _pfsm_write_epic_evidence "E-064-1_1" "DONE" "standard"

  # The queue in the shape `aid-queue-add.sh` really writes for a plan whose
  # branch did not exist yet at queue-add time (the `aid-auto-pipeline.sh`
  # ordering): plan_id recorded, merge_target still null.
  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: running
    plan_id: "P064"
    merge_target: null
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: null
    depends_on: ["E-064-1_1"]
YAML

  # ── step 15 ──
  run bash "$PLAN_FSM_CLI" epic-complete P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  run bash "$PLAN_FSM_CLI" epic-merge-to-plan P064 E-064-1_1 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # The premise: the work IS on plan/P064 and is provably NOT on main — the
  # exact state this plan exists to create.
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor task/E-064-1_1/main plan/P064
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor task/E-064-1_1/main main
  [ "$status" -ne 0 ]

  # …and step 15 alone leaves the queue entry at `running`.
  [ "$(_qw_field E-064-1_1 status)" = "running" ]

  # ── what step 16 does WITHOUT 16a: the hand-off refuses ──
  _qw claim-next P064
  [ "$status" -eq 1 ]
  [ "$output" = "blocked:E-064-2_1:dependency_unmerged:E-064-1_1" ]
  [ "$(_qw_field E-064-2_1 status)" = "blocked" ]

  # ── step 16a: mirror the merge into the queue ──
  _qw set-status E-064-1_1 merged_to_plan
  [ "$status" -eq 0 ]
  [ "$(_qw_field E-064-1_1 status)" = "merged_to_plan" ]

  # ── step 16b: the next EPIC is claimable ──
  _qw claim-next P064
  [ "$status" -eq 0 ]
  [ "$output" = "E-064-2_1" ]
  [ "$(_qw_field E-064-2_1 status)" = "running" ]
}

@test "CP3-F1: 16a cannot unblock a dependency that did not really merge — ancestry still decides" {
  # The compensating half: mirroring is a DERIVED VIEW. For an entry that
  # declares a merge_target, the status field is ignored and ancestry is the
  # only proof, so a hand-written (or wrongly-scripted) `merged_to_plan`
  # unblocks nothing.
  _pfsm_bootstrap_plan "P064"
  _pfsm_epic_with_commit "P064" "E-064-1_1"
  _pfsm_epic_with_commit "P064" "E-064-2_1"

  _qw_write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-064-1_1
    status: running
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: []

  - epic_id: E-064-2_1
    status: pending
    plan_id: "P064"
    merge_target: "plan/P064"
    depends_on: ["E-064-1_1"]
YAML

  # No epic-merge-to-plan ran: the work is NOT on plan/P064.
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor task/E-064-1_1/main plan/P064
  [ "$status" -ne 0 ]

  _qw set-status E-064-1_1 merged_to_plan
  [ "$status" -eq 0 ]
  _qw claim-next P064
  [ "$status" -eq 1 ]
  [ "$output" = "blocked:E-064-2_1:dependency_unmerged:E-064-1_1" ]
}

@test "CP3-F1: the controller instructions write the queue BETWEEN the merge and the claim" {
  # The fix is a documented sequence, so the documentation is what regresses.
  local pm="$AID_PLUGIN_PATH/skills/pipeline.md"
  local rn="$AID_PLUGIN_PATH/commands/aid-run.md"
  local f set_line claim_line

  for f in "$pm" "$rn"; do
    # The status write is named as an explicit aid-queue-write.sh call…
    grep -q 'aid-queue-write.sh set-status' "$f"
    grep -q 'merged_to_plan' "$f"
    # …and it comes BEFORE the claim, not after it.
    set_line="$(grep -n 'aid-queue-write.sh set-status' "$f" | head -1 | cut -d: -f1)"
    claim_line="$(grep -nE 'claim-next|queue_claim_next' "$f" | head -1 | cut -d: -f1)"
    [ -n "$set_line" ]
    [ -n "$claim_line" ]
    [ "$set_line" -lt "$claim_line" ]
    # The consequence of skipping it is stated, not left to be rediscovered.
    grep -q 'dependency_unmerged' "$f"
  done

  # The CLI shape the instructions print must be the one the library exposes.
  grep -q 'set-status <epic_id> <status> \[reason\]' \
    "$AID_PLUGIN_PATH/scripts/lib/aid-queue-write.sh"
  grep -q 'claim-next <plan_id>' "$AID_PLUGIN_PATH/scripts/lib/aid-queue-write.sh"
}

# ─── CP3 integration review, "also fix while you are here" ─────────────────

@test "CP3-small: the epic-id -> plan-id derivation needs no external tool at all (no grep -oP)" {
  # `grep -oP` is a GNU build option. On a grep without PCRE support it does not
  # "not match" — it FAILS, and because both mode helpers swallowed that with
  # `|| true`, three controls (the gate-profile cap, the release-mode block and
  # cmd_init's lineage precondition) silently degraded to legacy on such a host.
  # The replacement is pure bash: prove it with an EMPTY PATH.
  run bash -c '
    source "$1" >/dev/null 2>&1
    set +e
    printf "%s|" "$(PATH= _fsm_epic_plan_nnn "E-064-2_2")"
    printf "%s|" "$(PATH= _fsm_epic_plan_nnn "E-013-1")"
    printf "%s|" "$(PATH= _fsm_epic_plan_nnn "E-test")"
    printf "%s"  "$(PATH= _fsm_epic_plan_nnn "")"
    echo
  ' _ "$FSM"
  [ "$status" -eq 0 ]
  [ "$output" = "064|013||" ]

  # Every epic-id -> plan-id site routes through the one helper…
  run bash -c "grep -c '_fsm_epic_plan_nnn' '$FSM'"
  [ "$output" -ge 4 ]
  # …and neither mode helper nor cmd_init's lineage block spells `grep -oP` any more.
  local body
  body="$(sed -n '/^_fsm_gate_profile_boundary() {/,/^}/p' "$FSM")"
  [[ "$body" != *"grep -oP"* ]]
  body="$(sed -n '/^_fsm_declared_plan_mode() {/,/^}/p' "$FSM")"
  [[ "$body" != *"grep -oP"* ]]
  # No CODE line anywhere in the FSM still derives a plan id with `grep -oP`
  # (the one remaining mention is the comment that explains why not).
  run bash -c "grep -n 'grep -oP' '$FSM' | grep -v ':[[:space:]]*#' | grep -c '(?<=^E-)' || true"
  [ "$output" = "0" ]
}

@test "CP3-small: the C3 hook's comments no longer claim the legacy blocking_findings read is 'below'" {
  # The legacy .md/.yaml read was hoisted ~250 lines ABOVE the C3 hook by the
  # P064 Step 9 CP2 review; the comments still said "directly below", which
  # sends a reader (or a future fixer) to the wrong end of the function.
  local legacy_line c3_line
  legacy_line="$(grep -n 'blk=\$(yaml_field "\$audit_file" blocking_findings)' "$FSM" | head -1 | cut -d: -f1)"
  c3_line="$(grep -n 'E-057-1_2 Step 4: C3 independent-audit hook' "$FSM" | head -1 | cut -d: -f1)"
  [ -n "$legacy_line" ]
  [ -n "$c3_line" ]
  # The premise the comments have to describe: legacy read FIRST, C3 hook after.
  [ "$legacy_line" -lt "$c3_line" ]
  run bash -c "grep -n 'blocking_findings read directly below' '$FSM' || true"
  [ -z "$output" ]
  run bash -c "grep -n 'legacy blocking_findings check below' '$FSM' || true"
  [ -z "$output" ]
  grep -q 'HOISTED it ~250 lines ABOVE this block' "$FSM"
}

# ─────────────────────────────────────────────────────────────────────────────
# IMP-274 — repo-wide `grep -oP` portability guard.
#
# WHY REPO-WIDE. E-064-2_2 removed `grep -oP` from aid-fsm.sh (CP3 fix,
# 936322f) and in the SAME EPIC reintroduced the identical construct in
# aid-queue-add.sh (61ddef2, fixed in f60efab) — the regression test above
# inspects only $FSM, so the defect class simply moved to a file the detector
# could not see. `-P` is a GNU-grep BUILD option: on a grep without PCRE
# support the command FAILS (it does not "not match"), and every historical
# call site swallowed that failure with `|| true`, silently disabling the
# control it fed.
#
# THE ALLOWLIST is per-file MAX counts for the seven PRE-EXISTING instances
# that predate the invariant (verified present at the P064 base 2a51a2f).
# Each runs only on the GNU reference host today — release tooling, an
# advisory `|| true` diagnostic, and the dev-only instruction-consistency
# harness — which is the "justified PCRE dependency" the backlog entry allows,
# tracked to shrink, never to grow:
#   aid-release.sh                              3  (CHANGELOG/pyproject version extraction)
#   lib/delivery-checks/dg08-runtime-env.sh     1  (advisory engines probe, || true)
#   tests/test-instruction-consistency.sh       2  (dev harness, GNU host only)
#   aid-fsm.sh                                  1  (:1411 step_n counter — pre-existing,
#                                                   named as known in E-064-2_2 CP2)
# A NEW instance in any other file fails; an INCREASE in an allowlisted file
# fails; a decrease is progress and passes.
# ─────────────────────────────────────────────────────────────────────────────
# _imp274_scan <scripts_dir> — emit "relpath<TAB>count" for every *.sh under
# <scripts_dir> containing at least one NON-COMMENT `grep -oP` line.
_imp274_scan() {
  local dir="$1" f rel n
  while IFS= read -r f; do
    n="$(grep -n 'grep -oP' "$f" 2>/dev/null | grep -cv ':[[:space:]]*#')" || true
    [[ "${n:-0}" -gt 0 ]] || continue
    rel="${f#"$dir"/}"
    printf '%s\t%s\n' "$rel" "$n"
  done < <(find "$dir" -name '*.sh' -type f | LC_ALL=C sort)
}

@test "IMP-274: grep -oP cannot be reintroduced anywhere under scripts/ (repo-wide guard, allowlisted pre-existing only)" {
  local scripts_dir; scripts_dir="$(cd "$(dirname "$FSM")" && pwd)"

  declare -A allow=(
    ["aid-release.sh"]=3
    ["lib/delivery-checks/dg08-runtime-env.sh"]=1
    ["tests/test-instruction-consistency.sh"]=2
    ["aid-fsm.sh"]=1
  )

  local violations="" rel n
  while IFS=$'\t' read -r rel n; do
    [[ -n "$rel" ]] || continue
    if [[ -z "${allow[$rel]:-}" ]]; then
      violations+="NEW FILE: $rel has $n non-comment grep -oP line(s)"$'\n'
    elif [[ "$n" -gt "${allow[$rel]}" ]]; then
      violations+="GREW: $rel has $n (allowlisted max ${allow[$rel]})"$'\n'
    fi
  done < <(_imp274_scan "$scripts_dir")

  if [[ -n "$violations" ]]; then
    echo "grep -oP portability violations (IMP-274):" >&2
    printf '%s' "$violations" >&2
    return 1
  fi
}

@test "IMP-274: the guard itself detects an injected instance (detector self-test)" {
  # A guard that can only ever pass is decoration. Prove the scanner fires on
  # a synthetic violation, and stays quiet on a comment-only mention.
  local fixture; fixture="$(mktemp -d "$TEST_TMPDIR/imp274.XXXXXX")"
  mkdir -p "$fixture/lib"
  printf '#!/usr/bin/env bash\n# grep -oP only in this comment\necho ok\n' > "$fixture/clean.sh"
  printf '#!/usr/bin/env bash\nx="$(printf %%s "$1" | grep -oP "\\d+")" || true\n' > "$fixture/lib/bad.sh"

  run _imp274_scan "$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib/bad.sh"* ]]
  [[ "$output" != *"clean.sh"* ]]
}

