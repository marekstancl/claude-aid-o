#!/usr/bin/env bats
# aid-tier: t0
# test-aid-test-tier-lint.bats — P081 Step 3: the tag keeps telling the truth.
#
# WHAT THIS SUITE PROVES: each of the lint's three checks fires on the thing it
# is for and stays quiet on the thing it is not for. The quiet half carries the
# real weight — a lint that condemns `test-cp1-gate.sh` for containing "p1", or
# that reads a 47-line header as untagged, is a lint people switch off.
#
# Fixture suites are written with printf, never a heredoc: bats parses `@test`
# line by line and knows nothing about heredocs (IMP-494).
#
# Result count after any edit:
#   bats --tap test-aid-test-tier-lint.bats | grep -cE '^(ok|not ok)'   # == 10

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  LINT="$AID_PLUGIN_PATH/scripts/aid-test-tier-lint.sh"
  export AID_PLUGIN_PATH LINT
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  FIXTURE_TESTS="$TEST_TMPDIR/suites"
  ALLOWLIST="$TEST_TMPDIR/allowlist.txt"
  JOURNAL="$ROOT/.aid-o/work/test-durations.jsonl"
  export TEST_TMPDIR ROOT FIXTURE_TESTS ALLOWLIST JOURNAL
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT"
  mkdir -p "$FIXTURE_TESTS/bats"
  : > "$ALLOWLIST"
  cd "$ROOT"
  _tagged test-aid-test-durations.bats t0
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# _tagged <name> <tier> — a discovered suite declaring <tier>.
_tagged() {
  printf '#!/usr/bin/env bats\n# aid-tier: %s\n' "$2" > "$FIXTURE_TESTS/bats/$1"
}

# _untagged <name> — a discovered suite with a header but no tag.
_untagged() {
  printf '#!/usr/bin/env bats\n# a suite that forgot\n' > "$FIXTURE_TESTS/bats/$1"
}

_measure() {
  jq -nc --arg s "$1" --argjson d "$2" --argjson c "$3" \
    '{suite:$s, runner:"bats", duration_ms:$d, cases:$c, exit_code:0,
      source:"bats_timing", censored:false, host:"h", at:"2026-08-10T00:00:00Z"}' \
    >> "$JOURNAL"
}

_lint() { bash "$LINT" --tests-dir "$FIXTURE_TESTS" --allowlist "$ALLOWLIST" "$@"; }

@test "1: a tagged, well-named, affordable tree is clean" {
  _measure test-aid-test-durations.bats 500 1
  run _lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "2: an untagged suite fails the lint, naming the file" {
  _untagged test-aid-test-tier.bats
  run _lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"test-aid-test-tier.bats"* ]]
  [[ "$output" == *"no '# aid-tier:' tag"* ]]
}

@test "3: an unknown tier value fails, naming the accepted set" {
  _tagged test-aid-test-tier.bats t9
  run _lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown tier"* ]]
  [[ "$output" == *"t0 t1 t2"* ]]
}

@test "4: two tags is a contradiction, never first-wins" {
  printf '#!/usr/bin/env bats\n# aid-tier: t0\n# aid-tier: t2\n' \
    > "$FIXTURE_TESTS/bats/test-aid-test-tier.bats"
  run _lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicated"* ]]
}

@test "5: a 47-line leading header is read correctly, not as untagged" {
  {
    printf '#!/usr/bin/env bats\n'
    printf '# aid-tier: t1\n'
    for _ in $(seq 1 46); do printf '# prose about what this suite proves\n'; done
    printf '\n'
  } > "$FIXTURE_TESTS/bats/test-aid-test-tier.bats"
  run _lint
  [ "$status" -eq 0 ]
}

@test "6: a plan-numbered filename fails unless it is allowlisted" {
  _tagged test-p999-example.bats t2
  run _lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan/EPIC/task number"* ]]

  printf 'test-p999-example.bats\n' > "$ALLOWLIST"
  run _lint
  [ "$status" -eq 0 ]
}

@test "7: a missing allowlist means NO exceptions, never allow-everything" {
  _tagged test-p999-example.bats t2
  run bash "$LINT" --tests-dir "$FIXTURE_TESTS" --allowlist "$TEST_TMPDIR/absent.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan/EPIC/task number"* ]]
}

@test "8: a checkpoint name like cp1 is not a plan number" {
  printf '#!/usr/bin/env bash\n# aid-tier: t0\n' > "$FIXTURE_TESTS/test-cp1-gate.sh"
  run _lint
  [ "$status" -eq 0 ]
}

@test "9: a tier cheaper than its measurement supports is a violation" {
  _tagged test-aid-test-tier.bats t0
  _measure test-aid-test-durations.bats 100 1
  _measure test-aid-test-tier.bats 45000 1
  run _lint
  [ "$status" -eq 1 ]
  [[ "$output" == *"declares t0 but its newest measurement supports no cheaper than t2"* ]]
}

@test "10: a tier MORE expensive than its cost is fine, and unmeasured is unverified" {
  _tagged test-aid-test-tier.bats t2
  _measure test-aid-test-tier.bats 10 1
  run _lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIED"* ]]
  [[ "$output" == *"test-aid-test-durations.bats (t0)"* ]]
}
