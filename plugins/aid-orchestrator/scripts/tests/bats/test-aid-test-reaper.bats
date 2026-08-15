#!/usr/bin/env bats
# aid-tier: t0
# test-aid-test-reaper.bats — P081 Step 11: the way out of the portfolio.
#
# WHAT THIS SUITE PROVES: each candidate class arrives with its own reason,
# the two vetoes hold (a suite that failed recently, and one too young to
# judge, are never proposed), the tool names the input it did NOT have rather
# than implying full coverage, and it deletes nothing.
#
# The last one is asserted mechanically, over the script's own text: a reaper
# that can delete is one nobody dares run monthly.
#
# Result count after any edit:
#   bats --tap test-aid-test-reaper.bats | grep -cE "^(ok|not ok)"   # == 8

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  REAPER="$AID_PLUGIN_PATH/scripts/aid-test-reaper.sh"
  export AID_PLUGIN_PATH REAPER
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  NIGHTLY_DIR="$TEST_TMPDIR/nightly"
  FIXTURE_TESTS="$TEST_TMPDIR/suites"
  SCAN="$TEST_TMPDIR/content-scan.json"
  JOURNAL="$ROOT/.aid-o/work/test-durations.jsonl"
  export TEST_TMPDIR ROOT NIGHTLY_DIR FIXTURE_TESTS SCAN JOURNAL
  # AID_DURATIONS_DIR is an ABSOLUTE override that wins over the state root, and
  # the nightly workflow exports it (it points the journal at a shared host path
  # so a CI checkout stops throwing the measurements away every run). bats
  # inherits the environment, so without this line these cases assert the
  # state-root behaviour while the library is writing somewhere else entirely —
  # green on a developer's machine, red every night. Same reason the line below
  # unsets AID_PROJECT_ROOT.
  unset AID_DURATIONS_DIR
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT"
  mkdir -p "$FIXTURE_TESTS/bats" "$NIGHTLY_DIR"
  cd "$ROOT"
  echo '{"checks":{}}' > "$SCAN"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_suite() { : > "$FIXTURE_TESTS/bats/$1"; }

_measure() {
  jq -nc --arg s "$1" --argjson d "$2" \
    '{suite:$s, runner:"bats", duration_ms:$d, cases:1, exit_code:0,
      source:"bats_timing", censored:false, host:"h", at:"2026-08-10T00:00:00Z"}' \
    >> "$JOURNAL"
}

_reap() { bash "$REAPER" --content-scan "$SCAN" --dir "$NIGHTLY_DIR" \
  --tests-dir "$FIXTURE_TESTS" --repo "$ROOT" --json; }

_reasons() { jq -r --arg s "$1" '.candidates[] | select(.suite == $s) | .reasons | join("; ")'; }

@test "1: a vacuous-green suite is proposed, with that reason" {
  _suite test-vacuous.bats
  jq -n '{checks:{weak_oracle:[{file:"tests/bats/test-vacuous.bats", likely_legitimate:false}]}}' > "$SCAN"
  run _reap
  [ "$status" -eq 0 ]
  [[ "$(_reasons test-vacuous.bats <<<"$output")" == *"vacuous green"* ]]
}

@test "2: a suite the scanner marks legitimately status-only is left alone" {
  _suite test-schema.bats
  jq -n '{checks:{weak_oracle:[{file:"tests/bats/test-schema.bats", likely_legitimate:true}]}}' > "$SCAN"
  run _reap
  [ "$status" -eq 0 ]
  [ "$(jq '.candidates | length' <<<"$output")" -eq 0 ]
}

@test "3: both halves of a duplicate pair are proposed" {
  _suite test-one.bats
  _suite test-two.bats
  jq -n '{checks:{duplicate_test_cases:[{file_a:"a/test-one.bats", file_b:"b/test-two.bats", shared_cases:4}]}}' > "$SCAN"
  run _reap
  [ "$status" -eq 0 ]
  [[ "$(_reasons test-one.bats <<<"$output")" == *"duplicate"* ]]
  [[ "$(_reasons test-two.bats <<<"$output")" == *"duplicate"* ]]
}

@test "4: an expensive suite is proposed with its share of the portfolio" {
  _suite test-heavy.bats
  _suite test-light.bats
  _measure test-heavy.bats 90000
  _measure test-light.bats 1000
  run _reap
  [ "$status" -eq 0 ]
  [[ "$(_reasons test-heavy.bats <<<"$output")" == *"% of the whole portfolio"* ]]
  [ -z "$(_reasons test-light.bats <<<"$output")" ]
}

@test "5: a suite that failed in a recorded nightly is never a candidate" {
  _suite test-heavy.bats
  _measure test-heavy.bats 90000
  jq -n '{date:"2026-08-09", failed:[{suite:"test-heavy", streak:1}]}' \
    > "$NIGHTLY_DIR/2026-08-09.json"
  run _reap
  [ "$status" -eq 0 ]
  [ "$(jq '.candidates | length' <<<"$output")" -eq 0 ]
}

@test "6: a missing input is named, never silently implied to be covered" {
  run bash "$REAPER" --dir "$NIGHTLY_DIR" --tests-dir "$FIXTURE_TESTS" --repo "$ROOT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"content scan"* ]]
  [[ "$output" == *"failure age"* ]]
}

@test "7: a suite committed only days ago is too young to judge" {
  mkdir -p "$ROOT/suites/bats"
  : > "$ROOT/suites/bats/test-fresh.bats"
  git -C "$ROOT" add -A -f && git -C "$ROOT" commit -q -m "add a suite today"
  jq -n '{checks:{weak_oracle:[{file:"suites/bats/test-fresh.bats", likely_legitimate:false}]}}' > "$SCAN"
  run bash "$REAPER" --content-scan "$SCAN" --dir "$NIGHTLY_DIR" \
    --tests-dir "$ROOT/suites" --repo "$ROOT" --json
  [ "$status" -eq 0 ]
  [ "$(jq '.candidates | length' <<<"$output")" -eq 0 ]
}

@test "5b: a failure from years ago is not a permanent shield" {
  _suite test-heavy.bats
  _measure test-heavy.bats 90000
  jq -n '{date:"2020-01-01", failed:[{suite:"test-heavy", streak:1}]}' \
    > "$NIGHTLY_DIR/2020-01-01.json"
  run _reap
  [ "$status" -eq 0 ]
  [[ "$(_reasons test-heavy.bats <<<"$output")" == *"% of the whole portfolio"* ]]
}

@test "6b: a content scan that cannot be parsed is named, not read as empty" {
  _suite test-vacuous.bats
  printf '{ broken\n' > "$SCAN"
  run _reap
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not be read"* ]]
  [ "$(jq '.candidates | length' <<<"$output")" -eq 0 ]
}

@test "8: the reaper proposes only — it contains no removal operation" {
  run grep -nE '(^|[^[:alnum:]_])(rm|git rm|unlink|shred|truncate)[[:space:]]' "$REAPER"
  [ "$status" -ne 0 ]
}
