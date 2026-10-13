#!/usr/bin/env bats
# aid-tier: t0
# test-aid-plan-close-check.bats — aid-plan-close-check.sh (PM plugin-infra fix,
# branch fix/plan-close-consistency).
#
# Covers the fsm-state DONE-but-pending guard (Check 3) and the aggregate
# verdict. Check 4 (the queue) left with the EPIC path in 3.0.0 (P114).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SCRIPT="$AID_PLUGIN_PATH/scripts/aid-plan-close-check.sh"
  export SCRIPT
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixture helpers ─────────────────────────────────────────────────────

# write_fsm_state <epic_id> <run_id> <state> <pending_count>
#   Writes a minimal fsm-state.yaml with a steps[] array of 2 entries, the
#   first N of which are "pending" (pending_count) and the rest "completed".
write_fsm_state() {
  local epic_id="$1" run_id="$2" state="$3" pending_count="$4"
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/${run_id}"
  mkdir -p "$dir"
  local s1="completed" s2="completed"
  [[ "$pending_count" -ge 1 ]] && s1="pending"
  [[ "$pending_count" -ge 2 ]] && s2="pending"
  cat > "$dir/fsm-state.yaml" <<EOF
epic_id: $epic_id
run_id: $run_id
state: $state
current_step: 2
total_steps: 2
steps:
  - id: 1
    status: $s1
  - id: 2
    status: $s2
EOF
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 1 — DONE fsm-state with all steps pending → FAILS (Check 3)
# ═══════════════════════════════════════════════════════════════════════

@test "(1) DONE fsm-state with all steps pending -> self-check FAILS" {
  write_fsm_state "E-601-1_1" "R-1" "DONE" 2

  run "$SCRIPT" P601 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"*"state=DONE but 2 step(s) still status:pending"* ]]
}

# ═══════════════════════════════════════════════════════════════════════
# Scenario 6 — WAN-P062-like fixture (positive regression snapshot) -> PASS
# ═══════════════════════════════════════════════════════════════════════

@test "(6) three DONE EPICs with every step completed -> overall PASS" {
  # 3 EPICs, all DONE, all steps completed.
  write_fsm_state "E-062-1_3" "R-E062-1" "DONE" 0
  write_fsm_state "E-062-2_3" "R-E062-2" "DONE" 0
  write_fsm_state "E-062-3_3" "R-E062-3" "DONE" 0


  run "$SCRIPT" P062 --project-root "$TEST_PROJECT_ROOT"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OVERALL: PASS"* ]]
  ! [[ "$output" == *"FAIL"* ]]
}
