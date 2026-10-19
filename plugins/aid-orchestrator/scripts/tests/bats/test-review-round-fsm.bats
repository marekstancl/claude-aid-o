#!/usr/bin/env bats
# aid-tier: t1
# test-review-round-fsm.bats — fsm_check_review_round, the one FSM precondition
# of the step review (cp2): a closed passing round at
# HEAD advances; fail blocks; a hand-written skip without its timeline event is
# skip_unbound; a skip computed one commit back is step_check_stale; no_change
# needs at least one declared output that exists; a stubbed round is refused;
# a round not closed blocks; a disabled checkpoint passes with an audit line.
# (The EPIC review, CP3, its semantic-file rule and the D4 freshness exception
# left in 3.0.0, P114.)
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
  mkdir -p .aid-o/config/policies; echo '.aid-o/config/policies/' >> "$(git rev-parse --git-dir)/info/exclude"
}
teardown() { teardown_test_evidence_dir; }

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
@test "review_round_stale names the confirmation round as next, and its row" {
  aid_fixture_seed_step_review "$E" cp2 0 pass
  echo b >> src/app.py; git commit -qam fix
  _check cp2 0; [ "$status" -eq 1 ]
  [[ "$output" == *"next: bash $AID_PLUGIN_PATH/scripts/aid-step-check.sh --checkpoint cp2 --step 0 --evidence-dir $E && bash $AID_PLUGIN_PATH/scripts/aid-review-round.sh prepare --checkpoint cp2 --step 0 --evidence-dir $E --round 2"* ]]
  [[ "$output" == *"(pipeline.md §When AID refuses: review_round_stale)"* ]]
}
@test "drift: every measured reason has a row in pipeline.md and, where a script prints it, a next: line" {
  # P109 Step 7: four scripts print refusal codes. aid-fsm.sh through the arms
  # of _fsm_refusal_next (as before); aid-review-round.sh, aid-cp1-gate.sh and
  # lib/aid-plan-review-packet.sh at the refusal site — a `next:` within the
  # three lines that end with the code's `(pipeline.md §When AID refuses: …)`
  # suffix. A fixture reason no scanned script prints stays row-only.
  local tsv="$AID_PLUGIN_PATH/scripts/tests/fixtures/refusals/measured-2026-09.tsv"
  local table="$AID_PLUGIN_PATH/skills/pipeline.md" arms r missing="" f ln
  local -a sites=("$AID_PLUGIN_PATH/scripts/aid-review-round.sh" "$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh" "$AID_PLUGIN_PATH/scripts/lib/aid-plan-review-packet.sh"
                  "$AID_PLUGIN_PATH/scripts/aid-run-gates.sh" "$AID_PLUGIN_PATH/scripts/aid-plan-diff.sh" "$AID_PLUGIN_PATH/scripts/aid-release-policy.sh"   # + P110
                  "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh" "$AID_PLUGIN_PATH/scripts/lib/aid-dispatch-contract.sh"
                  "$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh" "$AID_PLUGIN_PATH/defaults/hooks/pre-commit")   # + P111
  arms="$(sed -n '/^_fsm_refusal_next()/,/^}/p' "$FSM")"
  while IFS=$'\t' read -r _ _ r; do
    r="${r%%_[0-9]*}"   # gates_runner_exit_1 → its row gates_runner_exit_<n>
    grep -q "\`${r}" "$table" || missing+=" row:$r"
    if grep -q "$r" "$FSM"; then [[ "$arms" == *"$r"* ]] || missing+=" next:$r"; fi
    for f in "${sites[@]}"; do
      while IFS=: read -r ln _; do
        [[ -n "$ln" ]] || continue
        sed -n "$(( ln > 2 ? ln - 2 : 1 )),${ln}p" "$f" | grep -q 'next:' || missing+=" next:$r@${f##*/}:$ln"
      done < <(grep -n "When AID refuses: ${r})" "$f")
    done
  done < <(grep -v '^#' "$tsv")
  # and the other direction: every code those three scripts print is in the
  # fixture and has its row — a new refusal cannot skip both
  local code
  while IFS= read -r code; do
    grep -qP "\t${code}$" "$tsv" || missing+=" fixture:$code"
    grep -q "\`${code}" "$table" || missing+=" row:$code"
  done < <({ grep -ohE 'When AID refuses: [a-z_]+\)' "${sites[@]}" | sed -E 's/.*: ([a-z_]+)\)/\1/'
              # a code handed to a refusal helper (_pr_refuse / _dlg_refuse <code> …) prints through "$1" (AID 12. 10. 2026)
              grep -ohE '_(pr|dlg)_refuse [a-z][a-z_]+' "${sites[@]}" | sed -E 's/.* //'; } | sort -u)
  [[ -z "$missing" ]] || { echo "missing:$missing"; false; }
}
@test "a disabled checkpoint passes with the audit line; the master switch disables too" {
  mkdir -p .aid-o/config/policies
  printf 'review_checkpoints:\n  cp2_step_review: false\n' > .aid-o/config/policies/review-checkpoints.yaml
  _check cp2 0; [ "$status" -eq 0 ]
  printf 'review_checkpoints:\n  enabled: false\n' > .aid-o/config/policies/review-checkpoints.yaml
  _check cp2 0; [ "$status" -eq 0 ]
}

@test "without yq the precondition fails loudly instead of enforcing from an unread file" {
  aid_fixture_seed_step_review "$E" cp2 0 pass
  # a PATH that is the real one minus yq — naming a few directories by hand
  # rots, and the function reaches for a dozen tools besides yq
  local nobin="$BATS_TEST_TMPDIR/nobin" d f; mkdir -p "$nobin"
  local IFS=:
  for d in $PATH; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*; do
      [[ -x "$f" && ! -d "$f" ]] || continue
      [[ "${f##*/}" == yq ]] && continue
      [[ -e "${nobin}/${f##*/}" ]] || ln -s "$f" "${nobin}/${f##*/}"
    done
  done
  unset IFS
  PATH="$nobin" _check cp2 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"yq is not installed"* ]]
  [[ "$output" == *"FAIL:yq_missing"* ]]
}
