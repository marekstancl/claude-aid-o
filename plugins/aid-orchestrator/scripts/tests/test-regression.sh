#!/usr/bin/env bash
# =============================================================================
# test-regression.sh — Structural equivalence tests for aid-auto-pipeline.sh
#
# Verifies that pipeline output STRUCTURE matches expected format. Tests do
# not compare exact content (which changes with timestamps, IDs, and filenames)
# but verify that required structural elements are present in the correct form.
#
# Structural checks cover:
#   - EPIC files:       frontmatter, Goal, Scope, Steps sections
#   - plan.json:        epic_id, steps array, dependencies array, parallel_groups
#   - run.md:           frontmatter, Phase sections
#   - queue.yaml:  epic_id, status, priority fields
#
# Usage:
#   ./test-regression.sh
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

skip() {
  TESTS_SKIPPED=$(( TESTS_SKIPPED + 1 ))
  echo "  SKIP: $1 -- $2"
}

run_test() {
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  echo ""
  echo "TEST: $1"
}

# Create an isolated workspace with the .aid-o/ directory tree.
make_workspace() {
  local name="$1"
  local ws="$TMPDIR_ROOT/$name"
  mkdir -p "$ws/.aid-o/plans"
  mkdir -p "$ws/.aid-o/tasks"
  mkdir -p "$ws/.aid-o/config"
  mkdir -p "$ws/.aid-o/work/evidence"
  mkdir -p "$ws/.aid-o/work/runs"
  printf 'counter: 0\n' > "$ws/.aid-o/config/counter.yaml"
  echo "$ws"
}

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
echo "=== test-regression.sh ==="
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
  echo "SKIP: jq is not installed. Install jq to run regression tests."
  echo "  macOS:  brew install jq"
  echo "  Debian: sudo apt install jq"
  echo "  Fedora: sudo dnf install jq"
  exit 0
fi

# ---------------------------------------------------------------------------
# Run the pipeline once into a shared workspace for all structural tests.
# All structural checks reference this single workspace, ensuring tests are
# fast and the output is from exactly one pipeline execution.
# ---------------------------------------------------------------------------
echo ""
echo "Running pipeline to produce output for structural analysis..."

SHARED_WS="$(make_workspace "shared")"
SHARED_STDOUT=""
SHARED_EXIT=0

stdout_file="$TMPDIR_ROOT/shared_stdout"
stderr_file="$TMPDIR_ROOT/shared_stderr"

(
  cd "$SHARED_WS" || exit 3
  "$SCRIPT_UNDER_TEST" \
    --plan "$MULTI_PHASE_PLAN" \
    --queue-mode "chain" \
    --plugin-dir "$PLUGIN_DIR" \
    > "$stdout_file" 2> "$stderr_file"
) || SHARED_EXIT=$?

SHARED_STDOUT="$(cat "$stdout_file" 2>/dev/null || true)"
SHARED_STDERR="$(cat "$stderr_file" 2>/dev/null || true)"
rm -f "$stdout_file" "$stderr_file"

if [[ "$SHARED_EXIT" -ne 0 ]]; then
  echo ""
  echo "ERROR: Pipeline failed with exit code $SHARED_EXIT — cannot run structural tests."
  echo "  stderr: $SHARED_STDERR"
  echo ""
  echo "Results: 0/$TESTS_RUN passed, 0 failed, all structural tests skipped (pipeline failed)"
  exit 1
fi

echo "  Pipeline completed (exit 0). Workspace: $SHARED_WS"
echo "  Manifest: $(echo "$SHARED_STDOUT" | jq -r '"\(.plan_id) — \(.epics | length) epic(s)"' 2>/dev/null || echo "(parse failed)")"

# ===========================================================================
# STRUCTURAL SUITE A: EPIC file structure
#
# Verify that every generated EPIC .md file contains the required sections
# and frontmatter fields. These checks are structural — they match on header
# names and frontmatter keys, not on the actual content values.
# ===========================================================================

echo ""
echo "--- Suite A: EPIC file structure ---"

# ===========================================================================
# TEST A1: Every EPIC file has YAML frontmatter (delimited by ---)
# ===========================================================================
run_test "A1: Each generated EPIC file has YAML frontmatter (--- delimiters)"

epic_dir="$SHARED_WS/.aid-o/tasks"
if [[ -d "$epic_dir" ]]; then
  missing_frontmatter=""
  while IFS= read -r epic_file; do
    # Frontmatter check: first line must be ---, and a closing --- must exist
    first_line="$(head -1 "$epic_file" 2>/dev/null)"
    second_dash_count="$(awk '/^---/{count++; if(count==2) exit} END{print count+0}' "$epic_file" 2>/dev/null)"

    if [[ "$first_line" != "---" || "$second_dash_count" -lt 2 ]]; then
      missing_frontmatter="${missing_frontmatter} $(basename "$epic_file")"
    fi
  done < <(find "$epic_dir" -maxdepth 1 -name "E-*.md" 2>/dev/null)

  if [[ -z "$missing_frontmatter" ]]; then
    pass "A1: all EPIC files have YAML frontmatter delimited by ---"
  else
    fail "A1: all EPIC files have YAML frontmatter" "missing in:$missing_frontmatter"
  fi
else
  fail "A1: EPIC directory exists" "not found: $epic_dir"
fi

# ===========================================================================
# TEST A2: Every EPIC frontmatter contains the required keys
# ===========================================================================
run_test "A2: Each EPIC frontmatter contains: status, plan_ref, plan_epics_total"

if [[ -d "$epic_dir" ]]; then
  missing_fields_report=""
  while IFS= read -r epic_file; do
    frontmatter="$(awk 'BEGIN{f=0} /^---/{f++; if(f==2) exit; next} f==1{print}' "$epic_file" 2>/dev/null)"
    missing=""
    echo "$frontmatter" | grep -q "^status:"           || missing="${missing} status"
    echo "$frontmatter" | grep -q "^plan_ref:"         || missing="${missing} plan_ref"
    echo "$frontmatter" | grep -q "^plan_epics_total:" || missing="${missing} plan_epics_total"

    if [[ -n "$missing" ]]; then
      missing_fields_report="${missing_fields_report} [$(basename "$epic_file"):$missing]"
    fi
  done < <(find "$epic_dir" -maxdepth 1 -name "E-*.md" 2>/dev/null)

  if [[ -z "$missing_fields_report" ]]; then
    pass "A2: all EPIC frontmatter sections have required keys"
  else
    fail "A2: EPIC frontmatter required keys" "issues:$missing_fields_report"
  fi
else
  fail "A2: EPIC frontmatter key check" "epic dir not found"
fi

# ===========================================================================
# TEST A3: Every EPIC file contains Goal, Scope, and Steps sections
# ===========================================================================
run_test "A3: Each EPIC file has ## Goal, ## Scope, and ## Steps (Role Pipeline) sections"

if [[ -d "$epic_dir" ]]; then
  section_errors=""
  while IFS= read -r epic_file; do
    missing_sections=""
    grep -q "^## Goal"                   "$epic_file" 2>/dev/null || missing_sections="${missing_sections} Goal"
    grep -q "^## Scope"                  "$epic_file" 2>/dev/null || missing_sections="${missing_sections} Scope"
    grep -q "^## Steps (Role Pipeline)"  "$epic_file" 2>/dev/null || missing_sections="${missing_sections} 'Steps (Role Pipeline)'"

    if [[ -n "$missing_sections" ]]; then
      section_errors="${section_errors} [$(basename "$epic_file"):$missing_sections]"
    fi
  done < <(find "$epic_dir" -maxdepth 1 -name "E-*.md" 2>/dev/null)

  if [[ -z "$section_errors" ]]; then
    pass "A3: all EPIC files have Goal, Scope, and Steps (Role Pipeline) sections"
  else
    fail "A3: EPIC required sections" "issues:$section_errors"
  fi
else
  fail "A3: EPIC section check" "epic dir not found"
fi

# ===========================================================================
# TEST A4: EPIC Steps section contains a markdown table (| delimiters)
# ===========================================================================
run_test "A4: Each EPIC Steps (Role Pipeline) section contains a markdown table"

if [[ -d "$epic_dir" ]]; then
  no_table_epics=""
  while IFS= read -r epic_file; do
    # After '## Steps (Role Pipeline)' there should be a table row starting with '|'
    has_table="$(awk '
      BEGIN { in_steps = 0; found = 0 }
      /^## Steps \(Role Pipeline\)/ { in_steps = 1; next }
      in_steps && /^##[^#]/ { exit }
      in_steps && /^\|/ { found = 1; exit }
      END { print found }
    ' "$epic_file" 2>/dev/null)"

    if [[ "$has_table" != "1" ]]; then
      no_table_epics="${no_table_epics} $(basename "$epic_file")"
    fi
  done < <(find "$epic_dir" -maxdepth 1 -name "E-*.md" 2>/dev/null)

  if [[ -z "$no_table_epics" ]]; then
    pass "A4: all EPIC Steps sections contain a markdown table"
  else
    fail "A4: EPIC Steps table" "no table found in:$no_table_epics"
  fi
else
  fail "A4: EPIC Steps table check" "epic dir not found"
fi

# ===========================================================================
# STRUCTURAL SUITE B: plan.json structure
#
# Verify that every plan.json produced by the pipeline conforms to the
# required JSON schema structure, without checking specific values.
# ===========================================================================

echo ""
echo "--- Suite B: plan.json structure ---"

RUNS_DIR="$SHARED_WS/.aid-o/work/runs"
# plan.json files are written to the evidence/ tree
EVIDENCE_DIR="$SHARED_WS/.aid-o/work/evidence"

# ===========================================================================
# TEST B1: Each plan.json has all required top-level JSON fields
# ===========================================================================
run_test "B1: Each plan.json has: epic_id (string), version (number), steps (array), dependencies (array), parallel_groups (array)"

plan_json_search_dir="$SHARED_WS/.aid-o"
plan_json_files="$(find "$plan_json_search_dir" -name "plan.json" 2>/dev/null)"
if [[ -n "$plan_json_files" ]]; then
  field_errors=""
  while IFS= read -r plan_json; do
    run_label="$(basename "$(dirname "$plan_json")")"
    missing=""
    jq -e '.epic_id | strings'          "$plan_json" >/dev/null 2>&1 || missing="${missing} epic_id"
    jq -e '.version | numbers'          "$plan_json" >/dev/null 2>&1 || missing="${missing} version"
    jq -e '.steps | arrays'             "$plan_json" >/dev/null 2>&1 || missing="${missing} steps"
    jq -e '.dependencies | arrays'      "$plan_json" >/dev/null 2>&1 || missing="${missing} dependencies"
    jq -e '.parallel_groups | arrays'   "$plan_json" >/dev/null 2>&1 || missing="${missing} parallel_groups"

    if [[ -n "$missing" ]]; then
      field_errors="${field_errors} [$run_label:$missing]"
    fi
  done <<< "$plan_json_files"

  if [[ -z "$field_errors" ]]; then
    pass "B1: all plan.json files have required top-level fields with correct types"
  else
    fail "B1: plan.json required fields" "issues:$field_errors"
  fi
else
  fail "B1: plan.json field check" "no plan.json files found under $plan_json_search_dir"
fi

# ===========================================================================
# TEST B2: Each step in plan.json has the required per-step fields
# ===========================================================================
run_test "B2: Each step object in plan.json has: id, role, objective, inputs, outputs, acceptance_criteria"

if [[ -n "$plan_json_files" ]]; then
  step_errors=""
  while IFS= read -r plan_json; do
    run_label="$(basename "$(dirname "$plan_json")")"
    step_count="$(jq '.steps | length' "$plan_json" 2>/dev/null)"

    for i in $(seq 0 $(( step_count - 1 ))); do
      missing=""
      jq -e ".steps[$i].id | strings"                    "$plan_json" >/dev/null 2>&1 || missing="${missing} id"
      jq -e ".steps[$i].role | strings"                  "$plan_json" >/dev/null 2>&1 || missing="${missing} role"
      jq -e ".steps[$i].objective | strings"             "$plan_json" >/dev/null 2>&1 || missing="${missing} objective"
      jq -e ".steps[$i].inputs | arrays"                 "$plan_json" >/dev/null 2>&1 || missing="${missing} inputs"
      jq -e ".steps[$i].outputs | arrays"                "$plan_json" >/dev/null 2>&1 || missing="${missing} outputs"
      jq -e ".steps[$i].acceptance_criteria | arrays"    "$plan_json" >/dev/null 2>&1 || missing="${missing} acceptance_criteria"

      if [[ -n "$missing" ]]; then
        step_errors="${step_errors} [$run_label/steps[$i]:$missing]"
      fi
    done
  done <<< "$plan_json_files"

  if [[ -z "$step_errors" ]]; then
    pass "B2: all step objects in plan.json files have required per-step fields"
  else
    fail "B2: plan.json step fields" "issues:$step_errors"
  fi
else
  fail "B2: plan.json step field check" "no plan.json files found"
fi

# ===========================================================================
# TEST B3: Step IDs follow the required naming pattern (step_N_role or step_N...)
# ===========================================================================
run_test "B3: All step IDs in plan.json files match the pattern step_[a-z0-9_]+"

if [[ -n "$plan_json_files" ]]; then
  bad_ids=""
  while IFS= read -r plan_json; do
    run_label="$(basename "$(dirname "$plan_json")")"
    invalid="$(jq -r '.steps[].id' "$plan_json" 2>/dev/null \
      | grep -Ev '^step_[a-z0-9_]+$' || true)"
    if [[ -n "$invalid" ]]; then
      bad_ids="${bad_ids} [$run_label: $invalid]"
    fi
  done <<< "$plan_json_files"

  if [[ -z "$bad_ids" ]]; then
    pass "B3: all step IDs match pattern step_[a-z0-9_]+"
  else
    fail "B3: step ID naming pattern" "non-conforming IDs:$bad_ids"
  fi
else
  fail "B3: step ID pattern check" "no plan.json files found"
fi

# ===========================================================================
# TEST B4: Each dependency object in plan.json has before and after fields
# ===========================================================================
run_test "B4: Each dependency object in plan.json has 'before' and 'after' string fields"

if [[ -n "$plan_json_files" ]]; then
  dep_errors=""
  while IFS= read -r plan_json; do
    run_label="$(basename "$(dirname "$plan_json")")"
    dep_count="$(jq '.dependencies | length' "$plan_json" 2>/dev/null)"

    for i in $(seq 0 $(( dep_count - 1 ))); do
      missing=""
      jq -e ".dependencies[$i].before | strings" "$plan_json" >/dev/null 2>&1 || missing="${missing} before"
      jq -e ".dependencies[$i].after | strings"  "$plan_json" >/dev/null 2>&1 || missing="${missing} after"
      if [[ -n "$missing" ]]; then
        dep_errors="${dep_errors} [$run_label/deps[$i]:$missing]"
      fi
    done
  done <<< "$plan_json_files"

  if [[ -z "$dep_errors" ]]; then
    pass "B4: all dependency objects in plan.json have 'before' and 'after' string fields"
  else
    fail "B4: dependency object fields" "issues:$dep_errors"
  fi
else
  fail "B4: dependency field check" "no plan.json files found"
fi

# ===========================================================================
# STRUCTURAL SUITE C: run.md structure
#
# Verify that every run.md file has the correct frontmatter keys and
# the required markdown section structure.
# ===========================================================================

echo ""
echo "--- Suite C: run.md structure ---"

# ===========================================================================
# TEST C1: Each run.md file has YAML frontmatter with required keys
# ===========================================================================
run_test "C1: Each run.md has frontmatter with: id, epic_id, orchestrated: true"

if [[ -d "$RUNS_DIR" ]]; then
  fm_errors=""
  while IFS= read -r run_md; do
    run_label="$(basename "$(dirname "$run_md")")"
    first_line="$(head -1 "$run_md" 2>/dev/null)"
    if [[ "$first_line" != "---" ]]; then
      fm_errors="${fm_errors} [$run_label: no frontmatter]"
      continue
    fi

    frontmatter="$(awk 'BEGIN{f=0} /^---/{f++; if(f==2) exit; next} f==1{print}' "$run_md" 2>/dev/null)"
    missing=""
    echo "$frontmatter" | grep -q "^id:"          || missing="${missing} id"
    echo "$frontmatter" | grep -q "^epic_id:"     || missing="${missing} epic_id"
    echo "$frontmatter" | grep -q "^orchestrated:" || missing="${missing} orchestrated"

    # Verify orchestrated is true (not just present)
    if [[ -z "$missing" ]]; then
      orch_val="$(echo "$frontmatter" | awk -F': ' '/^orchestrated:/{print $2}' | tr -d ' ')"
      [[ "$orch_val" == "true" ]] || missing="${missing} orchestrated=true"
    fi

    if [[ -n "$missing" ]]; then
      fm_errors="${fm_errors} [$run_label:$missing]"
    fi
  done < <(find "$RUNS_DIR" -name "*.md" 2>/dev/null)

  if [[ -z "$fm_errors" ]]; then
    pass "C1: all run.md files have required frontmatter keys and orchestrated: true"
  else
    fail "C1: run.md frontmatter" "issues:$fm_errors"
  fi
else
  fail "C1: run.md frontmatter check" "runs dir not found"
fi

# ===========================================================================
# TEST C2: Each run.md contains the required top-level sections
# ===========================================================================
run_test "C2: Each run.md has top-level sections: ## Phases, ## Dependencies, ## Quality Gates"

if [[ -d "$RUNS_DIR" ]]; then
  section_errors=""
  while IFS= read -r run_md; do
    run_label="$(basename "$(dirname "$run_md")")"
    missing_sections=""
    grep -q "^## Phases"       "$run_md" 2>/dev/null || missing_sections="${missing_sections} Phases"
    grep -q "^## Dependencies" "$run_md" 2>/dev/null || missing_sections="${missing_sections} Dependencies"
    grep -q "^## Quality Gates" "$run_md" 2>/dev/null || missing_sections="${missing_sections} 'Quality Gates'"

    if [[ -n "$missing_sections" ]]; then
      section_errors="${section_errors} [$run_label:$missing_sections]"
    fi
  done < <(find "$RUNS_DIR" -name "*.md" 2>/dev/null)

  if [[ -z "$section_errors" ]]; then
    pass "C2: all run.md files have required top-level sections"
  else
    fail "C2: run.md required sections" "issues:$section_errors"
  fi
else
  fail "C2: run.md section check" "runs dir not found"
fi

# ===========================================================================
# TEST C3: Each run.md contains at least one ### Phase N: subsection
# ===========================================================================
run_test "C3: Each run.md contains at least one '### Phase N:' subsection"

if [[ -d "$RUNS_DIR" ]]; then
  no_phase_runs=""
  while IFS= read -r run_md; do
    run_label="$(basename "$(dirname "$run_md")")"
    phase_count="$(grep -cE "^### Phase [0-9]+:" "$run_md" 2>/dev/null || echo "0")"
    if [[ "$phase_count" -lt 1 ]]; then
      no_phase_runs="${no_phase_runs} $run_label"
    fi
  done < <(find "$RUNS_DIR" -name "*.md" 2>/dev/null)

  if [[ -z "$no_phase_runs" ]]; then
    pass "C3: all run.md files contain at least one '### Phase N:' subsection"
  else
    fail "C3: run.md Phase subsections" "no Phase sections in:$no_phase_runs"
  fi
else
  fail "C3: run.md Phase subsection check" "runs dir not found"
fi

# ===========================================================================
# STRUCTURAL SUITE D: queue.yaml structure
#
# Verify that the generated queue file has the required YAML structure.
# ===========================================================================

echo ""
echo "--- Suite D: queue.yaml structure ---"

QUEUE_FILE="$SHARED_WS/.aid-o/config/queue.yaml"

# ===========================================================================
# TEST D1: Queue file has top-level 'queue:' and 'paused:' keys
# ===========================================================================
run_test "D1: queue.yaml has top-level 'queue:' and 'paused:' keys"

if [[ -f "$QUEUE_FILE" ]]; then
  missing_keys=""
  grep -q "^queue:"  "$QUEUE_FILE" 2>/dev/null || missing_keys="${missing_keys} queue:"
  grep -q "^paused:" "$QUEUE_FILE" 2>/dev/null || missing_keys="${missing_keys} paused:"

  if [[ -z "$missing_keys" ]]; then
    pass "D1: queue.yaml has top-level 'queue:' and 'paused:' keys"
  else
    fail "D1: queue YAML top-level keys" "missing:$missing_keys"
  fi
else
  fail "D1: queue file exists" "not found: $QUEUE_FILE"
fi

# ===========================================================================
# TEST D2: Every queue entry has epic_id, status, and priority fields
# ===========================================================================
run_test "D2: Every entry in queue.yaml has epic_id, status, and priority fields"

if [[ -f "$QUEUE_FILE" ]]; then
  # Parse each queue entry block and verify required fields exist.
  # Each entry is a YAML sequence item under 'queue:'.
  # We check using grep within the full file for these required keys.
  entry_count="$(grep -c "epic_id:" "$QUEUE_FILE" 2>/dev/null || echo 0)"
  status_count="$(grep -c "status:" "$QUEUE_FILE" 2>/dev/null || echo 0)"
  priority_count="$(grep -c "priority:" "$QUEUE_FILE" 2>/dev/null || echo 0)"
  entry_count="${entry_count//[[:space:]]/}"
  status_count="${status_count//[[:space:]]/}"
  priority_count="${priority_count//[[:space:]]/}"

  field_errors=""
  # Counts should all match the number of entries (all three fields per entry)
  [[ "$status_count" -eq "$entry_count" ]]   || field_errors="${field_errors} status_count=${status_count}!=${entry_count}"
  [[ "$priority_count" -eq "$entry_count" ]] || field_errors="${field_errors} priority_count=${priority_count}!=${entry_count}"

  if [[ -z "$field_errors" ]]; then
    pass "D2: all $entry_count queue entries have epic_id, status, and priority fields"
  else
    fail "D2: queue entry required fields" "count mismatches:$field_errors"
  fi
else
  fail "D2: queue entry field check" "queue file not found"
fi

# ===========================================================================
# TEST D3: All queue entries have a valid status value (queued, running, completed, failed)
# ===========================================================================
run_test "D3: All queue entry status values are one of: queued, running, completed, failed"

if [[ -f "$QUEUE_FILE" ]]; then
  invalid_statuses="$(grep "^\s*status:" "$QUEUE_FILE" 2>/dev/null \
    | sed 's/.*status:[[:space:]]*//' \
    | grep -Ev '^(queued|running|completed|failed)$' || true)"

  if [[ -z "$invalid_statuses" ]]; then
    pass "D3: all queue entry status values are valid"
  else
    fail "D3: queue entry status values" "invalid values: $invalid_statuses"
  fi
else
  fail "D3: queue status value check" "queue file not found"
fi

# ===========================================================================
# TEST D4: Queue entries have an ISO 8601 timestamp in the 'added_at' field
#
# The implementation and README both use 'added_at' as the canonical field name.
# ===========================================================================
run_test "D4: Each queue entry has an ISO 8601 timestamp in the added_at field"

if [[ -f "$QUEUE_FILE" ]]; then
  entry_count="$(grep -c "epic_id:" "$QUEUE_FILE" 2>/dev/null || echo 0)"
  entry_count="${entry_count//[[:space:]]/}"

  timestamp_count="$(grep -c "added_at:" "$QUEUE_FILE" 2>/dev/null || echo 0)"
  timestamp_count="${timestamp_count//[[:space:]]/}"

  if [[ "$timestamp_count" -ne "$entry_count" ]]; then
    fail "D4: added_at field count" \
      "found $timestamp_count 'added_at' entries, expected $entry_count"
  else
    # Verify timestamps look like ISO 8601 (YYYY-MM-DDTHH:MM:SS or with Z/offset)
    bad_timestamps="$(grep "added_at:" "$QUEUE_FILE" 2>/dev/null \
      | sed 's/.*added_at:[[:space:]]*//' \
      | tr -d '"' \
      | grep -Ev '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' || true)"

    if [[ -z "$bad_timestamps" ]]; then
      pass "D4: all queue entries have valid ISO 8601 timestamps in 'added_at' field"
    else
      fail "D4: ISO 8601 timestamp format" "invalid timestamps: $bad_timestamps"
    fi
  fi
else
  fail "D4: added_at field check" "queue file not found"
fi

# ===========================================================================
# TEST D5: Chain mode produces sequential depends_on wiring in queue entries
# ===========================================================================
run_test "D5: Chain queue mode: entries 2 and 3 have non-empty depends_on (referencing previous EPIC)"

if [[ -f "$QUEUE_FILE" ]]; then
  entry_count="$(grep -c "epic_id:" "$QUEUE_FILE" 2>/dev/null || echo "0")"
  if [[ "$entry_count" -ge 2 ]]; then
    # In chain mode, at least the 2nd entry should have a depends_on that is not empty.
    # We check by counting non-empty depends_on values.
    # Each entry has exactly one 'depends_on:' line (the field).
    depends_on_lines="$(grep "depends_on:" "$QUEUE_FILE" 2>/dev/null || true)"
    non_empty_deps="$(echo "$depends_on_lines" \
      | grep -Ev "depends_on:[[:space:]]*\[\]" \
      | grep -Ev "depends_on:[[:space:]]*$" || true)"
    non_empty_count="$(echo "$non_empty_deps" | grep -c "depends_on" || echo "0")"

    # With 3 phases in chain mode, entries 2 and 3 should have depends_on set
    if [[ "$non_empty_count" -ge 2 ]]; then
      pass "D5: at least 2 queue entries have non-empty depends_on (chain mode wiring confirmed)"
    else
      fail "D5: chain mode depends_on wiring" \
        "expected at least 2 entries with non-empty depends_on, got $non_empty_count"
    fi
  else
    skip "D5: chain mode wiring" "fewer than 2 entries in queue (entry_count=$entry_count)"
  fi
else
  fail "D5: chain depends_on check" "queue file not found"
fi

# ===========================================================================
# STRUCTURAL SUITE E: JSON manifest structure
#
# Cross-check the stdout manifest against the file system artifacts to
# ensure paths in the manifest refer to files that actually exist on disk.
# ===========================================================================

echo ""
echo "--- Suite E: JSON manifest cross-check ---"

# ===========================================================================
# TEST E1: Every epic_path in manifest points to an existing file
# ===========================================================================
run_test "E1: Every epic_path in the JSON manifest points to an existing file on disk"

if echo "$SHARED_STDOUT" | jq . >/dev/null 2>&1; then
  missing_epics=""
  while IFS= read -r epic_path; do
    # Paths may be relative to the workspace; resolve them
    if [[ "${epic_path:0:1}" != "/" ]]; then
      epic_path="$SHARED_WS/$epic_path"
    fi
    [[ -f "$epic_path" ]] || missing_epics="${missing_epics} $epic_path"
  done < <(echo "$SHARED_STDOUT" | jq -r '.epics[].epic_path' 2>/dev/null)

  if [[ -z "$missing_epics" ]]; then
    pass "E1: all epic_path entries in manifest point to existing files"
  else
    fail "E1: manifest epic_path file existence" "missing files:$missing_epics"
  fi
else
  fail "E1: manifest epic_path check" "manifest is not parseable JSON"
fi

# ===========================================================================
# TEST E2: Every plan_json path in manifest points to an existing file
# ===========================================================================
run_test "E2: Every plan_json path in the JSON manifest points to an existing file on disk"

if echo "$SHARED_STDOUT" | jq . >/dev/null 2>&1; then
  missing_jsons=""
  while IFS= read -r plan_json_path; do
    if [[ "${plan_json_path:0:1}" != "/" ]]; then
      plan_json_path="$SHARED_WS/$plan_json_path"
    fi
    [[ -f "$plan_json_path" ]] || missing_jsons="${missing_jsons} $plan_json_path"
  done < <(echo "$SHARED_STDOUT" | jq -r '.epics[].plan_json' 2>/dev/null)

  if [[ -z "$missing_jsons" ]]; then
    pass "E2: all plan_json entries in manifest point to existing files"
  else
    fail "E2: manifest plan_json file existence" "missing files:$missing_jsons"
  fi
else
  fail "E2: manifest plan_json check" "manifest is not parseable JSON"
fi

# ===========================================================================
# TEST E3: Every run_path in manifest points to an existing file
# ===========================================================================
run_test "E3: Every run_path in the JSON manifest points to an existing file on disk"

if echo "$SHARED_STDOUT" | jq . >/dev/null 2>&1; then
  missing_runs=""
  while IFS= read -r run_path; do
    if [[ "${run_path:0:1}" != "/" ]]; then
      run_path="$SHARED_WS/$run_path"
    fi
    [[ -f "$run_path" ]] || missing_runs="${missing_runs} $run_path"
  done < <(echo "$SHARED_STDOUT" | jq -r '.epics[].run_path' 2>/dev/null)

  if [[ -z "$missing_runs" ]]; then
    pass "E3: all run_path entries in manifest point to existing files"
  else
    fail "E3: manifest run_path file existence" "missing files:$missing_runs"
  fi
else
  fail "E3: manifest run_path check" "manifest is not parseable JSON"
fi

# ===========================================================================
# TEST E4: run_id values in manifest match the run directory names on disk
# ===========================================================================
run_test "E4: Each run_id in manifest matches a run directory that exists under .aid-o/work/runs/"

if echo "$SHARED_STDOUT" | jq . >/dev/null 2>&1; then
  missing_run_dirs=""
  while IFS= read -r run_id; do
    expected_dir="$SHARED_WS/.aid-o/work/runs/$run_id"
    [[ -d "$expected_dir" ]] || missing_run_dirs="${missing_run_dirs} $run_id"
  done < <(echo "$SHARED_STDOUT" | jq -r '.epics[].run_id' 2>/dev/null)

  if [[ -z "$missing_run_dirs" ]]; then
    pass "E4: all run_id values match existing run directories on disk"
  else
    fail "E4: run_id -> run directory mapping" "missing dirs for run IDs:$missing_run_dirs"
  fi
else
  fail "E4: run_id directory check" "manifest is not parseable JSON"
fi

# ===========================================================================
# STRUCTURAL SUITE F: Curator dispatch integrity (v2)
#
# Guards against regression of the Curator activation bug
# (FA-20260228T080115Z: Curator produced 0 proposals because dispatch
# was ambiguous and lacked observability).
#
# v2 change: CURATOR_RESOLVE state was eliminated. Curator is now an
# unconditional hook in GATES state, documented in skills/pipeline.md §5.
# ===========================================================================

echo ""
echo "--- Suite F: Curator dispatch integrity ---"

PIPELINE_MD="$PLUGIN_DIR/skills/pipeline.md"

# ===========================================================================
# TEST F1: pipeline.md §7 DONE has the Curator+Auditor dispatch model
# (Architecture moved Curator from §5 GATES → §7 DONE in commit 1dee28e —
# the previous "Curator hook" section was replaced by the C+A Execution
# Model in §7 DONE. §5 GATES now back-points to §7 for Curator/Auditor.)
# ===========================================================================
run_test "F1: pipeline.md §7 DONE has C+A Execution Model section"

if [[ -f "$PIPELINE_MD" ]]; then
  done_section="$(awk '
    /^## §7 DONE/{found=1; next}
    /^## §[0-9]/{if(found) exit}
    found{print}
  ' "$PIPELINE_MD" 2>/dev/null)"

  if echo "$done_section" | grep -q 'C+A Execution Model'; then
    pass "F1: pipeline.md §7 DONE contains C+A Execution Model"
  else
    fail "F1: C+A Execution Model in §7 DONE" \
      "pipeline.md §7 DONE missing 'C+A Execution Model' section"
  fi
else
  fail "F1: pipeline.md exists" "not found: $PIPELINE_MD"
fi

# ===========================================================================
# TEST F2: pipeline.md §7 DONE Curator dispatch has no conditional skipping
#          on empty discovered_issues (was previously in §5 GATES — moved
#          along with the Curator architecture refactor)
# ===========================================================================
run_test "F2: pipeline.md §7 DONE Curator dispatch has no skip conditional on discovered_issues"

if [[ -f "$PIPELINE_MD" ]]; then
  done_section="$(awk '
    /^## §7 DONE/{found=1; next}
    /^## §[0-9]/{if(found) exit}
    found{print}
  ' "$PIPELINE_MD" 2>/dev/null)"

  skip_patterns="$(echo "$done_section" \
    | grep -iE '(if.*no.*(discovered_issues|issues).*skip|skip.*curator.*no.*issues|discovered_issues.*empty.*skip)' \
    || true)"

  if [[ -z "$skip_patterns" ]]; then
    pass "F2: no conditional skipping Curator on empty discovered_issues"
  else
    fail "F2: Curator skip conditional found" \
      "problematic lines: $skip_patterns"
  fi
else
  fail "F2: pipeline.md exists" "not found: $PIPELINE_MD"
fi

# ===========================================================================
# TEST F3: pipeline.md Curator dispatch is unconditional in §7 DONE.
#          §5 GATES has the back-pointer "Transition to DONE: Curator,
#          Auditor, CP4, and CP5 now execute in DONE state (§7)" and §7
#          DONE has the "Parallel dispatch: Curator + Auditor" line.
# ===========================================================================
run_test "F3: pipeline.md Curator dispatch is unconditional (§5 GATES → §7 DONE handoff)"

if [[ -f "$PIPELINE_MD" ]]; then
  if grep -q 'Curator, Auditor.*now execute in DONE' "$PIPELINE_MD" 2>/dev/null &&
     grep -q 'Parallel dispatch.*Curator.*Auditor' "$PIPELINE_MD" 2>/dev/null; then
    pass "F3: pipeline.md §5→§7 Curator handoff + §7 parallel dispatch present"
  else
    fail "F3: unconditional Curator dispatch" \
      "pipeline.md missing §5 'Curator, Auditor ... execute in DONE' back-pointer or §7 'Parallel dispatch: Curator + Auditor'"
  fi
else
  fail "F3: pipeline.md exists" "not found: $PIPELINE_MD"
fi

# ===========================================================================
# TEST F4: pipeline.md §9 auto-mode does NOT suppress Curator hook
# ===========================================================================
run_test "F4: pipeline.md §9 auto-mode does not suppress Curator hook"

if [[ -f "$PIPELINE_MD" ]]; then
  auto_section="$(awk '
    /^## §9 /{found=1; next}
    /^## §[0-9]/{if(found) exit}
    found{print}
  ' "$PIPELINE_MD" 2>/dev/null)"

  suppress_patterns="$(echo "$auto_section" \
    | grep -iE '(skip.*curator|no.*curator|curator.*disabled|suppress.*curator)' \
    || true)"

  if [[ -z "$suppress_patterns" ]]; then
    pass "F4: pipeline.md §9 auto-mode does not suppress Curator"
  else
    fail "F4: auto-mode Curator suppression found" \
      "problematic lines: $suppress_patterns"
  fi
else
  fail "F4: pipeline.md exists" "not found: $PIPELINE_MD"
fi

# ===========================================================================
# TEST F5: pipeline.md §7 DONE Curator dispatch references both
#          curator.md and auditor.md agents (defense-in-depth: two
#          parallel observers — Curator proposes fixes, Auditor flags
#          issues independently). The previously-checked
#          `lessons-extractor.md` agent never existed in agents/ — the
#          dual-observer pattern has always been Curator + Auditor.
# ===========================================================================
run_test "F5: pipeline.md §7 DONE references both curator.md + auditor.md agents"

if [[ -f "$PIPELINE_MD" ]]; then
  if grep -q 'curator.md' "$PIPELINE_MD" 2>/dev/null &&
     grep -q 'auditor.md' "$PIPELINE_MD" 2>/dev/null; then
    pass "F5: pipeline.md references both curator.md + auditor.md"
  else
    fail "F5: Curator + Auditor dispatch" \
      "pipeline.md missing curator.md or auditor.md reference"
  fi
else
  fail "F5: pipeline.md exists" "not found: $PIPELINE_MD"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
[[ "$TESTS_FAILED" -eq 0 ]] && exit 0 || exit 1
