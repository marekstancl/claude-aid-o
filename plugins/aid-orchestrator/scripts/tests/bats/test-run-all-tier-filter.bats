#!/usr/bin/env bats
# aid-tier: t2
# test-run-all-tier-filter.bats — P081 Step 5: the runner executes one tier.
#
# WHAT THIS SUITE PROVES: filtering never hides anything. A suite skipped for
# its tier is COUNTED and printed, an untagged suite inside a tiered tree
# REFUSES the whole run rather than quietly never running, and a tree that has
# never adopted tiers behaves exactly as it does today — that last one is what
# lets a consumer project take a plugin upgrade without its portfolio breaking.
#
# Fixture suites are written with printf, never a heredoc (IMP-494).
#
# FD-3 HYGIENE: bats-inside-bats holds the parent's fd 3, so every inner runner
# invocation closes it (`3>&-`). Result count after any edit:
#   bats --tap test-run-all-tier-filter.bats | grep -cE '^(ok|not ok)'   # == 7

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  export TEST_TMPDIR ROOT
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT"
  TESTS="$(aid_test_mk_runner_tree "$ROOT")"
  RUNNER="$TESTS/run-all-tests.sh"
  export TESTS RUNNER
  cd "$ROOT"
  _suite bats/test-cheap.bats t0
  _suite bats/test-middling.bats t1
  _suite bats/test-heavy.bats t2
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# _suite <relative path> [tier] — a one-case fixture suite, tagged or not.
_suite() {
  local path="$TESTS/$1" tier="${2:-}"
  printf '#!/usr/bin/env bats\n' > "$path"
  [[ -n "$tier" ]] && printf '# aid-tier: %s\n' "$tier" >> "$path"
  printf '@test "%s" { true; }\n' "$(basename "$1")" >> "$path"
}

@test "1: --tier runs only that tier and counts what it skipped" {
  run bash "$RUNNER" --tier t1 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-middling"* ]]
  [[ "$output" != *"Suite 1/1: test-cheap"* ]]
  [[ "$output" == *"SKIPPED-BY-TIER: 2 suite(s) not in t1"* ]]
}

@test "2: no --tier runs everything, exactly as before" {
  run bash "$RUNNER" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"Discovered 3 test suite(s)"* ]]
  [[ "$output" != *"SKIPPED-BY-TIER"* ]]
}

@test "3: an untagged suite in a tiered tree refuses the run, naming file and lint" {
  _suite bats/test-forgotten.bats
  run bash "$RUNNER" 3>&-
  [ "$status" -eq 1 ]
  [[ "$output" == *"test-forgotten.bats"* ]]
  [[ "$output" == *"aid-test-tier-lint.sh"* ]]
}

@test "4: a tree that has never adopted tiers runs everything, refusing nothing" {
  rm -f "$TESTS"/bats/*.bats
  _suite bats/test-untiered-a.bats
  _suite bats/test-untiered-b.bats
  run bash "$RUNNER" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"Discovered 2 test suite(s)"* ]]
}

@test "5: a tier that selects NOTHING is a refusal, not a green run" {
  # Contract flipped by the P081 whole-diff review (2026-08-11). It previously
  # read "an empty tier is a legitimate state, reported and green" — and that
  # is exactly how the shipped consumer gate became a green no-op: a project
  # with no tags matched no tier, ran zero suites and exited 0 under a
  # `required: true` gate. A gate that verifies nothing must not report pass.
  rm -f "$TESTS/bats/test-heavy.bats"
  run bash "$RUNNER" --tier t2 3>&-
  [ "$status" -eq 1 ]
  [[ "$output" == *"selected 0 of"* ]]
  [[ "$output" == *"has no members"* ]]
}

@test "5b: an untiered portfolio told to run a tier says so and refuses" {
  # The consumer case: no suite carries a tag at all, so the untagged refusal
  # never fires and the tier can never match. The message must name that,
  # not merely report an empty tier.
  rm -f "$TESTS"/bats/*.bats "$TESTS"/test-*.sh
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > "$TESTS/bats/test-untagged.bats"
  run bash "$RUNNER" --tier t0 3>&-
  [ "$status" -eq 1 ]
  [[ "$output" == *"carries an '# aid-tier:' tag"* ]]
  [[ "$output" == *"WITHOUT --tier"* ]]
}

@test "6: an unknown tier is a usage error, not an empty run" {
  run bash "$RUNNER" --tier t9 3>&-
  [ "$status" -eq 2 ]
  [[ "$output" == *"accepted: t0 t1 t2"* ]]
}

@test "7: --list carries the tier column, and delegation still wins over tier" {
  _suite bats/test-aid-service.bats t2
  run bash "$RUNNER" --list 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"INLINE: test-cheap.bats [t0]"* ]]
  [[ "$output" == *"DELEGATED: test-aid-service.bats -> service-lib-tests [t2]"* ]]
  [ "$(grep -c 'test-aid-service.bats' <<<"$output")" -eq 1 ]
}
