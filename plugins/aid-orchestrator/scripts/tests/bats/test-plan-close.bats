#!/usr/bin/env bats
# test-plan-close.bats — tests for cmd_plan_close in aid-fsm.sh
# E-046-2_3 Step 7 — verifies plan-close precondition enforcement and toggle logic.

PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
AID_FSM="$PLUGIN_DIR/scripts/aid-fsm.sh"

# epic_id used in all tests — determines plan_id=P046 (nnn=046)
EPIC_ID="E-046-2_3"

setup() {
  export AID_TEST_MODE=1
  TMP=$(mktemp -d)
  export TMP
  # evidence_dir == project_root == TMP for simplicity.
  # delivery_report will be at $TMP/.aid-o/reports/P046-delivery.md
  mkdir -p "$TMP/.aid-o/config" "$TMP/.aid-o/work" "$TMP/.aid-o/reports"
  # Create the always-required base reports by default; individual tests remove what they need.
  touch "$TMP/curator-report.md"
  touch "$TMP/audit-report.md"
  touch "$TMP/simplifier-report.md"
  touch "$TMP/.aid-o/reports/P046-delivery.md"
}

teardown() {
  rm -rf "$TMP"
}

# ── Test 1: missing curator-report ───────────────────────────────────────

@test "plan-close: missing curator-report -> exit 1, no marker" {
  rm -f "$TMP/curator-report.md"
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

# ── Test 2: missing audit-report ─────────────────────────────────────────

@test "plan-close: missing audit-report -> exit 1, no marker" {
  rm -f "$TMP/audit-report.md"
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

# ── Test 3: missing simplifier-report ────────────────────────────────────

@test "plan-close: missing simplifier-report -> exit 1, no marker" {
  rm -f "$TMP/simplifier-report.md"
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

# ── Test 4: missing delivery-report ──────────────────────────────────────

@test "plan-close: missing delivery-report -> exit 1, no marker" {
  rm -f "$TMP/.aid-o/reports/P046-delivery.md"
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

# ── Test 5: all reports present -> marker created, exit 0 ────────────────

@test "plan-close: all present -> marker created, exit 0" {
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/ca-review-complete" ]
}

# ── Test 6: simplifier.enabled:false -> skip simplifier-report ───────────

@test "plan-close: simplifier.enabled:false -> skip simplifier-report, pass if delivery present" {
  cat > "$TMP/.aid-o/config/execution.yaml" << 'YAML'
simplifier:
  enabled: false
reporter:
  enabled: true
YAML
  rm -f "$TMP/simplifier-report.md"
  # curator + audit + delivery present, simplifier-report absent
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/ca-review-complete" ]
  [ -f "$TMP/.aid-o/work/audit-log.jsonl" ]
}

# ── Test 7: reporter.enabled:false -> skip delivery-report ───────────────

@test "plan-close: reporter.enabled:false -> skip delivery-report, pass if simplifier present" {
  cat > "$TMP/.aid-o/config/execution.yaml" << 'YAML'
simplifier:
  enabled: true
reporter:
  enabled: false
YAML
  rm -f "$TMP/.aid-o/reports/P046-delivery.md"
  # curator + audit + simplifier present, delivery-report absent
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/ca-review-complete" ]
}

# ── Test 8: toggle-skip writes audit-log.jsonl entry ─────────────────────

@test "plan-close: toggle-skip writes audit-log.jsonl entry" {
  cat > "$TMP/.aid-o/config/execution.yaml" << 'YAML'
simplifier:
  enabled: false
reporter:
  enabled: true
YAML
  rm -f "$TMP/simplifier-report.md"
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/.aid-o/work/audit-log.jsonl" ]
  grep -q "plan_close_skip" "$TMP/.aid-o/work/audit-log.jsonl"
  grep -q '"specialist":"simplifier"' "$TMP/.aid-o/work/audit-log.jsonl"
}

# ── Test 9: regression anchor — no required files -> must exit 1 ─────────
# Proves the precondition guard exists. If someone replaced plan-close with
# an unconditional touch, this test would fail.

@test "plan-close: missing all required reports -> exit 1 (regression anchor)" {
  rm -f "$TMP/curator-report.md"
  rm -f "$TMP/audit-report.md"
  rm -f "$TMP/simplifier-report.md"
  rm -f "$TMP/.aid-o/reports/P046-delivery.md"
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}
