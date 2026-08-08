#!/usr/bin/env bats
# test-scoped-preflights.bats — P074 Step 5: preflights scoped to what
# operations actually touch.
#
# Until P074 plan-start, epic-start and plan-merge-to-main all refused on ANY
# unrelated tracked edit via the repo-wide clean-worktree preflight, even
# though grounding proved all three never touch a worktree: plan-start and
# epic-start create refs only (`git branch` — no checkout, no tracked writes)
# and plan-merge-to-main publishes by plumbing (merge-tree/commit-tree +
# compare-and-swap update-ref). This suite locks the loosening:
#
#   1. the P074 HEADLINE case — plan-start and epic-start proceed with an
#      unrelated dirty tracked file in the primary checkout (refused before);
#   2. plan-merge-to-main completes with a dirty primary tree, on a fixture
#      with a valid frozen candidate (the PM-confirmed product tradeoff);
#   3. epic-merge-to-plan STILL refuses when ITS target tree is dirty — the
#      check survives, scoped, and names the tree it evaluated;
#   4. the detached-HEAD refusal is unchanged for both opening commands.
#
# The merge fixture is a condensed copy of test-aid-plan-final-boundary.bats'
# _seed_merge_project (same real library entry points, no hand-written
# manifests) — kept local because that suite is DELEGATED out of the aggregate
# runner and this one must be able to run standalone.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_FSM_CLI="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PLAN_FSM_CLI
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT

  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"

  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh"
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh"
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
}

teardown() {
  teardown_test_evidence_dir
}

PLAN_ID="P900"

_pf() { ( cd "$ROOT" && bash "$PLAN_FSM_CLI" "$@" ); }

# _dirty — an UNRELATED dirty tracked file the legacy5 classifier does NOT
# exempt (same shape as test-plan-force-commands.bats' _dirty: tracked, since
# the check runs with --untracked-files=no).
_dirty() { printf 'uncommitted unrelated edit\n' >> "$ROOT/.gitkeep"; }

_manifest_field() {
  jq -r --arg f "$2" '.plan_boundary_manifest[$f]' \
    "$ROOT/.aid-o/work/plan-state/${1}/plan-boundary-manifest.json"
}

# _seed_lifecycle — the plan source file + git-tracked lifecycle manifest
# plan-start's own lifecycle write needs; without it plan-start ends rc=3 for
# a reason unrelated to preflights (same seam test-plan-force-commands.bats'
# SCOPE NOTE documents). Seeding it lets the headline tests assert FULL
# success, not merely "got past the preflight".
_seed_lifecycle() {
  mkdir -p "$ROOT/.aid-o/plans"
  printf '# %s\n\n**EPIC 1: the delivered one**\n' "$PLAN_ID" \
    > "$ROOT/.aid-o/plans/${PLAN_ID}-lifecycle.md"
  aid_lifecycle_ensure_manifest "$PLAN_ID" "$ROOT" >/dev/null
}

# ─── 1. the headline case: ref-only commands ignore an unrelated dirty tree ─

@test "P074 Step 5: plan-start SUCCEEDS with an unrelated dirty tracked file (the headline case)" {
  _seed_lifecycle
  _dirty
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  # The old repo-wide refusal is gone, and the whole command succeeded.
  [ "$status" -eq 0 ]
  [[ "$output" != *"uncommitted changes present"* ]]
  # The command actually did its ref-only work: the plan branch exists (the
  # refused command created nothing — asserted by test-plan-force-commands.bats
  # before P074).
  run bash -c "git -C '$ROOT' branch --list 'plan/${PLAN_ID}'"
  [ -n "$output" ]
  # The dirty file was not consumed, stashed or reverted.
  run bash -c "git -C '$ROOT' status --porcelain --untracked-files=no"
  [[ "$output" == *".gitkeep"* ]]
}

@test "P074 Step 5: epic-start SUCCEEDS with an unrelated dirty tracked file (the headline case)" {
  _seed_lifecycle
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  _dirty
  run _pf epic-start "$PLAN_ID" E-900-1_1
  [ "$status" -eq 0 ]
  [[ "$output" != *"uncommitted changes present"* ]]
  # The task branch was created as a ref — no checkout happened, HEAD stayed
  # on main and the dirty edit survived untouched.
  run bash -c "git -C '$ROOT' branch --list 'task/E-900-1_1/main'"
  [ -n "$output" ]
  [ "$(git -C "$ROOT" symbolic-ref --short HEAD)" = "main" ]
  run bash -c "git -C '$ROOT' status --porcelain --untracked-files=no"
  [[ "$output" == *".gitkeep"* ]]
}

# ─── 1b. the targeted survivor: plan-start's own lifecycle write surface ───

@test "P074 Step 5: a dirty LIFECYCLE path refuses plan-start BEFORE any mutation, while unrelated dirt does not" {
  _seed_lifecycle
  # An unstaged edit to the tracked manifest plan-start itself will write —
  # exactly the file aid_lifecycle_set_plan_mode would otherwise refuse on
  # AFTER the branch and op record existed (the partial-mutation shape).
  printf '# user edit\n' >> "$ROOT/.aid-lifecycle/manifests/${PLAN_ID}.yaml"
  # Unrelated dirt too, to prove the refusal is the TARGETED check, not a
  # resurrected repo-wide one.
  _dirty
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"lifecycle path"* ]]
  [[ "$output" == *".aid-lifecycle/manifests/${PLAN_ID}.yaml"* ]]
  # The refusal happened BEFORE any mutation: no plan branch, no op record.
  run bash -c "git -C '$ROOT' branch --list 'plan/${PLAN_ID}'"
  [ -z "$output" ]
  [ ! -f "$ROOT/.aid-o/work/plan-state/${PLAN_ID}/operations.jsonl" ]

  # And it is not forceable — a force would only move the same refusal to
  # after the mutation.
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode --force \
    --reason "attempting to force past the lifecycle-path preflight"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FORCE CANNOT BYPASS 'lifecycle_paths_clean'"* ]]
  run bash -c "git -C '$ROOT' branch --list 'plan/${PLAN_ID}'"
  [ -z "$output" ]

  # With the lifecycle edit committed, the same dirty-elsewhere tree succeeds
  # (the headline loosening stands).
  ( cd "$ROOT" && git add .aid-lifecycle && git commit -qm "user lifecycle edit accepted" )
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
}

@test "P074 Step 5: an UNTRACKED colliding lifecycle file refuses plan-start before any ref — manifest and repo-identity alike" {
  # No lifecycle seeded: both paths are absent from git, so only the UNTRACKED
  # collision can trip the check — the case a tracked-only probe would miss
  # (ensure_manifest refuses an untracked colliding manifest, and aid_repo_id
  # would overwrite an untracked repo-identity.yaml, both AFTER the ref
  # existed).
  mkdir -p "$ROOT/.aid-lifecycle/manifests"
  printf 'stale: true\n' > "$ROOT/.aid-lifecycle/manifests/${PLAN_ID}.yaml"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"lifecycle path"* ]]
  [[ "$output" == *".aid-lifecycle/manifests/${PLAN_ID}.yaml"* ]]
  run bash -c "git -C '$ROOT' branch --list 'plan/${PLAN_ID}'"
  [ -z "$output" ]
  [ ! -f "$ROOT/.aid-o/work/plan-state/${PLAN_ID}/operations.jsonl" ]

  # Likewise an untracked repo-identity.yaml on its own.
  rm "$ROOT/.aid-lifecycle/manifests/${PLAN_ID}.yaml"
  printf 'repo: someone-elses\n' > "$ROOT/.aid-lifecycle/repo-identity.yaml"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"lifecycle path"* ]]
  [[ "$output" == *".aid-lifecycle/repo-identity.yaml"* ]]
  run bash -c "git -C '$ROOT' branch --list 'plan/${PLAN_ID}'"
  [ -z "$output" ]

  # An untracked file ELSEWHERE never trips the targeted check.
  rm "$ROOT/.aid-lifecycle/repo-identity.yaml"
  printf 'junk\n' > "$ROOT/unrelated-untracked.txt"
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [[ "$output" != *"lifecycle path"* ]]
}

# ─── 2. the detached-HEAD refusal is unchanged ─────────────────────────────

@test "P074 Step 5: plan-start still refuses on a detached HEAD" {
  git -C "$ROOT" checkout -q --detach
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached HEAD"* ]]
  run bash -c "git -C '$ROOT' branch --list 'plan/${PLAN_ID}'"
  [ -z "$output" ]
}

@test "P074 Step 5: epic-start still refuses on a detached HEAD" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  git -C "$ROOT" checkout -q --detach
  run _pf epic-start "$PLAN_ID" E-900-1_1
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached HEAD"* ]]
}

# ─── 3. the kept check: epic-merge-to-plan refuses on ITS dirty target tree ─

@test "P074 Step 5: epic-merge-to-plan still refuses when its target tree is dirty, naming the tree it evaluated" {
  run _pf plan-start "$PLAN_ID" --mode legacy_epic_release_mode
  run _pf epic-start "$PLAN_ID" E-900-1_1
  _dirty
  run _pf epic-merge-to-plan "$PLAN_ID" E-900-1_1
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes present"* ]]
  # The kept message now names the tree the check evaluated.
  [[ "$output" == *"tree evaluated: ${ROOT}"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# plan-merge-to-main with a dirty primary tree — the merge fixture.
# Condensed from test-aid-plan-final-boundary.bats (_bootstrap /
# _seed_merge_project / _seed_plan_final_evidence), built through the REAL
# library entry points.
# ═══════════════════════════════════════════════════════════════════════════

_run_dir() {
  printf '%s/%s' "$ROOT" "$(_manifest_field "$PLAN_ID" plan_final_evidence_dir)"
}

_commit_on() {
  local branch="$1" file="$2" text="$3" orig
  orig="$(git -C "$ROOT" symbolic-ref --short HEAD)"
  git -C "$ROOT" checkout -q "$branch"
  printf '%s\n' "$text" > "$ROOT/$file"
  git -C "$ROOT" add -- "$file"
  git -C "$ROOT" commit -q -m "$text"
  git -C "$ROOT" checkout -q "$orig"
}

_finalize() {
  local plan_id="$1" stage="$2"; shift 2
  run bash "$PLAN_FSM_CLI" plan-finalize "$plan_id" --stage "$stage" \
    --project-root "$ROOT" "$@"
}

_bootstrap() {
  local plan_id="${1:-$PLAN_ID}"
  printf '.aid-o/work/\n.aid-o/reports/\n' > "$ROOT/.gitignore"
  git -C "$ROOT" add -- .gitignore
  git -C "$ROOT" commit -q -m "gitignore the runtime area"
  # The git-tracked lifecycle manifest must exist on the TARGET branch BEFORE
  # the plan branch is cut (a later commit on main would advance the target
  # head past the frozen one).
  mkdir -p "$ROOT/.aid-o/plans"
  printf '# %s\n\n**EPIC 1: the delivered one**\n' "$plan_id" \
    > "$ROOT/.aid-o/plans/${plan_id}-lifecycle.md"
  aid_lifecycle_ensure_manifest "$plan_id" "$ROOT" >/dev/null
  local base; base="$(git -C "$ROOT" rev-parse main)"
  git -C "$ROOT" branch "plan/${plan_id}" "$base"
  plan_state_init "$plan_id" "plan_branch" "plan/${plan_id}" "main"
  plan_manifest_init "$plan_id" "plan/${plan_id}" "main" "$base" "$base" "plan_branch"
}

_add_epic() {
  local plan_id="$1" epic_id="$2"
  local base; base="$(git -C "$ROOT" rev-parse "plan/${plan_id}")"
  local ev=".aid-o/work/evidence/${epic_id}/R-${epic_id}-1"
  plan_manifest_add_epic "$plan_id" "$epic_id" "R-${epic_id}-1" \
    "task/${epic_id}/main" "$base" "plan/${plan_id}" \
    "$ev" "proven"
  mkdir -p "$ROOT/$ev"
  jq -n --arg e "$epic_id" \
    '{schema_version:"aid-2.0", epic_id:$e,
      steps:[{step_id:"S1", allowed_paths:["epic-work.txt","scripts/**"]}]}' \
    > "$ROOT/$ev/plan.json"
}

# _seed_plan_final_evidence — the plan-final review + C4 records the merge
# reads, written as REAL files with their REAL sha256 recorded, exactly as
# `--stage review` does (verbatim from test-aid-plan-final-boundary.bats).
_seed_plan_final_evidence() {
  local dir; dir="$(_run_dir)"
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  local run_id; run_id="$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  local base; base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  local thead; thead="$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)"
  mkdir -p "$dir"

  jq -n '{overall:"pass", gates:[]}' > "${dir}/gates_report.json"

  local f outputs='{}'
  for f in semantic-review-final.json audit-report.json audit-input-manifest.json curator-report.json \
           simplifier-report.md delivery-report.json review-profile.json \
           plan-diff.json delivery-gate.json acceptance-evidence.json dispatch-record.json; do
    if [[ ! -f "${dir}/${f}" ]]; then
      if [[ "$f" == *.md ]]; then
        printf 'Head: %s\n' "$cand" > "${dir}/${f}"
      elif [[ "$f" == "plan-diff.json" ]]; then
        jq -n --arg b "$base" --arg h "$cand" \
          '{base_commit:$b, head_commit:$h, overall_verdict:"pass", results:[], summary:{present_count:0,absent_count:0}}' > "${dir}/${f}"
      else
        jq -n --arg h "$cand" '{schema_version:"aid-2.0", revision:{head_sha:$h}}' > "${dir}/${f}"
      fi
    fi
    outputs="$(jq -c --arg k "$f" --arg v "sha256:$(sha256sum "${dir}/${f}" | awk '{print $1}')" \
      '. + {($k): $v}' <<<"$outputs")"
  done

  plan_manifest_update "$PLAN_ID" \
    ".plan_boundary_manifest.plan_final_inputs = {plan_diff_sha256: \"sha256:$(sha256sum "${dir}/plan-diff.json" | awk '{print $1}')\", candidate_sha: \"${cand}\", run_id: \"${run_id}\", ac_lens_required: false, plan_diff_verdict: \"present\"}" >/dev/null

  plan_manifest_update "$PLAN_ID" \
    ".plan_boundary_manifest.plan_final_review = $(jq -nc --arg c "$cand" --arg b "$base" \
      --arg r "$run_id" --argjson o "$outputs" \
      '{candidate_sha:$c, review_range:($b + ".." + $c), run_id:$r, outputs:$o,
        dispatch_counts:{}, utilities_run:[]}')" >/dev/null

  local sealed ref receipt_commit receipt_hash
  local target_head
  target_head="$(git -C "$ROOT" rev-parse main)"
  local frozen_at
  frozen_at="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  sealed="$(bash -c 'source "$1"; _pfsm_seal_plan_final_review "$2" "$3" "$4" "$5" main "$6" "$7" "$8" "$9"' \
    _ "$PLAN_FSM_CLI" "$ROOT" "$PLAN_ID" "$base" "$cand" "$target_head" "$frozen_at" "$run_id" "$outputs")"
  IFS='|' read -r ref receipt_commit receipt_hash <<< "$sealed"
  [[ -n "$ref" && -n "$receipt_hash" ]] || return 1
  plan_manifest_update "$PLAN_ID" \
    ".plan_boundary_manifest.plan_final_evidence_ref = \"${ref}\" | .plan_boundary_manifest.plan_final_evidence_receipt_sha256 = \"${receipt_hash}\"" >/dev/null

  jq -n --arg c "$cand" '{schema_version:"aid-2.0", artifact_type:"release_decision",
    release_decision:{release_ready:true, blockers:[], candidate_sha:$c}}' \
    > "${dir}/release-decision.json"
  jq -n --arg p "$PLAN_ID" --arg r "$run_id" --arg c "$cand" --arg t "$thead" \
    '{event:"release_policy_dual_run", plan_id:$p, run_id:$r, candidate_sha:$c,
      target_head:$t}' > "${dir}/release-policy-dual-run.json"
}

# _seed_merge_project — a plan at AWAITING_PM at a frozen candidate, reached
# through the REAL sync + freeze stages plus the real transition table.
_seed_merge_project() {
  _bootstrap
  _commit_on "plan/${PLAN_ID}" epic-work.txt "feat: the EPIC's work"
  _add_epic "$PLAN_ID" "E-900-1_1"
  local mc; mc="$(git -C "$ROOT" rev-parse "plan/$PLAN_ID")"
  plan_manifest_set_epic_status "$PLAN_ID" "E-900-1_1" "merged_to_plan" "$mc"

  _finalize "$PLAN_ID" sync
  [ "$status" -eq 0 ]
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  plan_state_transition "$PLAN_ID" "PLAN_GATES" "PLAN_REVIEW" >/dev/null
  plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "AWAITING_PM" >/dev/null

  local dir; dir="$(_run_dir)"
  mkdir -p "$dir"
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  jq -n --arg h "$cand" \
    '{schema_version:"aid-2.0", artifact_type:"audit_report",
      revision:{head_sha:$h}, status:"pass",
      audit_report:{reviewed_head:$h, blocking_findings:false}}' \
    > "${dir}/audit-report.json"
  jq -n '{schema_version:"aid-2.0", artifact_type:"curator",
          status:"pass", curator:{blocking_findings:false}}' \
    > "${dir}/curator-report.json"

  # The controller keeps the worktree on the candidate across the PM boundary.
  git -C "$ROOT" checkout -q "plan/${PLAN_ID}"
  _seed_plan_final_evidence
}

_decision_file() {
  local f="$TEST_TMPDIR/pm-decision.json"
  local _frozen; _frozen="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  jq -n --arg p "$PLAN_ID" \
        --arg r "$(_manifest_field "$PLAN_ID" plan_final_run_id)" \
        --arg c "$(_manifest_field "$PLAN_ID" candidate_sha)" \
        --arg t "$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)" \
        --arg at "$_frozen" \
    '{schema_version:"aid-pm-plan-decision-1.0", artifact_type:"pm_plan_decision",
      producer:"aid-test@1.0", created_at:$at,
      plan_id:$p, plan_final_run_id:$r, decision:"MERGE",
      candidate_sha:$c, target_branch:"main", target_head_sha:$t,
      decided_at:$at, decided_by:"pm"}' > "$f"
  printf '%s' "$f"
}

_merge_commit() {
  jq -r '.plan_boundary_manifest.plan_final_merge.merge_commit' \
    "$ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
}

# ─── 4. plan-merge-to-main completes with a dirty primary tree ─────────────

@test "P074 Step 5: plan-merge-to-main completes with a dirty primary tree on a valid frozen candidate" {
  _seed_merge_project
  local cand target
  cand="$(git -C "$ROOT" rev-parse "plan/$PLAN_ID")"
  target="$(git -C "$ROOT" rev-parse main)"

  # The P074 case: an unrelated tracked edit sits in the primary checkout at
  # merge time (HEAD is on the plan branch; epic-work.txt is tracked there).
  printf 'uncommitted unrelated edit\n' >> "$ROOT/epic-work.txt"

  run bash "$PLAN_FSM_CLI" plan-merge-to-main "$PLAN_ID" \
    --decision "$(_decision_file)" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"uncommitted changes present"* ]]

  # The published merge is real: one commit, parents = approved target head
  # and the candidate, candidate reachable from main.
  local mc; mc="$(_merge_commit)"
  [[ "$mc" =~ ^[0-9a-f]{40}$ ]]
  [ "$(git -C "$ROOT" rev-parse "${mc}^1")" = "$target" ]
  [ "$(git -C "$ROOT" rev-parse "${mc}^2")" = "$cand" ]
  run git -C "$ROOT" merge-base --is-ancestor "$cand" main
  [ "$status" -eq 0 ]

  # The dirty edit was neither consumed by the merge commit nor cleaned up:
  # the plumbing never touched the worktree.
  run bash -c "git -C '$ROOT' status --porcelain --untracked-files=no"
  [[ "$output" == *"epic-work.txt"* ]]
  run bash -c "git -C '$ROOT' show '${mc}:epic-work.txt'"
  [[ "$output" != *"uncommitted unrelated edit"* ]]
}
