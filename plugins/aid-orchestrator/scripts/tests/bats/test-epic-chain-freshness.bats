#!/usr/bin/env bats
# aid-tier: t2
# test-epic-chain-freshness.bats — P079 Step 3 (IMP-478): a chained EPIC's task
# branch is brought up to the live plan head before it executes.
#
# THE LIVE FAILURE MODE UNDER TEST: chain generation registers every EPIC of a
# plan at once, and epic-start cuts `task/<epic>/main` from the plan head at
# REGISTRATION time. Correct when it happens — stale by the time a later chain
# member starts, because its predecessors merged into `plan/<id>` in between.
# The shipped lineage check cannot see it: merge-base(stale branch, plan) still
# equals the recorded base, which is precisely what "merely behind" means. So
# EPIC 2 executed on a tree that did not contain EPIC 1's work.
#
# The fixture reproduces the REAL generation order — both fsm-state files
# created BEFORE EPIC 1 merges — because a fixture that creates EPIC 2's state
# file afterwards would hide the second half of the defect.
#
# FD-3 HYGIENE: every plan-FSM invocation runs with `3>&-`. After any edit:
#   bats --tap test-epic-chain-freshness.bats | grep -cE '^(ok|not ok)'   # == 9

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_FSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PLAN_FSM
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  export TEST_TMPDIR ROOT
  unset AID_PROJECT_ROOT
  export AID_PLAN_STATE_PROJECT_ROOT="$ROOT" AID_PLAN_MANIFEST_PROJECT_ROOT="$ROOT"
}

teardown() {
  cd /
  [[ -d "$TEST_TMPDIR" ]] && chmod -R u+rwX "$TEST_TMPDIR" 2>/dev/null || true
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_libs() {
  printf "%s" "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
                source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh'"
}

_in_root() {
  bash -c "cd '$ROOT' || exit 9
           export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
           $1" 3>&-
}

_pf() {
  local q="" a
  for a in "$@"; do q+=" '${a}'"; done
  bash -c "cd '$ROOT' && exec bash '$PLAN_FSM'${q}" 3>&-
}

_mk_project() {
  mkdir -p "$ROOT/.aid-o/plans" "$ROOT/.aid-o/config" "$ROOT/.aid-o/work/evidence"
  printf '.aid-o/\n.aid-worktrees/\n' > "$ROOT/.gitignore"
  printf 'seed\n' > "$ROOT/README.md"
  (
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed project"
  )
}

# _evidence <epic> — the evidence dir epic-start records for an EPIC.
_evidence() { printf '.aid-o/work/evidence/%s/R-%s-plan' "$1" "$1"; }

# _seed_chain — a plan with TWO EPICs registered together, each with a task
# branch cut from the plan head and an fsm-state.yaml already written. This is
# the P076 shape: everything exists before EPIC 1 merges anything.
_seed_chain() {
  _in_root "set -e
    $(_libs)
    base=\$(git -C '$ROOT' rev-parse main)
    git -C '$ROOT' branch plan/P900 \"\$base\"
    plan_state_init P900 plan_branch plan/P900 main >/dev/null
    plan_manifest_init P900 plan/P900 main \"\$base\" \"\$base\" plan_branch >/dev/null
    git -C '$ROOT' worktree add -q '$ROOT/.aid-worktrees/plan-P900' plan/P900
    plan_state_set_worktree_path P900 '$ROOT/.aid-worktrees/plan-P900'
    for e in E-900-1_2 E-900-2_2; do
      git -C '$ROOT' branch \"task/\$e/main\" \"\$base\"
      plan_manifest_add_epic P900 \"\$e\" \"R-\$e-plan\" \"task/\$e/main\" \\
        \"\$base\" plan/P900 \".aid-o/work/evidence/\$e/R-\$e-plan\" proven >/dev/null
      mkdir -p '$ROOT'/.aid-o/work/evidence/\$e/R-\$e-plan
      printf 'epic_id: %s\nrun_id: R-%s-plan\nstate: READY\ncurrent_step: 0\ntotal_steps: 1\nbase_commit: %s\n' \\
        \"\$e\" \"\$e\" \"\$base\" > '$ROOT'/.aid-o/work/evidence/\$e/R-\$e-plan/fsm-state.yaml
    done"
}

# _merge_epic1 — EPIC 1 lands a file on the plan branch, exactly as
# epic-merge-to-plan would. Echoes the new plan head.
_merge_epic1() {
  _in_root "set -e
    git -C '$ROOT' checkout -q task/E-900-1_2/main
    printf 'epic one work\n' > '$ROOT/epic-one.txt'
    git -C '$ROOT' add epic-one.txt
    git -C '$ROOT' -c user.email=t@e -c user.name=t commit -q -m 'EPIC 1 work'
    git -C '$ROOT' checkout -q main
    # plan/P900 is checked out in the plan worktree, so the integration
    # happens there — exactly as epic-merge-to-plan does it.
    git -C '$ROOT/.aid-worktrees/plan-P900' merge --ff-only -q task/E-900-1_2/main
    git -C '$ROOT' rev-parse plan/P900"
}

_manifest_base() {
  _in_root "$(_libs)
    plan_manifest_get P900 '.plan_boundary_manifest.epic_runs[] | select(.epic_id==\"$1\") | .epic_base_commit'"
}

_state_base() {
  grep '^base_commit:' "$ROOT/$(_evidence "$1")/fsm-state.yaml" | awk '{print $2}'
}

# ─── the chain case ────────────────────────────────────────────────────────

@test "P079 Step 3: EPIC 2's branch is fast-forwarded to the live plan head — its tree contains EPIC 1's merged work" {
  _mk_project
  _seed_chain
  local plan_head
  plan_head="$(_merge_epic1)"
  # Before: EPIC 2's branch predates the merge entirely.
  run git -C "$ROOT" cat-file -e "task/E-900-2_2/main:epic-one.txt"
  [ "$status" -ne 0 ]

  run _pf epic-start P900 E-900-2_2 --project-root "$ROOT"
  [ "$status" -eq 0 ]

  [ "$(git -C "$ROOT" rev-parse task/E-900-2_2/main)" = "$plan_head" ]
  git -C "$ROOT" cat-file -e "task/E-900-2_2/main:epic-one.txt"
}

@test "P079 Step 3: BOTH persisted base records follow the branch (manifest and the pre-existing fsm-state)" {
  _mk_project
  _seed_chain
  local plan_head
  plan_head="$(_merge_epic1)"

  run _pf epic-start P900 E-900-2_2 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(_manifest_base E-900-2_2)" = "$plan_head" ]
  [ "$(_state_base E-900-2_2)" = "$plan_head" ]
  # EPIC 1's records are untouched — the reconciliation is per-EPIC.
  [ "$(_manifest_base E-900-1_2)" != "$plan_head" ]
}

@test "P079 Step 3: the fast-forward is recorded as a task_branch_fastforward event naming old and new heads" {
  _mk_project
  _seed_chain
  local old_head plan_head
  old_head="$(git -C "$ROOT" rev-parse task/E-900-2_2/main)"
  plan_head="$(_merge_epic1)"

  run _pf epic-start P900 E-900-2_2 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  local tl="$ROOT/$(_evidence E-900-2_2)/timeline.jsonl"
  [ -f "$tl" ]
  [ "$(jq -r 'select(.event=="task_branch_fastforward") | .old_head' "$tl")" = "$old_head" ]
  [ "$(jq -r 'select(.event=="task_branch_fastforward") | .new_head' "$tl")" = "$plan_head" ]
}

# ─── crash windows converge ────────────────────────────────────────────────

@test "P079 Step 3: a re-run after a crash BETWEEN the fast-forward and the manifest write converges" {
  _mk_project
  _seed_chain
  local plan_head
  plan_head="$(_merge_epic1)"
  # Simulate the crash: the branch moved, neither record did.
  git -C "$ROOT" branch -f task/E-900-2_2/main "$plan_head"

  run _pf epic-start P900 E-900-2_2 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(_manifest_base E-900-2_2)" = "$plan_head" ]
  [ "$(_state_base E-900-2_2)" = "$plan_head" ]
}

@test "P079 Step 3: a re-run after a crash BETWEEN the manifest CAS and the fsm-state write does the remaining write only" {
  _mk_project
  _seed_chain
  local plan_head old_base
  old_base="$(_manifest_base E-900-2_2)"
  plan_head="$(_merge_epic1)"
  git -C "$ROOT" branch -f task/E-900-2_2/main "$plan_head"
  _in_root "$(_libs)
    plan_manifest_update_epic_base P900 E-900-2_2 '$old_base' '$plan_head'" >/dev/null
  [ "$(_state_base E-900-2_2)" = "$old_base" ]

  run _pf epic-start P900 E-900-2_2 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(_state_base E-900-2_2)" = "$plan_head" ]
}

@test "P079 Step 3: an fsm-state base_commit that is NOT an ancestor of the new base is refused, not overwritten" {
  _mk_project
  _seed_chain
  local plan_head foreign
  plan_head="$(_merge_epic1)"
  # Somebody else moved EPIC 2's recorded base to a commit that the
  # fast-forward does not supersede (a sibling line of history).
  foreign="$(_in_root "set -e
    git -C '$ROOT' checkout -q -b p079/foreign main
    printf 'foreign\n' > '$ROOT/foreign.txt'
    git -C '$ROOT' add foreign.txt
    git -C '$ROOT' -c user.email=t@e -c user.name=t commit -q -m foreign
    git -C '$ROOT' checkout -q main
    git -C '$ROOT' rev-parse p079/foreign")"
  sed -i "s|^base_commit:.*|base_commit: ${foreign}|" \
    "$ROOT/$(_evidence E-900-2_2)/fsm-state.yaml"

  run _pf epic-start P900 E-900-2_2 --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an ancestor"* ]]
  [ "$(_state_base E-900-2_2)" = "$foreign" ]           # untouched
}

# ─── refusals and no-ops ───────────────────────────────────────────────────

@test "P079 Step 3: a DIVERGED task branch is refused by name — nothing is merged, nothing is moved" {
  _mk_project
  _seed_chain
  local plan_head branch_head old_state
  plan_head="$(_merge_epic1)"
  # EPIC 2 has its own commit on the OLD base: behind AND ahead.
  _in_root "set -e
    git -C '$ROOT' checkout -q task/E-900-2_2/main
    printf 'epic two work\n' > '$ROOT/epic-two.txt'
    git -C '$ROOT' add epic-two.txt
    git -C '$ROOT' -c user.email=t@e -c user.name=t commit -q -m 'EPIC 2 work'
    git -C '$ROOT' checkout -q main"
  branch_head="$(git -C "$ROOT" rev-parse task/E-900-2_2/main)"
  old_state="$(_state_base E-900-2_2)"

  run _pf epic-start P900 E-900-2_2 --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"diverged"* ]]
  [[ "$output" == *"$branch_head"* ]]
  [[ "$output" == *"$plan_head"* ]]
  [ "$(git -C "$ROOT" rev-parse task/E-900-2_2/main)" = "$branch_head" ]
  [ "$(_state_base E-900-2_2)" = "$old_state" ]
}

@test "P079 Step 3: a branch that already CONTAINS the plan head (mid-execution, own commits) is left alone" {
  _mk_project
  _seed_chain
  local branch_head state_before
  # EPIC 1 is the first chain member: its branch is at the plan head and then
  # grows its own work. Nothing to reconcile.
  _in_root "set -e
    git -C '$ROOT' checkout -q task/E-900-1_2/main
    printf 'work in progress\n' > '$ROOT/wip.txt'
    git -C '$ROOT' add wip.txt
    git -C '$ROOT' -c user.email=t@e -c user.name=t commit -q -m 'in progress'
    git -C '$ROOT' checkout -q main"
  branch_head="$(git -C "$ROOT" rev-parse task/E-900-1_2/main)"
  state_before="$(_state_base E-900-1_2)"

  run _pf epic-start P900 E-900-1_2 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"fast-forward"* ]]
  [ "$(git -C "$ROOT" rev-parse task/E-900-1_2/main)" = "$branch_head" ]
  [ "$(_state_base E-900-1_2)" = "$state_before" ]
}

@test "P079 Step 3: a single-EPIC plan whose branch is already at the plan head is byte-identical (no event, no writes)" {
  _mk_project
  _seed_chain
  local state_before manifest_before
  state_before="$(_state_base E-900-1_2)"
  manifest_before="$(_manifest_base E-900-1_2)"

  run _pf epic-start P900 E-900-1_2 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(_state_base E-900-1_2)" = "$state_before" ]
  [ "$(_manifest_base E-900-1_2)" = "$manifest_before" ]
  [ ! -f "$ROOT/$(_evidence E-900-1_2)/timeline.jsonl" ]
}
