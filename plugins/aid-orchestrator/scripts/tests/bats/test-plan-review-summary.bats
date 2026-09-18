#!/usr/bin/env bats
# aid-tier: t0
# test-plan-review-summary.bats — the /aid-status line for a plan's review rounds.
# Known tokens are summed, unknown ones are counted and never summed as zero,
# roles that did not answer are named, and absent or legacy evidence says so.
# Origin: P093 Step 10 (plan review rebuild).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-review-summary.sh"
  ROOT="$(mktemp -d)"
  EV="$ROOT/.aid-o/work/evidence/P900"
}
teardown() { rm -rf "$ROOT"; }

# _measure <round> <reviewers-json> [degraded]
_measure() {
  mkdir -p "$EV/cp1/round-$1"
  jq -n --argjson r "$2" --argjson d "${3:-false}" '{reviewers: $r, degraded: $d}' > "$EV/cp1/round-$1/measurement.json"
}

@test "summary: two rounds with known tokens are summed" {
  _measure 1 '{"generalist_a": {"tokens": 100, "answered": true}, "reuse": {"tokens": 50, "answered": true}}'
  _measure 2 '{"reuse": {"tokens": 25, "answered": true}}'
  [ "$(aid_plan_review_summary P900 "$ROOT")" = "review: 2 rounds, 175 tokens, 0 unknown, missing: none, degraded: no" ]
}
@test "summary: an unknown value is counted, not added; a missing role is named; degraded shows" {
  _measure 1 '{"generalist_a": {"tokens": 100, "answered": true}, "generalist_b": {"tokens": "unknown", "answered": false, "reason": "codex_absent"}}' true
  [ "$(aid_plan_review_summary P900 "$ROOT")" = "review: 1 round, 100 tokens, 1 unknown, missing: generalist_b, degraded: yes" ]
}
@test "summary: a round without measurement is not closed; an unreadable one says so" {
  _measure 1 '{"generalist_a": {"tokens": 10, "answered": true}}'
  mkdir -p "$EV/cp1/round-2"
  [[ "$(aid_plan_review_summary P900 "$ROOT")" == *", round 2 not closed" ]]
  echo "{}" > "$EV/cp1/round-2/measurement.json"
  [ "$(aid_plan_review_summary P900 "$ROOT")" = "review: 2 rounds, measurement unreadable (round 2)" ]
}
@test "summary: no cp1 directory is none; an old cp1-deep directory is legacy evidence" {
  [ "$(aid_plan_review_summary P900 "$ROOT")" = "review: none" ]
  mkdir -p "$EV/cp1-deep"
  [ "$(aid_plan_review_summary P900 "$ROOT")" = "review: legacy evidence" ]
}
