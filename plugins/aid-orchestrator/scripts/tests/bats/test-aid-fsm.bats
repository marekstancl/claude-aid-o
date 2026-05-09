#!/usr/bin/env bats
# P032 Step 7 — aid-fsm.sh PRE-FLIGHT branch enforcement (Step 2)
# + EXECUTE→GATES gates_report._generated_by precondition (Step 3) +
# grandfather behavior. P033 Step 9 adds CP2 verifier-output preconditions +
# force_override --reason enforcement. 14 assertions total.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  # Force post-deploy mode for the gate-enforcement assertions.
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
}

teardown() {
  unset GIT_DIR
  teardown_test_evidence_dir
}

# ─── Step 2: PRE-FLIGHT branch enforcement (6 assertions) ────────────────

@test "PRE-FLIGHT: HEAD=main → auto-create task/E-test/main" {
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$current_branch" == "task/E-test/main" ]
}

@test "PRE-FLIGHT: HEAD=task/E-test/main → resume case (no branch change)" {
  git checkout -b task/E-test/main -q
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$current_branch" == "task/E-test/main" ]
  [[ "$output" =~ "Resume case" ]]
}

@test "PRE-FLIGHT: HEAD=task/E-OTHER/main → mismatch hard fail with copy-paste fix" {
  git checkout -b task/E-OTHER/main -q
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -ne 0 ]
  [[ "$output" =~ "git checkout main && git branch -d task/E-OTHER/main" ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_branch_mismatch_detected"
}

@test "PRE-FLIGHT: HEAD=feat/foo → unusual warn + event, accept" {
  git checkout -b feat/foo -q
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unusual branch"* ]]
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_branch_unusual_detected"
}

@test "PRE-FLIGHT: in worktree → skip enforcement, accept caller branch" {
  mock_git_worktree
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Worktree mode detected" ]]
}

@test "PRE-FLIGHT: uncommitted changes → reject with stash/commit suggestion" {
  echo "dirty modification" >> .gitkeep
  run "$FSM" init $(build_default_init_args E-test)
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Uncommitted changes present" ]]
}

# ─── Step 3: EXECUTE→GATES precondition + grandfather (3 assertions) ─────

@test "EXECUTE→GATES: missing _generated_by (post-deploy) → hard fail" {
  # Post-deploy state.yaml + hand-written gates_report.json.
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  echo '{"overall":"pass","gates":{}}' > "$TEST_EVIDENCE_DIR/gates/gates_report.json"

  run "$FSM" transition EXECUTE GATES "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "missing _generated_by" ]]
  [[ "$output" =~ "aid-run-gates.sh run-all" ]]
}

@test "EXECUTE→GATES: present _generated_by + CP3 outputs → accept" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  jq -n '{overall:"pass", gates:{}, _generated_by:"aid-run-gates.sh@v2.16.0", _generated_at:"2026-05-04T00:00:00Z", _command_log:[]}' \
    > "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  # Session B CP3: both verifier-output-cp3-*.md required (file presence check)
  printf '_generated_by: aid-orchestrator:verifier@abc123\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp3-code-review.md"
  printf '_generated_by: aid-orchestrator:verifier@def456\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp3-security.md"

  run "$FSM" transition EXECUTE GATES "$state_file"
  [ "$status" -eq 0 ]
}

@test "EXECUTE→GATES: pre-deploy grandfather (created_at < deploy_date) → accept regardless" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  # Override created_at to BEFORE AID_DEPLOY_DATE
  write_post_deploy_state_yaml "$state_file"
  sed -i 's/^created_at: .*/created_at: 2026-03-01T00:00:00Z/' "$state_file"
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  echo '{"overall":"pass","gates":{}}' > "$TEST_EVIDENCE_DIR/gates/gates_report.json"

  run "$FSM" transition EXECUTE GATES "$state_file"
  [ "$status" -eq 0 ]
}

# ─── P033 Step 9: CP2 verifier-output preconditions (3 assertions) ───────────

# Helper: write a fully-valid step-N-verify.md for a given step number.
write_valid_step_verify() {
  local file="$1" step="${2:-3}"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<VERIFY
# Step ${step} Verification

## Result: PASS

- [x] acceptance criterion met
- [x] output files match expected paths

Commit: abc1234def5678

## Memory Used
N/A — no prior memory applicable

## Memory Written
N/A — no new entries proposed
VERIFY
}

@test "increment-step: missing verifier-output-step-N.md (post-deploy) → hard fail" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # No verifier-output-step-3.md → CP2 precondition fails

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "verifier-output-step-3.md missing or invalid" ]]
}

@test "increment-step: verifier-output with verdict:pending (verifier not dispatched) → fail" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # Pre-filter wrote pending; verifier was NOT dispatched
  printf '_generated_by: aid-pre-filter.sh@v2.18.0\nclassification: RUN\nverdict: pending\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "verifier-output-step-3.md missing or invalid" ]]
}

@test "increment-step: verifier-output with classification:SKIP (docs diff) → accept" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"  # current_step: 3
  write_valid_step_verify "$TEST_EVIDENCE_DIR/step-3-verify.md" 3
  # SKIP classification is valid without verdict (pre-filter wrote reason field instead)
  printf '_generated_by: aid-pre-filter.sh@v2.18.0\nclassification: SKIP\nreason: docs_only\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-step-3.md"

  run "$FSM" increment-step "$state_file"
  [ "$status" -eq 0 ]
}

# ─── P033 Step 9: force_override --reason enforcement (2 assertions) ─────────

@test "transition --force without --reason → die with examples" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"

  run "$FSM" transition EXECUTE GATES "$state_file" --force
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--reason" ]]
  [[ "$output" =~ "min 20 characters" ]]
}

@test "increment-step --force with short reason (< 20 chars) → die" {
  local state_file="$TEST_EVIDENCE_DIR/state.yaml"
  write_post_deploy_state_yaml "$state_file"

  run "$FSM" increment-step "$state_file" --force --reason "too short"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "min 20 characters" ]]
}
