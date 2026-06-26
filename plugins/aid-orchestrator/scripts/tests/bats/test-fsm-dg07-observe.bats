#!/usr/bin/env bats
# test-fsm-dg07-observe.bats — DG-07 integration with aid-fsm.sh done-advance.
#
# Case 1: observe mode (default E2) — DG-07 detects pending child step →
#         done-advance PASSES + delivery_gate_would_block event written to timeline
# Case 2: blocking mode (DELIVERY_GATE_POLICY override enforcement: blocking) —
#         same DG-07 fail → done-advance REJECTED (non-zero) + fsm_done_advance_fail
#         event written to timeline. Proves the blocking branch is live code.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export FSM
  export AID_TEST_MODE=1
}

teardown() {
  unset GIT_DIR
  unset DELIVERY_GATE_POLICY
  teardown_test_evidence_dir
}

# ---------------------------------------------------------------------------
# Helper: seed a DONE/review state that satisfies ALL done-advance preconditions
# EXCEPT the DG-07 check (pending child step: current_step=2, total_steps=3).
#
# Satisfies:
#   - streamlined_mode absent → streamlined checks skipped
#   - curator-report.md with no git range (no prod changes) → CP4 skips
#   - audit-report.md with blocking_findings: false → CP5 passes
#   - pm_decision: merge
#   - no EPIC task file in tasks/ → task-file check passes
#   - gates_report.json with _generated_by → gates_generated_by=true
#   - branch: task/E-test/main → branch_correct=true
#   - current_step: 2, total_steps: 3 → DG-07 detects pending child step
# ---------------------------------------------------------------------------
_seed_dg07_state() {
  local state_file="$1"
  cat > "$state_file" <<YAML
epic_id: E-test
run_id: R-test
branch: task/E-test/main
state: DONE
done_phase: review
created_at: 2026-06-18T00:00:00Z
total_steps: 3
current_step: 2
pm_decision: merge
YAML

  mkdir -p "$TEST_EVIDENCE_DIR/gates"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/tasks" \
           "$TEST_PROJECT_ROOT/.aid-o/tasks/archive" \
           "$TEST_PROJECT_ROOT/.aid-o/work" \
           "$TEST_PROJECT_ROOT/.aid-o/config"
  touch "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"

  # gates_report.json with _generated_by (gates_generated_by check passes)
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-06-18T00:00:00Z","_command_log":[]}\n' \
    > "$TEST_EVIDENCE_DIR/gates/gates_report.json"

  # plugin.yaml (needed by dispatch_mode resolution in evaluate_compliance_checks)
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/plugin.yaml" <<YAML
plugin_path: "$AID_PLUGIN_PATH"
dispatch_mode: subagent
YAML

  # audit-report.md: blocking_findings: false (CP5 check passes)
  printf 'blocking_findings: false\n' > "$TEST_EVIDENCE_DIR/audit-report.md"

  # curator-report.md must exist (curator-report check passes).
  # CP4: no production file changes in HEAD range → CP4 skips safely.
  echo "curator ran" > "$TEST_EVIDENCE_DIR/curator-report.md"

  # verifier-output-cp4-curator-validation.md (satisfies CP4 when production files
  # are committed; in the test git repo there are no production file commits after
  # setup_test_evidence_dir, so CP4 skips — but provide it defensively).
  printf '_generated_by: aid-orchestrator:verifier@cp4-dg07-test\n_generated_at: 2026-06-18T00:00:00Z\nclassification: FULL_REVIEW\nverdict: pass\n' \
    > "$TEST_EVIDENCE_DIR/verifier-output-cp4-curator-validation.md"
}

# ---------------------------------------------------------------------------
# Helper: write a temporary delivery-gate.yaml with the given enforcement value.
# Exports DELIVERY_GATE_POLICY so the FSM hook uses it instead of the plugin default.
# ---------------------------------------------------------------------------
_write_delivery_gate_policy() {
  local enforcement="$1"
  local policy_file="$TEST_TMPDIR/delivery-gate-test.yaml"
  cat > "$policy_file" <<YAML
version: 1
enforcement: $enforcement
block_on_unverifiable: true
skip_reason_allowlist:
  - not_required
profiles:
  generic:
    detect: []
    commands: {}
checks:
  dg07:
    name: state-consistency
    required_when:
      - always: true
YAML
  export DELIVERY_GATE_POLICY="$policy_file"
}

# ---------------------------------------------------------------------------
# Case 1: Observe mode (E2 default)
#
# DG-07 detects pending child step (current_step=2 < total_steps=3).
# enforcement=observe → done-advance PASSES (exit 0).
# timeline.jsonl MUST contain a delivery_gate_would_block event.
# ---------------------------------------------------------------------------

@test "DG-07 observe: pending child step → done-advance passes + would_block event written" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_dg07_state "$state_file"
  _write_delivery_gate_policy "observe"

  run "$FSM" done-advance review release "$state_file"

  # Transition succeeds despite DG-07 detecting inconsistency
  [ "$status" -eq 0 ]

  # timeline.jsonl must have the delivery_gate_would_block event
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "delivery_gate_would_block"

  # done_phase should have advanced to release
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "release" ]
}

# ---------------------------------------------------------------------------
# Case 2: Blocking mode (E10 promotion path, test override)
#
# Same DG-07 fail (current_step=2 < total_steps=3).
# enforcement=blocking → done-advance REJECTED (non-zero exit).
# timeline.jsonl MUST contain a fsm_done_advance_fail event.
# Proves the blocking branch is live code, not dead code.
# ---------------------------------------------------------------------------

@test "DG-07 blocking: pending child step → done-advance rejected (non-zero) + fsm_done_advance_fail event" {
  local state_file="$TEST_EVIDENCE_DIR/fsm-state.yaml"
  _seed_dg07_state "$state_file"
  _write_delivery_gate_policy "blocking"

  run "$FSM" done-advance review release "$state_file"

  # Transition is REJECTED (non-zero exit)
  [ "$status" -ne 0 ]

  # timeline.jsonl must have the fsm_done_advance_fail event (from the blocking path)
  assert_timeline_event "$TEST_EVIDENCE_DIR/timeline.jsonl" "fsm_done_advance_fail"

  # done_phase must NOT have advanced (still review)
  [ "$(grep '^done_phase:' "$state_file" | awk '{print $2}')" = "review" ]
}
