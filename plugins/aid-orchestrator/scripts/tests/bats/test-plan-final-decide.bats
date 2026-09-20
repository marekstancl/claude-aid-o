#!/usr/bin/env bats
# aid-tier: t2
# The end of a plan, end to end: freeze, gates, produce, the whole-plan round
# (cp7) and decide, on a real git repository per case.
#
#   - the sabotage set (fixtures/plan-final/sabotage/README.md): a healthy plan is
#     decided ready with no waiver; an open blocker, a red gate and an unsettled
#     obligation are each refused with exactly their blocker
#   - a fix after the freeze: what the fix touched decides what is re-run
#   - the switched-off whole-plan review and the PM's waiver
#   - a decision input edited by hand is refused by name
#   - the former stage names say what replaced them
#
# The evidence verifier is stubbed (the double-gated AID_TEST_MODE seam of
# aid-release-policy.sh): its own suites cover it, and it costs ~9 s a call.

load test-helpers.bash

PLAN_ID="P900"

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"; ROUND="$AID_PLUGIN_PATH/scripts/aid-review-round.sh"
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT" AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=pass
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-obligations.sh"
  R="$TEST_PROJECT_ROOT"
}
teardown() { teardown_test_evidence_dir; }

# _project [<yq edit of the review policy>] — main with a plan branch carrying
# one merged EPIC's work, the plan file, a CHANGELOG, a two-gate execution
# config and a sealed plan review. The policy edit lands BEFORE the plan branch.
_project() {
  printf '.aid-o/work/\n.aid-o/reports/\n' > "$R/.gitignore"
  mkdir -p "$R/.aid-o/plans" "$R/.aid-o/config/policies" "$R/docs"
  printf -- '---\nid: %s\ntype: feature\n---\n# Plan\n\n### Step 1: the work\n\n**Acceptance Criteria:**\n- [ ] the app greets\n\n**Effort:** S\n\n## Success Criteria\n\n- it runs\n' "$PLAN_ID" > "$R/.aid-o/plans/${PLAN_ID}-x.md"
  cat > "$R/.aid-o/config/execution.yaml" <<'YAML'
version: '1.0'
gates:
  tests_pass:
    command: "test ! -f break-the-gate"
    required: true
    inputs: ["**", "!docs/**", "!CHANGELOG.md"]
    timeout_seconds: 30
    max_retries: 0
  plan_diff:
    command: "true"
    required: false
    timeout_seconds: 30
    max_retries: 0
gate_profiles:
  release:
    include: [tests_pass, plan_diff]
YAML
  # three claude reviewers, so no codex launcher is needed
  yq ".review_checkpoints.final_review.reviewers |= map(.provider = \"claude\" | .model = \"sonnet\") | ${1:-.}" \
    "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" > "$R/.aid-o/config/policies/review-checkpoints.yaml"
  git -C "$R" add -A; git -C "$R" commit -qm "project"
  local base; base="$(git -C "$R" rev-parse main)"
  git -C "$R" branch "plan/${PLAN_ID}" "$base"
  plan_state_init "$PLAN_ID" plan_branch "plan/${PLAN_ID}" main
  plan_manifest_init "$PLAN_ID" "plan/${PLAN_ID}" main "$base" "$base" plan_branch
  git -C "$R" checkout -q "plan/${PLAN_ID}"
  echo 'print("hello")' > "$R/app.py"; echo "- **Greeting** — the app greets" > "$R/CHANGELOG.md"
  git -C "$R" add -A; git -C "$R" commit -qm "feat: the EPIC's work"
  local ev=".aid-o/work/evidence/E-900-1_1/R-E-900-1_1-1"; mkdir -p "$R/$ev"
  jq -n '{epic_id: "E-900-1_1", steps: [{step_id: "S1", allowed_paths: ["app.py", "CHANGELOG.md", "docs/**"]}]}' > "$R/$ev/plan.json"
  plan_manifest_add_epic "$PLAN_ID" E-900-1_1 R-E-900-1_1-1 task/E-900-1_1/main "$base" "plan/${PLAN_ID}" "$ev" proven
  plan_manifest_set_epic_status "$PLAN_ID" E-900-1_1 merged_to_plan "$(git -C "$R" rev-parse HEAD)"
  mkdir -p "$R/.aid-o/work/evidence/${PLAN_ID}/generation"
  jq -n --arg h "$base" '{cp1: {verdict: "pass"}, target_head: $h}' > "$R/.aid-o/work/evidence/${PLAN_ID}/generation/generation-authority.json"
}
_stage() { run bash "$FSM" plan-finalize "$PLAN_ID" --stage "$1" --project-root "$R" "${@:2}"; }
_field() { jq -r ".plan_boundary_manifest.$1" "$R/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"; }
_run_dir() { printf '%s/%s' "$R" "$(_field plan_final_evidence_dir)"; }
_decision() { jq -r ".release_decision.$1" "$(_run_dir)/release-decision.json"; }
_blockers() { jq -r '[.release_decision.blockers[].input_id] | sort | join(",")' "$(_run_dir)/release-decision.json"; }
# _answer <role> [jq filter] — a no-finding cp7 answer, dispatched like an agent's
_answer() {
  local d; d="$(_run_dir)/cp7/round-${N:-1}"
  jq -n --arg r "$1" '{role: $r, checkpoint: "cp7", findings: [], no_findings_reason: "fixture"}' | jq "${2:-.}" > "$d/reviewer-$1.json"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus "cp7-${1//_/-}" --agent-id aid-orchestrator:review --evidence-dir "$d" >/dev/null
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus "cp7-${1//_/-}" --output-file "$d/reviewer-$1.json" --evidence-dir "$d" >/dev/null
}
# _round [claims filter] — the whole-plan round: every role that was not carried answers
_round() {
  local args=(--checkpoint cp7 --evidence-dir "$(_run_dir)" --project-root "$R" --round "${N:-1}") role tokens=()
  "$ROUND" prepare "${args[@]}" >/dev/null || return 1
  for role in $(jq -r '.reviewers_expected - ((.carried_from // {}) | keys) | .[]' "$(_run_dir)/cp7/round-${N:-1}/round.json"); do
    if [[ "$role" == final_claims ]]; then _answer "$role" "${1:-.}"; else _answer "$role"; fi
    tokens+=("${role}=1000")
  done
  "$ROUND" collect "${args[@]}" >/dev/null || return 1
  "$ROUND" close "${args[@]}" --tokens "${tokens[@]}" >/dev/null
}
# _close_up_to_decide [claims filter] — freeze, gates, produce, the round
_close_up_to_decide() {
  _stage freeze;  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  _stage gates;   [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  _stage produce; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  _round "${1:-.}"
}
_BLOCKER='.findings = [{id: "c-1", checkpoint: "cp7", step: null, severity: "blocker", claim: "the changelog claims a greeting the app never prints", command: "grep -n hello app.py", evidence: "app.py:1", fix: "print it"}] | del(.no_findings_reason)'

# ── the sabotage set ─────────────────────────────────────────────────────────
@test "healthy: decided ready with no waiver, the receipt of version 2 sealed, the PM page shows attempts, minutes and USD" {
  _project
  echo "plan: 2" > "$R/.aid-o/config/counter.yaml"          # AID's own bookkeeping is not dirt
  _close_up_to_decide
  _stage decide; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_decision release_ready)" = true ]; [ "$(_blockers)" = "" ]
  [ "$(_decision merge_mode)" != blocked ]
  [ -z "$(ls "$(_run_dir)"/waiver-*.json 2>/dev/null)" ]; [ ! -e "$(_run_dir)/delivery-report.json" ]
  [ "$(plan_state_get "$PLAN_ID" plan_state)" = AWAITING_PM ]
  local receipt; receipt="$(git -C "$R" show "$(_field plan_final_evidence_ref):receipt.json")"
  [ "$(jq -r .schema_version <<<"$receipt")" = aid-plan-final-evidence-2 ]
  [ "$(jq -c '.outputs | keys' <<<"$receipt")" = '["acceptance-evidence.json","cp7/rounds.json","gates_report.json","plan-diff.json","release-decision.json","review-profile.json","semantic-review-final.json"]' ]
  # the numbers on the page are the numbers in the files
  [ "$(_decision plan_summary.close.attempts)" -eq 1 ]
  local usd; usd="$(jq -s '[.[].reviewers[].usd] | add | . * 10000 | round / 10000' "$(_run_dir)"/cp7/round-*/measurement.json)"
  [ "$(_decision plan_summary.close.usd)" = "$usd" ]
  grep -q "Uzavření:\*\* 1 pokus" "$(_run_dir)/pm-summary.md"
  # deciding twice changes nothing
  _stage decide; [ "$status" -eq 0 ]; [[ "$output" == *"already decided"* ]]
}

@test "open blocker: refused naming the finding; the plan stays in PLAN_REVIEW with the page rendered" {
  _project
  _close_up_to_decide "$_BLOCKER"
  _stage decide; [ "$status" -eq 1 ]
  [ "$(_decision release_ready)" = false ]; [ "$(_blockers)" = final_review ]
  [[ "$(jq -r '.release_decision.blockers[0].reason' "$(_run_dir)/release-decision.json")" == *"a greeting the app never prints"* ]]
  [ "$(plan_state_get "$PLAN_ID" plan_state)" = PLAN_REVIEW ]; [ -s "$(_run_dir)/pm-summary.md" ]
  [[ "$output" == *"--stage freeze"* ]]                       # the refusal names the next command
}

@test "red gate: the gates stage refuses and names the report; nothing is decided" {
  _project
  touch "$R/break-the-gate"; git -C "$R" add -A; git -C "$R" commit -qm "break"
  _stage freeze; [ "$status" -eq 0 ]
  _stage gates; [ "$status" -eq 1 ]; [[ "$output" == *"GATES FAILED"* ]]
  _stage decide; [ "$status" -eq 1 ]; [[ "$output" == *"--stage gates"* ]]
  [ ! -e "$(_run_dir)/release-decision.json" ]
}

@test "unsettled obligation: refused naming it" {
  _project
  aid_obligation_add "$PLAN_ID" release_blocker "the migration order is written down nowhere" "cp3 round-2" >/dev/null
  _close_up_to_decide
  _stage decide; [ "$status" -eq 1 ]
  [ "$(_blockers)" = obligations ]
  [[ "$(jq -r '.release_decision.blockers[0].reason' "$(_run_dir)/release-decision.json")" == *"migration order"* ]]
}

# ── the round is owed ────────────────────────────────────────────────────────
@test "decide before a closed round refuses with the round command; produce before gates names gates" {
  _project
  _stage freeze; _stage produce; [ "$status" -eq 1 ]; [[ "$output" == *"--stage gates"* ]]
  _stage gates; _stage produce; [ "$status" -eq 0 ]; [[ "$output" == *"aid-review-round.sh prepare --checkpoint cp7"* ]]
  _stage decide; [ "$status" -eq 1 ]; [[ "$output" == *"--checkpoint cp7"* ]]
  [ ! -e "$(_run_dir)/release-decision.json" ]
}

@test "the whole-plan review switched off: blocked as final_review_disabled until the PM waives it for this candidate, with the audit entry" {
  _project '.review_checkpoints.cp7_plan_final_review = false'
  _stage freeze; _stage gates; _stage produce; [ "$status" -eq 0 ]
  _stage decide; echo "$output"; [ "$status" -eq 1 ]; [ "$(_blockers)" = final_review ]
  [[ "$(jq -r '.release_decision.blockers[0].reason' "$(_run_dir)/release-decision.json")" == final_review_disabled* ]]
  # a hand-written waiver, or one for another candidate, lifts nothing
  jq -n --arg c "$(_field candidate_sha)" '{candidate_sha: $c, reason: "written by hand"}' > "$(_run_dir)/final-review-waiver.json"
  _stage decide; [ "$status" -eq 1 ]; [ "$(_blockers)" = final_review ]
  rm "$(_run_dir)/final-review-waiver.json"
  _stage decide --waive-final-review --reason "short"; [ "$status" -eq 2 ]
  _stage decide --waive-final-review --reason "PM: docs-only hotfix, read by me line by line"; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_decision release_ready)" = true ]
  grep -q '"event":"final_review_waived"' "$R/.aid-o/work/audit-log.jsonl"
  grep -q "NOT READ AS A WHOLE" "$(_run_dir)/pm-summary.md"
}

@test "the switch flipped inside the plan's own range is ignored: the round is still required" {
  _project
  yq -i '.review_checkpoints.cp7_plan_final_review = false' "$R/.aid-o/config/policies/review-checkpoints.yaml"
  git -C "$R" add -A; git -C "$R" commit -qm "plan switches off its own review"
  _stage freeze; _stage gates; _stage produce
  _stage decide --waive-final-review --reason "PM: trying to waive what was never legitimately off"
  [ "$status" -eq 1 ]; [[ "$(jq -r '.release_decision.blockers[0].reason' "$(_run_dir)/release-decision.json")" == *"no closed cp7 round"* ]]
}

# ── a fix after the freeze ───────────────────────────────────────────────────
@test "a docs-only fix: one command mints attempt 2, the test gate is copied, only final_claims is asked again" {
  _project
  _close_up_to_decide "$_BLOCKER"; _stage decide; [ "$status" -eq 1 ]
  local first; first="$(_run_dir)"
  echo "- **Greeting** — the app prints hello" > "$R/CHANGELOG.md"; git -C "$R" commit -qam "docs: say what it does"
  _stage freeze; echo "$output"; [ "$status" -eq 0 ]; [[ "$(_field plan_final_run_id)" == *-final-2 ]]
  [ "$(jq -c '[.class, .docs_only, .invalidated_feeds]' "$(_run_dir)/fix-class.json")" = '["delivery",true,["claims"]]' ]
  _stage gates; [ "$status" -eq 0 ]
  [ "$(jq -r '.gates.tests_pass.reused_from' "$(_run_dir)/gates_report.json")" = "${PLAN_ID/#/R-}-final-1" ]
  _stage produce; [ "$status" -eq 0 ]
  _round
  [ "$(jq -c '.reviewers_expected - (.carried_from | keys)' "$(_run_dir)/cp7/round-1/round.json")" = '["final_claims"]' ]
  _stage decide; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_decision plan_summary.close.attempts)" -eq 2 ]
  [ -s "$first/release-decision.json" ]                          # attempt 1 is left as it was
}

@test "a code fix re-reads everything; an edit of the plan's criteria re-reads final_criteria; a rewritten branch carries nothing" {
  _project
  _close_up_to_decide; _stage decide; [ "$status" -eq 0 ]
  echo 'print("hello!")' > "$R/app.py"; git -C "$R" commit -qam "fix: louder"
  _stage freeze; [ "$status" -eq 0 ]
  [ "$(jq -c '.invalidated_feeds' "$(_run_dir)/fix-class.json")" = '["diff"]' ]
  _stage gates; _stage produce; _round
  [ "$(jq -r '.carried_from // {} | length' "$(_run_dir)/cp7/round-1/round.json")" -eq 0 ]
  sed -i 's/the app greets/the app greets loudly/' "$R/.aid-o/plans/${PLAN_ID}-x.md"; git -C "$R" commit -qam "plan: criterion"
  _stage freeze; [ "$status" -eq 0 ]
  [ "$(jq -c '.invalidated_feeds' "$(_run_dir)/fix-class.json")" = '["criteria"]' ]
  git -C "$R" commit -q --amend -m "plan: criterion, reworded"          # history rewritten past the candidate
  _stage freeze; [ "$status" -eq 0 ]
  [[ "$(jq -r .reason "$(_run_dir)/fix-class.json")" == rewritten_branch* ]]
  [ "$(jq -c '.invalidated_feeds' "$(_run_dir)/fix-class.json")" = '["criteria","claims","diff"]' ]
}

@test "an ancillary-only move keeps everything: freeze names --accept-ancillary, the receipt is written, the decision stands" {
  _project
  mkdir -p "$R/.aid-o/config"; echo "plan: 1" > "$R/.aid-o/config/counter.yaml"; git -C "$R" add -f .aid-o/config/counter.yaml; git -C "$R" commit -qm "counter"
  _close_up_to_decide
  echo "plan: 2" > "$R/.aid-o/config/counter.yaml"; git -C "$R" commit -qam "chore: counter"
  _stage decide; [ "$status" -eq 6 ]; [[ "$output" == *"--stage freeze"* ]]
  _stage freeze; [ "$status" -eq 1 ]; [[ "$output" == *"--stage freeze --accept-ancillary"* ]]
  _stage freeze --accept-ancillary; echo "$output"; [ "$status" -eq 0 ]
  [[ "$(_field plan_final_run_id)" == *-final-1 ]]; ls "$(_run_dir)"/review-equivalence-receipt*.json
  _stage decide; echo "$output"; [ "$status" -eq 0 ]; [ "$(_decision release_ready)" = true ]
}

# ── integrity of the run directory ───────────────────────────────────────────
@test "a decision input edited by hand is refused by name; a file a stage rewrote is a recorded write" {
  _project
  _close_up_to_decide
  _stage produce; [ "$status" -eq 0 ]                         # produce twice in one attempt: both writes recorded
  _round 2>/dev/null || true                                  # (round 1 is already closed; nothing changes)
  local f="$(_run_dir)/cp7/round-1/reviewer-final_criteria.json"
  jq '.no_findings_reason = "edited after the close"' "$f" > "$f.t" && mv "$f.t" "$f"
  _stage decide; [ "$status" -eq 1 ]; [[ "$output" == *"cp7/round-1/reviewer-final_criteria.json"* ]]
  [ ! -e "$(_run_dir)/release-decision.json" ]
}

# ── the former stage names ───────────────────────────────────────────────────
@test "sync, inputs, review, c4, summary and accept-ancillary exit 2 naming what replaced them" {
  _project
  local s; for s in sync inputs review c4 summary accept-ancillary; do
    _stage "$s"; [ "$status" -eq 2 ]; [[ "$output" == *"no longer exists. Run:"* ]]
  done
  _stage sync; [[ "$output" == *"plan-finalize ${PLAN_ID} --stage freeze"* ]]
  _stage c4;   [[ "$output" == *"--stage decide"* ]]
  _stage review; [[ "$output" == *"--checkpoint cp7"* ]]
}

@test "every refusal of a stage ends by naming the next command or the escalation" {
  _project
  _stage gates;   [ "$status" -ne 0 ]; [[ "${lines[-1]}" == next:* ]]                       # nothing frozen
  _stage produce; [ "$status" -ne 0 ]; [[ "${lines[-1]}" == next:* ]]
  _stage decide;  [ "$status" -ne 0 ]; [[ "${lines[-1]}" == next:*escalate:* ]]
  touch "$R/break-the-gate"; git -C "$R" add -A; git -C "$R" commit -qm break
  _stage freeze;  [ "$status" -eq 0 ]; [[ "${lines[-1]}" == next:* ]]                       # success names the next stage too
  _stage gates;   [ "$status" -eq 1 ]; [[ "${lines[-1]}" == next:*"--stage freeze"*escalate:* ]]   # a red gate
  echo x > "$R/app.py"                                                                        # a dirty tree
  _stage freeze;  [ "$status" -ne 0 ]; [[ "${lines[-1]}" == next:* ]]
}

