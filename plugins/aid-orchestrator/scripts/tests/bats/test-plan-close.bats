#!/usr/bin/env bats
# aid-tier: t2
# test-plan-close.bats — cmd_plan_close in aid-fsm.sh: it runs
# aid-plan-close-check.sh and writes ca-review-complete only when that passes.
# The fixture is a real git repo, since the queue check reads branch state.

PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
AID_FSM="$PLUGIN_DIR/scripts/aid-fsm.sh"

# epic_id used in all tests — determines plan_id=P046 (nnn=046)
EPIC_ID="E-046-2_3"

setup() {
  export AID_TEST_MODE=1
  TMP=$(mktemp -d)
  export TMP
  # evidence_dir == project_root == TMP for simplicity.
  mkdir -p "$TMP/.aid-o/config" "$TMP/.aid-o/work"
  git -C "$TMP" init -q -b main
  git -C "$TMP" config user.email "test@test.local"
  git -C "$TMP" config user.name "Test"
  echo "init" > "$TMP/.gitkeep"
  git -C "$TMP" add .gitkeep
  git -C "$TMP" commit -q -m "initial"
}

teardown() {
  rm -rf "$TMP" "$TMP.foreign"
}

@test "plan-close: a clean state -> aid-plan-close-check.sh PASS, marker created, exit 0" {
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/ca-review-complete" ]
  [[ "$output" =~ "OVERALL: PASS" ]]
}

@test "plan-close: fsm-state.yaml DONE but steps[] pending -> exit 1, no marker" {
  mkdir -p "$TMP/.aid-o/work/evidence/E-046-2_3/R-test"
  cat > "$TMP/.aid-o/work/evidence/E-046-2_3/R-test/fsm-state.yaml" <<'YAML'
epic_id: E-046-2_3
run_id: R-test
state: DONE
current_step: 2
total_steps: 2
steps:
  - id: 1
    status: completed
  - id: 2
    status: pending
YAML
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
  [[ "$output" =~ "aid-plan-close-check.sh" ]]
}

@test "plan-close: queue.yaml claims blocked but the branch is merged -> exit 1, no marker" {
  # A branch for E-046-2_3 that IS an ancestor of current HEAD (merged), while
  # queue.yaml still claims it is blocked — the stale-queue drift Check 4 catches.
  git -C "$TMP" branch task/E-046-2_3/main HEAD
  cat > "$TMP/.aid-o/config/queue.yaml" <<'YAML'
- epic_id: E-046-2_3
  path: p
  status: blocked
  depends_on: []
YAML
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP/ca-review-complete" ]
}

@test "plan-close: a report nobody writes any more is not asked for" {
  run bash "$AID_FSM" plan-close "$EPIC_ID" "$TMP" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" != *"required report not found"* ]]
  [[ "$output" != *"delivery"* ]]
}

# ── P111 Step 3: the close takes a plan whose only run is direct ─────────────
@test "direct: plan-finalize freezes a plan whose only run is direct (from PLAN_SYNC, no EPIC merge)" {
  export AID_PLUGIN_PATH="$PLUGIN_DIR"
  source "$PLUGIN_DIR/scripts/tests/lib/aid-test-plan-fixture.sh"
  local sf; sf="$(aid_fixture_direct_run "$TMP" P910 DONE review)"
  cd "$TMP"
  run bash "$AID_FSM" done-advance review release "$sf" --direct
  [ "$status" -eq 0 ]
  [ "$(yq -r '.plan_state' "$TMP/.aid-o/work/plan-state/P910/plan-state.yaml")" = "PLAN_SYNC" ]
  run bash "$PLUGIN_DIR/scripts/aid-plan-fsm.sh" plan-finalize P910 --stage freeze
  [ "$status" -eq 0 ]
  [ "$(yq -r '.plan_state' "$TMP/.aid-o/work/plan-state/P910/plan-state.yaml")" = "PLAN_GATES" ]
  [ -z "$(git -C "$TMP" branch --list 'task/*')" ]
}

# ── P111 Step 4: the close checks the foreign branches (repo_roots) ─────────
_foreign_frozen() {   # a direct run of P910 with repo_roots "docs", one foreign step commit, frozen
  export AID_PLUGIN_PATH="$PLUGIN_DIR"
  source "$PLUGIN_DIR/scripts/tests/lib/aid-test-plan-fixture.sh"
  SF="$(aid_fixture_direct_run "$TMP" P910 DONE review)"
  EVD="$(dirname "$SF")"
  FR="$TMP.foreign"; mkdir -p "$FR"; FR="$(realpath "$FR")"
  git -C "$FR" init -q -b main; git -C "$FR" config user.email t@t; git -C "$FR" config user.name t
  echo a > "$FR/page.md"; git -C "$FR" add page.md; git -C "$FR" commit -qm init
  FBASE="$(git -C "$FR" rev-parse main)"
  FWT="$FR/.aid-worktrees/plan-P910--docs"
  git -C "$FR" worktree add -q -b plan/P910-proj "$FWT" main
  echo b >> "$FWT/page.md"; git -C "$FWT" commit -qam "foreign step"
  jq --arg p "$FR" --arg w "$FWT" --arg b "$FBASE" '.repo_roots = [{name: "docs", path: $p, worktree: $w, branch: "plan/P910-proj", base: $b}]' \
    "$EVD/plan.json" > "$EVD/p" && mv "$EVD/p" "$EVD/plan.json"
  mkdir -p "$EVD/steps/step_1_backend"
  jq -n --arg r "${FBASE}..$(git -C "$FWT" rev-parse HEAD)" '{repo_commits: [{repo: "docs", range: $r}]}' > "$EVD/steps/step_1_backend/return.json"
  cd "$TMP"
  bash "$AID_FSM" done-advance review release "$SF" --direct >/dev/null 2>&1
  bash "$PLUGIN_DIR/scripts/aid-plan-fsm.sh" plan-finalize P910 --stage freeze >/dev/null 2>&1
  MFP="$TMP/.aid-o/work/plan-state/P910/plan-boundary-manifest.json"
  # straight to PLAN_REVIEW: the gates stage is not what these cases test
  yq -i '.plan_state = "PLAN_REVIEW"' "$TMP/.aid-o/work/plan-state/P910/plan-state.yaml"
}
_produce() { run bash "$PLUGIN_DIR/scripts/aid-plan-fsm.sh" plan-finalize P910 --stage produce; }

@test "foreign: freeze records each foreign branch's head and its commits since the base" {
  _foreign_frozen
  [ "$(jq -c '.plan_boundary_manifest.repo_roots[0] | [.name, .branch, .head, .commits]' "$MFP")" = "$(jq -nc --arg h "$(git -C "$FR" rev-parse plan/P910-proj)" '["docs","plan/P910-proj",$h,1]')" ]
}

@test "foreign: a reported range that is not on the foreign branch is refused foreign_branch_unverified" {
  _foreign_frozen
  echo c >> "$FR/page.md"; git -C "$FR" commit -qam "live checkout only"
  jq -n --arg r "${FBASE}..$(git -C "$FR" rev-parse main)" '{repo_commits: [{repo: "docs", range: $r}]}' > "$EVD/steps/step_1_backend/return.json"
  _produce
  [ "$status" -ne 0 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: foreign_branch_unverified)"* && "$output" == *"live checkout does not count"* ]]
}

@test "foreign: a foreign branch that moved after freeze is refused, naming the frozen head" {
  _foreign_frozen
  local frozen; frozen="$(git -C "$FR" rev-parse plan/P910-proj)"
  echo d >> "$FWT/page.md"; git -C "$FWT" commit -qam "after freeze"
  _produce
  [ "$status" -ne 0 ]
  [[ "$output" == *"foreign_branch_unverified"* && "$output" == *"moved after freeze (frozen ${frozen}"* ]]
}

@test "foreign: a foreign worktree removed before the close is refused, naming it" {
  _foreign_frozen
  git -C "$FR" worktree remove --force "$FWT"
  _produce
  [ "$status" -ne 0 ]
  [[ "$output" == *"foreign_branch_unverified"* && "$output" == *"${FWT} is gone"* ]]
}

@test "foreign: a plan without repo_roots is not touched by the foreign check" {
  export AID_PLUGIN_PATH="$PLUGIN_DIR"
  source "$PLUGIN_DIR/scripts/tests/lib/aid-test-plan-fixture.sh"
  local sf; sf="$(aid_fixture_direct_run "$TMP" P910 DONE review)"; cd "$TMP"
  bash "$AID_FSM" done-advance review release "$sf" --direct >/dev/null 2>&1
  run bash "$PLUGIN_DIR/scripts/aid-plan-fsm.sh" plan-finalize P910 --stage freeze
  [ "$status" -eq 0 ]
  [ "$(jq -r '.plan_boundary_manifest.repo_roots // "absent"' "$TMP/.aid-o/work/plan-state/P910/plan-boundary-manifest.json")" = "absent" ]
  yq -i '.plan_state = "PLAN_REVIEW"' "$TMP/.aid-o/work/plan-state/P910/plan-state.yaml"
  _produce
  [[ "$output" != *"foreign_branch_unverified"* ]]
}

_foreign_decision() {   # <dir> — a plan-mode release-decision carrying one foreign branch
  jq -n '{schema_version: "aid-2.0", artifact_type: "release_decision",
    release_decision: {release_ready: true, merge_mode: "manual", blockers: [], waivers_applied: [],
      plan_summary: {plan_id: "P910", plan_final_run_id: "R-1",
        reviewed_candidate_sha: "1111111111111111111111111111111111111111", approved_target_sha: "2222222222222222222222222222222222222222",
        target_ref: "main", final_merge_sha: null, release_tag_status: "not_tagged",
        epics: [{epic_id: "E-910-1_1", run_id: "R-E910-1", status: "merged_to_plan", skipped: false, reason: null}],
        plan_final_gates: {report: "g.json", result: "pass", quarantine_substitutes: []},
        specialist_review: null, remaining_backlog: [], close: {attempts: 1, minutes: 3, usd: 0.5, usd_unknown_roles: []},
        foreign_branches: [{name: "docs", branch: "plan/P910-proj", head: "abcdef1234567890abcdef1234567890abcdef12", commits: 2}]}}}' > "$1/release-decision.json"
}

@test "foreign: the PM card names the foreign branch to merge by hand, with its head and count" {
  mkdir -p "$TMP/ev"; _foreign_decision "$TMP/ev"
  run bash "$PLUGIN_DIR/scripts/aid-pm-brief.sh" "$TMP/ev"
  grep -q 'Foreign branches (merge by hand, repo_roots):.*`docs` plan/P910-proj at `abcdef123456` (2 commit(s))' "$TMP/ev/pm-summary.md"
}

@test "foreign: the close page names the foreign branch to merge by hand" {
  mkdir -p "$TMP/ev" "$TMP/out"; _foreign_decision "$TMP/ev"
  bash "$PLUGIN_DIR/scripts/aid-pm-brief.sh" "$TMP/ev" >/dev/null 2>&1 || true
  source "$PLUGIN_DIR/scripts/lib/aid-plan-close-summary.sh"
  run aid_plan_close_render "$TMP/ev/pm-decision-brief.json" "$TMP/ev/release-decision.json" P910 "$TMP/out"
  grep -q 'cizí větve k ručnímu merge: docs plan/P910-proj @abcdef1 (2 commit(ů))' "$TMP/out/plan-close-artifact.html"
}
