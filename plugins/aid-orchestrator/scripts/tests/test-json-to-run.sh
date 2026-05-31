#!/usr/bin/env bash
# =============================================================================
# test-json-to-run.sh — Unit tests for aid-json-to-run.sh
#
# Tests the plan.json -> run.md conversion script.
# Verifies: file generation, phase sections in output, error handling for
#           missing arguments, nonexistent inputs, and invalid JSON.
#
# Usage:
#   ./test-json-to-run.sh
#
# Exit codes: 0=all passed, 1=one or more tests failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-json-to-run.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEMPLATES_DIR="$REPO_ROOT/plugins/aid-orchestrator/defaults/templates"

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
# Isolated clean git repo (P040 Component E).
# aid-json-to-run.sh Step 18 now auto-inits the FSM (`aid-fsm.sh init`), which
# enforces a clean working tree on a valid task/main branch. Run all script
# invocations from a throwaway clean git repo so init succeeds and the real
# repo's .aid-o/ is never touched. Fixture/template/output paths are absolute,
# so changing cwd here is safe.
WORK_REPO="$TMPDIR_ROOT/work-repo"
mkdir -p "$WORK_REPO"
(
  cd "$WORK_REPO"
  git init -q
  git config user.email aid-test@example.com
  git config user.name "AID Test"
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo "seed" > .gitkeep
  git add -A
  git commit -q -m "seed"
)
cd "$WORK_REPO"

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

if [[ ! -f "$TEMPLATES_DIR/run-new-feature.md" ]]; then
  echo "ERROR: Run template not found: $TEMPLATES_DIR/run-new-feature.md" >&2
  echo "  Run /aid-init in the project to deploy templates." >&2
  exit 1
fi

echo "=== test-json-to-run.sh ==="
echo "Script: $SCRIPT_UNDER_TEST"
echo "Fixtures: $FIXTURES_DIR"
echo "Templates: $TEMPLATES_DIR"

PLAN_JSON="$FIXTURES_DIR/minimal-plan.json"
EPIC_FILE="$FIXTURES_DIR/E-TEST-001-1_1-minimal-test-plan.md"
RUN_TEMPLATE="$TEMPLATES_DIR/run-new-feature.md"

# ===========================================================================
# TEST 1: Missing --plan-json flag returns exit code 1
# ===========================================================================
run_test "Missing --plan-json flag returns exit code 1"

out_dir="$(make_output_dir "t01")"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --run-template "$RUN_TEMPLATE" \
  --epic "$EPIC_FILE" \
  --output-dir "$out_dir" \
  --run-id "R-TEST-001" \
  >/dev/null 2>&1 || actual_exit=$?

if [[ "$actual_exit" -eq 1 ]]; then
  pass "missing --plan-json exits with code 1"
else
  fail "missing --plan-json exits with code 1" "got exit code $actual_exit, expected 1"
fi

# ===========================================================================
# TEST 2: Valid plan.json produces run.md
# ===========================================================================
run_test "Valid plan.json produces run.md file"

out_dir="$(make_output_dir "t02")"

actual_exit=0
run_path="$("$SCRIPT_UNDER_TEST" \
  --plan-json "$PLAN_JSON" \
  --run-template "$RUN_TEMPLATE" \
  --epic "$EPIC_FILE" \
  --output-dir "$out_dir" \
  --run-id "R-TEST-001" \
  2>/dev/null)" || actual_exit=$?

if [[ "$actual_exit" -ne 0 ]]; then
  fail "valid plan.json exits with code 0" "got exit code $actual_exit"
elif [[ -z "$run_path" ]]; then
  fail "script prints run.md path to stdout" "stdout was empty"
elif [[ ! -f "$run_path" ]]; then
  fail "run.md exists at printed path" "file not found: $run_path"
else
  pass "valid plan.json produces run.md at path: $(basename "$run_path")"
fi

# Store for subsequent tests
RUN_PATH="${run_path:-}"

# ===========================================================================
# TEST 3: run.md contains all required phase sections
# ===========================================================================
run_test "Generated run.md contains Phase sections for each step in plan.json"

if [[ -n "$RUN_PATH" && -f "$RUN_PATH" ]]; then
  # The minimal plan.json has 2 steps, so run.md should contain Phase 1 and Phase 2
  missing_phases=""
  grep -q "### Phase 1:" "$RUN_PATH" 2>/dev/null || missing_phases="${missing_phases} Phase1"
  grep -q "### Phase 2:" "$RUN_PATH" 2>/dev/null || missing_phases="${missing_phases} Phase2"

  if [[ -z "$missing_phases" ]]; then
    pass "run.md contains Phase 1 and Phase 2 sections"
  else
    fail "run.md contains all phase sections" "missing sections:$missing_phases"
  fi
else
  fail "phase sections check" "skipped — run.md not available from TEST 2"
fi

# ===========================================================================
# TEST 4: run.md contains valid frontmatter with required fields
# ===========================================================================
run_test "Generated run.md frontmatter has id, epic_id, orchestrated=true"

if [[ -n "$RUN_PATH" && -f "$RUN_PATH" ]]; then
  frontmatter="$(awk 'BEGIN{f=0} /^---/{f++; if(f==2) exit; next} f==1{print}' "$RUN_PATH")"

  missing_fm=""
  echo "$frontmatter" | grep -q "^id:" || missing_fm="${missing_fm} id"
  echo "$frontmatter" | grep -q "^epic_id:" || missing_fm="${missing_fm} epic_id"
  echo "$frontmatter" | grep -q "^orchestrated:" || missing_fm="${missing_fm} orchestrated"

  if [[ -z "$missing_fm" ]]; then
    # Verify orchestrated is set to true
    orchestrated="$(echo "$frontmatter" | awk -F: '/^orchestrated:/{print $2}' | sed 's/ //g')"
    if [[ "$orchestrated" == "true" ]]; then
      pass "run.md frontmatter has id, epic_id, orchestrated: true"
    else
      fail "run.md orchestrated field is true" "got: '$orchestrated'"
    fi
  else
    fail "run.md frontmatter has required fields" "missing:$missing_fm"
  fi
else
  fail "run.md frontmatter check" "skipped — run.md not available from TEST 2"
fi

# ===========================================================================
# TEST 5: run.md contains Phases and Dependencies sections
# ===========================================================================
run_test "Generated run.md contains top-level sections: Phases, Dependencies, Quality Gates"

if [[ -n "$RUN_PATH" && -f "$RUN_PATH" ]]; then
  missing_sections=""
  grep -q "^## Phases" "$RUN_PATH" 2>/dev/null || missing_sections="${missing_sections} Phases"
  grep -q "^## Dependencies" "$RUN_PATH" 2>/dev/null || missing_sections="${missing_sections} Dependencies"
  grep -q "^## Quality Gates" "$RUN_PATH" 2>/dev/null || missing_sections="${missing_sections} 'Quality Gates'"

  if [[ -z "$missing_sections" ]]; then
    pass "run.md contains required top-level sections"
  else
    fail "run.md contains required sections" "missing:$missing_sections"
  fi
else
  fail "run.md section check" "skipped — run.md not available from TEST 2"
fi

# ===========================================================================
# TEST 6: Invalid JSON in plan.json returns non-zero exit code
# ===========================================================================
run_test "Invalid JSON in plan.json causes non-zero exit"

out_dir="$(make_output_dir "t06")"

# Write a malformed JSON file
bad_json="$TMPDIR_ROOT/bad-plan.json"
printf '{ "epic_id": "E-BAD", "steps": [INVALID' > "$bad_json"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --plan-json "$bad_json" \
  --run-template "$RUN_TEMPLATE" \
  --epic "$EPIC_FILE" \
  --output-dir "$out_dir" \
  --run-id "R-BAD-001" \
  >/dev/null 2>&1 || actual_exit=$?

if [[ "$actual_exit" -ne 0 ]]; then
  pass "invalid JSON in plan.json causes non-zero exit (got code $actual_exit)"
else
  fail "invalid JSON in plan.json causes non-zero exit" "unexpectedly exited with code 0"
fi

# ===========================================================================
# TEST 7: Plan.json with zero steps exits with code 1
# ===========================================================================
run_test "plan.json with zero steps exits with code 1"

out_dir="$(make_output_dir "t07")"

# Write a valid-JSON but empty-steps plan
empty_steps_json="$TMPDIR_ROOT/empty-steps.json"
printf '{"epic_id":"E-EMPTY","version":1,"steps":[],"dependencies":[]}\n' > "$empty_steps_json"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --plan-json "$empty_steps_json" \
  --run-template "$RUN_TEMPLATE" \
  --epic "$EPIC_FILE" \
  --output-dir "$out_dir" \
  --run-id "R-EMPTY-001" \
  >/dev/null 2>&1 || actual_exit=$?

if [[ "$actual_exit" -eq 1 ]]; then
  pass "zero-step plan.json exits with code 1"
else
  fail "zero-step plan.json exits with code 1" "got exit code $actual_exit, expected 1"
fi

# ===========================================================================
# TEST 8: Nonexistent EPIC file returns exit code 3
# ===========================================================================
run_test "Nonexistent EPIC file returns exit code 3"

out_dir="$(make_output_dir "t08")"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --plan-json "$PLAN_JSON" \
  --run-template "$RUN_TEMPLATE" \
  --epic "/nonexistent/EPIC.md" \
  --output-dir "$out_dir" \
  --run-id "R-TEST-NOEPIC" \
  >/dev/null 2>&1 || actual_exit=$?

if [[ "$actual_exit" -eq 3 ]]; then
  pass "nonexistent EPIC file exits with code 3"
else
  fail "nonexistent EPIC file exits with code 3" "got exit code $actual_exit, expected 3"
fi

# ===========================================================================
# TEST 9: run.md run title includes the run-id
# ===========================================================================
run_test "Generated run.md H1 title contains the run ID"

if [[ -n "$RUN_PATH" && -f "$RUN_PATH" ]]; then
  if grep -q "R-TEST-001" "$RUN_PATH" 2>/dev/null; then
    pass "run.md H1 title contains run ID R-TEST-001"
  else
    fail "run.md title contains run ID" "R-TEST-001 not found in run.md"
  fi
else
  fail "run.md title check" "skipped — run.md not available from TEST 2"
fi

# ===========================================================================
# TEST 10: run.md stdout path is absolute
# ===========================================================================
run_test "Script prints an absolute path to stdout"

out_dir="$(make_output_dir "t10")"

actual_exit=0
printed_path="$("$SCRIPT_UNDER_TEST" \
  --plan-json "$PLAN_JSON" \
  --run-template "$RUN_TEMPLATE" \
  --epic "$EPIC_FILE" \
  --output-dir "$out_dir" \
  --run-id "R-ABSPATH-001" \
  2>/dev/null)" || actual_exit=$?

if [[ "$actual_exit" -ne 0 ]]; then
  fail "absolute path test exits with code 0" "got exit code $actual_exit"
elif [[ "${printed_path:0:1}" != "/" ]]; then
  fail "printed path is absolute" "got relative path: $printed_path"
else
  pass "stdout path is absolute: $printed_path"
fi

# ===========================================================================
# TEST 11: --streamlined flag drives streamlined_mode: true END-TO-END
#          (CP3 activation gap guard — exercises the flag THROUGH
#          aid-json-to-run.sh → Step 18 aid-fsm.sh init, NOT a direct
#          aid-fsm.sh init --streamlined call).
# ===========================================================================
run_test "aid-json-to-run.sh --streamlined writes streamlined_mode: true to fsm-state.yaml"

# Helper: read .streamlined_mode from a generated fsm-state.yaml. Prefer yq;
# fall back to grep so the assertion works even without yq installed.
read_streamlined_mode() {
  local sf="$1"
  if command -v yq >/dev/null 2>&1; then
    # NOTE: do NOT use `// "default"` here — mikefarah yq treats a literal
    # `false` value as empty for the `//` operator, so `false // "X"` yields "X".
    # Plain selection returns the literal true/false (or "null" if absent).
    yq -r '.streamlined_mode' "$sf" 2>/dev/null
  else
    grep -E '^streamlined_mode:' "$sf" 2>/dev/null | head -1 \
      | sed -E 's/^streamlined_mode:[[:space:]]*//' | tr -d '"'
  fi
}

out_dir="$(make_output_dir "t11")"
run_id_on="R-STREAMLINED-ON"
fsm_state_on="$WORK_REPO/.aid-o/work/evidence/E-TEST-001-1_1/${run_id_on}/fsm-state.yaml"
rm -f "$fsm_state_on"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --plan-json "$PLAN_JSON" \
  --run-template "$RUN_TEMPLATE" \
  --epic "$EPIC_FILE" \
  --output-dir "$out_dir" \
  --run-id "$run_id_on" \
  --streamlined \
  >/dev/null 2>&1 || actual_exit=$?

# init may auto-checkout task/E-TEST-001-1_1/main; restore main for next test.
git checkout -q main 2>/dev/null || true

if [[ "$actual_exit" -ne 0 ]]; then
  fail "--streamlined run exits with code 0" "got exit code $actual_exit"
elif [[ ! -f "$fsm_state_on" ]]; then
  fail "Step 18 auto-init wrote fsm-state.yaml" "file not found: $fsm_state_on"
else
  sm_on="$(read_streamlined_mode "$fsm_state_on")"
  if [[ "$sm_on" == "true" ]]; then
    pass "--streamlined → fsm-state.yaml streamlined_mode: true"
  else
    fail "--streamlined → streamlined_mode: true" "got: '$sm_on'"
  fi
fi

# ===========================================================================
# TEST 12: NO flag → streamlined_mode: false END-TO-END (full mode default).
# ===========================================================================
run_test "aid-json-to-run.sh without --streamlined writes streamlined_mode: false"

out_dir="$(make_output_dir "t12")"
run_id_off="R-STREAMLINED-OFF"
fsm_state_off="$WORK_REPO/.aid-o/work/evidence/E-TEST-001-1_1/${run_id_off}/fsm-state.yaml"
rm -f "$fsm_state_off"

actual_exit=0
"$SCRIPT_UNDER_TEST" \
  --plan-json "$PLAN_JSON" \
  --run-template "$RUN_TEMPLATE" \
  --epic "$EPIC_FILE" \
  --output-dir "$out_dir" \
  --run-id "$run_id_off" \
  >/dev/null 2>&1 || actual_exit=$?

git checkout -q main 2>/dev/null || true

if [[ "$actual_exit" -ne 0 ]]; then
  fail "full-mode run exits with code 0" "got exit code $actual_exit"
elif [[ ! -f "$fsm_state_off" ]]; then
  fail "Step 18 auto-init wrote fsm-state.yaml" "file not found: $fsm_state_off"
else
  sm_off="$(read_streamlined_mode "$fsm_state_off")"
  if [[ "$sm_off" == "false" ]]; then
    pass "no flag → fsm-state.yaml streamlined_mode: false"
  else
    fail "no flag → streamlined_mode: false" "got: '$sm_off'"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
[[ "$TESTS_FAILED" -eq 0 ]] && exit 0 || exit 1
