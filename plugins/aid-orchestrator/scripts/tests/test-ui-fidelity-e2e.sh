#!/usr/bin/env bash
# test-ui-fidelity-e2e.sh -- E2E scenarios for existing_ui FSM guard
# Tests the full guard chain: verdict.json present/absent + result values.
# 4 scenarios: happy / un-applied-delta / collateral-damage / capture-absent
# Skip guard: exits 0 if Playwright browsers not installed (CI safety, L3 advisory).
# Part of AID E7B wiring (E-056-3_3 Step 5).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSM="${SCRIPT_DIR}/../aid-fsm.sh"
PASS=0; FAIL=0; SKIP=0

_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
_skip() { echo "SKIP: $1"; SKIP=$((SKIP + 1)); }

if [[ ! -f "$FSM" ]]; then
  echo "ERROR: aid-fsm.sh not found: $FSM" >&2; exit 1
fi

# ---------------------------------------------------------------------------
# Playwright availability check
# Skip guard: exits 0 (not fail) when Playwright browsers are not installed.
# Heuristic: check ms-playwright cache dir for chromium binaries.
# ---------------------------------------------------------------------------
check_playwright_available() {
  if ! command -v npx >/dev/null 2>&1; then
    return 1
  fi
  local cache_dir="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
  if [[ -d "$cache_dir" ]] && ls "$cache_dir"/chromium-*/chrome-linux/chrome >/dev/null 2>&1; then
    return 0
  fi
  # Fallback: system playwright binary
  if command -v playwright >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

PLAYWRIGHT_AVAILABLE=false
if check_playwright_available; then
  PLAYWRIGHT_AVAILABLE=true
fi

echo "=== test-ui-fidelity-e2e.sh ==="
if [[ "$PLAYWRIGHT_AVAILABLE" == "true" ]]; then
  echo "Playwright: available"
else
  echo "Playwright: not available -- T4 D-scenario will be skipped"
fi
echo ""

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ---------------------------------------------------------------------------
# Helper: setup minimal FSM run for existing_ui step
# Evidence layout mirrors test-fsm-ui-fidelity.sh (same guard under test).
# ---------------------------------------------------------------------------
setup_run() {
  local label="$1"
  local dir="$TMPDIR_ROOT/$label"
  mkdir -p "$dir/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/steps/step_1_frontend/ui"

  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/fsm-state.yaml" << FSMEOF
epic_id: E-TEST-E7B-E2E
run_id: R-TEST-E2E
state: EXECUTE
current_step: 0
total_steps: 1
mode: full
branch: task/E-TEST-E7B-E2E/main
base_commit: abc1234
gate_retries: 0
escalation_count: 0
streamlined_mode: false
started_at: "2026-06-30T00:00:00Z"
created_at: 2026-06-30T00:00:00Z
plan_json_hash: PLACEHOLDER
plan_path: null
steps:
  - id: 1
    name: ""
    status: pending
    started_at: null
    completed_at: null
FSMEOF

  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/plan.json" << PEOF
{
  "epic_id": "E-TEST-E7B-E2E",
  "version": "1.0",
  "steps": [
    {
      "id": "step_1_frontend",
      "role": "frontend",
      "objective": "E2E test existing_ui step",
      "inputs": [],
      "outputs": [],
      "constraints": [],
      "allowed_paths": [],
      "forbidden_paths": [],
      "acceptance_criteria": ["AC1"],
      "ui_change_mode": "existing_ui",
      "ui_change_contract": null
    }
  ],
  "dependencies": [],
  "gates": []
}
PEOF

  local hash
  hash="$(sha256sum "$dir/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/plan.json" | awk '{print $1}')"
  sed -i "s/plan_json_hash: PLACEHOLDER/plan_json_hash: $hash/" \
    "$dir/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/fsm-state.yaml"

  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/step-0-verify.md" << VEOF
# Step 0 Verify

**EPIC:** E-TEST-E7B-E2E | **Run:** R-TEST-E2E | **Commit:** abc1234abc

## AC Checklist

- [x] AC1: test criterion met

## Memory Used

N/A -- test

## Memory Written

N/A

## Result: PASS
VEOF

  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/verifier-output-step-0.md" << VOUT
_generated_by: test-harness
_generated_at: 2026-06-30T00:00:00Z
classification: SKIP
reason: test harness
VOUT

  echo "$dir"
}

write_verdict() {
  local dir="$1" result="$2"
  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/steps/step_1_frontend/ui/verdict.json" << EOF
{
  "artifact_type": "ui_fidelity",
  "ui_fidelity": {
    "verdict": {"kind": "none"},
    "result": "$result",
    "result_detail": "E2E scenario: result=$result"
  }
}
EOF
}

# ---------------------------------------------------------------------------
# T1: Happy path -- pass verdict -> increment proceeds
# Scenario: implementer applied the UI change correctly; baseline matches new UI.
# ---------------------------------------------------------------------------
echo "TEST: T1 -- Happy path (pass verdict -> increment proceeds)"
{
  d="$(setup_run T1)"
  write_verdict "$d" "pass"
  state_file="$d/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/fsm-state.yaml"
  out="$(cd "$d" && bash "$FSM" increment-step "$state_file" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _pass "T1 -- happy path: pass verdict allowed increment (exit 0)"
  else
    _fail "T1 -- happy path: expected exit 0, got $rc. Output: $out"
  fi
}

# ---------------------------------------------------------------------------
# T2: Un-applied delta -- implementer skipped the UI change -> verdict fail -> blocks
# Scenario: implementer wrote backend logic but forgot to update the component;
# ui-compare.mjs detected no visual change where change was expected.
# ---------------------------------------------------------------------------
echo "TEST: T2 -- Un-applied delta (fail verdict blocks increment)"
{
  d="$(setup_run T2)"
  write_verdict "$d" "fail"
  state_file="$d/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/fsm-state.yaml"
  out="$(cd "$d" && bash "$FSM" increment-step "$state_file" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]] && echo "$out" | grep -q "existing_ui step requires ui/verdict.json"; then
    _pass "T2 -- un-applied delta: fail verdict blocked increment (frontend_visual_fidelity_block)"
  elif [[ $rc -ne 0 ]]; then
    _fail "T2 -- un-applied delta: exited non-zero but wrong reason. Output: $out"
  else
    _fail "T2 -- un-applied delta: expected non-zero exit, got 0. Output: $out"
  fi
}

# ---------------------------------------------------------------------------
# T3: Collateral damage -- undeclared UI change detected -> verdict fail -> blocks
# Scenario: implementer changed a shared CSS class; comparison found diff
# outside the declared contract path -- result=fail to prevent silent regression.
# ---------------------------------------------------------------------------
echo "TEST: T3 -- Collateral damage (undeclared UI change = fail verdict -> blocks)"
{
  d="$(setup_run T3)"
  write_verdict "$d" "fail"
  state_file="$d/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/fsm-state.yaml"
  out="$(cd "$d" && bash "$FSM" increment-step "$state_file" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]] && echo "$out" | grep -q "existing_ui step requires ui/verdict.json"; then
    _pass "T3 -- collateral damage: fail verdict blocked increment (same guard, undeclared diff scenario)"
  elif [[ $rc -ne 0 ]]; then
    _fail "T3 -- collateral damage: exited non-zero but wrong reason. Output: $out"
  else
    _fail "T3 -- collateral damage: expected non-zero exit, got 0. Output: $out"
  fi
}

# ---------------------------------------------------------------------------
# T4: Capture-absent -- companion did not run; no baseline -> unverifiable -> blocks
# Scenario: Playwright not available in CI; ui-capture.mjs never ran;
# verdict.json absent -> FSM treats absent as non-pass (conservative).
# D-scenario: full page.route mock requires Playwright -- SKIP if not installed.
# ---------------------------------------------------------------------------
echo "TEST: T4 -- Capture-absent (no verdict.json -> unverifiable -> blocks)"
if [[ "$PLAYWRIGHT_AVAILABLE" == "true" ]]; then
  # When Playwright is available, verify the real infrastructure files exist
  # and that absent verdict.json blocks the FSM (full E2E infrastructure check).
  PLUGIN_PATH="$(cd "$SCRIPT_DIR/../../.." && pwd)/plugins/aid-orchestrator"
  {
    d="$(setup_run T4)"
    # No write_verdict -- file absent (simulates capture-absent)
    state_file="$d/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/fsm-state.yaml"
    out="$(cd "$d" && bash "$FSM" increment-step "$state_file" 2>&1)"
    rc=$?
    if [[ $rc -ne 0 ]] && echo "$out" | grep -q "existing_ui step requires ui/verdict.json"; then
      _pass "T4 -- capture-absent: absent verdict.json blocked increment (unverifiable -> blocked)"
    elif [[ $rc -ne 0 ]]; then
      _fail "T4 -- capture-absent: exited non-zero but wrong reason. Output: $out"
    else
      _fail "T4 -- capture-absent: expected non-zero exit, got 0. Output: $out"
    fi
  }
  # D-scenario infrastructure check (Playwright available)
  if [[ -f "$PLUGIN_PATH/lib/ui-fidelity/ui-capture.mjs" ]] && \
     [[ -f "$PLUGIN_PATH/lib/ui-fidelity/ui-compare.mjs" ]]; then
    _pass "T4 D-scenario infrastructure: ui-capture.mjs and ui-compare.mjs present"
  else
    _fail "T4 D-scenario: missing ui-capture.mjs or ui-compare.mjs in $PLUGIN_PATH/lib/ui-fidelity/"
  fi
else
  _skip "T4 -- D-scenario skipped: Playwright browsers not installed. Install with: npx playwright install chromium"
  # Still run the FSM-level absent-verdict check (does not need Playwright)
  {
    d="$(setup_run T4b)"
    state_file="$d/.aid-o/work/evidence/E-TEST-E7B-E2E/R-TEST-E2E/fsm-state.yaml"
    out="$(cd "$d" && bash "$FSM" increment-step "$state_file" 2>&1)"
    rc=$?
    if [[ $rc -ne 0 ]] && echo "$out" | grep -q "existing_ui step requires ui/verdict.json"; then
      _pass "T4 FSM-only: absent verdict.json blocked increment (Playwright skip, FSM guard still verified)"
    elif [[ $rc -ne 0 ]]; then
      _fail "T4 FSM-only: exited non-zero but wrong reason. Output: $out"
    else
      _fail "T4 FSM-only: expected non-zero exit, got 0. Output: $out"
    fi
  }
fi

echo ""
TOTAL=$((PASS + FAIL + SKIP))
echo "Results: $PASS/$TOTAL passed, $FAIL failed, $SKIP skipped"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
