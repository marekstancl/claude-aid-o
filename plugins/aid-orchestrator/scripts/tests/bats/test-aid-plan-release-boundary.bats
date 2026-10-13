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
# This suite is `# aid-tier: t2`: it runs in the NIGHTLY portfolio and never on
# the merge path. It used to have a dedicated push-triggered CI job
# (`plan-boundary-tests`) and a DELEGATED exclusion in run-all-tests.sh; both
# were removed 2026-08-14 (see that suite's twin note and
# scripts/tests/test-tier-ci-topology.sh).

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
  # The plugin-issues file exists, so its one-time "created" note (stderr)
  # does not land in the `run` output the cases compare exactly.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work" && : > "$TEST_PROJECT_ROOT/.aid-o/work/aid-plugin-issues.md"

  # shellcheck disable=SC1090
  source "$PLAN_STATE_LIB"      # also sources $LOCK_LIB (see its own header)
  # shellcheck disable=SC1090
  source "$PLAN_MANIFEST_LIB"   # also sources $LOCK_LIB + aid-gate-profile-select.sh
  # shellcheck disable=SC1090
  source "$LIFECYCLE_LIB"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixtures ────────────────────────────────────────────────────────────

# _state_file <plan_id> — the canonical state file path, reconstructed
# independently of the library's own (private) path helper.
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

# ─── AC4: a resumed command with no --op-id derives the same op_id as the
#          crashed original and finds its record ───────────────────────────

# ─── AC3: plan_op_reconcile returns git_applied for an operation whose
#          git_applied record exists but whose state_committed record does
#          not ─────────────────────────────────────────────────────────────


@test "plan_op_reconcile: none when operations.jsonl has no record for the op_id (including no file at all)" {
  _init_plan "P064"
  run plan_op_reconcile "P064" "some-op-id-nobody-wrote"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

# ─── AC5: negative test on key uniqueness — after epic-merge-to-plan for one
#          EPIC records state_committed, the same command for a second EPIC
#          still executes: distinct subjects never share a key ────────────

# ─── AC7: a truncated final line in operations.jsonl produces a non-zero
#          exit that names the line number ─────────────────────────────────


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


# ─── Corruption isolation: _plan_op_last_command_subject must skip unparseable
#     lines elsewhere in the file, not fail silently ──────────────────────────

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
# P097 Step 4: the rank is the declaration index in the project's own
# gate_profiles table, read from $(aid_state_root)/.aid-o/config/execution.yaml
# (here: AID_PLAN_MANIFEST_PROJECT_ROOT = TEST_PROJECT_ROOT). The function
# keeps its <plan_id> <profile> signature.
_write_profile_table() {  # [names...] in declared order (default: the four)
  local -a names=("$@"); (( ${#names[@]} )) || names=(targeted standard full release)
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  { printf 'gates:\n  g:\n    command: "true"\n    required: true\ndefault_profile: %s\ngate_profiles:\n' "${names[0]}"
    local n; for n in "${names[@]}"; do printf '  %s:\n    include: [g]\n' "$n"; done
  } > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

@test "P097 Step 4: plan_manifest_raise_final_profile reads the table from the state root's execution.yaml — a name it does not declare is refused, the first raise records profile_table" {
  _init_manifest "P900"
  _write_profile_table
  run plan_manifest_raise_final_profile "P900" "nightly"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not declared"* ]]
  run plan_manifest_raise_final_profile "P900" "full"
  [ "$status" -eq 0 ]
  run plan_manifest_get P900 '.plan_boundary_manifest.profile_table | join(",")'
  [ "$output" = "targeted,standard,full,release" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]
}

@test "P097 Step 4: a raise whose file order differs from the manifest's recorded profile_table refuses with profile_table_changed and writes nothing" {
  _init_manifest "P900"
  _write_profile_table
  plan_manifest_raise_final_profile "P900" "standard"
  _write_profile_table standard targeted full release
  run plan_manifest_raise_final_profile "P900" "release"
  [ "$status" -eq 1 ]
  [[ "$output" == *"profile_table_changed"* ]]
  run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "standard" ]
  run plan_manifest_get P900 '.plan_boundary_manifest.profile_table | join(",")'
  [ "$output" = "targeted,standard,full,release" ]
}

# ─── AC2: raising to a LOWER profile than current is a documented no-op ────
@test "AC2: plan_manifest_raise_final_profile to a LOWER profile than current is a no-op, current value unchanged" {
  _init_manifest "P900"
  _write_profile_table
  plan_manifest_update P900 '.plan_boundary_manifest.plan_final_required_profile = "standard"'

  run plan_manifest_raise_final_profile "P900" "targeted"
  [ "$status" -eq 0 ]

  run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "standard" ]
}

@test "plan_manifest_raise_final_profile: raising to a HIGHER profile actually raises it" {
  _init_manifest "P900"
  _write_profile_table
  plan_manifest_update P900 '.plan_boundary_manifest.plan_final_required_profile = "standard"'

  run plan_manifest_raise_final_profile "P900" "full"
  [ "$status" -eq 0 ]

  run plan_manifest_get P900 '.plan_boundary_manifest.plan_final_required_profile'
  [ "$output" = "full" ]
}

@test "plan_manifest_raise_final_profile: never decreases across two sequential calls (up then down)" {
  _init_manifest "P900"
  _write_profile_table
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
  _write_profile_table
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









@test "plan-state --repair refuses to run once the plan is past PLAN_SYNC" {
  _pfsm_bootstrap_plan "P064"
  plan_state_transition "P064" "OPEN" "EPIC_INTEGRATION"
  plan_state_transition "P064" "EPIC_INTEGRATION" "PLAN_SYNC"
  plan_state_transition "P064" "PLAN_SYNC" "PLAN_GATES"

  run bash "$PLAN_FSM_CLI" plan-state P064 --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"past PLAN_SYNC"* ]]
}


# ─── IMP-265b: healthy repair is a non-destructive no-op ─────────────────────


# ─── IMP-258: repair propagates per-entry write failures ─────────────────────

# ─── IMP-267: attestation re-derives ancestry from Git ───────────────────────


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




# ─── IMP-273: cmd_init routes its mode decision through the ONE committed-tree,
#     fail-closed authority (_fsm_declared_plan_mode) — the same resolver
#     done-advance uses. Every "cannot determine the mode" becomes
#     `plan_mode_unresolved` (a hard block with the audited --force override),
#     never a silent legacy downgrade that would skip THIS lineage precondition.
#     _fsm_init_timeline <state_file> — the timeline cmd_init writes for a block,
#     derived from the state file's own evidence dir (state file itself is absent
#     on a fresh init, so its DIRECTORY is the stable anchor).
_fsm_init_timeline() { echo "$(dirname "$1")/timeline.jsonl"; }


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




@test "Edge Case: an EPIC id that derives no plan id (ad-hoc EPIC) is a no-op, init succeeds normally" {
  local args; args="$(build_default_init_args E-test)"
  run "$FSM" init $args
  [ "$status" -eq 0 ]
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






# ─── AC1: only plan/<plan_id> moves ────────────────────────────────────────

# ─── AC2: crash after the Git merge converges on re-run ────────────────────

# ─── Edge Case: already merged — converge, never a second merge ────────────

# ─── AC3: the four pre-merge blocks (dirty worktree, MERGE_HEAD, unmerged
#          index path, stale --expected-plan-sha) ─────────────────────────────




# ─── AC4: state:DONE + a deleted task branch is NOT proof ──────────────────

# ─── Edge Case: deleted branch + a proven merge commit is still merged ─────

# ─── AC5: a conflict transitions to CONFLICT and records NO completion ─────

# ─── Security: the merge command never touches lineage ─────────────────────

# ─── epic-complete ─────────────────────────────────────────────────────────








# ─── CP2 fix regressions (E-064-2_2 Step 1) ────────────────────────────────
# Five defects found by the CP2 review of the commands above. Each test here
# fails against the pre-fix command and passes after it; none of them is an
# acceptance criterion of the step, so none carries an `ACn:` prefix.








# =============================================================================
# ─── Boundary-split gate profiles + self-host activation
#     (P064 EPIC E-064-2_2 Step 3 = plan Step 8) ─────────────────────────────
# =============================================================================
# P097 Step 4 replaced the two-question resolver with the project's own
# ordered gate_profiles table (lib/aid-gate-profile-select.sh): the EPIC's run
# profile is the widest declared profile whose when_paths matches, else
# default_profile; `epic-complete` records the wider of that and the run's
# profile into the plan-boundary manifest; the plan-final stage runs at least
# `release`.
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
#   AC8  test-aid-fsm.bats stays green (run, not asserted here)

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



# ─── lib/aid-gate-profile-select.sh — the table resolver (P097 Step 4) ─────
# The boundary split (cap at standard, out-of-band floor) is gone: an EPIC's
# run profile is the last declared profile whose when_paths matches, else
# default_profile, and the plan-final run is always at least `release`
# (gate_profile_wider by declaration index). The library's own suite is
# test-aid-gate-profile-select.bats; this is the sourced-through-manifest check.

@test "P097 Step 4: gate_profile_for_paths and gate_profile_wider are callable through the sourced manifest library" {
  _write_profile_table
  yq -i '.gate_profiles.full.when_paths = ["*/aid-fsm.sh"]' "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  local paths; paths="$(_gp_paths_file "plugins/aid-orchestrator/scripts/aid-fsm.sh")"
  run gate_profile_for_paths "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" "$paths"
  [ "$output" = "full" ]
  run gate_profile_wider "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" standard release
  [ "$output" = "release" ]
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
  for p in $(yq -r '.gate_profiles | keys | .[]' "$cfg"); do
    run _gp_yq_jq "$cfg" "(.gate_profiles[\"${p}\"].include | length) > 0"
    [ "$status" -eq 0 ]
    run _gp_yq_jq "$cfg" "([.gate_profiles[\"${p}\"].include[]] - [.gates | keys[]] | length) == 0"
    [ "$status" -eq 0 ]
  done
}

# ─── aid-plan-fsm.sh epic-complete — recording the floor ───────────────────





# ─── CP3 integration review finding 3: the floor reflects RISK, not the
#     EPIC's own done_phase ────────────────────────────────────────────────




# ─── aid-fsm.sh — the boundary-aware GATES:DONE recompute ──────────────────




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
  # A closed passing EPIC review round (cp3): every done-advance needs one (P094).
  # Bound to the root commit, an ancestor of every tree the advance may
  # evaluate; a case that needs the freshness check to see no later commit
  # re-seeds it at the head it advances from.
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/plugin.yaml" <<YAML
plugin_path: "$AID_PLUGIN_PATH"
dispatch_mode: subagent
YAML
  echo "$dir/fsm-state.yaml"
}

# _rs_install_spies — the spy harness: a temp directory
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



# _rs_event <epic_id> <event> — the LAST timeline event of that name, as JSON.
_rs_event() {
  local dir; dir="$(_rs_run_dir "$1")"
  jq -c --arg e "$2" 'select(.event==$e)' "$dir/timeline.jsonl" 2>/dev/null | tail -1
}

_rs_done_phase() {
  grep '^done_phase:' "$1" | awk '{print $2}'
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

# ─── AC2: the legacy-mode positive inverse ─────────────────────────────────



# ─── AC3: the skip is SCOPED, not blanket ──────────────────────────────────



# ─── AC4: the emitted list IS the source constant ──────────────────────────


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



# ─── Step 4 CP2 finding 4: the no-jq fallback must not lie about its type ───
# log_event (lib/aid-stage-log.sh) passes a value through as raw JSON only when
# it starts with '[' or '{'. The old jq-less fallback produced
# `c3_review_profile_presence,cp4_...`, which starts with 'c' and was emitted as
# a QUOTED STRING — every consumer doing `.skipped_stages[]` (including AC4's
# own assertion) broke on a jq-less host, silently degrading the telemetry
# contract while every other jq-dependent check in this function fails closed.


# ─── Step 4 CP2 finding 5: an unresolved-mode --force is AUDITABLE ─────────
# The run timeline is not the surface a PM audits. `fsm_handle_force_override`
# writes .aid-o/work/audit-log.jsonl with a GENERIC force carrying whatever
# --blocked-checks the operator typed, so an audit of that file alone could not
# tell that this EPIC advanced without knowing whether it was supposed to merge
# to the target branch.


# ─── Step 4 CP2 findings 2 + 7: the prose must match the FSM ───────────────

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


# ─── Edge Case: mode is resolved PER PLAN, never globally ──────────────────


# ─── Edge Case: a PM-requested mid-plan specialist review ──────────────────


# ─── Error Handling: an unresolvable mode BLOCKS, never falls back to legacy ─






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

# ─────────────────────────────────────────────────────────────────────────────
# IMP-274 — repo-wide `grep -oP` portability guard.
#
# WHY REPO-WIDE. E-064-2_2 removed `grep -oP` from aid-fsm.sh (CP3 fix,
# 936322f) and in the SAME EPIC reintroduced the identical construct in
# the former queue writer (61ddef2, fixed in f60efab) — the regression test above
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

