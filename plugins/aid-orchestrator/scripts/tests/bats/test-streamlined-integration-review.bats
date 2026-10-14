#!/usr/bin/env bats
# aid-tier: t2
# P083 Step 1 — fsm_check_streamlined_integration_review accepts the gates
# report at either the canonical gates/ subdirectory (the EPIC-stage writer's
# path, and every other reader's) or the legacy flat sibling (still written
# today by the plan-final gate stage).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
}

teardown() {
  teardown_test_evidence_dir
}

_seed_streamlined_state() {
  cat > "$TEST_EVIDENCE_DIR/fsm-state.yaml" <<EOF
epic_id: E-test
run_id: R-test
state: DONE
base_commit: HEAD
streamlined_mode: true
EOF
}

_run_check() {
  local ev_dir="$1" state_file="$2" proj_root="$3"
  run bash -c '
    set -euo pipefail
    source "'"$FSM"'"
    # a streamlined run is reviewed only by the close (CP7), so it runs in
    # plan_branch mode; the gate-report paths are what this suite is about
    _fsm_declared_plan_mode() { printf "plan_branch\tP900\t\n"; }
    epic_id=E-test run_id=R-test project_root="'"$proj_root"'"
    fsm_check_streamlined_integration_review "'"$ev_dir"'" "'"$state_file"'"
  '
}

@test "canonical gates/gates_report.json passes done-advance without --force" {
  _seed_streamlined_state
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  echo '{}' > "$TEST_EVIDENCE_DIR/gates/gates_report.json"

  _run_check "$TEST_EVIDENCE_DIR" "$TEST_EVIDENCE_DIR/fsm-state.yaml" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  grep -q '"event":"streamlined_integration_review_gates_source"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  grep -q '"source":"canonical"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

@test "report missing at both paths fails naming both paths searched" {
  _seed_streamlined_state
  # No gates_report.json anywhere.

  _run_check "$TEST_EVIDENCE_DIR" "$TEST_EVIDENCE_DIR/fsm-state.yaml" "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"gates/gates_report.json"* ]]
  [[ "$output" == *"${TEST_EVIDENCE_DIR}/gates_report.json"* ]]
}

@test "legacy flat gates_report.json passes and logs the fallback" {
  _seed_streamlined_state
  echo '{}' > "$TEST_EVIDENCE_DIR/gates_report.json"

  _run_check "$TEST_EVIDENCE_DIR" "$TEST_EVIDENCE_DIR/fsm-state.yaml" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"legacy flat path"* ]]
  grep -q '"event":"streamlined_integration_review_gates_source"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
  grep -q '"source":"legacy_flat"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}

@test "both paths present prefers canonical and notes the flat sibling exists" {
  _seed_streamlined_state
  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  echo '{"marker":"canonical"}' > "$TEST_EVIDENCE_DIR/gates/gates_report.json"
  echo '{"marker":"flat"}' > "$TEST_EVIDENCE_DIR/gates_report.json"

  _run_check "$TEST_EVIDENCE_DIR" "$TEST_EVIDENCE_DIR/fsm-state.yaml" "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"present at both"* ]]
  grep -q '"source":"canonical"' "$TEST_EVIDENCE_DIR/timeline.jsonl"
}
