#!/usr/bin/env bats
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
  run "$FSM" transition READY EXECUTE "$STATE_FILE"
  [ "$status" -eq 0 ]
  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "EXECUTE" ]
}

@test "transition EXECUTE to GATES succeeds" {
  init_state
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  run "$FSM" transition EXECUTE GATES "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "transition EXECUTE to ESCALATION succeeds" {
  init_state
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  run "$FSM" transition EXECUTE ESCALATION "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "transition GATES to DONE succeeds" {
  init_state
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE GATES "$STATE_FILE" 2>/dev/null
  run "$FSM" transition GATES DONE "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "transition GATES to EXECUTE (retry) succeeds" {
  init_state
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE GATES "$STATE_FILE" 2>/dev/null
  run "$FSM" transition GATES EXECUTE "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "transition ESCALATION to EXECUTE succeeds" {
  init_state
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE ESCALATION "$STATE_FILE" 2>/dev/null
  run "$FSM" transition ESCALATION EXECUTE "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "transition ESCALATION to GATES (skip gate) succeeds" {
  init_state
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE ESCALATION "$STATE_FILE" 2>/dev/null
  run "$FSM" transition ESCALATION GATES "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "EXECUTE to EXECUTE (internal loop) succeeds" {
  init_state
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  run "$FSM" transition EXECUTE EXECUTE "$STATE_FILE"
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
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE GATES "$STATE_FILE" 2>/dev/null
  "$FSM" transition GATES DONE "$STATE_FILE" 2>/dev/null
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
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE ESCALATION "$STATE_FILE" 2>/dev/null
  run grep '^escalation_count: 1' "$STATE_FILE"
  [ "$status" -eq 0 ]
}

@test "multiple escalations accumulate count" {
  init_state
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE ESCALATION "$STATE_FILE" 2>/dev/null
  "$FSM" transition ESCALATION EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE ESCALATION "$STATE_FILE" 2>/dev/null
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
  run "$FSM" increment-step "$STATE_FILE"
  [ "$output" = "1" ]
  run "$FSM" get-field current_step "$STATE_FILE"
  [ "$output" = "1" ]
}

@test "increment-step can be called multiple times" {
  init_state
  "$FSM" increment-step "$STATE_FILE" >/dev/null
  "$FSM" increment-step "$STATE_FILE" >/dev/null
  run "$FSM" increment-step "$STATE_FILE"
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
