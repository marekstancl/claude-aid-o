#!/usr/bin/env bats
# aid-tier: t0
# test-review-summary.bats — the /aid-status lines for a checkpoint's review
# rounds and for an EPIC's step reviews, and the USD figure behind them.
# Known tokens are summed, unknown ones are counted and never summed as zero,
# roles that did not answer are named, absent or legacy evidence says so, a
# known model and count give a known USD from a fixture table, an unlisted
# model is "unknown" and the total says "+ N unknown".
# Origin: P094 Step 11 (generalised from test-plan-review-summary.bats, P093).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-review-summary.sh"
  ROOT="$(mktemp -d)"
  export AID_PROJECT_ROOT="$ROOT"
  EV="$ROOT/.aid-o/work/evidence/P900"
  RUN="$ROOT/.aid-o/work/evidence/E-900-1_1/R-1"
  mkdir -p "$ROOT/.aid-o/config"
  cat > "$ROOT/.aid-o/config/prices.yaml" <<'YAML'
version: 1
models:
  opus:   {input: 5, output: 25, cache_read: 0.5, cache_write: 6.25, blended: 16.4, source: fixture, as_of: "2026-09-19"}
  sonnet: {input: 2, output: 10, cache_read: 0.2, cache_write: 2.5, blended: 6.56, source: fixture, as_of: "2026-09-19"}
YAML
}
teardown() { rm -rf "$ROOT"; }

# _measure <cp dir> <round> <reviewers-json> [degraded]
_measure() {
  mkdir -p "$1/round-$2"
  jq -n --argjson r "$3" --argjson d "${4:-false}" '{reviewers: $r, degraded: $d}' > "$1/round-$2/measurement.json"
}

@test "usd: a known model and count give a known figure; an unlisted model, a missing count and a missing table are unknown" {
  [ "$(aid_review_usd opus 1000000 100000 2000000 0)" = "8.5000" ]
  [ "$(aid_review_usd sonnet 500000 50000 0 100000)" = "1.7500" ]
  [ "$(aid_review_usd_blended opus 1000000)" = "16.4000" ]
  [ "$(aid_review_usd gpt-9 10 10 0 0)" = unknown ]
  [ "$(aid_review_usd opus unknown 10 0 0)" = unknown ]
  [ "$(aid_review_usd_blended opus unknown)" = unknown ]
  [ "$(aid_review_prices_file)" = "$ROOT/.aid-o/config/prices.yaml" ]
  rm "$ROOT/.aid-o/config/prices.yaml"
  [ "$(aid_review_prices_file)" = "$AID_PLUGIN_PATH/defaults/prices.yaml" ]
  AID_REVIEW_PRICES=/nonexistent/prices.yaml run aid_review_usd opus 1 1 0 0
  [[ "$output" == unknown ]]
}
@test "summary: two rounds with known tokens and USD are summed" {
  _measure "$EV/cp1" 1 '{"generalist_a": {"tokens": 100, "usd": 0.0016, "answered": true}, "reuse": {"tokens": 50, "usd": 0.0008, "answered": true}}'
  _measure "$EV/cp1" 2 '{"reuse": {"tokens": 25, "usd": 0.0004, "answered": true}}'
  [ "$(aid_review_summary "$EV/cp1")" = "review: 2 rounds, 175 tokens, 0 unknown, 0.0028 USD, missing: none, degraded: no" ]
}
@test "summary: an unknown value is counted, not added; the USD total says + N unknown; a missing role is named; degraded shows" {
  _measure "$EV/cp1" 1 '{"generalist_a": {"tokens": 100, "usd": 0.0016, "answered": true}, "generalist_b": {"tokens": "unknown", "usd": "unknown", "answered": false, "reason": "codex_absent"}}' true
  [ "$(aid_review_summary "$EV/cp1")" = "review: 1 round, 100 tokens, 1 unknown, 0.0016 USD + 1 unknown, missing: generalist_b, degraded: yes" ]
}
@test "summary: a round without measurement is not closed; an unreadable one says so; a failed verdict shows" {
  _measure "$EV/cp1" 1 '{"generalist_a": {"tokens": 10, "usd": 0.0002, "answered": true}}'
  mkdir -p "$EV/cp1/round-2"
  [[ "$(aid_review_summary "$EV/cp1")" == *", round 2 not closed" ]]
  echo "{}" > "$EV/cp1/round-2/measurement.json"
  [ "$(aid_review_summary "$EV/cp1")" = "review: 2 rounds, measurement unreadable (round 2)" ]
  rm -rf "$EV/cp1/round-2"; jq -n '{verdict: "fail", rounds: [{round: 1}]}' > "$EV/cp1/rounds.json"
  [[ "$(aid_review_summary "$EV/cp1")" == *", verdict fail" ]]
}
@test "summary: no directory is none; an old cp1-deep directory is legacy evidence; a skip index is a skip" {
  [ "$(aid_review_summary "$EV/cp1")" = "review: none" ]
  mkdir -p "$EV/cp1-deep"
  [ "$(aid_review_summary "$EV/cp1")" = "review: legacy evidence" ]
  mkdir -p "$RUN/cp2/step-0"; jq -n '{verdict: "skip", reason: "small, clean, in scope", rounds: []}' > "$RUN/cp2/step-0/rounds.json"
  [ "$(aid_review_summary "$RUN/cp2/step-0")" = "review: skip (small, clean, in scope)" ]
}
@test "epic: two step rounds and one cp3 round sum tokens and USD, count skips, and name a step whose round is not closed" {
  mkdir -p "$RUN/cp2/step-0" "$RUN/cp2/step-3/round-1"
  jq -n '{verdict: "skip", reason: "x", rounds: []}' > "$RUN/cp2/step-0/rounds.json"
  _measure "$RUN/cp2/step-1" 1 '{"step_generalist": {"tokens": 1000, "usd": 0.0066, "answered": true}}'
  jq -n '{verdict: "pass"}' > "$RUN/cp2/step-1/rounds.json"
  _measure "$RUN/cp2/step-2" 1 '{"step_generalist": {"tokens": 2000, "usd": "unknown", "answered": true}}'
  jq -n '{verdict: "pass"}' > "$RUN/cp2/step-2/rounds.json"
  jq -n '{verdict: "fail", rounds: [{round: 1}]}' > "$RUN/cp2/step-3/rounds.json"   # prepared, never closed
  _measure "$RUN/cp3" 1 '{"epic_generalist": {"tokens": 5000, "usd": 0.0328, "answered": true}}'
  jq -n '{verdict: "pass"}' > "$RUN/cp3/rounds.json"
  [ "$(aid_epic_review_summary "$RUN")" = "steps: 4 (1 skip, 3 rounds), cp3: pass, 8000 tokens, 0 unknown, 0.0394 USD + 1 unknown, step 3 round 1 not closed" ]
  [ "$(aid_epic_review_summary "$ROOT/nowhere")" = "steps: none reviewed" ]
}
@test "epic: a missing price table is named, exit 0" {
  rm "$ROOT/.aid-o/config/prices.yaml"
  _measure "$RUN/cp3" 1 '{"epic_generalist": {"tokens": 5000, "usd": "unknown", "answered": true}}'
  jq -n '{verdict: "pass"}' > "$RUN/cp3/rounds.json"
  AID_REVIEW_PRICES=/nonexistent/prices.yaml run aid_epic_review_summary "$RUN"
  [ "$status" -eq 0 ]; [[ "$output" == *"prices.yaml missing"* ]]; [[ "$output" == *"USD unknown"* ]]
}
@test "prices: every model the checkpoints name has a source and an as_of in defaults/prices.yaml" {
  local m
  for m in $(grep -oE 'model: [a-z0-9.-]+' "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" | awk '{print $2}' | sort -u); do
    [ -n "$(yq -r ".models[\"$m\"].source // \"\"" "$AID_PLUGIN_PATH/defaults/prices.yaml")" ]
    [ -n "$(yq -r ".models[\"$m\"].as_of // \"\"" "$AID_PLUGIN_PATH/defaults/prices.yaml")" ]
  done
  # while the CP1-only suite existed, this one had to carry at least its cases (P094 Step 14 removed it)
  [ ! -f "$BATS_TEST_DIRNAME/test-plan-review-summary.bats" ] || [ "$(grep -c '^@test' "$BATS_TEST_DIRNAME/test-plan-review-summary.bats")" -le "$(grep -c '^@test' "$BATS_TEST_FILENAME")" ]
}
