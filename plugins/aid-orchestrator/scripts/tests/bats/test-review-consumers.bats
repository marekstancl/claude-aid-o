#!/usr/bin/env bats
# aid-tier: t2
# test-review-consumers.bats — the EPIC-scoped semantic-review-final.json a real
# cp3 `close` writes is read by its two consumers where they always read it:
# the FSM's routed-findings reconciliation (aid-fsm.sh
# _fsm_routed_findings_check, which since P094 Step 7 REFUSES a closed cp3
# round without the file and passes a skipped one with an audit line) and the
# release policy's required-input row (aid-release-policy.sh). Cross-component
# by design (round engine → FSM, round engine → release policy), so t2 whatever
# it costs. The plan-finalize --stage produce case (review-profile.json after
# P094 Step 14) is added by that step.
# Origin: P094 Step 7.

load test-helpers.bash

setup() {
  export TZ=UTC AID_TEST_MODE=1 AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=pass
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  ROUND_SH="$AID_PLUGIN_PATH/scripts/aid-review-round.sh"
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  FIX="$AID_PLUGIN_PATH/scripts/tests/fixtures/release-policy"
  TEST_TMPDIR="$(mktemp -d)"; export TEST_TMPDIR
  ROOT="$TEST_TMPDIR/project"
  unset AID_PROJECT_ROOT AID_PLAN_STATE_PROJECT_ROOT
  EPIC="E-059-2_2"; RUN="R-E059-2_2-1"
  EV="$ROOT/.aid-o/work/evidence/$EPIC/$RUN"
  aid_test_mk_repo "$ROOT" "$ROOT/.aid-o/work/plan-state" "$ROOT/.aid-o/config" "$EV" "$ROOT/src"
  cp "$FIX/config/execution.yaml" "$ROOT/.aid-o/config/execution.yaml"
  cp "$FIX/config/permissions-auto.yaml" "$ROOT/.aid-o/config/permissions.yaml"
  mkdir -p "$ROOT/.aid-o/config/policies"
  yq '.review_checkpoints.epic_review.rounds_default = 1 | .review_checkpoints.epic_review.reviewers = [{"role":"epic_generalist","provider":"claude","model":"opus"}]' \
     "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  BASE_SHA="$(git -C "$ROOT" rev-parse HEAD)"
  echo base > "$ROOT/src/app.py"; git -C "$ROOT" add src; git -C "$ROOT" commit -qm s0
  seq 1 60 >> "$ROOT/src/app.py"; git -C "$ROOT" add src; git -C "$ROOT" commit -qm work
  printf 'epic_id: %s\nrun_id: %s\nstate: DONE\ndone_phase: review\ncurrent_step: 1\ntotal_steps: 1\npm_decision: merge\nbase_commit: %s\nbranch: task/%s/main\nstreamlined_mode: false\n' \
    "$EPIC" "$RUN" "$BASE_SHA" "$EPIC" > "$EV/fsm-state.yaml"
  jq -n '{steps: [{id: "s0", role: "backend", objective: "x", acceptance_criteria: ["y"], outputs: ["Modify: `src/app.py` — x"], allowed_paths: ["src/app.py"]}]}' > "$EV/plan.json"
  printf '{"ts":"2026-09-19T00:00:00Z","event":"run_started"}\n' > "$EV/timeline.jsonl"
}
teardown() { cd /; [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"; return 0; }

# _cp3_round <evidence path of the finding> — a real cp3 round with one major from epic_generalist, closed
_cp3_round() {
  (cd "$ROOT" && bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp3 --evidence-dir "$EV") >/dev/null
  local args=(--checkpoint cp3 --evidence-dir "$EV" --project-root "$ROOT") d="$EV/cp3/round-1"
  "$ROUND_SH" prepare "${args[@]}" --round 1 >/dev/null
  jq -n --arg ev "$1" '{role: "epic_generalist", checkpoint: "cp3", findings: [{id: "e-1", checkpoint: "cp3", step: 0, severity: "major", claim: "the file is unfinished", command: "grep -n x src/app.py", evidence: $ev, fix: "finish"}]}' > "$d/reviewer-epic_generalist.json"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus cp3-epic-generalist --agent-id aid-orchestrator:review --evidence-dir "$d" >/dev/null
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus cp3-epic-generalist --output-file "$d/reviewer-epic_generalist.json" --evidence-dir "$d" >/dev/null
  "$ROUND_SH" collect "${args[@]}" --round 1 >/dev/null
  "$ROUND_SH" close "${args[@]}" --round 1 --tokens epic_generalist=3
}
_reconcile() { run bash -c "cd '$ROOT' && source '$FSM' && _fsm_routed_findings_check '$EPIC' '$EV'" 3>&-; }

@test "the semantic file a cp3 close wrote is what the FSM reconciliation reads: the routed finding blocks, the file's absence after a closed round refuses, and a resolved route passes" {
  run _cp3_round "src/app.py:3"; echo "$output"; [ "$status" -eq 0 ]
  [ -f "$EV/semantic-review-final.json" ]
  local fp; fp="$(jq -r '.semantic_review.findings[0].fingerprint' "$EV/semantic-review-final.json")"
  # consumer half: close routed the major to this EPIC, so completion is refused by fingerprint
  _reconcile; [ "$status" -eq 1 ]; [[ "$output" == *"$fp"* ]]; [[ "$output" == *"routed epic:${EPIC}"* ]]
  # the producer's file gone after a closed round: refused, naming the close command
  mv "$EV/semantic-review-final.json" "$TEST_TMPDIR/srf.json"
  _reconcile; [ "$status" -eq 1 ]; [[ "$output" == *"semantic-review-final.json is missing"* ]]; [[ "$output" == *"close --checkpoint cp3"* ]]
  mv "$TEST_TMPDIR/srf.json" "$EV/semantic-review-final.json"
  # the PM resolves the route: the finding's target is inside the steps' scope, so nothing else is owed
  bash -c "cd '$ROOT' && source '$AID_PLUGIN_PATH/scripts/lib/aid-routed-findings.sh' && aid_finding_resolve P059 '$fp' 'fixed in a follow-up commit'"
  _reconcile; echo "$output"; [ "$status" -eq 0 ]
}
@test "a skipped cp3 (no reviewer ran) passes the reconciliation without the file and leaves an audit line" {
  git -C "$ROOT" reset -q --hard HEAD~1; echo tiny >> "$ROOT/src/app.py"; git -C "$ROOT" commit -qam tiny
  (cd "$ROOT" && bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp3 --evidence-dir "$EV") >/dev/null
  [ "$(jq -r .verdict "$EV/cp3/rounds.json")" = skip ]
  [ ! -f "$EV/semantic-review-final.json" ]
  _reconcile; echo "$output"; [ "$status" -eq 0 ]
  grep -q cp3_reconciliation_skipped "$ROOT/.aid-o/work/audit-log.jsonl"
}
@test "the release policy reads the written file as a present required input, not a blocker" {
  run _cp3_round "src/app.py:3"; [ "$status" -eq 0 ]
  local f
  for f in review-profile.json acceptance-evidence.json gates_report.json epic_input.md; do cp "$FIX/pack/$f" "$EV/$f"; done
  local head; head="$(git -C "$ROOT" rev-parse HEAD)"
  for f in review-profile.json acceptance-evidence.json; do
    jq --arg h "$head" '.revision.head_sha = $h' "$EV/$f" > "$EV/$f.tmp" && mv "$EV/$f.tmp" "$EV/$f"
  done
  mkdir -p "$ROOT/.aid-o/work/evidence/P059-release-policy/generation"
  jq -n --arg h "$head" '{cp1: {verdict: "pass"}, target_head: $h}' > "$ROOT/.aid-o/work/evidence/P059-release-policy/generation/generation-authority.json"
  run env AID_PLUGIN_PATH="$AID_PLUGIN_PATH" AID_PROJECT_ROOT="$ROOT" bash "$AID_PLUGIN_PATH/scripts/aid-release-policy.sh" "$EPIC" "$RUN" --out "$EV/release-decision.json"
  echo "$output"
  [ -f "$EV/release-decision.json" ]
  [ "$(jq -r '.release_decision.inputs[] | select(.id == "semantic_review_final") | .verdict' "$EV/release-decision.json")" != blocked ]
  jq -e '.release_decision.blockers | any(.input_id == "semantic_review_final") | not' "$EV/release-decision.json" >/dev/null
  [ "$(jq -r '.release_decision.inputs[] | select(.id == "semantic_review_final") | .head_match' "$EV/release-decision.json")" = true ]
}
