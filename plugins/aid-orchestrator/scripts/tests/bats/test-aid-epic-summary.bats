#!/usr/bin/env bats
# aid-tier: t0
# IMP-090 — aid-epic-summary.sh: epic-summary.md generation (2 assertions)

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SUMMARY="$AID_PLUGIN_PATH/scripts/aid-epic-summary.sh"
  export SUMMARY

  # Minimal fsm-state.yaml required by the generator
  cat > "$TEST_EVIDENCE_DIR/fsm-state.yaml" <<'EOF'
epic_id: E-test
run_id: R-test
state: DONE
done_phase: release
current_step: 2
total_steps: 2
mode: manual
branch: task/E-test/main
base_commit: HEAD
gate_retries: 0
escalation_count: 0
started_at: "2026-05-08T00:00:00Z"
created_at: 2026-05-08T00:00:00Z
EOF
}

teardown() {
  teardown_test_evidence_dir
}

# ─── Assertion 1: file exists with all 5 required section headers ──────────────

@test "generate: epic-summary.md exists with all 5 required section headers" {
  run "$SUMMARY" generate "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  local out="$TEST_EVIDENCE_DIR/epic-summary.md"
  [ -f "$out" ]
  grep -q '## ✅ Co bylo dodáno'            "$out"
  grep -q '## ⚠️ Varování a přeskočené kroky' "$out"
  grep -q '## ❌ Co se nestihlo'             "$out"
  grep -q '## 📋 Co dělat dál'              "$out"
  grep -q '## 🔍 Honest signal'             "$out"
}

# ─── Assertion 2: force_override in timeline → summary mentions it ────────────

@test "generate: fsm_force_override event in timeline → warnings section mentions it" {
  # Write a timeline with one force_override event
  printf '{"ts":"2026-05-08T10:00:00Z","event":"fsm_force_override","from":"EXECUTE","to":"GATES","reason":"plan.json bug blocking precondition, verified safe","caller":"transition","operator":"test"}\n' \
    > "$TEST_EVIDENCE_DIR/timeline.jsonl"

  run "$SUMMARY" generate "$TEST_EVIDENCE_DIR"
  [ "$status" -eq 0 ]

  local out="$TEST_EVIDENCE_DIR/epic-summary.md"
  [ -f "$out" ]
  grep -q 'Force override' "$out"
  grep -q 'force override' "$out"
}
