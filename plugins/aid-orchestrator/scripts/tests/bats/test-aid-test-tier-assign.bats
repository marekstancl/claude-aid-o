#!/usr/bin/env bats
# aid-tier: t0
# test-aid-test-tier-assign.bats — P081 Step 2: tiers come from the numbers.
#
# WHAT THIS SUITE PROVES: the four rules that make an assignment defensible —
# the cost thresholds INCLUDING which side of the boundary a suite falls on,
# the scope override (an unresolvable subject is t2 whatever it costs), the
# aggregate budgets that force a demotion rather than tolerating an overflow,
# and the refusal to default an unmeasured suite into any tier at all.
#
# The last one is the reason the tool exits non-zero on a partial table: an
# untiered suite silently landing in T0 is how a portfolio drifts back into
# "everything is cheap", which is the state this whole plan exists to end.
#
# Result count after any edit:
#   bats --tap test-aid-test-tier-assign.bats | grep -cE '^(ok|not ok)'   # == 8

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  ASSIGN="$AID_PLUGIN_PATH/scripts/aid-test-tier-assign.sh"
  export AID_PLUGIN_PATH ASSIGN
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  FIXTURE_TESTS="$TEST_TMPDIR/suites"
  export TEST_TMPDIR ROOT FIXTURE_TESTS
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT"
  mkdir -p "$FIXTURE_TESTS/bats"
  JOURNAL="$ROOT/.aid-o/work/test-durations.jsonl"
  export JOURNAL
  cd "$ROOT"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# _suite <name> — an empty discovered suite of that name.
_suite() { : > "$FIXTURE_TESTS/bats/$1"; }

# _measure <name> <duration_ms> <cases> [censored] — one journal record.
_measure() {
  jq -nc --arg s "$1" --argjson d "$2" --argjson c "$3" \
         --arg cen "${4:-false}" \
    '{suite:$s, runner:"bats", duration_ms:$d, cases:$c, exit_code:0,
      source:"bats_timing", censored:($cen == "true"),
      host:"test-host", at:"2026-08-10T00:00:00.000Z"}' >> "$JOURNAL"
}

_assign() { bash "$ASSIGN" --tests-dir "$FIXTURE_TESTS" "$@"; }

# _tier_of <tsv output> <suite> — the assigned tier column.
_tier_of() { awk -F'\t' -v s="$2" '$1 == s { print $7 }' <<<"$1"; }

@test "1: cost decides the tier — under 2s per case is t0" {
  _suite test-aid-test-durations.bats
  _measure test-aid-test-durations.bats 1999 1
  run _assign
  [ "$status" -eq 0 ]
  [ "$(_tier_of "$output" test-aid-test-durations.bats)" = "t0" ]
}

@test "2: a suite exactly on a threshold falls into the MORE expensive tier" {
  _suite test-aid-test-durations.bats
  _suite test-aid-test-tier.bats
  _measure test-aid-test-durations.bats 2000 1
  _measure test-aid-test-tier.bats 30000 1
  run _assign
  [ "$status" -eq 0 ]
  [ "$(_tier_of "$output" test-aid-test-durations.bats)" = "t1" ]
  [ "$(_tier_of "$output" test-aid-test-tier.bats)" = "t2" ]
}

@test "3: the threshold is per CASE, not per suite" {
  _suite test-aid-test-durations.bats
  _measure test-aid-test-durations.bats 20000 20
  run _assign
  [ "$status" -eq 0 ]
  [ "$(_tier_of "$output" test-aid-test-durations.bats)" = "t0" ]
}

@test "4: an unresolvable subject is t2 however cheap it is" {
  _suite test-no-such-unit-anywhere.bats
  _measure test-no-such-unit-anywhere.bats 5 1
  run _assign
  [ "$status" -eq 0 ]
  [ "$(_tier_of "$output" test-no-such-unit-anywhere.bats)" = "t2" ]
  [[ "$output" == *"unresolvable subject"* ]]
}

@test "5: an overflowing T0 demotes its most expensive member, with a reason" {
  _suite test-aid-test-durations.bats
  _suite test-aid-test-tier.bats
  _measure test-aid-test-durations.bats 79960 40   # 1999 ms/case
  _measure test-aid-test-tier.bats      59970 30   # 1999 ms/case
  run _assign
  [ "$status" -eq 0 ]
  [ "$(_tier_of "$output" test-aid-test-durations.bats)" = "t1" ]
  [ "$(_tier_of "$output" test-aid-test-tier.bats)" = "t0" ]
  [[ "$output" == *"T0 budget"* ]]
  [ "$(awk -F'\t' '$1 == "test-aid-test-durations.bats" { print $9 }' <<<"$output")" = "t0" ]
}

@test "6: an unmeasured suite is listed, never tiered, and the table is partial" {
  _suite test-aid-test-durations.bats
  _suite test-aid-test-tier.bats
  _measure test-aid-test-durations.bats 100 1
  run _assign
  [ "$status" -eq 1 ]
  [ -z "$(_tier_of "$output" test-aid-test-tier.bats)" ]
  [[ "$output" == *"no usable measurement"* ]]
}

@test "7: a censored measurement counts as unmeasured, not as a cheap suite" {
  _suite test-aid-test-durations.bats
  _measure test-aid-test-durations.bats 12 1 true
  run _assign
  [ "$status" -eq 1 ]
  [ -z "$(_tier_of "$output" test-aid-test-durations.bats)" ]
  [[ "$output" == *"censored"* ]]
}

@test "8: the markdown artifact reproduces the table with its host and totals" {
  _suite test-aid-test-durations.bats
  _measure test-aid-test-durations.bats 1000 1
  run _assign --format md
  [ "$status" -eq 0 ]
  [[ "$output" == *"| Suite | Runner |"* ]]
  [[ "$output" == *"test-host"* ]]
  [[ "$output" == *"T0: 1 suite(s), 1000 ms total"* ]]
}
