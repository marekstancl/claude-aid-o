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
LIST_ONLY=0
# P081 Step 1 — timing is OPT-IN. Without the flag this runner's output, its
# exit code and its cost are exactly what they were: every gate, CI job and
# developer invocation keeps paying nothing for a measurement it did not ask
# for.
TIMING=0
DURATIONS_WARNED=0
# P081 Step 5 — empty means every tier, which is exactly today's behaviour.
TIER=""
ONLY=""
USAGE="Usage: $(basename "$0") [--verbose] [--list] [--tier t0|t1|t2] [--timing] [--include-delegated]"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose|-v)
      VERBOSE=1
      ;;
    --timing)
      TIMING=1
      ;;
    --only)
      [[ $# -ge 2 ]] || { echo "--only requires a suite basename" >&2; exit 2; }
      ONLY="$2"; shift 2; continue ;;
    --tier)
      TIER="${2:-}"; shift
      case "$TIER" in
        t0|t1|t2) ;;
        *) echo "Unknown tier: '$TIER' (accepted: t0 t1 t2)" >&2; exit 2 ;;
      esac
      ;;
    --include-delegated)
      # DEPRECATED, accepted as a no-op for one release (removed 2026-08-14 with
      # delegation itself). An untiered run is already the whole portfolio, so
      # this flag now asks for what it gets anyway. It is still ACCEPTED rather
      # than rejected because callers this repository cannot see — a cron line,
      # someone's shell history — would otherwise exit 2 on an unknown flag.
      [[ "$VERBOSE" -eq 1 ]] && echo "NOTE: --include-delegated is deprecated and does nothing (delegation was removed 2026-08-14; an untiered run is the full portfolio)." >&2
      ;;
    --list)
      # P079 Step 12: enumerate WITHOUT running anything. The delegation test
      # needs to see which suites are inline and which are delegated, and
      # running the whole aggregate suite to find out would cost half an hour
      # to answer a question about a directory listing.
      LIST_ONLY=1
      ;;
    --help|-h)
      echo "$USAGE"
      echo ""
      echo "Runs all test-*.sh scripts in the tests directory."
      echo ""
      echo "Options:"
      echo "  --verbose, -v        Show full output from each test suite"
      echo "  --list               List discovered suites, run nothing"
      echo "  --tier <t0|t1|t2>    Run only suites declaring that tier (see aid-test-tier-lint.sh)"
      echo "  --only <basename>    Run exactly one suite, under the runner's own conditions"
      echo "  --timing             Record one duration per suite into the durations journal"
      echo "  --include-delegated  DEPRECATED no-op (delegation removed 2026-08-14; untiered = full portfolio)"
      echo "  --help, -h           Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "$USAGE" >&2
      exit 1
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Timing mode (P081 Step 1)
#
# The parser `lib/aid-test-timing-bats.sh` has shipped since P072 with exactly
# one caller — the per-unit profiler. This is its PORTFOLIO caller; nothing
# here re-implements timing. The libs are sourced only under --timing so a
# normal run gains no dependency it did not already have.
# ---------------------------------------------------------------------------
BATS_TIMED=0
if [[ "$TIMING" -eq 1 ]]; then
  # shellcheck source=../lib/aid-test-timing-bats.sh
  source "$SCRIPT_DIR/../lib/aid-test-timing-bats.sh"
  # shellcheck source=../lib/aid-test-durations.sh
  source "$SCRIPT_DIR/../lib/aid-test-durations.sh"
  bats_timing_supported && BATS_TIMED=1
fi

# ─── record_suite_duration <suite> <runner> <wall_ms> <exit> <output> ────────
#
# One journal record per executed suite. A bats suite's duration is the SUM of
# its per-test durations when the runner reported them, and the wall-clock
# bracket otherwise; the record says which, so a later reader can tell a
# measured figure from a bracketed one. A truncated TAP stream is recorded
# `censored` — its duration is a partial and must never be tiered.
#
# Timing is observational: an unwritable journal warns ONCE and the run
# continues. A measurement must never be able to fail a test run.
record_suite_duration() {
  local suite="$1" runner="$2" wall_ms="$3" exit_code="$4" output="$5"
  local never_ran="${6:-false}"
  local duration_ms="$wall_ms" source="wallclock" cases=1 censored="false"

  # A suite that never executed (bats absent) took ~0 ms and passed no cases.
  # Recorded plainly, the assigner would read that as the cheapest suite in the
  # portfolio and put it in T0 — an unrun suite promoted to the merge path's
  # fastest tier. `censored` is exactly the "this duration is not a
  # measurement" marker, and the assigner already refuses to tier it.
  if [[ "$never_ran" == "true" ]]; then
    censored="true"
  fi

  if [[ "$runner" == "bats" && "$BATS_TIMED" -eq 1 && "$never_ran" != "true" ]]; then
    local parsed sum n
    parsed="$(bats_timing_parse "$output" "$(basename "$suite")" 2>/dev/null)" || parsed=""
    if [[ -n "$parsed" ]]; then
      sum="$(jq -r '[.cases[].duration_ms] as $d
                    | if ($d | length) == 0 or ($d | map(. == null) | any)
                      then "" else ($d | add) end' <<<"$parsed" 2>/dev/null)"
      if [[ "$sum" =~ ^[0-9]+$ ]]; then
        duration_ms="$sum"; source="bats_timing"
      fi
      n="$(jq -r '.cases | length' <<<"$parsed" 2>/dev/null)"
      [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] && cases="$n"
      [[ "$(jq -r '.truncated' <<<"$parsed" 2>/dev/null)" == "true" ]] && censored="true"
    fi
  fi

  if ! aid_durations_append "$(basename "$suite")" "$runner" \
        "$duration_ms" "$exit_code" "$source" "$cases" "$censored"; then
    if [[ "$DURATIONS_WARNED" -eq 0 ]]; then
      echo "WARNING: suite durations are not being recorded (timing is observational; the run continues)" >&2
      DURATIONS_WARNED=1
    fi
  fi
}

# ---------------------------------------------------------------------------
# Delegation is GONE (2026-08-14) — the tier tag is the only authority
#
# Five suites used to be listed here as "owned by a dedicated CI job" and were
# skipped by this runner for that reason. All five are `# aid-tier: t2`, and the
# ecosystem test standard says T2 runs nightly and never on the merge path — so
# the jobs that made them merge-blocking were the bug, and they are deleted
# (.github/workflows/ci.yml). With them gone there is nothing left for a second
# authority to say: `--tier t0`/`--tier t1` select the merge path, an untiered
# run is the whole portfolio, and scripts/tests/test-tier-ci-topology.sh fails
# if a T2 suite ever reappears on a push/PR-triggered job.
#
# What this runner must NOT lose in the process is the failure mode the old
# delegation test existed for: a suite that is run by NOTHING. That is now the
# topology test's first assertion, not a property of a map.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Discover test suites
# ---------------------------------------------------------------------------
SUITES=()
for f in "$SCRIPT_DIR"/test-*.sh; do
  [[ -f "$f" ]] || continue
  SUITES+=("$f")
done
# Also discover bats suites in bats/ subdirectory (E-046-1_3 Step 6)
for f in "$SCRIPT_DIR"/bats/test-*.bats; do
  [[ -f "$f" ]] || continue
  SUITES+=("$f")
done

if [[ ${#SUITES[@]} -eq 0 ]]; then
  echo "ERROR: No test-*.sh or bats/test-*.bats suites found in $SCRIPT_DIR" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Tiers (P081 Step 5)
#
# Filtering happens AFTER discovery on purpose: the globs, the empty-set guard,
# the delegation map and the ledger's unit-id derivation all keep working on
# the paths they already knew. That is the whole argument for a header tag over
# tier directories — moving the files would have broken every one of them.
#
# ONE REFUSAL RULE, stated once and used by both layers: an untagged suite is
# refused only when at least one suite in the tree already carries a tag. A
# project that has never adopted tiers runs everything exactly as it does
# today; inside a tree that HAS adopted them, defaulting an untagged suite into
# a tier is how a portfolio drifts back into "everything is cheap", so there
# the refusal is absolute.
# ---------------------------------------------------------------------------
# shellcheck source=../lib/aid-test-tier.sh
source "$SCRIPT_DIR/../lib/aid-test-tier.sh"
declare -A SUITE_TIER=()
TAGGED_COUNT=0
UNTAGGED_SUITES=()
# A tag that is DUPLICATED or names an unknown tier is kept apart from a
# missing one. Folding it into "untagged" made an invalid declaration look like
# a project that has not adopted tiers — so a tree where every tag was
# misspelled would run happily and match no tier filter at all.
INVALID_TAG_SUITES=()
while IFS= read -r _s; do
  [[ -n "$_s" ]] || continue
  _rc=0
  _t="$(aid_test_tier_of "$_s" 2>/dev/null)" || _rc=$?
  case "$_rc" in
    0) SUITE_TIER["$(basename "$_s")"]="$_t"; TAGGED_COUNT=$(( TAGGED_COUNT + 1 )) ;;
    1) UNTAGGED_SUITES+=("$(basename "$_s")") ;;
    *) INVALID_TAG_SUITES+=("$(basename "$_s")") ;;
  esac
done < <(aid_test_discover_suites "$SCRIPT_DIR")

if [[ "${#INVALID_TAG_SUITES[@]}" -gt 0 ]]; then
  echo "ERROR: ${#INVALID_TAG_SUITES[@]} suite(s) carry an aid-tier tag that is duplicated or names an unknown tier:" >&2
  for _u in "${INVALID_TAG_SUITES[@]}"; do echo "  - $_u" >&2; done
  echo "A tag nobody can read is not the same as no tag — see aid-test-tier-lint.sh." >&2
  exit 1
fi

if [[ "$TAGGED_COUNT" -gt 0 && "${#UNTAGGED_SUITES[@]}" -gt 0 ]]; then
  echo "ERROR: this portfolio declares test tiers, but ${#UNTAGGED_SUITES[@]} suite(s) carry no '# aid-tier:' tag:" >&2
  for _u in "${UNTAGGED_SUITES[@]}"; do echo "  - $_u" >&2; done
  echo "An untagged suite would silently never run under --tier. Tag them, then re-run;" >&2
  echo "aid-test-tier-lint.sh reports the same thing with the full rule set." >&2
  exit 1
fi

SKIPPED_BY_TIER=0
if [[ -n "$TIER" ]]; then
  _kept=()
  for suite in ${SUITES[@]+"${SUITES[@]}"}; do
    if [[ "${SUITE_TIER[$(basename "$suite")]:-}" == "$TIER" ]]; then
      _kept+=("$suite")
    else
      SKIPPED_BY_TIER=$(( SKIPPED_BY_TIER + 1 ))
    fi
  done
  SUITES=(${_kept[@]+"${_kept[@]}"})

  # P081 whole-diff review fix: a tier that selects NOTHING is not a pass.
  # Without this, an untiered tree (TAGGED_COUNT == 0, so the untagged refusal
  # above never fires) ran zero suites and reported RESULT: PASS / exit 0 —
  # and defaults/execution.yaml ships exactly that invocation as a consumer's
  # `required: true` gate. An empty selection is now a loud refusal; a project
  # that has genuinely adopted no tiers must run without --tier at all.
  if [[ "${#SUITES[@]}" -eq 0 ]]; then
    echo "ERROR: --tier $TIER selected 0 of $SKIPPED_BY_TIER discovered suite(s)." >&2
    if [[ "$TAGGED_COUNT" -eq 0 ]]; then
      echo "No suite in this portfolio carries an '# aid-tier:' tag, so no tier can ever match." >&2
      echo "A project that has not adopted tiers must invoke this runner WITHOUT --tier." >&2
    else
      echo "Tier '$TIER' has no members. If that is intended, remove this tier from the gate" >&2
      echo "rather than running a gate that verifies nothing." >&2
    fi
    exit 1
  fi
fi

# --only: one suite, under the runner's own conditions. Added so the nightly's
# retry-once can re-run a failed suite the SAME way it was run the first time —
# a bare `bats path` re-run changed cwd, environment and fd discipline, so a
# runner-conditional failure passed standalone and was laundered into a silent
# quarantine while the night reported green.
if [[ -n "$ONLY" ]]; then
  _o=()
  for suite in ${SUITES[@]+"${SUITES[@]}"}; do
    [[ "$(basename "$suite")" == "$ONLY" ]] && _o+=("$suite")
  done
  if [[ "${#_o[@]}" -eq 0 ]]; then
    echo "ERROR: --only '$ONLY' matched no discovered suite." >&2
    exit 1
  fi
  SUITES=("${_o[@]}")
fi

if [[ "$LIST_ONLY" -eq 1 ]]; then
  echo "Discovered ${#SUITES[@]} test suite(s)"
  for suite in ${SUITES[@]+"${SUITES[@]}"}; do
    echo "INLINE: $(basename "$suite") [${SUITE_TIER[$(basename "$suite")]:-untagged}]"
  done
  [[ "$SKIPPED_BY_TIER" -gt 0 ]] && echo "SKIPPED-BY-TIER: $SKIPPED_BY_TIER suite(s) not in $TIER"
  exit 0
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
# Never silent: a suite that does not run is exactly what this reports.
[[ "$SKIPPED_BY_TIER" -gt 0 ]] && echo "SKIPPED-BY-TIER: $SKIPPED_BY_TIER suite(s) not in $TIER"
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
  wall_start_ms=0
  [[ "$TIMING" -eq 1 ]] && wall_start_ms="$(date -u +%s%3N)"
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
    elif [[ "$BATS_TIMED" -eq 1 ]] && bats_timing_can_time_argv "$BATS_BIN"; then
      suite_output="$("$BATS_BIN" --timing "$suite" 2>&1)" && suite_exit=0 || suite_exit=$?
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

  if [[ "$TIMING" -eq 1 ]]; then
    record_suite_duration "$suite" \
      "$([[ "$is_bats" -eq 1 ]] && echo bats || echo sh)" \
      "$(( $(date -u +%s%3N) - wall_start_ms ))" "$suite_exit" "$suite_output" \
      "$([[ "$bats_missing_hard_fail" -eq 1 ]] && echo true || echo false)"
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
