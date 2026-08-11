#!/usr/bin/env bats
# aid-tier: t2
# test-run-all-tests-result-grammar.bats — P072 Step 9.
#
# Seven suites emitted nothing the aggregate collector could read and were
# recorded as `0/0`. That made a fully passing suite and a suite that crashed
# before running anything identical in the totals, and it meant a green run
# silently contributed zero tests to the portfolio's own measured size —
# which is the number every later cost and membership claim is built on.
#
# The fix converges the SUITES onto one canonical line rather than teaching
# the parser more grammars, because a parser taught N grammars is always one
# suite away from needing N+1.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  RUNNER="$PLUGIN_DIR/scripts/tests/run-all-tests.sh"
  TESTS_DIR="$PLUGIN_DIR/scripts/tests"
}

teardown() { teardown_test_evidence_dir; }

# _parse <output> — run the collector's own parser in isolation and echo
# "passed run failed skipped state".
_parse() {
  bash -c '
    # Pull just the parser out of the runner: sourcing the whole script would
    # execute the entire suite sweep.
    sed -n "/^parse_suite_result()/,/^}/p" "$1" > "$2/parser.sh"
    # shellcheck disable=SC1090
    source "$2/parser.sh"
    parse_suite_result "$3"
    echo "$PSR_PASSED $PSR_RUN $PSR_FAILED $PSR_SKIPPED $PSR_STATE"
  ' _ "$RUNNER" "$TEST_TMPDIR" "$1"
}

@test "grammar A parses passed/total/failed" {
  run _parse "some output
Results: 12/15 passed, 3 failed"
  [ "$output" = "12 15 3 0 parsed" ]
}

@test "grammar A parses the skipped variant" {
  run _parse "Results: 10/15 passed, 3 failed, 2 skipped"
  [ "$output" = "10 15 3 2 parsed" ]
}

@test "grammar B is tolerated, and its total is derived as passed+failed" {
  run _parse "=== Results: 8 passed, 2 failed ==="
  [ "$output" = "8 10 2 0 parsed" ]
}

@test "a suite emitting BOTH grammars is counted from the canonical one" {
  # test-semantic-review.sh emits both after this step. Taking the numbers
  # from the decorated line would silently prefer the looser format.
  run _parse "=== Results: 8 passed, 2 failed ===
Results: 8/10 passed, 2 failed"
  [ "$output" = "8 10 2 0 parsed" ]
}

@test "a genuinely empty suite parses as 0/0, distinct from unparsed" {
  run _parse "Results: 0/0 passed, 0 failed"
  [ "$output" = "0 0 0 0 parsed" ]
}

@test "output with no result line at all is UNPARSED, not a silent 0/0" {
  run _parse "test-something: OK"
  [ "$output" = "0 0 0 0 unparsed" ]
}

@test "a nested/quoted result line does not masquerade as the outer result" {
  # Anchoring at line start is what keeps an echoed inner invocation from
  # being read as this suite's own verdict.
  run _parse "  the child printed 'Results: 99/99 passed, 0 failed'
test-outer: OK"
  [ "$output" = "0 0 0 0 unparsed" ]
}

@test "the LAST canonical line wins when a suite prints several" {
  run _parse "Results: 1/1 passed, 0 failed
Results: 5/7 passed, 2 failed"
  [ "$output" = "5 7 2 0 parsed" ]
}

# ─── The seven suites this step converted ──────────────────────────────────

@test "all seven previously-uncounted suites now emit a canonical Results line" {
  local suites=(test-semantic-review test-instruction-consistency
                test-control-boundary test-instruction-sweep
                test-generation-finalize test-cp1-grounding
                test-plan-quality-enforcement)
  local missing=()
  for s in "${suites[@]}"; do
    grep -qE 'echo "Results: ' "$TESTS_DIR/$s.sh" || missing+=("$s")
  done
  [ "${#missing[@]}" -eq 0 ] || { echo "no canonical emission in: ${missing[*]}"; return 1; }
}

@test "test-semantic-review reports its real count, never 0/0" {
  run bash "$TESTS_DIR/test-semantic-review.sh"
  local line; line="$(printf '%s\n' "$output" | grep -E '^Results:' | tail -1)"
  [[ -n "$line" ]]
  [[ "$line" != "Results: 0/0 passed, 0 failed" ]]
  run _parse "$output"
  [[ "$output" == *" parsed" ]]
  [[ "$output" != "0 0 "* ]]
}

@test "the exit-code-driven suites report at suite granularity, honestly" {
  # They have no per-case counters. 1/1 says "this suite passed", which is
  # what they actually know — and is not the 0/0 that meant "nothing ran".
  run bash "$TESTS_DIR/test-instruction-sweep.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Results: 1/1 passed, 0 failed"* ]]
}

@test "a failing exit-code-driven suite reports 0/1, not 1/1" {
  # The emitter reads the real exit status, so a failure cannot be reported
  # as a pass by a trap that fires regardless.
  local fake="$TEST_TMPDIR/fake-suite.sh"
  cat > "$fake" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
_p072_emit_results() {
  local rc="${1:-$?}"
  if [[ "$rc" -eq 0 ]]; then echo "Results: 1/1 passed, 0 failed"
  else echo "Results: 0/1 passed, 1 failed"; fi
}
trap '_p072_rc=$?; _p072_emit_results "$_p072_rc"' EXIT
exit 3
SH
  run bash "$fake"
  [ "$status" -eq 3 ]
  [[ "$output" == *"Results: 0/1 passed, 1 failed"* ]]
}

@test "composing with an existing cleanup trap preserves the cleanup" {
  # A shell has exactly one EXIT trap. Installing a second silently discards
  # the first, which would have leaked every temp dir these suites create.
  local fake="$TEST_TMPDIR/fake-cleanup.sh" marker="$TEST_TMPDIR/cleanup-target"
  mkdir -p "$marker"
  cat > "$fake" <<SH
#!/usr/bin/env bash
set -euo pipefail
_p072_emit_results() {
  local rc="\${1:-\$?}"
  if [[ "\$rc" -eq 0 ]]; then echo "Results: 1/1 passed, 0 failed"
  else echo "Results: 0/1 passed, 1 failed"; fi
}
trap '_p072_rc=\$?; _p072_emit_results "\$_p072_rc"; rm -rf "$marker"' EXIT
exit 0
SH
  run bash "$fake"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Results: 1/1 passed"* ]]
  [ ! -d "$marker" ]
}

@test "the aggregate refuses to pass while any suite is unparsed" {
  grep -q 'UNPARSED_SUITES\[@\]' "$RUNNER"
  grep -q 'produced no readable Results line' "$RUNNER"
  # and the escape hatch is named, so enabling the rule was a deliberate act
  grep -q 'AID_ALLOW_UNPARSED_SUITES' "$RUNNER"
}

# ─── The other grammars this tree really contains ──────────────────────────
#
# The first cut of this step handled two shapes and was written from a scan
# for suites emitting NO `Results:` line. That scan missed suites emitting a
# DIFFERENT `Results:` shape — four more of them — and they were only found by
# running the full aggregate. Reading tokens instead of whole shapes is what
# makes a seventh shape compose rather than need a seventh pattern.

@test "grammar: 'N/T run, P passed, F failed' is read correctly" {
  run _parse "Results: 10/10 run, 10 passed, 0 failed"
  [ "$output" = "10 10 0 0 parsed" ]
}

@test "grammar: a bare 'N passed, M failed' with no fraction derives its total" {
  run _parse "Results: 54 passed, 0 failed"
  [ "$output" = "54 54 0 0 parsed" ]
}

@test "grammar: 'N/T passed' with no failed clause is complete, not unparsed" {
  run _parse "Results: 7/7 passed"
  [ "$output" = "7 7 0 0 parsed" ]
}

@test "grammar: trailing prose after the counts does not defeat the parse" {
  run _parse "Results: 5/9 passed, 4 failed (plus 2 advisory grandfathered notes)"
  [ "$output" = "5 9 4 0 parsed" ]
}

@test "the fraction and the bare passed token are read from the right places" {
  run _parse "Results: 3/12 run, 3 passed, 9 failed"
  [ "$output" = "3 12 9 0 parsed" ]
}

@test "a suite reporting more passes than tests is named, not silently summed" {
  grep -q 'INCONSISTENT_SUITES' "$RUNNER"
  grep -q 'more passes than tests' "$RUNNER"
}

@test "test-cp1-gate no longer mixes assertions and tests in one fraction" {
  # It reported 54/28 — assertions over tests — which the aggregate then added
  # to its totals as if both counted the same thing. The behavioural proof is
  # the "reports TESTS in the fraction" case below; this pins that the source
  # no longer contains the mixed-unit expression at all.
  ! grep -q 'Results: \$TESTS_PASSED/\$TESTS_RUN' "$TESTS_DIR/test-cp1-gate.sh"
  grep -q 'TESTS_PASSED_UNIQUE' "$TESTS_DIR/test-cp1-gate.sh"
}

# ─── Behavioural, not grep-based (Codex review) ────────────────────────────
#
# Several assertions above prove the SOURCE contains an emitter or a message.
# These run the real collector logic over fixture suites and assert what it
# actually does with them.

_run_collector_over() {
  # Feed one fixture suite's output through the real parser and echo the
  # collector's own view of it.
  local out; out="$(bash "$1" 2>&1 || true)"
  _parse "$out"
}

@test "BEHAVIOUR: a fixture suite emitting the canonical line is counted, not 0/0" {
  local f="$TEST_TMPDIR/s-ok.sh"
  printf '#!/usr/bin/env bash\necho "Results: 4/5 passed, 1 failed"\nexit 0\n' > "$f"
  run _run_collector_over "$f"
  [ "$output" = "4 5 1 0 parsed" ]
}

@test "BEHAVIOUR: a fixture suite emitting nothing readable is unparsed, not 0/0-parsed" {
  local f="$TEST_TMPDIR/s-silent.sh"
  printf '#!/usr/bin/env bash\necho "all good"\nexit 0\n' > "$f"
  run _run_collector_over "$f"
  [ "$output" = "0 0 0 0 unparsed" ]
}

@test "BEHAVIOUR: a thousands-separated count is refused rather than read as zero" {
  # `1,000 passed` used to yield 000 — a confident zero. A miscount that
  # claims to be parsed is worse than an unparsed suite, because it is
  # invisible in the totals.
  run _parse "Results: 1,000 passed, 0 failed"
  [ "$output" = "0 0 0 0 unparsed" ]
}

@test "BEHAVIOUR: two 'N passed' tokens on one line are ambiguous, so unparsed" {
  run _parse "Results: 5 passed, 1 failed and then 99 passed"
  [ "$output" = "0 0 0 0 unparsed" ]
}

@test "BEHAVIOUR: an implausible count is refused rather than corrupting the totals" {
  run _parse "Results: 99999999 passed, 0 failed"
  [ "$output" = "0 0 0 0 unparsed" ]
}

@test "BEHAVIOUR: test-cp1-gate reports TESTS in the fraction, assertions on their own line" {
  run bash "$TESTS_DIR/test-cp1-gate.sh"
  [ "$status" -eq 0 ]
  local line; line="$(printf '%s\n' "$output" | grep -E '^Results:' | tail -1)"
  # tests, not assertions: the numerator must equal the denominator here and
  # both must be the TEST count, so the aggregate's "Tests" total stays tests.
  [[ "$line" =~ ^Results:\ ([0-9]+)/([0-9]+)\ passed ]]
  [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ]
  [[ "$output" == *"passing assertions"* ]]
  # and the assertion count really is different from the test count
  [[ "$output" != *"(${BASH_REMATCH[1]} passing assertions"* ]]
}

@test "BEHAVIOUR: the emitter preserves a failing exit status through the trap" {
  local f="$TEST_TMPDIR/s-fail.sh"
  cat > "$f" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
_p072_emit_results() { set +e; local rc="${1:-$?}"
  if [[ "$rc" -eq 0 ]]; then echo "Results: 1/1 passed, 0 failed"
  else echo "Results: 0/1 passed, 1 failed"; fi; return 0; }
trap '_p072_rc=$?; _p072_emit_results "$_p072_rc"' EXIT
exit 7
SH
  run bash "$f"
  [ "$status" -eq 7 ]
  [[ "$output" == *"Results: 0/1 passed, 1 failed"* ]]
}

@test "BEHAVIOUR: cleanup still runs when reporting cannot write" {
  # errexit inside an EXIT trap would abort before the cleanup that follows.
  local f="$TEST_TMPDIR/s-closed.sh" marker="$TEST_TMPDIR/must-be-removed"
  mkdir -p "$marker"
  cat > "$f" <<SH
#!/usr/bin/env bash
set -euo pipefail
_p072_emit_results() { set +e; local rc="\${1:-\$?}"
  if [[ "\$rc" -eq 0 ]]; then echo "Results: 1/1 passed, 0 failed"
  else echo "Results: 0/1 passed, 1 failed"; fi; return 0; }
trap '_p072_rc=\$?; _p072_emit_results "\$_p072_rc"; rm -rf "$marker"' EXIT
exit 0
SH
  bash "$f" >&- 2>/dev/null || true
  [ ! -d "$marker" ]
}
