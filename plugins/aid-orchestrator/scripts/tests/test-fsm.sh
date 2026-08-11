#!/usr/bin/env bats
# aid-tier: t2
# Tests for aid-fsm.sh

setup() {
  TEST_DIR=$(mktemp -d)
  STATE_FILE="$TEST_DIR/fsm-state.yaml"
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  FSM="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-fsm.sh"

  # P032 Step 2: cmd_init now PRE-FLIGHT-enforces a git working tree.
  # Initialize a minimal repo in TEST_DIR so init_state's git checks succeed.
  ( cd "$TEST_DIR" && git init -q \
      && git config user.email t@t.io && git config user.name T \
      && echo init > .gitkeep && git add .gitkeep && git commit -q -m initial )

  # Helper: init a fresh state file
  init_state() {
    "$FSM" init "E-001" "run-001" "5" "auto" "v2/redesign" "abc123" "$STATE_FILE" 2>/dev/null
  }

  # These are state-machine UNIT tests: they exercise transition validity, state
  # updates, and counters in isolation. The precondition layer that cmd_transition
  # / increment-step enforce (plan.json, gates evidence, step-verify.md, CP2/CP3
  # verifier outputs — all added across P032/P040/Session-A+B after these tests were
  # written) is NOT what these mechanics tests assert; its real block/pass behaviour
  # is covered separately by the "precondition layer" tests at the END of this file,
  # which call transition WITHOUT --force. Here we bypass it with --force, which still
  # runs the transition whitelist + side-effects (escalation_count, done_phase) and
  # only skips the precondition fixtures. --force requires a 20+ char audit reason.
  FORCE_REASON="unit test: isolate FSM state-machine mechanics from precondition layer"
  # Transition with precondition layer bypassed (mechanics under test).
  fsm_tr() { "$FSM" transition "$1" "$2" "$STATE_FILE" --force --reason "$FORCE_REASON" 2>/dev/null; }
  # Increment step with precondition layer bypassed (counter mechanics under test).
  fsm_inc() { "$FSM" increment-step "$STATE_FILE" --force --reason "$FORCE_REASON" 2>/dev/null; }

  # Run all tests with TEST_DIR as cwd so PRE-FLIGHT git checks have a repo.
  cd "$TEST_DIR"
}

teardown() { rm -rf "$TEST_DIR"; }

# --- init ---

@test "init creates state file with READY state" {
  run "$FSM" init "E-001" "run-001" "5" "auto" "v2/redesign" "abc123" "$STATE_FILE"
  [ "$status" -eq 0 ]
  [ -f "$STATE_FILE" ]
  run grep '^state: READY' "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "init with existing state_file exits 1" {
  init_state
  run "$FSM" init "E-001" "run-001" "5" "auto" "v2/redesign" "abc123" "$STATE_FILE"
  [ "$status" -eq 1 ]
}

@test "init stores epic_id and run_id" {
  init_state
  run grep '^epic_id: E-001' "$STATE_FILE"
  [ "$status" -eq 0 ]
  run grep '^run_id: run-001' "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "init sets current_step to 0" {
  init_state
  run grep '^current_step: 0' "$STATE_FILE"
  [ "$status" -eq 0 ]
}

# --- valid transitions ---

@test "transition READY to EXECUTE succeeds" {
  init_state
  run fsm_tr READY EXECUTE
  [ "$status" -eq 0 ]
  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "EXECUTE" ]
}

@test "transition EXECUTE to GATES succeeds" {
  init_state
  fsm_tr READY EXECUTE
  run fsm_tr EXECUTE GATES
  [ "$status" -eq 0 ]
}

@test "transition EXECUTE to ESCALATION succeeds" {
  init_state
  fsm_tr READY EXECUTE
  run fsm_tr EXECUTE ESCALATION
  [ "$status" -eq 0 ]
}

@test "transition GATES to DONE succeeds" {
  init_state
  fsm_tr READY EXECUTE
  fsm_tr EXECUTE GATES
  run fsm_tr GATES DONE
  [ "$status" -eq 0 ]
}

@test "transition GATES to EXECUTE (retry) succeeds" {
  init_state
  fsm_tr READY EXECUTE
  fsm_tr EXECUTE GATES
  run fsm_tr GATES EXECUTE
  [ "$status" -eq 0 ]
}

@test "transition ESCALATION to EXECUTE succeeds" {
  init_state
  fsm_tr READY EXECUTE
  fsm_tr EXECUTE ESCALATION
  run fsm_tr ESCALATION EXECUTE
  [ "$status" -eq 0 ]
}

@test "transition ESCALATION to GATES (skip gate) succeeds" {
  init_state
  fsm_tr READY EXECUTE
  fsm_tr EXECUTE ESCALATION
  run fsm_tr ESCALATION GATES
  [ "$status" -eq 0 ]
}

@test "EXECUTE to EXECUTE (internal loop) succeeds" {
  init_state
  fsm_tr READY EXECUTE
  run fsm_tr EXECUTE EXECUTE
  [ "$status" -eq 0 ]
}

# --- invalid transitions ---

@test "transition READY to DONE is rejected" {
  init_state
  run "$FSM" transition READY DONE "$STATE_FILE"
  [ "$status" -eq 1 ]
}

@test "transition READY to GATES is rejected" {
  init_state
  run "$FSM" transition READY GATES "$STATE_FILE"
  [ "$status" -eq 1 ]
}

@test "transition DONE to EXECUTE is rejected" {
  init_state
  fsm_tr READY EXECUTE
  fsm_tr EXECUTE GATES
  fsm_tr GATES DONE
  # DONE→EXECUTE is not in the whitelist; rejection happens before the
  # precondition layer, so the assertion uses the real (non-forced) call.
  run "$FSM" transition DONE EXECUTE "$STATE_FILE"
  [ "$status" -eq 1 ]
}

@test "transition with wrong current state exits 1" {
  init_state
  run "$FSM" transition EXECUTE GATES "$STATE_FILE"
  [ "$status" -eq 1 ]
  run bash -c "\"$FSM\" transition EXECUTE GATES \"$STATE_FILE\" 2>&1"
  [[ "$output" =~ "expected state EXECUTE but found READY" ]]
}

@test "transition to invalid state name exits 1" {
  init_state
  run "$FSM" transition READY INVALID_STATE "$STATE_FILE"
  [ "$status" -eq 1 ]
}

# --- escalation_count ---

@test "transition to ESCALATION increments escalation_count" {
  init_state
  fsm_tr READY EXECUTE
  fsm_tr EXECUTE ESCALATION
  run grep '^escalation_count: 1' "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "multiple escalations accumulate count" {
  init_state
  fsm_tr READY EXECUTE
  fsm_tr EXECUTE ESCALATION
  fsm_tr ESCALATION EXECUTE
  fsm_tr EXECUTE ESCALATION
  run grep '^escalation_count: 2' "$STATE_FILE"
  [ "$status" -eq 0 ]
}

# --- get-state ---

@test "get-state outputs exactly the state with no whitespace" {
  init_state
  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "READY" ]
}

@test "get-state fails when file not found" {
  run "$FSM" get-state "/nonexistent/fsm-state.yaml"
  [ "$status" -eq 1 ]
}

# --- increment-step ---

@test "increment-step advances counter and outputs new value" {
  init_state
  run fsm_inc
  # IMP-263 (2026-07-23) replaced the bare number with a machine-readable line —
  # `status=advanced advanced_from=N advanced_to=N+1` — precisely so a caller
  # cannot misread a bare "0" as an error, which is what caused a double advance.
  # This assertion had expected the old form ever since, and only the CI step
  # timeout kept it from being seen.
  [[ "$output" == *"status=advanced"* ]]
  [[ "$output" == *"advanced_to=1"* ]]
  run "$FSM" get-field current_step "$STATE_FILE"
  [ "$output" = "1" ]
}

@test "increment-step can be called multiple times" {
  init_state
  fsm_inc >/dev/null
  fsm_inc >/dev/null
  run fsm_inc
  [[ "$output" == *"advanced_to=3"* ]]
  run "$FSM" get-field current_step "$STATE_FILE"
  [ "$output" = "3" ]
}

# --- get-field ---

@test "get-field returns correct value" {
  init_state
  run "$FSM" get-field epic_id "$STATE_FILE"
  [ "$output" = "E-001" ]
}

@test "get-field returns total_steps" {
  init_state
  run "$FSM" get-field total_steps "$STATE_FILE"
  [ "$output" = "5" ]
}

# --- precondition layer (REAL path — no --force) ---
# These guard check_preconditions itself: a transition must be BLOCKED when its
# precondition is unmet and ALLOWED when it is satisfied. Without these, the
# precondition layer (e.g. the anti-AID-005 gates _generated_by check) could be
# silently weakened and no test would notice — the "detector without enforcement"
# failure mode that AID-v3-principles.md #1 warns against. The mechanics tests
# above use --force precisely so they DON'T overlap this coverage.

@test "precondition BLOCKS READY→EXECUTE when plan.json is missing" {
  init_state   # total_steps=5, but no plan.json in the run dir (dirname of state file)
  run "$FSM" transition READY EXECUTE "$STATE_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "plan.json not found" ]]
  # State must NOT have advanced.
  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "READY" ]
}

@test "precondition ALLOWS READY→EXECUTE when plan.json is present" {
  init_state
  # plan.json lives next to the state file (run dir); presence + total_steps>=1 is
  # the READY→EXECUTE precondition. No --force: this is the real check_preconditions.
  echo '{"epic_id":"E-001","steps":[]}' > "$(dirname "$STATE_FILE")/plan.json"
  run "$FSM" transition READY EXECUTE "$STATE_FILE"
  [ "$status" -eq 0 ]
  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "EXECUTE" ]
}
