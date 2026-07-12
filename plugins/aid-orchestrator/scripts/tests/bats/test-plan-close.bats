#!/usr/bin/env bats
# test-plan-close.bats — tests for cmd_plan_close in aid-fsm.sh
# E-046-2_3 Step 7 — verifies plan-close precondition enforcement and toggle logic.
# Extended (wiring fix): cmd_plan_close now also runs aid-plan-close-check.sh
# (gated on reporter_enabled — Check 1 there has no concept of that toggle)
# before writing ca-review-complete. Fixture is now a real git repo with a
# committed, Head-fresh delivery report so aid-plan-close-check.sh's checks
# have something valid to evaluate by default.

PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
AID_FSM="$PLUGIN_DIR/scripts/aid-fsm.sh"

# epic_id used in all tests — determines plan_id=P046 (nnn=046)
EPIC_ID="E-046-2_3"

# write_fresh_delivery_report — (re)writes .aid-o/reports/P046-delivery.md
# with Head == current HEAD, then commits the report itself. Check 2's own-
# annotation-commit exclusion (a commit can't embed its own SHA) makes this
# PASS as "fresh": the only delta between recorded Head and the new current
# HEAD is the report file's own commit.
write_fresh_delivery_report() {
  local base_head
  base_head=$(git -C "$TMP" rev-parse HEAD)
  cat > "$TMP/.aid-o/reports/P046-delivery.md" <<EOF
---
Head: ${base_head}
---
# P046 Delivery Report
EOF
  git -C "$TMP" add .aid-o/reports/P046-delivery.md
  git -C "$TMP" commit -q -m "delivery report"
}

setup() {
  export AID_TEST_MODE=1
  TMP=$(mktemp -d)
  export TMP
  # evidence_dir == project_root == TMP for simplicity.
  # delivery_report will be at $TMP/.aid-o/reports/P046-delivery.md
  mkdir -p "$TMP/.aid-o/config" "$TMP/.aid-o/work" "$TMP/.aid-o/reports"
  git -C "$TMP" init -q -b main
  git -C "$TMP" config user.email "test@test.local"
  git -C "$TMP" config user.name "Test"
  echo "init" > "$TMP/.gitkeep"
  git -C "$TMP" add .gitkeep
  git -C "$TMP" commit -q -m "initial"

  # Create the always-required base reports by default; individual tests remove what they need.
  touch "$TMP/curator-report.md"
  touch "$TMP/audit-report.md"
  touch "$TMP/simplifier-report.md"
  write_fresh_delivery_report
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
  # curator + audit + simplifier present, delivery-report absent. reporter
  # disabled passes --skip-delivery-report to aid-plan-close-check.sh — only
  # the missing-delivery-report requirement is relaxed; the script still
  # runs and still evaluates Checks 2-4 (nothing to flag here: no evidence
  # dir, no queue.yaml).
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/ca-review-complete" ]
}

# ── Tests 7b-7e: reporter.enabled:false must narrow (not widen) the skip ──
# aid-plan-close-check.sh's Checks 2-4 are unrelated to the delivery report
# and must keep running/blocking even when reporter is disabled.

@test "plan-close: reporter disabled + fsm-state DONE-but-pending -> still FAILS (Check 3 unaffected)" {
  cat > "$TMP/.aid-o/config/execution.yaml" << 'YAML'
reporter:
  enabled: false
YAML
  rm -f "$TMP/.aid-o/reports/P046-delivery.md"
  mkdir -p "$TMP/.aid-o/work/evidence/E-046-2_3/R-test"
  cat > "$TMP/.aid-o/work/evidence/E-046-2_3/R-test/fsm-state.yaml" <<'YAML'
epic_id: E-046-2_3
run_id: R-test
state: DONE
current_step: 2
total_steps: 2
steps:
  - id: 1
    status: completed
  - id: 2
    status: pending
YAML
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

@test "plan-close: reporter disabled + queue.yaml claims blocked but branch merged -> still FAILS (Check 4 unaffected)" {
  cat > "$TMP/.aid-o/config/execution.yaml" << 'YAML'
reporter:
  enabled: false
YAML
  rm -f "$TMP/.aid-o/reports/P046-delivery.md"
  # A branch for E-046-2_3 that IS an ancestor of current HEAD (merged), but
  # queue.yaml still claims it's blocked/waiting-for-merge — the classic
  # stale-queue drift Check 4 exists to catch.
  git -C "$TMP" branch task/E-046-2_3/main HEAD
  cat > "$TMP/.aid-o/config/queue.yaml" <<'YAML'
- epic_id: E-046-2_3
  path: p
  status: blocked
  depends_on: []
YAML
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

@test "plan-close: reporter disabled + otherwise clean state -> PASS, marker created" {
  cat > "$TMP/.aid-o/config/execution.yaml" << 'YAML'
reporter:
  enabled: false
YAML
  rm -f "$TMP/.aid-o/reports/P046-delivery.md"
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

# ── Tests 10-14: aid-plan-close-check.sh wiring ───────────────────────────

@test "plan-close: fsm-state.yaml DONE but steps[] pending -> exit 1, no marker" {
  mkdir -p "$TMP/.aid-o/work/evidence/E-046-2_3/R-test"
  cat > "$TMP/.aid-o/work/evidence/E-046-2_3/R-test/fsm-state.yaml" <<'YAML'
epic_id: E-046-2_3
run_id: R-test
state: DONE
current_step: 2
total_steps: 2
steps:
  - id: 1
    status: completed
  - id: 2
    status: pending
YAML
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
  [[ "$output" =~ "aid-plan-close-check.sh" ]]
}

@test "plan-close: delivery report Head stale after a CODE commit -> exit 1, no marker" {
  mkdir -p "$TMP/src"
  echo "print('changed')" > "$TMP/src/app.py"
  git -C "$TMP" add src/app.py
  git -C "$TMP" commit -q -m "feat: change app logic"
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

@test "plan-close: delivery report Head stale after a DOCS-only commit -> auto-annotates, exit 0, marker created" {
  mkdir -p "$TMP/docs"
  echo "# notes" > "$TMP/docs/notes.md"
  git -C "$TMP" add docs/notes.md
  git -C "$TMP" commit -q -m "docs: add notes"
  local new_head
  new_head=$(git -C "$TMP" rev-parse HEAD)
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/ca-review-complete" ]
  # yq treats the whole file as a 2-document YAML stream (frontmatter +
  # markdown body after the second ---), so $output has a trailing "---\nnull"
  # for the second (bodyless) document — only the first line is the value.
  run yq -r '.Head' "$TMP/.aid-o/reports/P046-delivery.md"
  [ "${lines[0]}" = "$new_head" ]
}

@test "plan-close: official delivery report present on disk but UNTRACKED (committed mode) -> exit 1, no marker" {
  git -C "$TMP" rm -q --cached .aid-o/reports/P046-delivery.md
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

@test "plan-close: aid-plan-close-check.sh PASS -> ca-review-complete created (canonical happy path)" {
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/ca-review-complete" ]
  [[ "$output" =~ "OVERALL: PASS" ]]
}
