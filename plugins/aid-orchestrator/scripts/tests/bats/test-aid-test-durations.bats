#!/usr/bin/env bats
# aid-tier: t0
# test-aid-test-durations.bats — P081 Step 1: the per-suite duration journal.
#
# WHAT THIS SUITE PROVES: a tier is only as honest as the measurement behind
# it, so the journal has to be readable, has to prefer the NEWEST record, and
# has to refuse rather than shrug. The two refusals are the point:
#
#   * no resolvable state root — a durations file written next to whatever
#     directory the caller happened to stand in is a measurement nobody will
#     ever find again;
#   * a malformed line — skipping it makes a suite read as UNMEASURED, which
#     is the exact state that lets an expensive suite keep a cheap tier.
#
# Result count after any edit:
#   bats --tap test-aid-test-durations.bats | grep -cE '^(ok|not ok)'   # == 7

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-test-durations.sh"
  export AID_PLUGIN_PATH LIB
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  export TEST_TMPDIR ROOT
  # AID_DURATIONS_DIR is an ABSOLUTE override that wins over the state root, and
  # the nightly workflow exports it (it points the journal at a shared host path
  # so a CI checkout stops throwing the measurements away every run). bats
  # inherits the environment, so without this line these cases assert the
  # state-root behaviour while the library is writing somewhere else entirely —
  # green on a developer's machine, red every night. Same reason the line below
  # unsets AID_PROJECT_ROOT.
  unset AID_DURATIONS_DIR
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT" "$ROOT/.aid-o/work"
  cd "$ROOT"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_journal() { printf '%s/.aid-o/work/test-durations.jsonl' "$ROOT"; }

@test "1: an appended record reads back with its fields intact" {
  run bash -c 'source "$LIB"
    aid_durations_append test-thing.bats bats 1234 0 bats_timing 7 false
    aid_durations_latest_json test-thing.bats'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.suite'       <<<"$output")" = "test-thing.bats" ]
  [ "$(jq -r '.runner'      <<<"$output")" = "bats" ]
  [ "$(jq -r '.duration_ms' <<<"$output")" = "1234" ]
  [ "$(jq -r '.cases'       <<<"$output")" = "7" ]
  [ "$(jq -r '.source'      <<<"$output")" = "bats_timing" ]
  [ "$(jq -r '.censored'    <<<"$output")" = "false" ]
  [ -n "$(jq -r '.at' <<<"$output")" ]
}

@test "2: the journal lands under the state root, not under \$PWD" {
  mkdir -p "$ROOT/deep/nested"
  run bash -c 'cd "$ROOT/deep/nested"; source "$LIB"
    aid_durations_append test-thing.bats bats 10 0'
  [ "$status" -eq 0 ]
  [ -f "$(_journal)" ]
  [ ! -e "$ROOT/deep/nested/.aid-o" ]
}

@test "3: two records for one suite yield the newer" {
  run bash -c 'source "$LIB"
    aid_durations_append test-thing.bats bats 1000 0
    aid_durations_append test-other.bats bats 9999 0
    aid_durations_append test-thing.bats bats 2000 1
    aid_durations_latest test-thing.bats'
  [ "$status" -eq 0 ]
  [ "$output" = "2000" ]
}

@test "8: aid_durations_by_suite works with NO argument under set -u" {
  # The documented no-argument form was unusable: `"$1"` was unguarded, so
  # every strict-mode caller — which is every script here — died on
  # "$1: unbound variable" before reading a single record. Found from a strict
  # caller in P062 Step 5. The assertion is that it RUNS, not what it counts:
  # the count depends on the journal, the crash did not.
  run bash -c 'set -euo pipefail
    source "'"$BATS_TEST_DIRNAME"'/../../lib/aid-test-durations.sh"
    aid_durations_by_suite >/dev/null'
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
}

@test "4: a suite with no record is reported absent, never as zero" {
  run bash -c 'source "$LIB"
    aid_durations_append test-thing.bats bats 1000 0
    aid_durations_latest test-never-run.bats'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "5: an unresolvable state root refuses loudly instead of guessing a path" {
  run bash -c 'cd "$TEST_TMPDIR"; mkdir -p outside; cd outside; source "$LIB"
    aid_durations_append test-thing.bats bats 10 0'
  [ "$status" -ne 0 ]
  [[ "$output" == *"state root"* ]]
  [ ! -e "$TEST_TMPDIR/outside/.aid-o" ]
}

@test "6: a malformed line fails closed — never read as 'this suite was never measured'" {
  run bash -c 'source "$LIB"
    aid_durations_append test-thing.bats bats 1000 0
    printf "{not json at all\n" >> "'"$(_journal)"'"
    aid_durations_latest test-thing.bats'
  [ "$status" -eq 3 ]
  [[ "$output" == *"malformed"* ]]
}

@test "7: a record missing required fields is malformed too" {
  run bash -c 'source "$LIB"
    printf "{\"suite\":\"test-thing.bats\"}\n" >> "'"$(_journal)"'"
    aid_durations_latest test-thing.bats'
  [ "$status" -eq 3 ]
  [[ "$output" == *"malformed"* ]]
}
