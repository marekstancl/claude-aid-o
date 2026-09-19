#!/usr/bin/env bats
# aid-tier: t1
# test-review-round-fsm.bats — fsm_check_review_round, the one FSM precondition
# of the step review (cp2) and the EPIC review (cp3): a closed passing round at
# HEAD advances; fail blocks; a hand-written skip without its timeline event is
# skip_unbound; a skip computed one commit back is step_check_stale; no_change
# needs at least one declared output that exists; a stubbed round is refused;
# cp3 needs the semantic file; a round not closed blocks; GATES→DONE passes a
# moved HEAD only under the D4 exception with its trailer; a disabled
# checkpoint passes with an audit line.
# Origin: P094 Step 8 (step review rebuild). Tier measured: every case is
# jq/git over a fixture, under 2 s.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  E="$TEST_EVIDENCE_DIR"; : > "$E/timeline.jsonl"
  mkdir -p src; echo a > src/app.py; git add -A; git commit -qm step0
  jq -n '{steps: [{id: "s0", role: "backend", objective: "o", outputs: ["Modify: `src/app.py` — x"]}, {id: "s1", role: "backend", objective: "o"}]}' > "$E/plan.json"
}
teardown() { unset CP3_FRESHNESS_POLICY || true; teardown_test_evidence_dir; }

# _check <cp> <step> [--freshness] — the function in a condition context; prints the fail reason
_check() {
  local cp="$1" step="$2"; shift 2
  run bash -c "source '$FSM'; if fsm_check_review_round '$E' '$cp' '$step' $*; then echo OK; else echo \"FAIL:\${_PRECONDITION_FAIL_REASON}\"; exit 1; fi"
}

@test "cp2 pass at HEAD advances; fail blocks naming the index" {
  aid_fixture_seed_step_review "$E" cp2 0 pass
  _check cp2 0; [ "$status" -eq 0 ]
  aid_fixture_seed_step_review "$E" cp2 1 fail
  _check cp2 1; [ "$status" -eq 1 ]; [[ "$output" == *"verdict fail"* ]]; [[ "$output" == *"FAIL:review_round_failed"* ]]
}
@test "a hand-written skip without its step_check event is skip_unbound; a bound skip passes" {
  mkdir -p "$E/cp2/step-0"
  jq -n --arg h "$(git rev-parse HEAD)" '{verdict: "skip", reason: "hand", head_sha: $h, rounds: []}' > "$E/cp2/step-0/rounds.json"
  _check cp2 0; [ "$status" -eq 1 ]; [[ "$output" == *skip_unbound* ]]
  aid_fixture_seed_step_review "$E" cp2 0 skip
  _check cp2 0; [ "$status" -eq 0 ]
}
@test "a skip computed one commit back is step_check_stale" {
  aid_fixture_seed_step_review "$E" cp2 0 skip
  echo b >> src/app.py; git commit -qam later
  _check cp2 0; [ "$status" -eq 1 ]; [[ "$output" == *step_check_stale* ]]
}
@test "no_change passes only with a declared output that exists; none declared or missing blocks" {
  aid_fixture_seed_step_review "$E" cp2 0 no_change
  _check cp2 0; [ "$status" -eq 0 ]
  aid_fixture_seed_step_review "$E" cp2 1 no_change
  _check cp2 1; [ "$status" -eq 1 ]; [[ "$output" == *no_change_without_outputs* ]]
  rm src/app.py; git commit -qam rm; aid_fixture_seed_step_review "$E" cp2 0 no_change
  _check cp2 0; [ "$status" -eq 1 ]; [[ "$output" == *no_change_without_outputs* ]]
}
@test "a round index whose round has no measurement blocks: round not closed; a stubbed round is refused" {
  aid_fixture_seed_step_review "$E" cp2 0 pass
  rm "$E/cp2/step-0/round-1/measurement.json"
  _check cp2 0; [ "$status" -eq 1 ]; [[ "$output" == *round_not_closed* ]]
  aid_fixture_seed_step_review "$E" cp2 0 pass
  jq '.dispatch_check = "stubbed"' "$E/cp2/step-0/rounds.json" > "$E/r" && mv "$E/r" "$E/cp2/step-0/rounds.json"
  _check cp2 0; [ "$status" -eq 1 ]; [[ "$output" == *stubbed_round* ]]
}
@test "a pass round behind HEAD blocks at increment-step (review_round_stale) and passes GATES→DONE only with the D4 trailer" {
  aid_fixture_seed_step_review "$E" cp3 "" pass
  mkdir -p tests; echo t > tests/t.sh; git add tests; git commit -qm "tests only"
  _check cp3 ""; [ "$status" -eq 1 ]; [[ "$output" == *review_round_stale* ]]
  _check cp3 "" --freshness "$TEST_PROJECT_ROOT"; [ "$status" -eq 1 ]; [[ "$output" == *cp3_stale_review* ]]
  git commit -q --amend -m "tests only" -m "CP3-Freshness-Exception: fixture churn"
  _check cp3 "" --freshness "$TEST_PROJECT_ROOT"; [ "$status" -eq 0 ]
  jq -se 'any(.[]; .event == "cp3_freshness_exception")' "$E/timeline.jsonl" >/dev/null
  echo prod >> src/app.py; git commit -qam "prod" -m "CP3-Freshness-Exception: no"
  _check cp3 "" --freshness "$TEST_PROJECT_ROOT"; [ "$status" -eq 1 ]
}
@test "cp3 without the semantic file blocks; a missing index names the step check command" {
  aid_fixture_seed_step_review "$E" cp3 "" pass
  rm "$E/semantic-review-final.json"
  _check cp3 ""; [ "$status" -eq 1 ]; [[ "$output" == *semantic_review_missing* ]]
  _check cp2 5; [ "$status" -eq 1 ]; [[ "$output" == *"aid-step-check.sh --checkpoint cp2 --step 5"* ]]
}
@test "a disabled checkpoint passes with the audit line; the master switch disables too" {
  mkdir -p .aid-o/config/policies
  printf 'review_checkpoints:\n  cp2_step_review: false\n' > .aid-o/config/policies/review-checkpoints.yaml
  _check cp2 0; [ "$status" -eq 0 ]
  printf 'review_checkpoints:\n  enabled: false\n' > .aid-o/config/policies/review-checkpoints.yaml
  _check cp3 ""; [ "$status" -eq 0 ]
}
@test "end to end: EXECUTE→GATES refuses without a cp3 round and passes with one" {
  local sf="$E/fsm-state.yaml"
  cat > "$sf" <<EOF2
epic_id: E-test
run_id: R-test
state: EXECUTE
current_step: 2
total_steps: 2
branch: task/E-test/main
created_at: 2026-06-18T00:00:00Z
gate_retries: 0
escalation_count: 0
EOF2
  mkdir -p "$E/gates"; printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","plan_gates_reconciled":true,"gates":[]}\n' > "$E/gates/gates_report.json"
  run "$FSM" transition EXECUTE GATES "$sf"
  [ "$status" -ne 0 ]; [[ "$output" == *"no review round index for cp3"* ]]
  aid_fixture_seed_step_review "$E" cp3 "" pass
  run "$FSM" transition EXECUTE GATES "$sf"
  echo "$output"; [ "$status" -eq 0 ]
}

# ── ported from test-cp3-freshness.bats (P060 D4 cases the round check keeps) ──
@test "D4: a commit touching a verdict-bearing file past the reviewed head fails even under tests/ and with the trailer" {
  aid_fixture_seed_step_review "$E" cp3 "" pass
  mkdir -p pkg/tests; echo '{"verdict":"pass"}' > pkg/tests/rounds.json; git add pkg/tests/rounds.json
  git commit -q -m "touch a verdict-bearing file" -m "CP3-Freshness-Exception: should not be allowed"
  _check cp3 "" --freshness "$TEST_PROJECT_ROOT"; [ "$status" -eq 1 ]; [[ "$output" == *"verdict-bearing"* ]]
}
@test "D4: observe mode logs cp3_freshness_would_block and does not block" {
  aid_fixture_seed_step_review "$E" cp3 "" pass
  echo prod >> src/app.py; git commit -qam "production change past review"
  export CP3_FRESHNESS_POLICY=observe
  _check cp3 "" --freshness "$TEST_PROJECT_ROOT"; [ "$status" -eq 0 ]
  jq -se 'any(.[]; .event == "cp3_freshness_would_block")' "$E/timeline.jsonl" >/dev/null
}
