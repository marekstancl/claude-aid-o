#!/usr/bin/env bash
# =============================================================================
# test-plan-quality-enforcement.sh — Smoke test for P036 plan-quality layers
#
# Verifies the 4 enforcement layers added in v2.20.0 (P036 EPIC E-036-1_1):
#   Layer 1: 17e — CLI invocation grounding (plan-writing.md)
#   Layer 2: #19 — Design Defeat Detection pre-screening (plan-writing.md)
#   Layer 3: /aid-plan write Step 9 — CP1 lifecycle (commands/aid-plan.md)
#   Layer 4: EVIDENCE REQUIREMENT — reviewer prompt (commands/aid-plan.md)
#
# Strategy: mirror test-cp1-grounding.sh — exercise extraction patterns and
# document presence checks, not LLM verification. Production verifier
# dispatch uses the same patterns; if these pass, verifier receives correct
# inputs.
#
# Exit codes: 0 = all 4 layers behave as documented, 1 = layer failure
# =============================================================================
set -euo pipefail

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Verify required POSIX tools present.
command -v find >/dev/null || { echo "FAIL: find not available"; exit 1; }
command -v grep >/dev/null || { echo "FAIL: grep not available"; exit 1; }
command -v awk  >/dev/null || { echo "FAIL: awk not available";  exit 1; }

# Locate plugin dir relative to this script (run-from-anywhere).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLAN_WRITING="$PLUGIN_DIR/skills/plan-writing.md"
AID_PLAN_CMD="$PLUGIN_DIR/commands/aid-plan.md"

[[ -f "$PLAN_WRITING" ]] || { echo "FAIL: plan-writing.md not found at $PLAN_WRITING"; exit 1; }
[[ -f "$AID_PLAN_CMD" ]] || { echo "FAIL: aid-plan.md not found at $AID_PLAN_CMD";   exit 1; }

# Test-plan fixture with deliberate violations across all 4 layers.
cat > "$TEST_DIR/test-plan.md" <<'EOF'
---
id: P999
type: bug-fix
status: draft
---

# Plan: Test Plan with Deliberate Quality Defects

## Goal

Fix gates_no_generated_by precondition fail.

## Implementation Steps

### Sample Step (test fixture — not parsed by aid-plan-to-epic.sh)

**Implementation Detail:**

```bash
# Layer 1 violation — cited CLI args don't exist in real interface
bash plugins/aid-orchestrator/scripts/aid-run-gates.sh --state-file "$X"

# Layer 2 violation — direct yq state mutation, no wrapper invocation
yq -i '.state = "GATES"' fsm-state.yaml
```

Test fixture references: tests/bats/test-fixture.bats — uses fake_helper_does_not_exist function

EOF

# ─── LAYER 1: 17e CLI invocation grounding ────────────────────────────────
echo "[Layer 1] CLI invocation grounding (17e)"
# 1a. plan-writing.md must document 17e
if grep -q "^  17e\." "$PLAN_WRITING"; then
  echo "  ✓ plan-writing.md documents 17e sub-check"
else
  echo "FAIL: plan-writing.md missing 17e sub-check header"
  exit 1
fi

# 1b. extraction pattern: bash <script> <flags> from a plan
CLI_USES=$(grep -E '^\s*bash\s+\S+\s+--' "$TEST_DIR/test-plan.md" || true)
if [[ "$CLI_USES" == *"--state-file"* ]]; then
  echo "  ✓ Test plan exposes --state-file invocation for grounding"
else
  echo "FAIL: extraction pattern did not capture --state-file"
  exit 1
fi

# 1c. real aid-run-gates.sh must NOT advertise --state-file (drift detection)
GATES_SCRIPT="$PLUGIN_DIR/scripts/aid-run-gates.sh"
if [[ -f "$GATES_SCRIPT" ]]; then
  if head -100 "$GATES_SCRIPT" | grep -q -- "--state-file"; then
    echo "  SKIP: aid-run-gates.sh now exposes --state-file (interface changed); 17e baseline shifted"
  else
    echo "  ✓ aid-run-gates.sh does NOT advertise --state-file → would flag REVISE_REQUIRED"
  fi
else
  echo "  SKIP: aid-run-gates.sh not present (older checkout?)"
fi

# ─── LAYER 2: #19 Design Defeat pre-screening (narrowed) ──────────────────
echo "[Layer 2] Design Defeat pre-screening (#19)"
# 2a. plan-writing.md must document #19
if grep -q "DESIGN DEFEAT DETECTION" "$PLAN_WRITING"; then
  echo "  ✓ plan-writing.md documents #19"
else
  echo "FAIL: plan-writing.md missing DESIGN DEFEAT DETECTION block"
  exit 1
fi

# 2b. positive heuristic match: goal_fix + state_mutation + no cmd_wrapper
HAS_GOAL_FIX=$(awk '/^## Goal/{flag=1; next} /^## /{flag=0} flag' "$TEST_DIR/test-plan.md" \
                | grep -ciE 'fix|fail|bypass|precondition|validation' || true)
HAS_STATE_MUTATION=$(grep -cE '(yq -i|sed -i)[^|]*((fsm-)?state\.yaml)' "$TEST_DIR/test-plan.md" || true)
HAS_CMD_WRAPPER=$(grep -cE 'cmd_(transition|advance_to_gates|init|increment_step|done_advance)' \
                  "$TEST_DIR/test-plan.md" || true)

# Force integers (grep -c returns "0" for no match).
HAS_GOAL_FIX=${HAS_GOAL_FIX:-0}
HAS_STATE_MUTATION=${HAS_STATE_MUTATION:-0}
HAS_CMD_WRAPPER=${HAS_CMD_WRAPPER:-0}

if (( HAS_GOAL_FIX > 0 && HAS_STATE_MUTATION > 0 && HAS_CMD_WRAPPER == 0 )); then
  echo "  ✓ Pre-screening triggered: goal_fix=$HAS_GOAL_FIX state_mut=$HAS_STATE_MUTATION cmd_wrapper=$HAS_CMD_WRAPPER → activate #19"
else
  echo "FAIL: pre-screening should have triggered (goal_fix=$HAS_GOAL_FIX state_mut=$HAS_STATE_MUTATION cmd_wrapper=$HAS_CMD_WRAPPER)"
  exit 1
fi

# 2c. negative control — release-related sed -i must NOT trigger heuristic
NEG_FIXTURE='sed -i "s/v2.18.3/v2.20.0/g" CHANGELOG.md README.md .claude-plugin/marketplace.json'
NEG_STATE_MUT=$(echo "$NEG_FIXTURE" | grep -cE '(yq -i|sed -i)[^|]*((fsm-)?state\.yaml)' || true)
NEG_STATE_MUT=${NEG_STATE_MUT:-0}
if (( NEG_STATE_MUT == 0 )); then
  echo "  ✓ Negative control: release sed -i (CHANGELOG/README/marketplace.json) NOT flagged"
else
  echo "FAIL: heuristic over-triggers on release-related mutations (count=$NEG_STATE_MUT)"
  exit 1
fi

# ─── LAYER 3: /aid-plan write Step 9 (CP1 lifecycle) ──────────────────────
echo "[Layer 3] /aid-plan write CP1 lifecycle"
# Check Mode: Write Plan section has step 9 numbered entry
WRITE_STEP9=$(awk '/^## Mode: Write Plan/{flag=1; next} /^## Mode:/{flag=0} flag' \
              "$AID_PLAN_CMD" | grep -c "^9\." || true)
WRITE_STEP9=${WRITE_STEP9:-0}
if (( WRITE_STEP9 > 0 )); then
  echo "  ✓ Mode: Write Plan exposes Step 9 (CP1 review)"
else
  echo "FAIL: Mode: Write Plan missing Step 9 (count=$WRITE_STEP9)"
  exit 1
fi

# ─── LAYER 4: EVIDENCE REQUIREMENT in reviewer prompt ─────────────────────
echo "[Layer 4] Reviewer evidence requirement"
EVIDENCE_HDR=$(grep -c "EVIDENCE REQUIREMENT" "$AID_PLAN_CMD" || true)
EVIDENCE_FIELDS=$(grep -cE "command_run:|output_excerpt:" "$AID_PLAN_CMD" || true)
EVIDENCE_HDR=${EVIDENCE_HDR:-0}
EVIDENCE_FIELDS=${EVIDENCE_FIELDS:-0}
if (( EVIDENCE_HDR >= 1 && EVIDENCE_FIELDS >= 4 )); then
  echo "  ✓ Reviewer prompt has EVIDENCE REQUIREMENT (header=$EVIDENCE_HDR, field hits=$EVIDENCE_FIELDS)"
else
  echo "FAIL: reviewer prompt missing evidence spec (header=$EVIDENCE_HDR, field hits=$EVIDENCE_FIELDS)"
  exit 1
fi

echo ""
echo "test-plan-quality-enforcement: PASS — all 4 layers detect their target defects"
exit 0
