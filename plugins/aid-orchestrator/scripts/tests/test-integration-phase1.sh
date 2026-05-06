#!/usr/bin/env bats
# Integration tests for Phase 1 scripts (Steps 4–8)
# Tests end-to-end interactions between FSM, logging, gates, and token counting

setup() {
  TEST_DIR=$(mktemp -d)
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  FSM="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-fsm.sh"
  RUN_GATES="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-run-gates.sh"
  FIXTURES="$REPO_ROOT/plugins/aid-orchestrator/scripts/tests/fixtures"
  STATE_FILE="$TEST_DIR/state.yaml"
  TIMELINE="$TEST_DIR/timeline.jsonl"

  source "$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-stage-log.sh"
  source "$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-token-count.sh"

  # P032 Step 2: cmd_init now PRE-FLIGHT-enforces a git working tree.
  ( cd "$TEST_DIR" && git init -q \
      && git config user.email t@t.io && git config user.name T \
      && echo init > .gitkeep && git add .gitkeep && git commit -q -m initial )
  cd "$TEST_DIR"
}

teardown() { rm -rf "$TEST_DIR"; }

# --- Full FSM cycle with timeline logging ---

@test "full FSM cycle: READY → EXECUTE → GATES → DONE with timeline logging" {
  # Init
  "$FSM" init E-TEST R-TEST 3 manual main abc123 "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "initialized" epic_id=E-TEST

  # READY → EXECUTE
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "state_enter" state=EXECUTE

  # Increment step
  "$FSM" increment-step "$STATE_FILE" >/dev/null

  # EXECUTE → GATES
  "$FSM" transition EXECUTE GATES "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "state_enter" state=GATES

  # GATES → DONE
  "$FSM" transition GATES DONE "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "state_enter" state=DONE

  # Verify final state
  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "DONE" ]

  # Verify 4 events were logged
  run bash -c "jq -s 'length' '$TIMELINE'"
  [ "$output" = "4" ]
}

@test "FSM with ESCALATION path: EXECUTE → ESCALATION → EXECUTE → GATES → DONE" {
  "$FSM" init E-ESC R-ESC 2 manual main abc123 "$STATE_FILE" 2>/dev/null

  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "state_enter" state=EXECUTE

  "$FSM" transition EXECUTE ESCALATION "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "escalation" reason=test

  "$FSM" transition ESCALATION EXECUTE "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "resume" state=EXECUTE

  "$FSM" transition EXECUTE GATES "$STATE_FILE" 2>/dev/null
  "$FSM" transition GATES DONE "$STATE_FILE" 2>/dev/null

  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "DONE" ]

  run "$FSM" get-field escalation_count "$STATE_FILE"
  [ "$output" = "1" ]
}

# --- Gates integrated with FSM state ---

@test "gate runner with passing gates allows FSM to proceed to DONE" {
  "$FSM" init E-GATE R-GATE 1 auto main abc123 "$STATE_FILE" 2>/dev/null
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE GATES "$STATE_FILE" 2>/dev/null

  # Run gates
  run "$RUN_GATES" run-all "$FIXTURES/execution-test.yaml" "E-GATE" "R-GATE" "$TIMELINE"
  [ "$status" -eq 0 ]

  # Gates passed → transition to DONE
  "$FSM" transition GATES DONE "$STATE_FILE" 2>/dev/null
  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "DONE" ]
}

@test "gate runner failure triggers ESCALATION path" {
  "$FSM" init E-FAIL R-FAIL 1 auto main abc123 "$STATE_FILE" 2>/dev/null
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  "$FSM" transition EXECUTE GATES "$STATE_FILE" 2>/dev/null

  # Run failing required gates
  run "$RUN_GATES" run-all "$FIXTURES/execution-failing.yaml" "E-FAIL" "R-FAIL" "$TIMELINE"
  [ "$status" -eq 1 ]

  # Gate failed → transition to ESCALATION (not DONE)
  "$FSM" transition GATES ESCALATION "$STATE_FILE" 2>/dev/null
  run "$FSM" get-state "$STATE_FILE"
  [ "$output" = "ESCALATION" ]
}

# --- Timeline completeness across tools ---

@test "timeline has events from both FSM transitions and gate runner" {
  "$FSM" init E-TL R-TL 1 auto main abc123 "$STATE_FILE" 2>/dev/null
  "$FSM" transition READY EXECUTE "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "step_start" step=1
  "$FSM" transition EXECUTE GATES "$STATE_FILE" 2>/dev/null

  "$RUN_GATES" run-all "$FIXTURES/execution-test.yaml" "E-TL" "R-TL" "$TIMELINE" >/dev/null

  "$FSM" transition GATES DONE "$STATE_FILE" 2>/dev/null
  log_event "$TIMELINE" "run_complete" state=DONE

  # Timeline has entries from both log_event and run_gates
  run bash -c "jq -s 'length' '$TIMELINE'"
  local count="$output"
  [ "$count" -ge 4 ]  # step_start + gate_start(s) + gate_complete(s) + gates_complete + run_complete

  # All timeline entries are valid JSON
  run bash -c "while IFS= read -r line; do echo \"\$line\" | jq -e . >/dev/null || exit 1; done < '$TIMELINE'"
  [ "$status" -eq 0 ]
}

# --- Token counting for context sizing ---

@test "token count works on state.yaml file" {
  "$FSM" init E-TOK R-TOK 5 auto main abc123 "$STATE_FILE" 2>/dev/null

  run count_tokens "$STATE_FILE" mixed
  [ "$status" -eq 0 ]
  run bash -c "echo '$output' | jq -e '.estimated_tokens > 0'"
  [ "$status" -eq 0 ]
}

# --- Phase 1 scripts all have dedicated test files ---

@test "all Phase 1 scripts have dedicated test files" {
  local scripts_dir="$REPO_ROOT/plugins/aid-orchestrator/scripts"
  local tests_dir="$scripts_dir/tests"

  # Phase 1 scripts
  local phase1_scripts=(
    "lib/aid-stage-log.sh:test-stage-log.sh"
    "lib/aid-token-count.sh:test-token-count.sh"
    "aid-fsm.sh:test-fsm.sh"
    "aid-run-gates.sh:test-run-gates.sh"
    "aid-release.sh:test-release.sh"
  )

  for pair in "${phase1_scripts[@]}"; do
    local script="${pair%%:*}"
    local test_file="${pair##*:}"
    [ -f "$scripts_dir/$script" ] || { echo "MISSING script: $script" >&2; return 1; }
    [ -f "$tests_dir/$test_file" ] || { echo "MISSING test: $test_file" >&2; return 1; }
  done
}
