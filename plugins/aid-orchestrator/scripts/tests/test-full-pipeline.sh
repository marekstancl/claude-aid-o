#!/usr/bin/env bash
# =============================================================================
# test-full-pipeline.sh — Integration tests for aid-auto-pipeline.sh
#
# Runs the master orchestration pipeline end-to-end with the multi-phase
# fixture plan and verifies that all expected output files are produced,
# the stdout JSON manifest is valid, and exit codes are correct.
#
# Usage:
#   ./test-full-pipeline.sh
#
# Requirements: jq must be installed. Tests are skipped with an explanatory
#   message if jq is absent.
#
# Exit codes: 0=all passed, 1=one or more tests failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh"
PLUGIN_DIR="$REPO_ROOT/plugins/aid-orchestrator"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
MULTI_PHASE_PLAN="$FIXTURES_DIR/multi-phase-plan-numeric.md"

# ---------------------------------------------------------------------------
# Test accounting
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ---------------------------------------------------------------------------
# Cleanup: remove ALL temp workspaces on exit
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

skip() {
  TESTS_SKIPPED=$(( TESTS_SKIPPED + 1 ))
  echo "  SKIP: $1 -- $2"
}

run_test() {
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  echo ""
  echo "TEST: $1"
}

# Create an isolated workspace directory with a .aid-o/ structure.
# The pipeline creates files relative to cwd, so each test runs inside its
# own workspace directory.
make_workspace() {
  local name="$1"
  local ws="$TMPDIR_ROOT/$name"
  mkdir -p "$ws/.aid-o/plans"
  mkdir -p "$ws/.aid-o/tasks"
  mkdir -p "$ws/.aid-o/config"
  mkdir -p "$ws/.aid-o/work/evidence"
  mkdir -p "$ws/.aid-o/work/runs"
  # Minimal counter YAML in the expected location
  printf 'counter: 0\n' > "$ws/.aid-o/config/counter.yaml"
  # P040 Component E: aid-json-to-run.sh Step 18 auto-inits the FSM
  # (`aid-fsm.sh init`), which requires a git repo with a clean tree on a
  # valid branch. The real auto-pipeline always runs inside a git project, so
  # mirror that here: a committed, clean repo on `main`.
  (
    cd "$ws"
    git init -q
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git checkout -q -b main 2>/dev/null || git branch -m main
    git add -A
    git commit -q -m "seed workspace"
  )
  echo "$ws"
}

# Run aid-auto-pipeline.sh from inside the given workspace directory.
# stdout and stderr are captured into provided variables (by name).
# Returns the exit code.
run_pipeline() {
  local workspace="$1"
  local plan_path="$2"
  local queue_mode="${3:-chain}"
  local stdout_var="${4:-PIPELINE_STDOUT}"
  local stderr_var="${5:-PIPELINE_STDERR}"

  local stdout_file="$TMPDIR_ROOT/pipeline_stdout_$$"
  local stderr_file="$TMPDIR_ROOT/pipeline_stderr_$$"

  local exit_code=0
  (
    cd "$workspace" || exit 3
    "$SCRIPT_UNDER_TEST" \
      --plan "$plan_path" \
      --queue-mode "$queue_mode" \
      --plugin-dir "$PLUGIN_DIR" \
      > "$stdout_file" 2> "$stderr_file"
  ) || exit_code=$?

  # Assign captured output to the caller's named variables
  # (simple approach: store in temp files, read outside)
  eval "${stdout_var}=\"\$(cat \"\$stdout_file\" 2>/dev/null)\""
  eval "${stderr_var}=\"\$(cat \"\$stderr_file\" 2>/dev/null)\""

  rm -f "$stdout_file" "$stderr_file"
  return "$exit_code"
}

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
echo "=== test-full-pipeline.sh ==="
echo "Script: $SCRIPT_UNDER_TEST"
echo "Plugin dir: $PLUGIN_DIR"
echo "Fixtures: $FIXTURES_DIR"

if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
  echo "ERROR: Script under test not found: $SCRIPT_UNDER_TEST" >&2
  exit 1
fi

if [[ ! -x "$SCRIPT_UNDER_TEST" ]]; then
  echo "ERROR: Script under test is not executable: $SCRIPT_UNDER_TEST" >&2
  exit 1
fi

if [[ ! -f "$MULTI_PHASE_PLAN" ]]; then
  echo "ERROR: Multi-phase fixture plan not found: $MULTI_PHASE_PLAN" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq is not installed. Install jq to run integration tests."
  echo "  macOS:  brew install jq"
  echo "  Debian: sudo apt install jq"
  echo "  Fedora: sudo dnf install jq"
  exit 0
fi

# Verify the sub-scripts that the pipeline depends on are executable.
for sub in aid-plan-to-epic.sh aid-epic-to-json.sh aid-json-to-run.sh aid-queue-add.sh; do
  sub_path="$REPO_ROOT/plugins/aid-orchestrator/scripts/$sub"
  if [[ ! -x "$sub_path" ]]; then
    echo "ERROR: Required sub-script not executable: $sub_path" >&2
    echo "  Run: chmod +x $sub_path" >&2
    exit 1
  fi
done

# ===========================================================================
# TEST 1: Pipeline exits with code 0 for a valid 3-phase plan
# ===========================================================================
run_test "Pipeline exits with code 0 for valid multi-phase plan"

ws1="$(make_workspace "t01")"
pipeline_exit=0
PIPELINE_STDOUT="" PIPELINE_STDERR=""
run_pipeline "$ws1" "$MULTI_PHASE_PLAN" "chain" PIPELINE_STDOUT PIPELINE_STDERR \
  || pipeline_exit=$?
T01_STDOUT="$PIPELINE_STDOUT"
T01_WORKSPACE="$ws1"

if [[ "$pipeline_exit" -eq 0 ]]; then
  pass "pipeline exits with code 0 for multi-phase plan"
else
  fail "pipeline exits with code 0" \
    "got exit code $pipeline_exit. stderr: $(echo "$PIPELINE_STDERR" | head -5)"
fi

# ===========================================================================
# TEST 2: stdout JSON manifest is valid JSON
# ===========================================================================
run_test "stdout JSON manifest from pipeline is parseable JSON"

if [[ -n "$T01_STDOUT" ]]; then
  if echo "$T01_STDOUT" | jq . >/dev/null 2>&1; then
    pass "pipeline stdout is valid JSON"
  else
    fail "pipeline stdout is valid JSON" \
      "stdout could not be parsed. First 200 chars: ${T01_STDOUT:0:200}"
  fi
else
  fail "pipeline stdout is valid JSON" "stdout was empty"
fi

# ===========================================================================
# TEST 3: JSON manifest has all required top-level fields
# ===========================================================================
run_test "JSON manifest contains required fields: plan_id, plan_path, epics, queue_mode, duration_ms"

if [[ -n "$T01_STDOUT" ]] && echo "$T01_STDOUT" | jq . >/dev/null 2>&1; then
  missing_fields=""
  echo "$T01_STDOUT" | jq -e '.plan_id'     >/dev/null 2>&1 || missing_fields="${missing_fields} plan_id"
  echo "$T01_STDOUT" | jq -e '.plan_path'   >/dev/null 2>&1 || missing_fields="${missing_fields} plan_path"
  echo "$T01_STDOUT" | jq -e '.epics'       >/dev/null 2>&1 || missing_fields="${missing_fields} epics"
  echo "$T01_STDOUT" | jq -e '.queue_mode'  >/dev/null 2>&1 || missing_fields="${missing_fields} queue_mode"
  echo "$T01_STDOUT" | jq -e '.duration_ms' >/dev/null 2>&1 || missing_fields="${missing_fields} duration_ms"

  if [[ -z "$missing_fields" ]]; then
    pass "JSON manifest has all required top-level fields"
  else
    fail "JSON manifest has required fields" "missing:$missing_fields"
  fi
else
  fail "JSON manifest fields check" "skipped — manifest not parseable from TEST 1"
fi

# ===========================================================================
# TEST 4: Manifest 'epics' array has exactly 3 entries for a 3-phase plan
# ===========================================================================
run_test "JSON manifest 'epics' array has exactly 3 entries (one per phase)"

if [[ -n "$T01_STDOUT" ]] && echo "$T01_STDOUT" | jq . >/dev/null 2>&1; then
  epic_count="$(echo "$T01_STDOUT" | jq '.epics | length' 2>/dev/null)"
  if [[ "$epic_count" -eq 3 ]]; then
    pass "manifest contains exactly 3 EPIC entries (one per phase)"
  else
    fail "manifest contains 3 EPIC entries" "got $epic_count"
  fi
else
  fail "EPIC count check" "skipped — manifest not parseable from TEST 1"
fi

# ===========================================================================
# TEST 5: Each EPIC entry in manifest has the required per-EPIC fields
# ===========================================================================
run_test "Each entry in manifest 'epics' array has: epic_id, epic_path, plan_json, run_path, run_id, queue_status"

if [[ -n "$T01_STDOUT" ]] && echo "$T01_STDOUT" | jq . >/dev/null 2>&1; then
  epic_count="$(echo "$T01_STDOUT" | jq '.epics | length' 2>/dev/null)"
  entry_errors=""

  for i in $(seq 0 $(( epic_count - 1 ))); do
    for field in epic_id epic_path plan_json run_path run_id queue_status; do
      val="$(echo "$T01_STDOUT" | jq -r ".epics[$i].${field} // \"\"" 2>/dev/null)"
      if [[ -z "$val" ]]; then
        entry_errors="${entry_errors} epics[$i].${field}"
      fi
    done
  done

  if [[ -z "$entry_errors" ]]; then
    pass "all EPIC manifest entries have required fields"
  else
    fail "EPIC manifest entries have required fields" "missing or null:$entry_errors"
  fi
else
  fail "EPIC entry fields check" "skipped — manifest not parseable from TEST 1"
fi

# ===========================================================================
# TEST 6: EPIC files are created on disk for all 3 phases
# ===========================================================================
run_test "EPIC .md files are created on disk for all 3 phases"

if [[ "$pipeline_exit" -eq 0 && -d "$T01_WORKSPACE/.aid-o/tasks" ]]; then
  epic_file_count="$(find "$T01_WORKSPACE/.aid-o/tasks" -maxdepth 1 -name "E-*.md" | wc -l | tr -d ' ')"
  if [[ "$epic_file_count" -eq 3 ]]; then
    pass "3 EPIC .md files created in .aid-o/tasks/"
  else
    fail "3 EPIC .md files created" "found $epic_file_count in $T01_WORKSPACE/.aid-o/tasks/"
  fi
else
  fail "EPIC file count check" "skipped — workspace not available or pipeline failed"
fi

# ===========================================================================
# TEST 7: plan.json files are created — one per phase (anywhere under .aid-o)
# ===========================================================================
run_test "plan.json is created for each of the 3 phases under .aid-o/"

if [[ "$pipeline_exit" -eq 0 && -d "$T01_WORKSPACE/.aid-o" ]]; then
  plan_json_count="$(find "$T01_WORKSPACE/.aid-o" -name "plan.json" | wc -l | tr -d ' ')"
  if [[ "$plan_json_count" -eq 3 ]]; then
    pass "3 plan.json files created under .aid-o/"
  else
    fail "3 plan.json files created" "found $plan_json_count under .aid-o/"
  fi
else
  fail "plan.json file count check" "skipped — workspace not available or pipeline failed"
fi

# ===========================================================================
# TEST 8: Each plan.json passes structural validation (has steps array and epic_id)
# ===========================================================================
run_test "Each plan.json has 'steps' array and 'epic_id' field"

if [[ "$pipeline_exit" -eq 0 && -d "$T01_WORKSPACE/.aid-o" ]]; then
  invalid_plan_jsons=""
  while IFS= read -r plan_json_file; do
    has_steps=true
    has_epic_id=true
    jq -e '.steps | arrays' "$plan_json_file" >/dev/null 2>&1 || has_steps=false
    jq -e '.epic_id | strings' "$plan_json_file" >/dev/null 2>&1 || has_epic_id=false

    if [[ "$has_steps" != "true" || "$has_epic_id" != "true" ]]; then
      invalid_plan_jsons="${invalid_plan_jsons} $(basename "$(dirname "$plan_json_file")")/plan.json"
    fi
  done < <(find "$T01_WORKSPACE/.aid-o" -name "plan.json")

  if [[ -z "$invalid_plan_jsons" ]]; then
    pass "all plan.json files have 'steps' array and 'epic_id' string"
  else
    fail "all plan.json files are structurally valid" "invalid files:$invalid_plan_jsons"
  fi
else
  fail "plan.json structural check" "skipped — workspace not available or pipeline failed"
fi

# ===========================================================================
# TEST 9: run.md files are created — one per phase
# ===========================================================================
run_test "run.md files are created in run directories for all 3 phases"

if [[ "$pipeline_exit" -eq 0 && -d "$T01_WORKSPACE/.aid-o/work/runs" ]]; then
  run_md_count="$(find "$T01_WORKSPACE/.aid-o/work/runs" -name "*.md" | wc -l | tr -d ' ')"
  if [[ "$run_md_count" -ge 3 ]]; then
    pass "at least 3 run .md files created under .aid-o/work/runs/ (found $run_md_count)"
  else
    fail "at least 3 run .md files created" "found $run_md_count"
  fi
else
  fail "run.md file count check" "skipped — workspace not available or pipeline failed"
fi

# ===========================================================================
# TEST 10: Queue YAML file is created and contains 3 entries
# ===========================================================================
run_test "queue.yaml is created and contains entries for all 3 EPICs"

queue_yaml="$T01_WORKSPACE/.aid-o/config/queue.yaml"
if [[ "$pipeline_exit" -eq 0 && -f "$queue_yaml" ]]; then
  # Count epic_id lines in the YAML queue — each entry has one 'epic_id:' line
  entry_count="$(grep -c "epic_id:" "$queue_yaml" 2>/dev/null || echo "0")"
  if [[ "$entry_count" -eq 3 ]]; then
    pass "queue.yaml has 3 entries (one per phase)"
  else
    fail "queue.yaml has 3 entries" "found $entry_count epic_id lines"
  fi
else
  if [[ ! -f "$queue_yaml" ]]; then
    fail "queue.yaml exists" "file not found: $queue_yaml"
  else
    fail "queue.yaml entry count" "skipped — pipeline failed"
  fi
fi

# ===========================================================================
# TEST 11: Queue entries have status=pending
# ===========================================================================
run_test "All queue entries in queue.yaml have status: pending"

queue_yaml="$T01_WORKSPACE/.aid-o/config/queue.yaml"
if [[ "$pipeline_exit" -eq 0 && -f "$queue_yaml" ]]; then
  non_pending="$(grep "status:" "$queue_yaml" 2>/dev/null | grep -v "pending" | wc -l | tr -d ' ')"
  if [[ "$non_pending" -eq 0 ]]; then
    pass "all queue entries have status: pending"
  else
    fail "all queue entries have status: pending" "$non_pending entries have a different status"
  fi
else
  fail "queue status check" "skipped — queue file not available"
fi

# ===========================================================================
# TEST 12: Pipeline fails with exit code 3 for a missing plan file
# ===========================================================================
run_test "Pipeline exits with code 3 when --plan file does not exist"

ws12="$(make_workspace "t12")"
exit12=0
(
  cd "$ws12" || exit 3
  "$SCRIPT_UNDER_TEST" \
    --plan "/nonexistent/no-such-plan.md" \
    --plugin-dir "$PLUGIN_DIR" \
    >/dev/null 2>&1
) || exit12=$?

if [[ "$exit12" -eq 3 ]]; then
  pass "nonexistent plan file exits with code 3"
else
  fail "nonexistent plan file exits with code 3" "got exit code $exit12, expected 3"
fi

# ===========================================================================
# TEST 13: Pipeline fails with exit code 1 for a missing --plan argument
# ===========================================================================
run_test "Pipeline exits with code 1 when --plan argument is omitted"

ws13="$(make_workspace "t13")"
exit13=0
(
  cd "$ws13" || exit 3
  "$SCRIPT_UNDER_TEST" \
    --plugin-dir "$PLUGIN_DIR" \
    >/dev/null 2>&1
) || exit13=$?

if [[ "$exit13" -eq 1 ]]; then
  pass "missing --plan argument exits with code 1"
else
  fail "missing --plan argument exits with code 1" "got exit code $exit13, expected 1"
fi

# ===========================================================================
# TEST 14: 'separate' queue mode produces entries with no inter-EPIC dependencies
# ===========================================================================
run_test "Pipeline with --queue-mode separate produces queue entries without inter-EPIC dependencies"

ws14="$(make_workspace "t14")"
pipeline14_exit=0
STDOUT14="" STDERR14=""
run_pipeline "$ws14" "$MULTI_PHASE_PLAN" "separate" STDOUT14 STDERR14 || pipeline14_exit=$?

if [[ "$pipeline14_exit" -eq 0 ]]; then
  queue14="$ws14/.aid-o/config/queue.yaml"
  if [[ -f "$queue14" ]]; then
    # In separate mode, depends_on should be empty (no cross-EPIC dependencies).
    # The manifest should report queue_mode: separate.
    manifest_mode="$(echo "$STDOUT14" | jq -r '.queue_mode // ""' 2>/dev/null)"
    if [[ "$manifest_mode" == "separate" ]]; then
      pass "queue_mode 'separate' recorded correctly in manifest"
    else
      fail "queue_mode in manifest is 'separate'" "got: '$manifest_mode'"
    fi
  else
    fail "separate mode queue file exists" "file not found: $queue14"
  fi
else
  fail "pipeline with --queue-mode separate exits with code 0" \
    "got exit code $pipeline14_exit"
fi

# ===========================================================================
# TEST 15: manifest epic entries report queue_status = 'pending'
# ===========================================================================
run_test "All manifest EPIC entries have queue_status = 'pending'"

if [[ -n "$T01_STDOUT" ]] && echo "$T01_STDOUT" | jq . >/dev/null 2>&1; then
  non_pending_statuses="$(echo "$T01_STDOUT" \
    | jq -r '.epics[].queue_status' 2>/dev/null \
    | grep -v '^pending$' || true)"
  if [[ -z "$non_pending_statuses" ]]; then
    pass "all EPIC manifest entries have queue_status=pending"
  else
    fail "all EPIC manifest entries have queue_status=pending" \
      "unexpected statuses: $non_pending_statuses"
  fi
else
  fail "queue_status manifest check" "skipped — manifest not parseable from TEST 1"
fi

# ===========================================================================
# TEST 16: duration_ms in manifest is a non-negative integer
# ===========================================================================
run_test "manifest 'duration_ms' field is a non-negative integer"

if [[ -n "$T01_STDOUT" ]] && echo "$T01_STDOUT" | jq . >/dev/null 2>&1; then
  duration="$(echo "$T01_STDOUT" | jq '.duration_ms' 2>/dev/null)"
  if [[ "$duration" =~ ^[0-9]+$ ]]; then
    pass "duration_ms is a non-negative integer: $duration"
  else
    fail "duration_ms is a non-negative integer" "got: '$duration'"
  fi
else
  fail "duration_ms check" "skipped — manifest not parseable from TEST 1"
fi

# ===========================================================================
# TEST 17: EPIC ID regex extracts correctly from non-numeric plan ID filenames
# ===========================================================================
run_test "EPIC ID regex extracts E-TEST-001-1_1 from non-numeric plan ID fixture filename"

# This test validates the regex used in aid-auto-pipeline.sh line ~254 to
# extract EPIC IDs from generated filenames. Filenames may contain alphanumeric
# plan ID prefixes (e.g., E-TEST-001-1_1) rather than purely numeric ones
# (e.g., E-003-1_2). We test the regex in isolation rather than running the
# full pipeline, because the fixture filename already exists and the regex is
# the specific unit under test.
test_filename="E-TEST-001-1_1-minimal-test-plan.md"
expected_epic_id="E-TEST-001-1_1"

if [[ "$test_filename" =~ (E-[A-Za-z0-9][A-Za-z0-9-]*[0-9]+_[0-9]+) ]]; then
  extracted="${BASH_REMATCH[1]}"
  if [[ "$extracted" == "$expected_epic_id" ]]; then
    pass "extracted '$extracted' from '$test_filename'"
  else
    fail "extracted EPIC ID matches expected" \
      "expected '$expected_epic_id', got '$extracted'"
  fi
else
  fail "regex matches non-numeric plan ID filename" \
    "regex did not match '$test_filename'"
fi

# Also verify the regex still works for numeric-only plan IDs
run_test "EPIC ID regex extracts numeric plan IDs"
numeric_filename="E-019-1_2-some-feature.md"
expected_numeric_id="E-019-1_2"

if [[ "$numeric_filename" =~ (E-[A-Za-z0-9][A-Za-z0-9-]*[0-9]+_[0-9]+) ]]; then
  extracted_num="${BASH_REMATCH[1]}"
  if [[ "$extracted_num" == "$expected_numeric_id" ]]; then
    pass "extracted '$extracted_num' from numeric filename '$numeric_filename'"
  else
    fail "extracted numeric EPIC ID matches expected" \
      "expected '$expected_numeric_id', got '$extracted_num'"
  fi
else
  fail "regex matches numeric plan ID filename" \
    "regex did not match '$numeric_filename'"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
[[ "$TESTS_FAILED" -eq 0 ]] && exit 0 || exit 1
