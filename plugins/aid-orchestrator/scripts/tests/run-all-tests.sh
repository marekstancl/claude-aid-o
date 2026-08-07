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

# ─── parse_suite_result <suite_output> ──────────────────────────────────────
#
# Sets PSR_PASSED / PSR_RUN / PSR_FAILED / PSR_SKIPPED / PSR_STATE
# (`parsed` or `unparsed`).
#
# TOKEN-based, not shape-based. This tree really does contain six different
# `Results:` shapes:
#
#   Results: N/T passed, M failed[, W skipped]      <- canonical
#   Results: N/T passed
#   Results: N/T run, P passed, F failed
#   Results: N passed, M failed
#   === Results: N passed, M failed ===
#   Results: N/T passed, M failed ... (trailing prose)
#
# Matching whole shapes would need six patterns and would still be one new
# suite away from a seventh. Reading the TOKENS — `X/Y passed`, `X/Y run`,
# `N passed`, `M failed`, `W skipped` — is one rule that covers all of them,
# and a shape nobody has written yet composes from the same tokens.
#
# A missing `Results:` line remains `unparsed` rather than 0/0: a suite whose
# output cannot be read is a distinct, visible state, not a suite that ran
# nothing.
parse_suite_result() {
  local out="$1" line
  PSR_PASSED=0; PSR_RUN=0; PSR_FAILED=0; PSR_SKIPPED=0; PSR_STATE="unparsed"

  line="$(printf '%s\n' "$out" | grep -E '^(===[[:space:]]*)?Results:' | tail -1)"
  [[ -n "$line" ]] || return 0

  # AMBIGUITY IS UNPARSED, never a guess. Three shapes previously produced a
  # confident wrong number instead of an honest "cannot read this":
  #   `Results: 1,000 passed`      -> the regex took `000`, i.e. zero
  #   `... 5 passed ... 99 passed` -> the first token won, silently
  #   a child's own line echoed verbatim at line start
  # A miscount that claims to be parsed is worse than an unparsed suite,
  # because it is invisible; this step exists to remove exactly that.
  local _n_passed _n_failed
  _n_passed="$(grep -oE '[0-9]+[[:space:]]+passed' <<<"$line" | wc -l)"
  _n_failed="$(grep -oE '[0-9]+[[:space:]]+failed' <<<"$line" | wc -l)"
  if [[ "$_n_passed" -gt 1 || "$_n_failed" -gt 1 ]]; then
    return 0
  fi
  # A digit-group separator means the number is not what a bare [0-9]+ reads.
  if grep -qE '[0-9],[0-9]' <<<"$line"; then
    return 0
  fi

  # Fraction first, wherever it appears: `N/T passed` or `N/T run`.
  if [[ "$line" =~ ([0-9]+)/([0-9]+)[[:space:]]+passed ]]; then
    PSR_PASSED="${BASH_REMATCH[1]}"; PSR_RUN="${BASH_REMATCH[2]}"; PSR_STATE="parsed"
  elif [[ "$line" =~ ([0-9]+)/([0-9]+)[[:space:]]+run ]]; then
    PSR_RUN="${BASH_REMATCH[2]}"; PSR_STATE="parsed"
  fi

  # Bare `N passed` — the authority when there was no fraction to read it from.
  if [[ "$PSR_PASSED" -eq 0 && "$line" =~ (^|[^/0-9])([0-9]+)[[:space:]]+passed ]]; then
    PSR_PASSED="${BASH_REMATCH[2]}"; PSR_STATE="parsed"
  fi
  if [[ "$line" =~ ([0-9]+)[[:space:]]+failed ]]; then
    PSR_FAILED="${BASH_REMATCH[1]}"; PSR_STATE="parsed"
  fi
  if [[ "$line" =~ ([0-9]+)[[:space:]]+skipped ]]; then
    PSR_SKIPPED="${BASH_REMATCH[1]}"
  fi

  # No explicit total: the honest one is what actually ran.
  if [[ "$PSR_STATE" == "parsed" && "$PSR_RUN" -eq 0 ]]; then
    PSR_RUN=$(( PSR_PASSED + PSR_FAILED + PSR_SKIPPED ))
  fi

  # A count no real suite could produce means the line was misread. Refusing
  # it keeps one nonsense number from corrupting the portfolio totals every
  # later cost claim is built on.
  local _max=1000000
  if [[ "$PSR_PASSED" -gt "$_max" || "$PSR_RUN" -gt "$_max" || "$PSR_FAILED" -gt "$_max" ]]; then
    PSR_PASSED=0; PSR_RUN=0; PSR_FAILED=0; PSR_SKIPPED=0; PSR_STATE="unparsed"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
VERBOSE=0
UNPARSED_SUITES=()
INCONSISTENT_SUITES=()
# Suites whose TAP plan promised more results than arrived (P074 EPIC 1).
TRUNCATED_SUITES=()
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
  # P069 EPIC 5 CI fix — same reasoning as the two lines above: this suite
  # (Step 6's isolation-experiment protocol) creates a REAL disposable git
  # worktree per test (git worktree add/remove), which measured 5m58s total
  # locally for just its own 11 tests — bash-tests' own real CI run reached
  # this suite at ~18m32s already elapsed (suite 89/132) and the job's
  # 20-minute budget was hit mid-suite as a direct, deterministic result,
  # not a flake. Delegated to its own job with its own budget instead of
  # eating this job's headroom, exactly like the two entries above.
  ["test-aid-test-isolation-experiment.bats"]="isolation-experiment-tests"
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
  # ─── Execution ledger (P072 Step 26) ─────────────────────────────────
  # One entry per suite this runner dispatches. Unset outside a gate run, in
  # which case this appends nothing — a developer running the suite by hand
  # has no run to account for.
  if [[ -n "${AID_EXECUTION_LEDGER:-}" ]]; then
    _lg_rel="${suite#"$SCRIPT_DIR/"}"
    case "$suite" in
      *.bats) _lg_unit="bats:plugins/aid-orchestrator/scripts/tests/bats/$(basename "$suite" .bats)" ;;
      *)      _lg_unit="sh:plugins/aid-orchestrator/scripts/tests/$(basename "$suite")" ;;
    esac
    bash "$SCRIPT_DIR/../aid-test-execution-ledger.sh" append \
      --path "$AID_EXECUTION_LEDGER" --run-unit-id "$_lg_unit" \
      --gate-id "${AID_CURRENT_GATE_ID:-gate:shell_pipeline_smoke}" \
      --fingerprint "$(printf '%s' "$_lg_rel" | sha256sum | cut -c1-16)" \
      --dispatch-point aggregate_runner || exit 2
  fi

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
    else
      # P074 EPIC 1 — TRUNCATED TAP IS A FAILURE, NOT A GREEN RUN.
      # bats announces its plan (`1..N`) before running anything and reports
      # each result over fd 3. A child process that inherits and holds that
      # fd open truncates the result stream: the plan still says N, only M<N
      # results arrive, and bats still exits 0 — so a suite can lose its last
      # tests (exactly the assertions a step added) while CI reports success.
      # The plan line is a contract; hold the suite to it.
      _tap_reported=$(( suite_passed + suite_failed + suite_skipped ))
      if [[ "$_tap_reported" -lt "$suite_run" ]]; then
        TRUNCATED_SUITES+=("${suite_name} (plan ${suite_run}, reported ${_tap_reported})")
        suite_failed=$(( suite_failed + suite_run - _tap_reported ))
        suite_exit=1
      fi
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
    # P072 Step 9 — one tested parser, and an explicit `unparsed` state.
    #
    # Seven suites used to emit nothing this could read and were recorded as
    # 0/0: a passing suite and a crashed one were indistinguishable, and a
    # fully green run silently contributed zero tests to the totals.
    parse_suite_result "$suite_output"
    suite_passed="$PSR_PASSED"; suite_run="$PSR_RUN"
    suite_failed="$PSR_FAILED"; suite_skipped="$PSR_SKIPPED"
    if [[ "$PSR_STATE" == "unparsed" ]]; then
      UNPARSED_SUITES+=("$suite_name")
    fi
    # A suite reporting more passes than tests is counting two different
    # things in one line (assertions over tests, typically). It inflates the
    # aggregate totals silently, so name it rather than adding it up.
    if [[ "$suite_passed" -gt "$suite_run" ]]; then
      INCONSISTENT_SUITES+=("${suite_name} (${suite_passed}/${suite_run})")
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

# P072 Step 9 — an `unparsed` suite is one whose output this collector cannot
# read. It used to be recorded as 0/0, which made a passing suite and a
# crashed one identical in the totals.
if [[ "${#UNPARSED_SUITES[@]}" -gt 0 ]]; then
  echo ""
  echo "  UNPARSED suites (no readable Results line — counted as 0/0):"
  for _u in "${UNPARSED_SUITES[@]}"; do echo "    - $_u"; done
fi
if [[ "${#INCONSISTENT_SUITES[@]}" -gt 0 ]]; then
  echo ""
  echo "  INCONSISTENT suites (more passes than tests — mixed units in one line):"
  for _i in "${INCONSISTENT_SUITES[@]}"; do echo "    - $_i"; done
fi
if [[ "${#TRUNCATED_SUITES[@]}" -gt 0 ]]; then
  echo ""
  echo "  TRUNCATED suites (TAP plan promised more results than arrived — tests"
  echo "  silently disappeared; usually a child process holding bats' fd 3):"
  for _t in "${TRUNCATED_SUITES[@]}"; do echo "    - $_t"; done
fi
echo "  Total:   $TOTAL_TESTS tests across $SUITES_RUN suites"
echo ""

# Fail the aggregate on an unparsed suite. Enabled only after a full run
# measured zero of them (P072 Step 9 acceptance): 138 suites, 2564 tests,
# zero unparsed and zero inconsistent.
if [[ "${AID_ALLOW_UNPARSED_SUITES:-0}" != "1" && "${#UNPARSED_SUITES[@]}" -gt 0 ]]; then
  echo "RESULT: FAIL — ${#UNPARSED_SUITES[@]} suite(s) produced no readable Results line; their tests are not counted in the totals above"
  echo ""
  exit 1
fi

# A truncated suite is never acceptable: the missing results are exactly the
# tests nobody would notice losing. No opt-out env var — unlike an unparsed
# legacy suite, this is always a defect in the suite or its children.
if [[ "${#TRUNCATED_SUITES[@]}" -gt 0 ]]; then
  echo "RESULT: FAIL — ${#TRUNCATED_SUITES[@]} suite(s) reported fewer results than their TAP plan announced; those tests did not run or their results were lost"
  echo ""
  exit 1
fi

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
