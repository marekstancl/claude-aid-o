#!/usr/bin/env bats
# test-worktree-enforcement.bats — P074 Step 8: every plan-linked lifecycle
# command that touches a tree runs in the PLAN's tree, or refuses.
#
# THE GROUNDED FAILURE MODE UNDER TEST: "the controller dispatches agents with
# cwd = the plan worktree" is a promise an instruction file makes and nothing
# checks. epic-merge-to-plan checks out `plan/<id>` and merges; plan-finalize
# sync/freeze/gates do the same; `aid-fsm.sh init` creates the task branch and
# `done-advance` attributes the EPIC diff — all of them against whatever tree
# they are handed. A direct operator call from the primary checkout would
# therefore hijack the PM's own tree, which is precisely the single-stream
# behaviour P074 removes. So each of them now reads the plan's recorded
# worktree and RE-EXECUTES there (the default), or REFUSES naming the repair
# (only when the worktree itself is broken).
#
# `plan-close` and `plan-rollback` get the INVERSE: they REMOVE that tree, and
# nothing may delete the directory it is standing in — so they refuse from
# inside it, with the exact `cd <state_root>` instruction.
#
# FD-3 HYGIENE: bats reports results over fd 3; a child that inherits and holds
# it truncates the suite's TAP output (missing results still exit 0). Every
# invocation below runs with `3>&-`, and every `run` goes through a `bash -c`
# helper that can never itself be a missing command — a `run` child exiting 127
# writes a bats warning to fd 3, which with `3>&-` destroys the whole file's
# output. After any edit verify:
#   bats --tap test-worktree-enforcement.bats | grep -cE '^(ok|not ok)'  # == 19

load test-helpers.bash

PLAN_ID="P941"
EPIC_ID="E-941-1_1"

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_FSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export PLAN_FSM FSM
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  ROOT="$TEST_TMPDIR/project"
  export ROOT
  unset AID_PROJECT_ROOT AID_WT_REDIRECTED
  export AID_PLAN_STATE_PROJECT_ROOT="$ROOT" AID_PLAN_MANIFEST_PROJECT_ROOT="$ROOT"
}

teardown() {
  cd /
  [[ -d "$TEST_TMPDIR" ]] && chmod -R u+rwX "$TEST_TMPDIR" 2>/dev/null || true
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_wt() { printf '%s/.aid-worktrees/plan-%s' "$ROOT" "$PLAN_ID"; }
_phys() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

_in_root() {
  bash -c "cd '$ROOT' || exit 9
           export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
           $1" 3>&-
}

# _from <dir> <script> <args...> — run a real CLI with <dir> as cwd. `bash -c`
# can never be a missing command, so no 127-on-fd-3.
_from() {
  local d="$1" prog="$2"; shift 2
  local q="" a
  for a in "$@"; do q+=" '${a}'"; done
  bash -c "cd '$d' && exec bash '$prog'${q}" 3>&-
}

_primary_head() { git -C "$ROOT" rev-parse HEAD 3>&-; }
_primary_branch() { git -C "$ROOT" symbolic-ref --short HEAD 2>/dev/null 3>&- || echo DETACHED; }

# _mk_project — a committed checkout with the gitignored runtime area and the
# tracked delivery file the EPIC work lands in.
_mk_project() {
  mkdir -p "$ROOT/.aid-o/plans" "$ROOT/.aid-o/config" "$ROOT/.aid-o/work/evidence"
  printf 'counter: 0\n' > "$ROOT/.aid-o/config/counter.yaml"
  printf '.aid-o/\n.aid-worktrees/\n' > "$ROOT/.gitignore"
  printf 'seed\n' > "$ROOT/README.md"
  printf 'delivered\n' > "$ROOT/epic-work.txt"
  printf '# %s\n\n## Acceptance Criteria\n- [ ] something\n' "$PLAN_ID" \
    > "$ROOT/.aid-o/plans/${PLAN_ID}-test-plan.md"
  (
    exec 3>&-        # never hand bats' report fd to the git bootstrap
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed project"
  )
}

# _seed_plan <with_worktree:0|1> [record_override]
#   The plan branch, its state file and its manifest; the worktree is created
#   and recorded when asked. `record_override` (a path) is written into
#   plan-state INSTEAD of the real worktree path — the "plan-state lies"
#   fixture the loop guard exists for.
_seed_plan() {
  local with_wt="${1:-1}" override="${2:-}"
  _in_root "set -e
    source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
    source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh'
    base=\$(git -C '$ROOT' rev-parse main)
    git -C '$ROOT' branch plan/${PLAN_ID} \"\$base\"
    plan_state_init ${PLAN_ID} plan_branch plan/${PLAN_ID} main >/dev/null
    plan_manifest_init ${PLAN_ID} plan/${PLAN_ID} main \"\$base\" \"\$base\" plan_branch >/dev/null
    if [[ '$with_wt' == '1' ]]; then
      git -C '$ROOT' worktree add -q '$(_wt)' plan/${PLAN_ID}
    fi
    if [[ -n '$override' ]]; then
      plan_state_set_worktree_path ${PLAN_ID} '$override'
    elif [[ '$with_wt' == '1' ]]; then
      plan_state_set_worktree_path ${PLAN_ID} '$(_wt)'
    fi"
}

# _seed_completed_epic — an epic_runs[] entry, a real task branch carrying one
# marker commit made IN THE WORKTREE, and the full completion evidence
# epic-merge-to-plan's F2 gate demands: the recorded completion sha / run id /
# evidence dir, a DONE fsm-state.yaml in that dir, and an `epic-complete`
# operation ledger record at `state_committed`. Built through the real library
# entry points, because the merge verifies all of it.
_seed_completed_epic() {
  _in_root "set -e
    source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
    source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh'
    ev='.aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1'
    base=\$(git -C '$ROOT' rev-parse plan/${PLAN_ID})
    git -C '$ROOT' branch task/${EPIC_ID}/main \"\$base\"
    plan_manifest_add_epic ${PLAN_ID} ${EPIC_ID} R-${EPIC_ID}-1 \
      task/${EPIC_ID}/main \"\$base\" plan/${PLAN_ID} \"\$ev\" proven >/dev/null
    # The delivery, committed in the plan worktree.
    git -C '$(_wt)' checkout -q task/${EPIC_ID}/main
    printf 'epic marker\n' > '$(_wt)/epic-marker.txt'
    git -C '$(_wt)' add epic-marker.txt
    git -C '$(_wt)' commit -q -m 'the EPIC delivery'
    git -C '$(_wt)' checkout -q plan/${PLAN_ID}
    tip=\$(git -C '$ROOT' rev-parse task/${EPIC_ID}/main)
    mkdir -p '$ROOT'/\"\$ev\"
    printf 'state: DONE\n' > '$ROOT'/\"\$ev\"/fsm-state.yaml
    plan_manifest_update ${PLAN_ID} \".plan_boundary_manifest.epic_runs |= map(
        if .epic_id == \\\"${EPIC_ID}\\\"
        then . + {merge_status: \\\"pending\\\",
                  epic_completion_sha: \\\"\$tip\\\",
                  epic_completion_run_id: \\\"R-${EPIC_ID}-1\\\",
                  epic_completion_evidence_dir: \\\"\$ev\\\"}
        else . end)\" >/dev/null
    op=\$(plan_op_key epic-complete ${PLAN_ID} - 0 ${EPIC_ID})
    plan_op_begin ${PLAN_ID} \"\$op\" epic-complete ${EPIC_ID} \"\$tip\" >/dev/null
    plan_op_mark_git_applied ${PLAN_ID} \"\$op\" \"\$tip\" >/dev/null
    plan_op_commit ${PLAN_ID} \"\$op\" >/dev/null"
}

# ─── 1-3. the redirect: the worktree moves, the primary checkout does not ──

@test "P074 Step 8: plan-finalize --stage sync invoked FROM THE PRIMARY CHECKOUT executes in the plan worktree" {
  _mk_project
  _seed_plan 1
  local before_head before_branch
  before_head="$(_primary_head)"; before_branch="$(_primary_branch)"

  run _from "$ROOT" "$PLAN_FSM" plan-finalize "$PLAN_ID" --stage sync --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"executes in its own worktree"* ]]
  [[ "$output" == *"$(_phys "$(_wt)")"* ]]
  # The PM's checkout never moved: same branch, same HEAD.
  [ "$(_primary_branch)" = "$before_branch" ]
  [ "$(_primary_head)" = "$before_head" ]
}

@test "P074 Step 8: epic-merge-to-plan invoked FROM THE PRIMARY CHECKOUT merges in the plan worktree, not in the PM's tree" {
  _mk_project
  _seed_plan 1
  _seed_completed_epic
  local before_head before_branch
  before_head="$(_primary_head)"; before_branch="$(_primary_branch)"

  run _from "$ROOT" "$PLAN_FSM" epic-merge-to-plan "$PLAN_ID" "$EPIC_ID" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"executes in its own worktree"* ]]
  # The merge landed on the plan branch and the marker is present in the
  # WORKTREE's tree...
  [ -f "$(_wt)/epic-marker.txt" ]
  # ...and nowhere near the PM's checkout, which is still on main at main.
  [ ! -f "$ROOT/epic-marker.txt" ]
  [ "$(_primary_branch)" = "$before_branch" ]
  [ "$(_primary_head)" = "$before_head" ]
}

@test "P074 Step 8: aid-fsm.sh init invoked FROM THE PRIMARY CHECKOUT creates the task branch in the plan worktree" {
  _mk_project
  _seed_plan 1
  local before_head before_branch
  before_head="$(_primary_head)"; before_branch="$(_primary_branch)"

  run _from "$ROOT" "$FSM" init "$EPIC_ID" "R-${EPIC_ID}-1" 2 manual main HEAD \
    ".aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"executes in its own worktree"* ]]
  # The task branch exists and is CHECKED OUT in the worktree...
  run bash -c "git -C '$(_wt)' symbolic-ref --short HEAD" 3>&-
  [ "$output" = "task/${EPIC_ID}/main" ]
  # ...while the PM's checkout is untouched.
  [ "$(_primary_branch)" = "$before_branch" ]
  [ "$(_primary_head)" = "$before_head" ]
  # State still lives in the PRIMARY .aid-o, never in the worktree.
  [ -f "$ROOT/.aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml" ]
  [ ! -d "$(_wt)/.aid-o" ]
}

@test "P074 Step 8: aid-fsm.sh done-advance invoked FROM THE PRIMARY CHECKOUT redirects into the plan worktree" {
  _mk_project
  _seed_plan 1
  local sf=".aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml"
  run _from "$ROOT" "$FSM" init "$EPIC_ID" "R-${EPIC_ID}-1" 2 manual main HEAD "$sf"
  [ "$status" -eq 0 ]
  # done-advance's own DONE-state precondition will refuse (the run is READY) —
  # what this case proves is that the refusal is reported from the WORKTREE,
  # i.e. the redirect happened before the first tree/state read, and that the
  # RELATIVE state-file path survived the change of directory.
  run _from "$ROOT" "$FSM" done-advance review release "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"executes in its own worktree"* ]]
  [[ "$output" == *"done-advance requires state DONE"* ]]
}

# ─── 4. already inside the worktree: no redirect, zero overhead ────────────

@test "P074 Step 8: a command run FROM INSIDE the plan worktree does not redirect" {
  _mk_project
  _seed_plan 1
  run _from "$(_wt)" "$PLAN_FSM" plan-finalize "$PLAN_ID" --stage sync --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"executes in its own worktree"* ]]
}

# ─── 5-6. refusals: a broken worktree is never a silent fallback ───────────

@test "P074 Step 8: a RECORDED but missing worktree refuses, naming --recreate-worktree" {
  _mk_project
  _seed_plan 1
  # Remove the tree behind git's back — the crash/manual-rm shape.
  rm -rf "$(_wt)"
  run _from "$ROOT" "$PLAN_FSM" plan-finalize "$PLAN_ID" --stage sync --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or is no longer registered"* ]]
  [[ "$output" == *"--recreate-worktree"* ]]
}

@test "P074 Step 8: aid-fsm.sh init also refuses a recorded-but-missing worktree, naming --recreate-worktree" {
  _mk_project
  _seed_plan 1
  rm -rf "$(_wt)"
  run _from "$ROOT" "$FSM" init "$EPIC_ID" "R-${EPIC_ID}-1" 2 manual main HEAD \
    ".aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--recreate-worktree"* ]]
  # It refused BEFORE writing anything.
  [ ! -f "$ROOT/.aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml" ]
}

@test "P074 Step 8: the crash window (a worktree exists but is UNRECORDED) refuses instead of passing as legacy" {
  _mk_project
  # Worktree created, plan-state NOT told about it — exactly what a kill
  # between `worktree add` and the state write leaves behind.
  _seed_plan 1 ""
  _in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
            plan_state_set_worktree_path ${PLAN_ID} ''"
  run _from "$ROOT" "$PLAN_FSM" plan-finalize "$PLAN_ID" --stage sync --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"records NO execution worktree, but one exists"* ]]
  [[ "$output" == *"plan-start"* ]]
  [[ "$output" == *"--recreate-worktree"* ]]
}

# ─── 7. legacy plans are byte-identical to pre-P074 ────────────────────────

@test "P074 Step 8: a legacy plan (no worktree anywhere) runs in the primary checkout, unchanged" {
  _mk_project
  _seed_plan 0
  local before_branch; before_branch="$(_primary_branch)"
  run _from "$ROOT" "$PLAN_FSM" plan-finalize "$PLAN_ID" --stage sync --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"executes in its own worktree"* ]]
  [[ "$output" == *"no execution worktree"* ]]
  [ "$(_primary_branch)" = "$before_branch" ]
}

@test "P074 Step 8: aid-fsm.sh init for a legacy plan behaves exactly as before (task branch in the primary checkout)" {
  _mk_project
  _seed_plan 0
  run _from "$ROOT" "$FSM" init "$EPIC_ID" "R-${EPIC_ID}-1" 2 manual main HEAD \
    ".aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" != *"executes in its own worktree"* ]]
  [ "$(_primary_branch)" = "task/${EPIC_ID}/main" ]
}

# ─── 8. the loop guard ─────────────────────────────────────────────────────

@test "P074 Step 8: a redirect that did not land inside the recorded tree terminates on the loop guard" {
  _mk_project
  _seed_plan 1
  # The state a second redirect would be entered in: we have already been
  # re-executed once (AID_WT_REDIRECTED set) and are still OUTSIDE the recorded
  # worktree — the shape a plan-state that describes a place it is not produces.
  # The guard must TERMINATE here; the failure mode it exists for is unbounded
  # recursion, so "refuses" is the assertion, and the exit is what proves it.
  run bash -c "cd '$ROOT' && AID_WT_REDIRECTED=1 exec bash '$PLAN_FSM' \
    plan-finalize '$PLAN_ID' --stage sync --project-root '$ROOT'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"worktree redirect loop"* ]]
  [[ "$output" == *"--recreate-worktree"* ]]
}

# ─── 9-10. the INVERSE: never delete the tree you are standing in ─────────

@test "P074 Step 8: plan-close refuses when invoked from INSIDE the worktree it would remove" {
  _mk_project
  _seed_plan 1
  run _from "$(_wt)" "$PLAN_FSM" plan-close "$PLAN_ID" --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"you are standing inside it"* ]]
  [[ "$output" == *"cd ${ROOT}"* ]]
  # It refused before doing anything: the worktree is still there.
  [ -d "$(_wt)" ]
}

@test "P074 Step 8: plan-rollback refuses when invoked from INSIDE the worktree it would remove" {
  _mk_project
  _seed_plan 1
  run _from "$(_wt)" "$PLAN_FSM" plan-rollback "$PLAN_ID" \
    --revert-commit "$(git -C "$ROOT" rev-parse main 3>&-)" --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"you are standing inside it"* ]]
  [[ "$output" == *"cd ${ROOT}"* ]]
  [ -d "$(_wt)" ]
}

# ─── 11-12. a recorded path that is NOT a linked worktree is a lie ─────────
#
# `git worktree list` includes the PRIMARY checkout, so "recorded + exists +
# registered" is satisfied by a `worktree_path` naming the state root — and the
# cwd comparison would then pass it as "already there", running every checkout
# and merge in the PM's own tree while the command reported isolation. No
# redirect is attempted, so the loop guard can never fire either. Both CLIs
# therefore validate LINKEDNESS before the cwd check.

@test "P074 Step 8: a worktree_path recorded as the PRIMARY checkout is refused, not accepted as 'already there'" {
  _mk_project
  _seed_plan 0 "$ROOT"
  local before_branch; before_branch="$(_primary_branch)"
  run _from "$ROOT" "$PLAN_FSM" plan-finalize "$PLAN_ID" --stage sync --project-root "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a LINKED worktree"* ]]
  [[ "$output" == *"--recreate-worktree"* ]]
  # The decisive assertion: the PM's checkout was never used as the plan's tree.
  [ "$(_primary_branch)" = "$before_branch" ]
}

@test "P074 Step 8: aid-fsm.sh init also refuses a worktree_path recorded as the primary checkout" {
  _mk_project
  _seed_plan 0 "$ROOT"
  local before_branch; before_branch="$(_primary_branch)"
  run _from "$ROOT" "$FSM" init "$EPIC_ID" "R-${EPIC_ID}-1" 2 manual main HEAD \
    ".aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a LINKED worktree"* ]]
  # It refused before creating a branch or writing state in the PM's tree.
  [ "$(_primary_branch)" = "$before_branch" ]
  [ ! -f "$ROOT/.aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml" ]
}

# ─── 13. the in-worktree flow: a RELATIVE state file must still resolve ────

@test "P074 Step 8: done-advance invoked FROM INSIDE the plan worktree resolves the relative state file to the PRIMARY .aid-o" {
  _mk_project
  _seed_plan 1
  local sf=".aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml"
  run _from "$ROOT" "$FSM" init "$EPIC_ID" "R-${EPIC_ID}-1" 2 manual main HEAD "$sf"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/$sf" ]

  # `.aid-o` exists ONLY in the primary checkout, so before the state-root
  # re-anchoring this died on "state_file not found" — making the in-worktree
  # flow, which IS the normal case in worktree mode, impossible.
  run _from "$(_wt)" "$FSM" done-advance review release "$sf"
  [ "$status" -ne 0 ]
  [[ "$output" != *"state_file not found"* ]]
  [[ "$output" == *"done-advance requires state DONE"* ]]
  # No forked workspace was created in the worktree on the way.
  [ ! -d "$(_wt)/.aid-o" ]
}

@test "P074 Step 8: init invoked FROM INSIDE the plan worktree writes state to the PRIMARY .aid-o, not a forked one" {
  _mk_project
  _seed_plan 1
  run _from "$(_wt)" "$FSM" init "$EPIC_ID" "R-${EPIC_ID}-1" 2 manual main HEAD \
    ".aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/.aid-o/work/evidence/${EPIC_ID}/R-${EPIC_ID}-1/fsm-state.yaml" ]
  [ ! -d "$(_wt)/.aid-o" ]
}

# ─── 14-15. the redirect must carry OPERATOR-RELATIVE PATHS across the cd ──

@test "P074 Step 8: a relative --execution-yaml survives the redirect (resolved against the operator's cwd, not the worktree)" {
  _mk_project
  _seed_plan 1
  # The config exists ONLY in the primary checkout, addressed relatively.
  mkdir -p "$ROOT/myconf"
  printf 'version: "1.0"\ngates: {}\ngate_profiles: {release: {include: []}}\n' \
    > "$ROOT/myconf/execution.yaml"
  run _from "$ROOT" "$PLAN_FSM" plan-finalize "$PLAN_ID" --stage gates \
    --execution-yaml myconf/execution.yaml --project-root "$ROOT"
  [ "$status" -ne 0 ]   # no frozen candidate yet — that is the NEXT precondition
  [[ "$output" == *"executes in its own worktree"* ]]
  # The proof: the config was FOUND on the other side of the cd. Unrewritten it
  # would have resolved inside the worktree, where myconf/ does not exist.
  [[ "$output" != *"execution config not found"* ]]
  [[ "$output" == *"no frozen candidate"* ]]
}

@test "P074 Step 8: the argv rewriter absolutizes only the VALUE half of --substitute-receipt <gate>=<path>" {
  _mk_project
  # A direct contract check on the rewriter: compound `key=value` flags are the
  # shape a purely string-shaped heuristic gets wrong (the first component of
  # `bats_all=receipts/pass.json` is `bats_all=receipts`, which is no directory).
  mkdir -p "$ROOT/receipts"
  printf '{}\n' > "$ROOT/receipts/pass.json"
  run bash -c "cd '$ROOT'
    source '$PLAN_FSM'
    _pfsm_wt_abs_args plan-finalize P941 --stage gates \\
      --substitute-receipt bats_all=receipts/pass.json \\
      --execution-yaml myconf/execution.yaml --project-root . -- task/E-941-1_1/main" 3>&-
  [ "$status" -eq 0 ]
  # The gate id is untouched; only the path half is absolutized.
  [[ "$output" == *"bats_all=${ROOT}/receipts/pass.json"* ]]
  # Enumerated path flags are absolutized by declaration, existing or not.
  [[ "$output" == *"${ROOT}/myconf/execution.yaml"* ]]
  [[ "$output" == *"${ROOT}/."* ]]
  # Ids, stage names and branch-shaped arguments pass through verbatim.
  [[ "$output" == *"P941"* ]]
  [[ "$output" == *"gates"* ]]
  [[ "$output" == *"task/E-941-1_1/main"* ]]
  [[ "$output" != *"${ROOT}/task/E-941-1_1/main"* ]]
}
