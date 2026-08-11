#!/usr/bin/env bash
# aid-tier: t2
# test-fsm-ui-fidelity.sh — Proves the existing_ui FSM guard ACTUALLY blocks
# (not just grep for presence). Tests cmd_increment_step with fake plan.json + verdict.json.
# Part of AID E7B wiring (E-056-3_3 Step 4). Pattern: P026 "detector without enforcement".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSM="${SCRIPT_DIR}/../aid-fsm.sh"
PASS=0; FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

if [[ ! -f "$FSM" ]]; then
  echo "ERROR: aid-fsm.sh not found: $FSM" >&2; exit 1
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Helper: create minimal FSM state + plan.json for an existing_ui step
setup_run() {
  local label="$1"
  local dir="$TMPDIR_ROOT/$label"
  mkdir -p "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/steps/step_1_frontend/ui"

  # fsm-state.yaml
  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/fsm-state.yaml" << FSMEOF
epic_id: E-TEST-E7B
run_id: R-TEST-E7B
state: EXECUTE
current_step: 0
total_steps: 1
mode: full
branch: task/E-TEST-E7B/main
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

  # plan.json with existing_ui step
  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/plan.json" << PEOF
{
  "epic_id": "E-TEST-E7B",
  "version": "1.0",
  "steps": [
    {
      "id": "step_1_frontend",
      "role": "frontend",
      "objective": "Test existing UI change",
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

  # Update plan_json_hash in state file
  local hash
  hash="$(sha256sum "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/plan.json" | awk '{print $1}')"
  sed -i "s/plan_json_hash: PLACEHOLDER/plan_json_hash: $hash/" \
    "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/fsm-state.yaml"

  # IMP-263: step-bound evidence binding (deploy-date is well before this
  # fixture's created_at, so the run is not grandfathered and strict binding
  # is required). plan_step_hash mirrors _increment_plan_step_hash in aid-fsm.sh:
  # sha256 of `jq -S -c .steps[0]`.
  local plan_step_hash
  plan_step_hash="$(printf '%s' "$(jq -S -c '.steps[0]' "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/plan.json")" | sha256sum | awk '{print $1}')"

  # step-0-verify.md with all required sections
  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/step-0-verify.md" << VEOF
# Step 0 Verify

**EPIC:** E-TEST-E7B | **Run:** R-TEST-E7B | **Commit:** abc1234abc

## AC Checklist

- [x] AC1: test criterion met

## Memory Used

N/A — test

## Memory Written

N/A
step_index: 0
step_id: step_1_frontend
plan_step_hash: ${plan_step_hash}
reviewed_commit: abc1234abc
idempotency_token: TOK-${label}

## Result: PASS
VEOF

  # verifier-output-step-0.md (SKIP classification to bypass CP2 check)
  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/verifier-output-step-0.md" << VOUT
_generated_by: test-harness
_generated_at: 2026-06-30T00:00:00Z
classification: SKIP
reason: test harness
VOUT

  echo "$dir"
}

write_verdict() {
  local dir="$1" result="$2"
  cat > "$dir/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/steps/step_1_frontend/ui/verdict.json" << EOF
{
  "artifact_type": "ui_fidelity",
  "ui_fidelity": {
    "verdict": {"kind": "none"},
    "result": "$result",
    "result_detail": "test: result=$result"
  }
}
EOF
}

# --- T1: pass verdict → increment proceeds ---
echo "TEST: T1 — pass verdict allows increment"
{
  d="$(setup_run T1)"
  write_verdict "$d" "pass"
  state_file="$d/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/fsm-state.yaml"
  out="$(cd "$d" && bash "$FSM" increment-step "$state_file" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    _pass "T1 — pass verdict: increment succeeded (exit 0)"
  else
    _fail "T1 — pass verdict: expected exit 0, got $rc. Output: $out"
  fi
}

# --- T2: fail verdict → _increment_fail blocks ---
echo "TEST: T2 — fail verdict blocks increment"
{
  d="$(setup_run T2)"
  write_verdict "$d" "fail"
  state_file="$d/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/fsm-state.yaml"
  out="$(cd "$d" && bash "$FSM" increment-step "$state_file" 2>&1)"
  rc=$?
  # _increment_fail prints the message lines (not the reason id) to stderr;
  # check for the guard's unique message text instead.
  if [[ $rc -ne 0 ]] && echo "$out" | grep -q "existing_ui step requires ui/verdict.json"; then
    _pass "T2 — fail verdict: blocked by existing_ui guard (frontend_visual_fidelity_block, exit $rc)"
  elif [[ $rc -ne 0 ]]; then
    _fail "T2 — fail verdict: exited non-zero but wrong reason. Output: $out"
  else
    _fail "T2 — fail verdict: expected non-zero exit, got 0. Output: $out"
  fi
}

# --- T3: absent verdict.json → blocks (absent) ---
echo "TEST: T3 — absent verdict.json blocks increment"
{
  d="$(setup_run T3)"
  # NO write_verdict — file absent
  state_file="$d/.aid-o/work/evidence/E-TEST-E7B/R-TEST-E7B/fsm-state.yaml"
  out="$(cd "$d" && bash "$FSM" increment-step "$state_file" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]] && echo "$out" | grep -q "existing_ui step requires ui/verdict.json"; then
    _pass "T3 — absent verdict: blocked by existing_ui guard (frontend_visual_fidelity_block, exit $rc)"
  elif [[ $rc -ne 0 ]]; then
    _fail "T3 — absent verdict: exited non-zero but wrong reason. Output: $out"
  else
    _fail "T3 — absent verdict: expected non-zero exit, got 0. Output: $out"
  fi
}

echo ""
echo "Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
