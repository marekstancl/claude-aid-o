#!/usr/bin/env bash
# =============================================================================
# test-epic-to-json.sh — Unit tests for aid-epic-to-json.sh
#
# Tests the EPIC.md -> plan.json + state.yaml conversion script.
# Verifies: file generation, step count, parallel group detection,
#           cycle detection, and error handling for missing arguments.
#
# Usage:
#   ./test-epic-to-json.sh
#
# Exit codes: 0=all passed, 1=one or more tests failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-epic-to-json.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
SCHEMA_FILE="$REPO_ROOT/plugins/aid-orchestrator/defaults/templates/plan.schema.json"

# ---------------------------------------------------------------------------
# Test accounting
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
TMPDIR_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pass() {
  TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$(( TESTS_FAILED + 1 ))
  echo "  FAIL: $1 -- $2"
}

run_test() {
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  echo ""
  echo "TEST: $1"
}

make_output_dir() {
  local name="$1"
  local d="$TMPDIR_ROOT/$name"
  mkdir -p "$d"
  echo "$d"
}

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
  echo "ERROR: Script under test not found: $SCRIPT_UNDER_TEST" >&2
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: Schema file not found: $SCHEMA_FILE" >&2
  echo "  Run /aid-init in the project to deploy templates." >&2
  exit 1
fi

echo "=== test-epic-to-json.sh ==="
echo "Script: $SCRIPT_UNDER_TEST"
echo "Fixtures: $FIXTURES_DIR"
echo "Schema: $SCHEMA_FILE"

MINIMAL_EPIC="$FIXTURES_DIR/E-TEST-001-1_1-minimal-test-plan.md"
PARALLEL_EPIC="$FIXTURES_DIR/E-TEST-002-2_3-multi-phase-test-plan.md"
CIRCULAR_EPIC="$FIXTURES_DIR/E-TEST-003-1_1-circular-deps.md"

# ===========================================================================
# TEST 1: Missing --epic flag returns exit code 1
# ===========================================================================
run_test "Missing --epic flag returns exit code 1"

out_dir="$(make_output_dir "t01")"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --schema "$SCHEMA_FILE" \
  --output-dir "$out_dir" \
  >/dev/null 2>&1 || actual_exit=$?

if [[ "$actual_exit" -eq 1 ]]; then
  pass "missing --epic exits with code 1"
else
  fail "missing --epic exits with code 1" "got exit code $actual_exit, expected 1"
fi

# ===========================================================================
# TEST 2: EPIC file not found returns exit code 3
# ===========================================================================
run_test "Nonexistent EPIC file returns exit code 3"

out_dir="$(make_output_dir "t02")"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --epic "/nonexistent/E-000.md" \
  --schema "$SCHEMA_FILE" \
  --output-dir "$out_dir" \
  >/dev/null 2>&1 || actual_exit=$?

if [[ "$actual_exit" -eq 3 ]]; then
  pass "nonexistent EPIC file exits with code 3"
else
  fail "nonexistent EPIC file exits with code 3" "got exit code $actual_exit, expected 3"
fi

# ===========================================================================
# TEST 3: Valid EPIC produces plan.json and state.yaml
# ===========================================================================
run_test "Valid EPIC produces plan.json and state.yaml"

out_dir="$(make_output_dir "t03")"

actual_exit=0
manifest="$("$SCRIPT_UNDER_TEST" \
  --epic "$MINIMAL_EPIC" \
  --schema "$SCHEMA_FILE" \
  --output-dir "$out_dir" \
  2>/dev/null)" || actual_exit=$?

if [[ "$actual_exit" -ne 0 ]]; then
  fail "valid EPIC exits with code 0" "got exit code $actual_exit"
else
  # Extract plan_json and progress paths from the manifest JSON
  plan_json_path="$(echo "$manifest" | jq -r '.plan_json // ""' 2>/dev/null)"
  progress_path="$(echo "$manifest" | jq -r '.progress // ""' 2>/dev/null)"

  missing=""
  [[ -z "$plan_json_path" || ! -f "$plan_json_path" ]] && missing="${missing} plan.json"
  [[ -z "$progress_path" || ! -f "$progress_path" ]] && missing="${missing} state.yaml"

  if [[ -z "$missing" ]]; then
    pass "valid EPIC produces plan.json and state.yaml"
  else
    fail "valid EPIC produces required output files" "missing:$missing (manifest: $manifest)"
  fi
fi

# Store for subsequent tests
PLAN_JSON_PATH="${plan_json_path:-}"
PROGRESS_PATH="${progress_path:-}"

# ===========================================================================
# TEST 4: plan.json has correct step count matching EPIC steps table
# ===========================================================================
run_test "plan.json step count matches the EPIC Steps table (2 steps for minimal EPIC)"

if [[ -n "$PLAN_JSON_PATH" && -f "$PLAN_JSON_PATH" ]]; then
  step_count="$(jq '.steps | length' "$PLAN_JSON_PATH" 2>/dev/null)"
  # The minimal EPIC has 2 steps in the Steps table
  if [[ "$step_count" -eq 2 ]]; then
    pass "plan.json has 2 steps matching minimal EPIC Steps table"
  else
    fail "plan.json step count equals 2" "got $step_count steps"
  fi
else
  fail "plan.json step count check" "skipped — plan.json not available from TEST 3"
fi

# ===========================================================================
# TEST 5: plan.json is valid JSON with required top-level fields
# ===========================================================================
run_test "plan.json contains required top-level fields: epic_id, version, steps, dependencies"

if [[ -n "$PLAN_JSON_PATH" && -f "$PLAN_JSON_PATH" ]]; then
  missing_fields=""

  jq -e '.epic_id' "$PLAN_JSON_PATH" >/dev/null 2>&1 || missing_fields="${missing_fields} epic_id"
  jq -e '.version' "$PLAN_JSON_PATH" >/dev/null 2>&1 || missing_fields="${missing_fields} version"
  jq -e '.steps' "$PLAN_JSON_PATH" >/dev/null 2>&1 || missing_fields="${missing_fields} steps"
  jq -e '.dependencies' "$PLAN_JSON_PATH" >/dev/null 2>&1 || missing_fields="${missing_fields} dependencies"

  if [[ -z "$missing_fields" ]]; then
    pass "plan.json has required fields: epic_id, version, steps, dependencies"
  else
    fail "plan.json has required fields" "missing:$missing_fields"
  fi
else
  fail "plan.json required fields check" "skipped — plan.json not available from TEST 3"
fi

# ===========================================================================
# TEST 6: state.yaml initializes all steps as 'pending'
# ===========================================================================
run_test "state.yaml initializes all steps with status: pending"

if [[ -n "$PROGRESS_PATH" && -f "$PROGRESS_PATH" ]]; then
  non_pending="$(jq '[.[] | select(.status != "pending")] | length' "$PROGRESS_PATH" 2>/dev/null)"
  total_entries="$(jq 'length' "$PROGRESS_PATH" 2>/dev/null)"

  if [[ "$total_entries" -gt 0 && "$non_pending" -eq 0 ]]; then
    pass "state.yaml has $total_entries entries all with status=pending"
  else
    fail "state.yaml all steps are pending" \
      "total=$total_entries non-pending=$non_pending"
  fi
else
  fail "state.yaml status check" "skipped — progress file not available from TEST 3"
fi

# ===========================================================================
# TEST 7: Parallel groups detected correctly for EPIC with group-1 annotation
# ===========================================================================
run_test "Parallel groups detected: EPIC with group-1 annotation produces parallel_groups in plan.json"

out_dir="$(make_output_dir "t07")"

actual_exit=0
parallel_manifest="$("$SCRIPT_UNDER_TEST" \
  --epic "$PARALLEL_EPIC" \
  --schema "$SCHEMA_FILE" \
  --output-dir "$out_dir" \
  2>/dev/null)" || actual_exit=$?

if [[ "$actual_exit" -ne 0 ]]; then
  fail "parallel EPIC exits with code 0" "got exit code $actual_exit"
else
  parallel_plan_json="$(echo "$parallel_manifest" | jq -r '.plan_json // ""' 2>/dev/null)"

  if [[ -n "$parallel_plan_json" && -f "$parallel_plan_json" ]]; then
    pg_count="$(jq '.parallel_groups | length' "$parallel_plan_json" 2>/dev/null)"
    # The EPIC has steps 1 and 2 in group-1, so at least one parallel group expected
    if [[ "$pg_count" -ge 1 ]]; then
      pass "parallel EPIC produces $pg_count parallel_group(s) in plan.json"
    else
      fail "parallel EPIC produces at least 1 parallel group" "got $pg_count"
    fi
  else
    fail "parallel EPIC plan.json readable" "path: $parallel_plan_json"
  fi
fi

# ===========================================================================
# TEST 8: Cycle detection: EPIC with circular deps exits with code 1
# ===========================================================================
run_test "Circular dependency in EPIC Steps table exits with code 1"

out_dir="$(make_output_dir "t08")"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --epic "$CIRCULAR_EPIC" \
  --schema "$SCHEMA_FILE" \
  --output-dir "$out_dir" \
  >/dev/null 2>&1 || actual_exit=$?

if [[ "$actual_exit" -eq 1 ]]; then
  pass "circular dependency EPIC exits with code 1"
else
  fail "circular dependency EPIC exits with code 1" "got exit code $actual_exit, expected 1"
fi

# ===========================================================================
# TEST 9: stdout manifest is valid JSON
# ===========================================================================
run_test "stdout manifest from valid EPIC is valid JSON with plan_json, progress, run_id, evidence_dir"

out_dir="$(make_output_dir "t09")"

actual_exit=0
manifest2="$("$SCRIPT_UNDER_TEST" \
  --epic "$MINIMAL_EPIC" \
  --schema "$SCHEMA_FILE" \
  --output-dir "$out_dir" \
  2>/dev/null)" || actual_exit=$?

if [[ "$actual_exit" -ne 0 ]]; then
  fail "manifest output exits with code 0" "got exit code $actual_exit"
else
  missing_manifest_keys=""
  echo "$manifest2" | jq -e '.plan_json' >/dev/null 2>&1 || missing_manifest_keys="${missing_manifest_keys} plan_json"
  echo "$manifest2" | jq -e '.progress' >/dev/null 2>&1 || missing_manifest_keys="${missing_manifest_keys} progress"
  echo "$manifest2" | jq -e '.run_id' >/dev/null 2>&1 || missing_manifest_keys="${missing_manifest_keys} run_id"
  echo "$manifest2" | jq -e '.evidence_dir' >/dev/null 2>&1 || missing_manifest_keys="${missing_manifest_keys} evidence_dir"

  if [[ -z "$missing_manifest_keys" ]]; then
    pass "stdout manifest is valid JSON with required keys"
  else
    fail "stdout manifest has required keys" "missing:$missing_manifest_keys"
  fi
fi

# ===========================================================================
# TEST 10: step IDs in plan.json follow the pattern step_N_role
# ===========================================================================
run_test "Step IDs in plan.json follow the required pattern: step_N_role"

if [[ -n "$PLAN_JSON_PATH" && -f "$PLAN_JSON_PATH" ]]; then
  invalid_ids="$(jq -r '.steps[].id' "$PLAN_JSON_PATH" 2>/dev/null \
    | grep -Ev '^step_[a-z0-9_]+$' || true)"

  if [[ -z "$invalid_ids" ]]; then
    pass "all step IDs match pattern step_[a-z0-9_]+"
  else
    fail "all step IDs match required pattern" "invalid IDs found: $invalid_ids"
  fi
else
  fail "step ID pattern check" "skipped — plan.json not available from TEST 3"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
[[ "$TESTS_FAILED" -eq 0 ]] && exit 0 || exit 1
