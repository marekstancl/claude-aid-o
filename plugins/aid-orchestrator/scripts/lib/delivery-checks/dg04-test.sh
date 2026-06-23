#!/usr/bin/env bash
# dg04-test.sh — run tests, unverifiable if zero tests discovered
#
# Exit: 0=pass, 1=fail, 2=unverifiable
# Args: [<command> <args>...] — test command (from policy profile)
# Env:  AID_PROJECT_ROOT — project root directory
#
# Logic:
#   1. No argv → unverifiable
#   2. Run test command; capture output
#   3. Exit non-0 → fail
#   4. Exit 0 but zero tests in output → unverifiable (can't confirm tests ran)
#   5. Exit 0 with test results → pass
#
# Test discovery patterns (at least one must match for "tests found"):
#   - "<N> tests? passing", "<N> passing"
#   - "<N> (test|spec|suite)s? (run|passed|found|ok)"
#   - "ok <N> -" (TAP format)
#   - "PASS" or "FAIL" lines (jest/bats)
#   - "bats: <N> test(s)?"
#   - "Tests:\s+<N>", "Test Suites:\s+<N>" (jest summary)
#   - "<N> tests" anywhere in output
#   - "<N> test" followed by end-of-word

set -uo pipefail

ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"

# ---------------------------------------------------------------------------
# No argv → unverifiable
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  echo "dg04: unverifiable — no test command provided in policy profile"
  echo "dg04: configure dg04.cmd in the policy profile to run your test suite"
  exit 2
fi

# ---------------------------------------------------------------------------
# Run test command
# ---------------------------------------------------------------------------
echo "dg04: running test command: $*"

test_output=""
test_exit=0

# Run from project root; capture combined stdout+stderr
if test_output="$(cd "$ROOT" && "$@" 2>&1)"; then
  test_exit=0
else
  test_exit=$?
fi

echo "$test_output"

# ---------------------------------------------------------------------------
# Exit non-0 → fail immediately
# ---------------------------------------------------------------------------
if [[ "$test_exit" -ne 0 ]]; then
  echo "dg04: fail — test command exited ${test_exit}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Test discovery: check output for test result patterns
# ---------------------------------------------------------------------------

_has_test_results() {
  local output="$1"

  # N tests passing / N passing (mocha/chai style)
  echo "$output" | grep -qiE '[0-9]+ tests? passing' && return 0
  echo "$output" | grep -qiE '^[[:space:]]*[0-9]+ passing' && return 0

  # N (test|spec|suite)s? (run|passed|found|ok) (various frameworks)
  echo "$output" | grep -qiE '[0-9]+ (tests?|specs?|suites?) (run|passed|found|ok)' && return 0

  # TAP format: "ok N -" or "not ok N -"
  echo "$output" | grep -qE '^(ok|not ok) [0-9]+' && return 0

  # jest/bats PASS/FAIL lines
  echo "$output" | grep -qE '^(PASS|FAIL) ' && return 0

  # jest summary: "Tests: N ..." or "Test Suites: N ..."
  echo "$output" | grep -qiE 'Tests:[[:space:]]+[0-9]+' && return 0
  echo "$output" | grep -qiE 'Test Suites:[[:space:]]+[0-9]+' && return 0

  # bats: "N test(s)" at end of line
  echo "$output" | grep -qE '[0-9]+ tests?$' && return 0

  # Generic "N tests" in output
  echo "$output" | grep -qiE '[0-9]+ tests?' && return 0

  # pytest / go test style
  echo "$output" | grep -qiE 'passed|failed|error' && return 0

  # bats output format: "✓" or "✗" lines
  echo "$output" | grep -qE '^[[:space:]]*(✓|✗|x ) ' && return 0

  return 1
}

_has_zero_tests() {
  local output="$1"

  echo "$output" | grep -qiE '0 tests? passing' && return 0
  echo "$output" | grep -qiE '^[[:space:]]*0 passing' && return 0
  echo "$output" | grep -qiE 'no tests?' && return 0
  echo "$output" | grep -qiE 'Tests:[[:space:]]+0' && return 0
  echo "$output" | grep -qiE 'Test Suites:[[:space:]]+0' && return 0
  echo "$output" | grep -qiE '0 tests? (run|found|ok)' && return 0
  echo "$output" | grep -qiE '^[[:space:]]*0 tests?$' && return 0

  return 1
}

# Check for zero tests explicitly first
if _has_zero_tests "$test_output"; then
  echo "dg04: unverifiable — test command succeeded but reported zero tests"
  echo "dg04: zero tests in output counts as unverifiable, not pass"
  exit 2
fi

# Check for positive test evidence
if _has_test_results "$test_output"; then
  echo "dg04: pass — tests ran and passed"
  exit 0
fi

# Test command succeeded but no test-result patterns found → unverifiable
echo "dg04: unverifiable — test command exited 0 but no test result patterns found in output"
echo "dg04: cannot confirm any tests actually ran; treating as unverifiable"
exit 2
