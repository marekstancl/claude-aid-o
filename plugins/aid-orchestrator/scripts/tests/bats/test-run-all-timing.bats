#!/usr/bin/env bats
# aid-tier: t2
# test-run-all-timing.bats — P081 Step 1: the portfolio runner's timing mode.
#
# WHAT THIS SUITE PROVES: the shipped `bats --timing` parser finally has a
# portfolio caller, and that caller costs nothing when it is not asked for.
# Both halves matter — a timing mode that quietly changed the default run
# would put a measurement on every gate and CI job in the tree.
#
# The runner is exercised over a FIXTURE portfolio (`aid_test_mk_runner_tree`),
# never the live 191-suite one: this is a question about argument handling and
# journal writes, not about the portfolio.
#
# FD-3 HYGIENE: bats-inside-bats holds the parent's fd 3, so every inner runner
# invocation closes it (`3>&-`). Result count after any edit:
#   bats --tap test-run-all-timing.bats | grep -cE '^(ok|not ok)'   # == 6

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
  JOURNAL="$ROOT/.aid-o/work/test-durations.jsonl"
  export TESTS RUNNER JOURNAL
  cd "$ROOT"

  # printf, never a heredoc: bats parses `@test` line by line and knows nothing
  # about heredocs, so a fixture body written with `cat <<EOF` registers phantom
  # tests in THIS file (IMP-494).
  _mk_bats "$TESTS/bats/test-alpha.bats" one:true two:true
  printf '#!/usr/bin/env bash\necho "Results: 3/3 passed, 0 failed"\n' \
    > "$TESTS/test-beta.sh"
}

# _mk_bats <path> <name:body…> — a fixture bats suite, one case per argument.
_mk_bats() {
  local path="$1"; shift
  printf '#!/usr/bin/env bats\n' > "$path"
  local c
  for c in "$@"; do
    printf '@test "%s" { %s; }\n' "${c%%:*}" "${c#*:}" >> "$path"
  done
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_rec() { jq -c --arg s "$1" 'select(.suite == $s)' "$JOURNAL"; }

@test "1: without --timing the runner writes no journal and still passes" {
  run bash "$RUNNER" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
  [ ! -e "$JOURNAL" ]
}

@test "2: --timing records one duration per executed suite" {
  run bash "$RUNNER" --timing 3>&-
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$JOURNAL")" -eq 2 ]
  [ "$(jq -r '.duration_ms' <<<"$(_rec test-alpha.bats)")" -ge 0 ]
  [ "$(jq -r '.duration_ms' <<<"$(_rec test-beta.sh)")" -ge 0 ]
}

@test "3: a bats suite is timed by the runner and carries its case count" {
  run bash "$RUNNER" --timing 3>&-
  [ "$status" -eq 0 ]
  rec="$(_rec test-alpha.bats)"
  [ "$(jq -r '.runner' <<<"$rec")" = "bats" ]
  [ "$(jq -r '.source' <<<"$rec")" = "bats_timing" ]
  [ "$(jq -r '.cases'  <<<"$rec")" = "2" ]
  [ "$(jq -r '.censored' <<<"$rec")" = "false" ]
}

@test "4: a shell suite is bracketed by wall clock and counts as one case" {
  run bash "$RUNNER" --timing 3>&-
  [ "$status" -eq 0 ]
  rec="$(_rec test-beta.sh)"
  [ "$(jq -r '.runner' <<<"$rec")" = "sh" ]
  [ "$(jq -r '.source' <<<"$rec")" = "wallclock" ]
  [ "$(jq -r '.cases'  <<<"$rec")" = "1" ]
}

@test "5: a failing suite is still measured, with its exit code" {
  _mk_bats "$TESTS/bats/test-red.bats" fails:false
  run bash "$RUNNER" --timing 3>&-
  [ "$status" -eq 1 ]
  rec="$(_rec test-red.bats)"
  [ -n "$rec" ]
  [ "$(jq -r '.exit_code' <<<"$rec")" -ne 0 ]
}

@test "6: an untiered run measures every suite, and --include-delegated is an accepted no-op" {
  # Delegation was removed 2026-08-14 (the five "delegated" suites were all t2
  # and their push-triggered CI jobs contradicted the standard). An untiered run
  # is now the whole portfolio, so the suite that used to need the flag is
  # measured without it — and the flag itself must still be ACCEPTED, because a
  # caller this repo cannot see would otherwise exit 2 on an unknown option.
  _mk_bats "$TESTS/bats/test-aid-service.bats"
  run bash "$RUNNER" --timing 3>&-
  [ "$status" -eq 0 ]
  [ -n "$(_rec test-aid-service.bats)" ]

  run bash "$RUNNER" --timing --include-delegated 3>&-
  [ "$status" -eq 0 ]
  [ -n "$(_rec test-aid-service.bats)" ]
}
