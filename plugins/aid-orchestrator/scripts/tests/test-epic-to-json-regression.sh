#!/usr/bin/env bash
# =============================================================================
# test-epic-to-json-regression.sh — Golden snapshot regression for aid-epic-to-json.sh
#
# Verifies that the plan-graph lib refactor produces IDENTICAL plan.json output
# compared to the golden snapshot captured before the refactor.
#
# Usage:
#   ./test-epic-to-json-regression.sh
#
# First-run mode: if golden dir is absent, generates it from current output.
# Exit: 0 all pass, 1 any fail
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-epic-to-json.sh"
SCHEMA_FILE="$REPO_ROOT/plugins/aid-orchestrator/defaults/templates/plan.schema.json"
GOLDEN_DIR="$SCRIPT_DIR/fixtures/epic-to-json-golden"
FIXTURE_MINIMAL="$SCRIPT_DIR/fixtures/E-TEST-001-1_1-minimal-test-plan.md"
FIXTURE_CYCLE="$SCRIPT_DIR/fixtures/E-TEST-003-1_1-circular-deps.md"

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0

_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
  echo "ERROR: Script not found: $SCRIPT_UNDER_TEST" >&2
  exit 1
fi
if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: Schema not found: $SCHEMA_FILE" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE_MINIMAL" ]]; then
  echo "ERROR: Minimal fixture not found: $FIXTURE_MINIMAL" >&2
  exit 1
fi
if [[ ! -f "$FIXTURE_CYCLE" ]]; then
  echo "ERROR: Cycle fixture not found: $FIXTURE_CYCLE" >&2
  exit 1
fi

echo "=== test-epic-to-json-regression.sh ==="
echo "Script: $SCRIPT_UNDER_TEST"
echo "Golden: $GOLDEN_DIR"
echo ""

# ---------------------------------------------------------------------------
# Helper: run script on a fixture, return path to plan.json
# ---------------------------------------------------------------------------
run_on_fixture() {
  local fixture="$1"
  local out_dir="$2"
  local result
  result="$(bash "$SCRIPT_UNDER_TEST" \
    --epic "$fixture" \
    --schema "$SCHEMA_FILE" \
    --output-dir "$out_dir" 2>/dev/null)"
  echo "$result" | jq -r '.plan_json'
}

# ---------------------------------------------------------------------------
# First-run mode: generate golden snapshots if directory absent
# ---------------------------------------------------------------------------
if [[ ! -d "$GOLDEN_DIR" ]]; then
  echo "Golden directory not found — generating snapshots (first-run mode)."
  mkdir -p "$GOLDEN_DIR"

  out_dir="$TMPDIR_ROOT/gen-minimal"
  mkdir -p "$out_dir"
  plan_path="$(run_on_fixture "$FIXTURE_MINIMAL" "$out_dir")"
  if [[ -z "$plan_path" || ! -f "$plan_path" ]]; then
    echo "ERROR: Failed to generate output for minimal fixture." >&2
    exit 1
  fi
  # Save golden without the timestamp field (it changes each run)
  jq -S 'del(.created_at)' "$plan_path" > "$GOLDEN_DIR/minimal-plan.golden.json"

  echo "Generated golden snapshot: $GOLDEN_DIR/minimal-plan.golden.json"
  echo ""
  echo "Results: 0/0 run, 0 passed, 0 failed"
  exit 0
fi

# ---------------------------------------------------------------------------
# T1: Minimal fixture — plan.json matches golden (keys-sorted, no timestamp)
# ---------------------------------------------------------------------------
echo "TEST: T1 — Minimal fixture output matches golden snapshot"
{
  t1_out="$TMPDIR_ROOT/t1"
  mkdir -p "$t1_out"
  plan_path="$(run_on_fixture "$FIXTURE_MINIMAL" "$t1_out")"
  if [[ -z "$plan_path" || ! -f "$plan_path" ]]; then
    _fail "T1: script failed to produce plan.json"
  else
    actual="$(jq -S 'del(.created_at)' "$plan_path")"
    expected="$(jq -S '.' "$GOLDEN_DIR/minimal-plan.golden.json")"
    if diff_out="$(diff <(echo "$expected") <(echo "$actual") 2>&1)"; then
      _pass "T1: plan.json matches golden (keys sorted, timestamp excluded)"
    else
      _fail "T1: plan.json differs from golden"
      echo "--- diff (expected vs actual) ---"
      echo "$diff_out"
    fi
  fi
}

# ---------------------------------------------------------------------------
# T2: Minimal fixture — two consecutive runs produce identical output
#     (determinism check for topological_order)
# ---------------------------------------------------------------------------
echo "TEST: T2 — Two runs on minimal fixture produce identical output (determinism)"
{
  t2a_out="$TMPDIR_ROOT/t2a"
  t2b_out="$TMPDIR_ROOT/t2b"
  mkdir -p "$t2a_out" "$t2b_out"
  plan_a="$(run_on_fixture "$FIXTURE_MINIMAL" "$t2a_out")"
  plan_b="$(run_on_fixture "$FIXTURE_MINIMAL" "$t2b_out")"
  if [[ -z "$plan_a" || ! -f "$plan_a" || -z "$plan_b" || ! -f "$plan_b" ]]; then
    _fail "T2: one or both runs failed to produce plan.json"
  else
    actual_a="$(jq -S 'del(.created_at)' "$plan_a")"
    actual_b="$(jq -S 'del(.created_at)' "$plan_b")"
    if diff_out="$(diff <(echo "$actual_a") <(echo "$actual_b") 2>&1)"; then
      _pass "T2: two consecutive runs produce identical output"
    else
      _fail "T2: runs differ (non-deterministic output)"
      echo "--- diff (run 1 vs run 2) ---"
      echo "$diff_out"
    fi
  fi
}

# ---------------------------------------------------------------------------
# T3: Cycle fixture — exits non-zero with "Circular dependency" in stderr
# ---------------------------------------------------------------------------
echo "TEST: T3 — Cycle fixture exits non-zero with circular dependency error"
{
  t3_out="$TMPDIR_ROOT/t3"
  mkdir -p "$t3_out"
  stderr_out="$TMPDIR_ROOT/t3-stderr.txt"
  AID_ALLOW_SPARSE_AC=1 bash "$SCRIPT_UNDER_TEST" \
    --epic "$FIXTURE_CYCLE" \
    --schema "$SCHEMA_FILE" \
    --output-dir "$t3_out" \
    >"$TMPDIR_ROOT/t3-stdout.txt" 2>"$stderr_out"
  exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    if grep -q "Circular dependency" "$stderr_out"; then
      _pass "T3: cycle fixture exits $exit_code and stderr contains 'Circular dependency'"
    else
      _fail "T3: exits non-zero but stderr missing 'Circular dependency' — got: $(cat "$stderr_out")"
    fi
  else
    _fail "T3: cycle fixture should exit non-zero but exited 0"
  fi
}

# ---------------------------------------------------------------------------
# T4: ui_change_contract round-trip — steps[0].ui_change_contract non-null
# ---------------------------------------------------------------------------
echo "TEST: T4 — ui_change_contract envelope round-trip"
{
  FIXTURE_UI_CONTRACT="$SCRIPT_DIR/fixtures/epic-to-json-golden/ui-contract-plan/epic.md"
  EXPECTED_UI_CONTRACT="$SCRIPT_DIR/fixtures/epic-to-json-golden/ui-contract-plan/expected.json"

  if [[ ! -f "$FIXTURE_UI_CONTRACT" ]]; then
    _fail "T4 — fixture missing: $FIXTURE_UI_CONTRACT"
  elif [[ ! -f "$EXPECTED_UI_CONTRACT" ]]; then
    _fail "T4 — expected.json missing: $EXPECTED_UI_CONTRACT"
  else
    t4_out="$TMPDIR_ROOT/t4"
    mkdir -p "$t4_out"
    t4_plan="$(run_on_fixture "$FIXTURE_UI_CONTRACT" "$t4_out")"

    if [[ -z "$t4_plan" || ! -f "$t4_plan" ]]; then
      _fail "T4 — aid-epic-to-json.sh failed on ui-contract fixture"
    else
      # Check that steps[0].ui_change_contract is non-null
      step0_contract="$(jq -r '.steps[0].ui_change_contract' "$t4_plan")"
      if [[ "$step0_contract" == "null" || -z "$step0_contract" ]]; then
        _fail "T4 — steps[0].ui_change_contract is null (expected non-null)"
      else
        # Verify specific fields match expected.json
        contract_path="$(jq -r '.steps[0].ui_change_contract.path' "$t4_plan")"
        contract_sha="$(jq -r '.steps[0].ui_change_contract.sha256' "$t4_plan")"
        contract_schema="$(jq -r '.steps[0].ui_change_contract.schema_version' "$t4_plan")"

        expected_path="$(jq -r '.steps[0].ui_change_contract.path' "$EXPECTED_UI_CONTRACT")"
        expected_sha="$(jq -r '.steps[0].ui_change_contract.sha256' "$EXPECTED_UI_CONTRACT")"
        expected_schema="$(jq -r '.steps[0].ui_change_contract.schema_version' "$EXPECTED_UI_CONTRACT")"

        if [[ "$contract_path" == "$expected_path" && "$contract_sha" == "$expected_sha" && "$contract_schema" == "$expected_schema" ]]; then
          _pass "T4 — ui_change_contract round-trip: path/sha256/schema_version match"
        else
          _fail "T4 — ui_change_contract mismatch. Got: path=$contract_path sha256=$contract_sha schema=$contract_schema | Expected: path=$expected_path sha256=$expected_sha schema=$expected_schema"
        fi
      fi
    fi
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total=$((PASS + FAIL))
echo ""
echo "Results: $total/$total run, $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
