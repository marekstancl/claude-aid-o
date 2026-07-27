#!/usr/bin/env bash
# =============================================================================
# run-all-tests.sh — Master test runner for AID pipeline scripts
#
# Discovers and runs all test-*.sh scripts in this directory, tracks pass/fail
# counts per suite and total, and reports a unified summary.
#
# Usage:
#   ./run-all-tests.sh              # Compact output (summary per suite)
#   ./run-all-tests.sh --verbose    # Full output from each suite
#
# Exit codes: 0=all suites passed, 1=one or more suites failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v)
      VERBOSE=1
      ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--verbose]"
      echo ""
      echo "Runs all test-*.sh scripts in the tests directory."
      echo ""
      echo "Options:"
      echo "  --verbose, -v   Show full output from each test suite"
      echo "  --help, -h      Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $(basename "$0") [--verbose]" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Suites delegated to a dedicated CI job (P064 E-064-1_2 Step 1)
#
# A suite listed here owns its own job in .github/workflows/ci.yml and is
# deliberately SKIPPED by this aggregate runner — running it here too would
# execute it in both jobs and risk blowing this job's timeout budget for no
# benefit (the dedicated job already covers it, usually with a larger
# budget this job doesn't have room for). Keyed by bats file basename;
# value is the owning CI job name, purely for the DELEGATED report line
# below — never run silently, always visible in the output.
# ---------------------------------------------------------------------------
declare -A DELEGATED_SUITES=(
  ["test-aid-plan-release-boundary.bats"]="plan-boundary-tests"
  # P068 E-068-1_2 Step 1 — same reasoning as the line above: this suite
  # creates a real Git repository per test and drives real merges, version
  # bumps and freeze/invalidation cycles through the CLI, so it gets its own
  # job with its own budget instead of eating this job's headroom.
  ["test-aid-plan-final-boundary.bats"]="plan-final-tests"
)

# ---------------------------------------------------------------------------
# Discover test suites
# ---------------------------------------------------------------------------
SUITES=()
DELEGATED_LOG=()
for f in "$SCRIPT_DIR"/test-*.sh; do
  [[ -f "$f" ]] || continue
  SUITES+=("$f")
done
# Also discover bats suites in bats/ subdirectory (E-046-1_3 Step 6)
for f in "$SCRIPT_DIR"/bats/test-*.bats; do
  [[ -f "$f" ]] || continue
  bn="$(basename "$f")"
  if [[ -n "${DELEGATED_SUITES[$bn]:-}" ]]; then
    DELEGATED_LOG+=("$bn -> ${DELEGATED_SUITES[$bn]}")
    continue
  fi
  SUITES+=("$f")
done

if [[ ${#SUITES[@]} -eq 0 && ${#DELEGATED_LOG[@]} -eq 0 ]]; then
  echo "ERROR: No test-*.sh or bats/test-*.bats suites found in $SCRIPT_DIR" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Run suites and collect results
# ---------------------------------------------------------------------------
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
SUITES_PASSED=0
SUITES_FAILED=0
SUITES_RUN=0

# Track failed suite names for the final report
FAILED_SUITE_NAMES=()

# Separator for output
SEP="$(printf '%0.s-' {1..70})"

echo "========================================================================"
echo "  AID Pipeline Tests"
echo "========================================================================"
echo ""
echo "Discovered ${#SUITES[@]} test suite(s)"
if [[ ${#DELEGATED_LOG[@]} -gt 0 ]]; then
  for entry in "${DELEGATED_LOG[@]}"; do
    echo "DELEGATED: $entry"
  done
fi
echo ""

for suite in "${SUITES[@]}"; do
  suite_name="$(basename "$suite" .bats)"
  suite_name="${suite_name%.sh}"   # strip .sh if .bats didn't match
  SUITES_RUN=$(( SUITES_RUN + 1 ))

  echo "$SEP"
  echo "Suite $SUITES_RUN/${#SUITES[@]}: $suite_name"
  echo "$SEP"

  # Detect if suite is a bats test (shebang line)
  is_bats=0
  if head -1 "$suite" 2>/dev/null | grep -q 'bats'; then
    is_bats=1
  fi

  # Run the suite, capturing output and exit code
  suite_output=""
  suite_exit=0
  bats_missing_hard_fail=0
  if [[ "$is_bats" -eq 1 ]]; then
    # bats test: requires bats binary. A missing binary is a HARD FAILURE,
    # not a green skip — every bats suite in the repo used to report green
    # when bats was simply absent, which is worse than useless (it looks
    # like coverage that never ran). Set AID_ALLOW_MISSING_BATS=1 to accept
    # the skip explicitly (e.g. a contributor without bats installed who
    # knows CI will still run these suites).
    BATS_BIN="$(command -v bats 2>/dev/null || echo "")"
    if [[ -z "$BATS_BIN" ]]; then
      if [[ "${AID_ALLOW_MISSING_BATS:-0}" == "1" ]]; then
        suite_output="SKIP: bats not installed (AID_ALLOW_MISSING_BATS=1)"
        suite_exit=0
      else
        suite_output="FAIL: bats not installed — this suite did not run. Install bats, or set AID_ALLOW_MISSING_BATS=1 to explicitly accept skipping bats suites."
        suite_exit=1
        bats_missing_hard_fail=1
      fi
    else
      suite_output="$("$BATS_BIN" "$suite" 2>&1)" && suite_exit=0 || suite_exit=$?
    fi
    [[ "$VERBOSE" -eq 1 ]] && echo "$suite_output"
  elif [[ "$VERBOSE" -eq 1 ]]; then
    # In verbose mode, tee output to both terminal and capture variable
    suite_output="$(bash "$suite" 2>&1)" && suite_exit=0 || suite_exit=$?
    echo "$suite_output"
  else
    suite_output="$(bash "$suite" 2>&1)" && suite_exit=0 || suite_exit=$?
  fi

  suite_passed=0
  suite_run=0
  suite_failed=0
  suite_skipped=0

  if [[ "$is_bats" -eq 1 ]]; then
    # Parse bats TAP output: "ok N description" / "not ok N description" / "1..N"
    while IFS= read -r line; do
      if [[ "$line" =~ ^1\.\.([0-9]+) ]]; then
        suite_run="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^ok\ [0-9] ]]; then
        suite_passed=$(( suite_passed + 1 ))
      elif [[ "$line" =~ ^not\ ok\ [0-9] ]]; then
        suite_failed=$(( suite_failed + 1 ))
      elif [[ "$line" =~ ^ok.*\#\ skip ]]; then
        suite_skipped=$(( suite_skipped + 1 ))
        suite_passed=$(( suite_passed - 1 ))  # correct overcounting
      fi
    done <<< "$suite_output"
    # If run count wasn't in TAP plan line, infer from pass+fail
    if [[ "$suite_run" -eq 0 ]]; then
      suite_run=$(( suite_passed + suite_failed + suite_skipped ))
    fi
    # bats never ran at all (missing binary, no AID_ALLOW_MISSING_BATS) —
    # there is no TAP output to parse; report one explicit failed test
    # rather than a misleading 0/0.
    if [[ "$bats_missing_hard_fail" -eq 1 ]]; then
      suite_run=1
      suite_passed=0
      suite_failed=1
      suite_skipped=0
    fi
  else
    # Parse the Results line from the bash suite output
    # Expected formats:
    #   "Results: X/Y passed, Z failed"
    #   "Results: X/Y passed, Z failed, W skipped"
    results_line="$(echo "$suite_output" | grep -E '^Results:' | tail -1)"

    if [[ -n "$results_line" ]]; then
      # Extract passed/total
      if [[ "$results_line" =~ ([0-9]+)/([0-9]+)\ passed ]]; then
        suite_passed="${BASH_REMATCH[1]}"
        suite_run="${BASH_REMATCH[2]}"
      fi
      # Extract failed count
      if [[ "$results_line" =~ ([0-9]+)\ failed ]]; then
        suite_failed="${BASH_REMATCH[1]}"
      fi
      # Extract skipped count (if present)
      if [[ "$results_line" =~ ([0-9]+)\ skipped ]]; then
        suite_skipped="${BASH_REMATCH[1]}"
      fi
    fi
  fi

  # Accumulate totals
  TOTAL_TESTS=$(( TOTAL_TESTS + suite_run ))
  TOTAL_PASSED=$(( TOTAL_PASSED + suite_passed ))
  TOTAL_FAILED=$(( TOTAL_FAILED + suite_failed ))
  TOTAL_SKIPPED=$(( TOTAL_SKIPPED + suite_skipped ))

  # Determine suite pass/fail
  if [[ "$suite_exit" -eq 0 ]]; then
    SUITES_PASSED=$(( SUITES_PASSED + 1 ))
    status_icon="PASS"
  else
    SUITES_FAILED=$(( SUITES_FAILED + 1 ))
    FAILED_SUITE_NAMES+=("$suite_name")
    status_icon="FAIL"
  fi

  # Print compact summary for this suite
  skip_info=""
  if [[ "$suite_skipped" -gt 0 ]]; then
    skip_info=", $suite_skipped skipped"
  fi
  echo "  [$status_icon] $suite_passed/$suite_run passed, $suite_failed failed${skip_info}"
  echo ""
done

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo "========================================================================"
echo "  Summary"
echo "========================================================================"
echo ""
echo "  Suites:  $SUITES_PASSED/$SUITES_RUN passed, $SUITES_FAILED failed"

skip_summary=""
if [[ "$TOTAL_SKIPPED" -gt 0 ]]; then
  skip_summary=" ($TOTAL_SKIPPED skipped)"
fi
echo "  Tests:   $TOTAL_PASSED/$TOTAL_TESTS passed, $TOTAL_FAILED failed${skip_summary}"
echo "  Total:   $TOTAL_TESTS tests across $SUITES_RUN suites"
echo ""

if [[ "$SUITES_FAILED" -gt 0 ]]; then
  echo "  Failed suites:"
  for name in "${FAILED_SUITE_NAMES[@]}"; do
    echo "    - $name"
  done
  echo ""
  echo "RESULT: FAIL"
  echo ""
  exit 1
else
  echo "RESULT: PASS"
  echo ""
  exit 0
fi
