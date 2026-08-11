#!/usr/bin/env bats
# aid-tier: t2
# P033 Step 9 — aid-compliance-report.sh: --era filter, --era latest, --compare,
# force triple-condition reflect detection (4 assertions)

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  COMPLIANCE="$AID_PLUGIN_PATH/scripts/aid-compliance-report.sh"
  export COMPLIANCE

  # Scratch dir for compliance.json fixtures independent of TEST_EVIDENCE_DIR
  EVIDENCE_ROOT="$TEST_TMPDIR/evidence"
  export EVIDENCE_ROOT
}

teardown() {
  teardown_test_evidence_dir
}

# Helper: write a minimal compliance.json for era-based filtering tests.
write_compliance() {
  local epic="$1" run="$2" era="$3" force_count="${4:-0}"
  mkdir -p "$EVIDENCE_ROOT/$epic/$run"
  jq -n \
    --arg era "$era" --arg epic "$epic" --arg run "$run" \
    --argjson fc "$force_count" \
    '{
      epic_id: $epic, run_id: $run, deploy_era: $era,
      evaluated_at: "2026-05-08T00:00:00Z",
      overall: true,
      force_override_count: $fc,
      force_override_reasons: [],
      checks: {
        branch_correct: true,
        execution_yaml_present: true,
        gates_generated_by: true,
        verifier_outputs: {
          cp2_per_step_dispatched: true, cp2_per_step_verdict: "pass",
          cp3_code_review_dispatched: true, cp3_code_review_verdict: "pass",
          cp3_security_dispatched: true,  cp3_security_verdict: "pass",
          aggregate: true
        }
      }
    }' > "$EVIDENCE_ROOT/$epic/$run/compliance.json"
}

# ─── --era filter ─────────────────────────────────────────────────────────────

@test "compliance-report: --era post-session-b filters to post-session-b EPICs only" {
  write_compliance "E-pre-a"  "R-001" "pre-session-a"
  write_compliance "E-post-a" "R-001" "post-session-a"
  write_compliance "E-post-b" "R-001" "post-session-b"

  run "$COMPLIANCE" --era post-session-b --evidence-roots "$EVIDENCE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Post-Session-B:        1 EPICs" ]]
  [[ "$output" =~ "Pre-Session-A:         0 EPICs" ]]
}

# ─── --era latest ─────────────────────────────────────────────────────────────

@test "compliance-report: --era latest auto-resolves to newest post-session-* era" {
  write_compliance "E-post-a" "R-001" "post-session-a"
  write_compliance "E-post-b" "R-001" "post-session-b"

  run "$COMPLIANCE" --era latest --evidence-roots "$EVIDENCE_ROOT"
  [ "$status" -eq 0 ]
  # latest should resolve to post-session-b (lexicographically last)
  [[ "$output" =~ "Filter --era:          post-session-b" ]]
}

# ─── --compare ────────────────────────────────────────────────────────────────

@test "compliance-report: --compare ERA1,ERA2 produces side-by-side table header" {
  write_compliance "E-post-a" "R-001" "post-session-a"
  write_compliance "E-post-b" "R-001" "post-session-b"

  run "$COMPLIANCE" --compare post-session-a,post-session-b --evidence-roots "$EVIDENCE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Era Comparison" ]]
  [[ "$output" =~ "post-session-a" ]]
  [[ "$output" =~ "post-session-b" ]]
}

# ─── --reflect force triple-condition ─────────────────────────────────────────

@test "compliance-report --reflect: avg force_override > 1 per EPIC → SYSTEMATIC pattern" {
  # 2 post-session-b EPICs with force_override_count=2 each → avg=2.0 > 1 threshold
  write_compliance "E-post-b-1" "R-001" "post-session-b" 2
  write_compliance "E-post-b-2" "R-001" "post-session-b" 2

  run "$COMPLIANCE" --era post-session-b --reflect --evidence-roots "$EVIDENCE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SYSTEMATIC" ]]
}
