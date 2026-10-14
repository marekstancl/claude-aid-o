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
  # a plain number (no trailing zeros): jq 1.7 keeps a literal as written
  [ "$(aid_review_usd opus 1000000 100000 2000000 0)" = "8.5" ]
  [ "$(aid_review_usd sonnet 500000 50000 0 100000)" = "1.75" ]
  [ "$(aid_review_usd_blended opus 1000000)" = "16.4" ]
  local n; for n in "0 0:0" "2000000 0:10" "20000000 0:100" "20000 0:0.1" "210000 0:1.05"; do   # opus input 5 USD/M
    [ "$(aid_review_usd opus ${n%%:*} 0 0)" = "${n##*:}" ] || { echo "$n -> $(aid_review_usd opus ${n%%:*} 0 0)"; return 1; }
  done
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
@test "summary: a claude stand-in for a codex role is named right after the round count" {
  _measure "$EV/cp1" 1 '{"generalist_b": {"provider": "claude", "fallback_reason": "usage_limit", "tokens": 10, "usd": 0.0002, "answered": true}}'
  [ "$(aid_review_summary "$EV/cp1")" = "review: 1 round, codex→claude 1×, 10 tokens, 0 unknown, 0.0002 USD, missing: none, degraded: no" ]
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
@test "epic: the step rounds sum tokens and USD, count skips, and name a step whose round is not closed; an old run's EPIC-review directory is not read" {
  mkdir -p "$RUN/cp2/step-0" "$RUN/cp2/step-3/round-1"
  jq -n '{verdict: "skip", reason: "x", rounds: []}' > "$RUN/cp2/step-0/rounds.json"
  _measure "$RUN/cp2/step-1" 1 '{"step_generalist": {"tokens": 1000, "usd": 0.0066, "answered": true}}'
  jq -n '{verdict: "pass"}' > "$RUN/cp2/step-1/rounds.json"
  _measure "$RUN/cp2/step-2" 1 '{"step_generalist": {"tokens": 2000, "usd": "unknown", "answered": true}}'
  jq -n '{verdict: "pass"}' > "$RUN/cp2/step-2/rounds.json"
  jq -n '{verdict: "fail", rounds: [{round: 1}]}' > "$RUN/cp2/step-3/rounds.json"   # prepared, never closed
  _measure "$RUN/cp3" 1 '{"epic_generalist": {"tokens": 5000, "usd": 0.0328, "answered": true}}'
  jq -n '{verdict: "pass"}' > "$RUN/cp3/rounds.json"
  [ "$(aid_epic_review_summary "$RUN")" = "steps: 4 (1 skip, 3 rounds), 3000 tokens, 0 unknown, 0.0066 USD + 1 unknown, step 3 round 1 not closed" ]
  [ "$(aid_epic_review_summary "$ROOT/nowhere")" = "steps: none reviewed" ]
}
@test "epic: a missing price table is named, exit 0" {
  rm "$ROOT/.aid-o/config/prices.yaml"
  _measure "$RUN/cp2/step-0" 1 '{"step_generalist": {"tokens": 5000, "usd": "unknown", "answered": true}}'
  jq -n '{verdict: "pass"}' > "$RUN/cp2/step-0/rounds.json"
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

# ── P110 Step 7: the run and the plan costed ────────────────────────────────
_r() { _measure "$@"; }
@test "cost: aid_plan_run_cost sums two runs (three cp2 rounds; an old EPIC-review round is not counted) and two close attempts, counting rounds and attempts" {
  local e1="$ROOT/.aid-o/work/evidence/E-900-1_2/R-1" e2="$ROOT/.aid-o/work/evidence/E-900-2_2/R-1"
  _r "$e1/cp2/step-0" 1 '{"step_generalist": {"tokens": 1000, "usd": 1.5}}'
  _r "$e1/cp2/step-0" 2 '{"step_generalist": {"tokens": 500, "usd": 0.5}}'
  _r "$e2/cp2/step-1" 1 '{"step_security": {"tokens": 2000, "usd": 2}}'
  _r "$e2/cp3" 1 '{"epic_generalist": {"tokens": 100, "usd": 0.25}}'
  _r "$EV/R-P900-final-1/cp7" 1 '{"final_criteria": {"tokens": 300, "usd": 3}}'
  mkdir -p "$EV/R-P900-final-2/cp7"; _r "$EV/R-P900-final-2/cp7" 1 '{"final_criteria": {"tokens": 200, "usd": 1}}'
  run aid_plan_run_cost "$EV" P900 "$e1" "$e2"; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -c '{usd, tokens, rounds, attempts}' <<< "$output")" = '{"usd":8,"tokens":4000,"rounds":5,"attempts":2}' ]
}
@test "cost: a role with an unknown USD lands in usd_unknown_roles and the known sum is kept" {
  local e1="$ROOT/.aid-o/work/evidence/E-900-1_1/R-1"
  _r "$e1/cp2/step-0" 1 '{"step_generalist": {"tokens": 1000, "usd": 1.5}, "step_security": {"tokens": "unknown", "usd": "unknown"}}'
  run aid_plan_run_cost "$EV" P900 "$e1"
  [ "$(jq -c '{usd, usd_unknown_roles}' <<< "$output")" = '{"usd":1.5,"usd_unknown_roles":["step_security"]}' ]
}
@test "cost: aid_plan_plan_cost sums a CP1 round and a set-aside attempt and prices the Codex critic from its events" {
  _r "$EV/cp1" 1 '{"generalist_a": {"tokens": 1000, "usd": 2}}'
  _r "$EV/cp1/attempt-1" 1 '{"generalist_a": {"tokens": 1000, "usd": 3}}'
  mkdir -p "$EV/critic/plan"
  printf '{"type":"turn.completed","usage":{"input_tokens":1000000,"cached_input_tokens":0,"output_tokens":0}}\n' > "$EV/critic/plan/codex-events.jsonl"
  printf '{"event":"dispatch_start","agent_id":"codex:sonnet"}\n' > "$EV/critic/plan/timeline.jsonl"
  run aid_plan_plan_cost "$EV" P900; echo "$output"
  [ "$(jq -c '{usd, cp1_rounds, critic, critic_reason}' <<< "$output")" = '{"usd":7,"cp1_rounds":2,"critic":{"usd":2,"tokens":1000000,"runs":1},"critic_reason":null}' ]
}
@test "cost: a critic answered by the stand-in leaves no events — critic null with the reason" {
  _r "$EV/cp1" 1 '{"generalist_a": {"tokens": 1000, "usd": 2}}'
  mkdir -p "$EV/critic/plan"
  run aid_plan_plan_cost "$EV" P900
  [ "$(jq -c '{critic, critic_reason}' <<< "$output")" = '{"critic":null,"critic_reason":"stand-in or no events"}' ]
}
@test "cost: aid_review_tokens_from_events returns what dispatch used to compute; an unreadable measurement is measurement_unreadable" {
  printf '{"type":"x"}\n{"type":"turn.completed","usage":{"input_tokens":5,"cached_input_tokens":2,"output_tokens":7}}\n' > "$ROOT/ev.jsonl"
  [ "$(aid_review_tokens_from_events "$ROOT/ev.jsonl")" = '{"tokens_in":5,"cache_read":2,"tokens_out":7}' ]
  mkdir -p "$EV/R-P900-final-1/cp7/round-1"; echo "{broken" > "$EV/R-P900-final-1/cp7/round-1/measurement.json"
  run aid_plan_run_cost "$EV" P900; [ "$status" -eq 3 ]; [[ "$output" == *"measurement_unreadable"* ]]
}
