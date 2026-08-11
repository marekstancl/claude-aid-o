#!/usr/bin/env bats
# aid-tier: t2
# test-worktree-topology.bats — P074 Step 9: inside the plan worktree, EPIC
# execution uses exactly today's branch model.
#
# THE GROUNDED FAILURE MODE UNDER TEST: `is_worktree()` made `aid-fsm.sh init`
# skip branch enforcement in ANY linked worktree ("the caller controls the
# branch" — true for the disposable worktrees other tools create). Once the
# plan's OWN worktree becomes the place its EPICs run, that blanket skip would
# leave init sitting on `plan/<id>` with no task branch at all, and done-advance
# would then attribute an EMPTY diff to the EPIC. So the skip narrows: in the
# plan's recorded worktree enforcement RUNS — the worktree behaves exactly like
# a dedicated "main" for that plan, with `plan/<id>` playing the integration
# role and `task/<epic>/main` cut FROM IT (not from main, which is what makes a
# second EPIC start from the ADVANCED plan head). A foreign worktree keeps the
# old skip, and the primary checkout is byte-identical to pre-P074.
#
# FD-3 HYGIENE: bats reports results over fd 3; a child that inherits and holds
# it truncates the suite's TAP output (missing results still exit 0). Every
# invocation below runs with `3>&-`, and every `run` goes through a `bash -c`
# helper that can never itself be a missing command — a `run` child exiting 127
# writes a bats warning to fd 3, which with `3>&-` destroys the whole file's
# output. After any edit verify:
#   bats --tap test-worktree-topology.bats | grep -cE '^(ok|not ok)'   # == 8

load test-helpers.bash

PLAN_ID="P942"
EPIC_A="E-942-1_2"
EPIC_B="E-942-2_2"

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

_in_root() {
  bash -c "cd '$ROOT' || exit 9
           export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
           $1" 3>&-
}

_from() {
  local d="$1" prog="$2"; shift 2
  local q="" a
  for a in "$@"; do q+=" '${a}'"; done
  bash -c "cd '$d' && exec bash '$prog'${q}" 3>&-
}

# _init_in <dir> <epic_id> — `aid-fsm.sh init` with the state file expressed
# RELATIVE to the state root, exactly as every real caller passes it.
_init_in() {
  local d="$1" e="$2"
  _from "$d" "$FSM" init "$e" "R-${e}-1" 2 manual main HEAD \
    ".aid-o/work/evidence/${e}/R-${e}-1/fsm-state.yaml"
}

_head_of() { git -C "$1" symbolic-ref --short HEAD 2>/dev/null 3>&- || echo DETACHED; }

_mk_project() {
  mkdir -p "$ROOT/.aid-o/plans" "$ROOT/.aid-o/config" "$ROOT/.aid-o/work/evidence"
  printf 'counter: 0\n' > "$ROOT/.aid-o/config/counter.yaml"
  printf '.aid-o/\n.aid-worktrees/\n' > "$ROOT/.gitignore"
  printf 'seed\n' > "$ROOT/README.md"
  printf 'delivered\n' > "$ROOT/epic-work.txt"
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

# _seed_plan <with_worktree:0|1> — plan branch, state, manifest, worktree.
_seed_plan() {
  local with_wt="${1:-1}"
  _in_root "set -e
    source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh'
    source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh'
    base=\$(git -C '$ROOT' rev-parse main)
    git -C '$ROOT' branch plan/${PLAN_ID} \"\$base\"
    plan_state_init ${PLAN_ID} plan_branch plan/${PLAN_ID} main >/dev/null
    plan_manifest_init ${PLAN_ID} plan/${PLAN_ID} main \"\$base\" \"\$base\" plan_branch >/dev/null
    if [[ '$with_wt' == '1' ]]; then
      git -C '$ROOT' worktree add -q '$(_wt)' plan/${PLAN_ID}
      plan_state_set_worktree_path ${PLAN_ID} '$(_wt)'
    fi"
}

# ─── 1. the fresh-init case inside the plan worktree ──────────────────────

@test "P074 Step 9: init inside the plan worktree cuts task/<epic>/main FROM the plan head and checks it out THERE" {
  _mk_project
  _seed_plan 1
  local plan_head; plan_head="$(git -C "$ROOT" rev-parse "plan/${PLAN_ID}" 3>&-)"
  local primary_before; primary_before="$(_head_of "$ROOT")"

  run _init_in "$(_wt)" "$EPIC_A"
  [ "$status" -eq 0 ]
  # Enforcement RAN (it did not take the foreign-worktree skip)...
  [[ "$output" != *"skipping branch enforcement"* ]]
  [[ "$output" == *"from plan/${PLAN_ID} (plan worktree)"* ]]
  # ...the branch exists, is based on the plan head, and is checked out in the
  # WORKTREE.
  [ "$(_head_of "$(_wt)")" = "task/${EPIC_A}/main" ]
  run bash -c "git -C '$ROOT' rev-parse 'task/${EPIC_A}/main'" 3>&-
  [ "$output" = "$plan_head" ]
  # The primary checkout never moved.
  [ "$(_head_of "$ROOT")" = "$primary_before" ]
}

# ─── 2. the second EPIC starts from the ADVANCED plan head ────────────────

@test "P074 Step 9: a second EPIC's branch is cut from the plan head AFTER the first EPIC merged, not from main" {
  _mk_project
  _seed_plan 1
  run _init_in "$(_wt)" "$EPIC_A"
  [ "$status" -eq 0 ]
  # EPIC A delivers and its work lands on the plan branch.
  _in_root "set -e
    printf 'A delivered\n' > '$(_wt)/a.txt'
    git -C '$(_wt)' add a.txt
    git -C '$(_wt)' commit -q -m 'EPIC A'
    git -C '$(_wt)' checkout -q plan/${PLAN_ID}
    git -C '$(_wt)' merge -q --no-ff --no-edit task/${EPIC_A}/main"
  local advanced; advanced="$(git -C "$ROOT" rev-parse "plan/${PLAN_ID}" 3>&-)"
  [ "$advanced" != "$(git -C "$ROOT" rev-parse main 3>&-)" ]

  run _init_in "$(_wt)" "$EPIC_B"
  [ "$status" -eq 0 ]
  run bash -c "git -C '$ROOT' rev-parse 'task/${EPIC_B}/main'" 3>&-
  [ "$output" = "$advanced" ]
  # EPIC A's delivery is visible from EPIC B's branch — the whole point of
  # basing on the plan head instead of on main.
  [ -f "$(_wt)/a.txt" ]
}

# ─── 3. a foreign worktree keeps the old blanket skip ─────────────────────

@test "P074 Step 9: init inside a FOREIGN worktree still skips branch enforcement" {
  _mk_project
  _seed_plan 1
  local foreign="$TEST_TMPDIR/foreign"
  git -C "$ROOT" worktree add -q "$foreign" -b someone-elses/branch 3>&-
  # An EPIC that belongs to NO worktree-recorded plan, so the Step 8 enforcer
  # is a no-op and only the Step 9 skip decision is under test.
  run _init_in "$foreign" "E-909-1_1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping branch enforcement"* ]]
  [ "$(_head_of "$foreign")" = "someone-elses/branch" ]
}

# ─── 4. the full in-worktree cycle ────────────────────────────────────────

@test "P074 Step 9: the full cycle (task branch -> commit -> merge to plan) runs in the worktree and leaves it on the plan branch" {
  _mk_project
  _seed_plan 1
  local primary_before_branch primary_before_head
  primary_before_branch="$(_head_of "$ROOT")"
  primary_before_head="$(git -C "$ROOT" rev-parse HEAD 3>&-)"

  run _init_in "$(_wt)" "$EPIC_A"
  [ "$status" -eq 0 ]
  _in_root "set -e
    printf 'the delivery\n' > '$(_wt)/delivered-by-epic.txt'
    git -C '$(_wt)' add delivered-by-epic.txt
    git -C '$(_wt)' commit -q -m 'EPIC A delivery'
    git -C '$(_wt)' checkout -q plan/${PLAN_ID}
    git -C '$(_wt)' merge -q --no-ff --no-edit task/${EPIC_A}/main"

  # The merge is on the plan branch, the worktree ends on the plan branch...
  [ "$(_head_of "$(_wt)")" = "plan/${PLAN_ID}" ]
  [ -f "$(_wt)/delivered-by-epic.txt" ]
  # ...and the PM's checkout is untouched throughout.
  [ "$(_head_of "$ROOT")" = "$primary_before_branch" ]
  [ "$(git -C "$ROOT" rev-parse HEAD 3>&-)" = "$primary_before_head" ]
  [ ! -f "$ROOT/delivered-by-epic.txt" ]
}

# ─── 5. legacy primary-checkout behaviour, regression-asserted ────────────

@test "P074 Step 9 regression: a legacy plan in the primary checkout auto-creates from main exactly as before" {
  _mk_project
  _seed_plan 0
  local main_head; main_head="$(git -C "$ROOT" rev-parse main 3>&-)"
  run _init_in "$ROOT" "$EPIC_A"
  [ "$status" -eq 0 ]
  [[ "$output" != *"plan worktree"* ]]
  [ "$(_head_of "$ROOT")" = "task/${EPIC_A}/main" ]
  run bash -c "git -C '$ROOT' rev-parse 'task/${EPIC_A}/main'" 3>&-
  [ "$output" = "$main_head" ]
}

# ─── 6. the different-EPIC hard fail still fires inside the worktree ──────

@test "P074 Step 9: task/E-<other>/main inside the plan worktree still hard-fails (EPICs stay sequential)" {
  _mk_project
  _seed_plan 1
  run _init_in "$(_wt)" "$EPIC_A"
  [ "$status" -eq 0 ]
  [ "$(_head_of "$(_wt)")" = "task/${EPIC_A}/main" ]
  # A second EPIC init while the worktree still sits on the first EPIC's branch.
  run _init_in "$(_wt)" "$EPIC_B"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected task/${EPIC_B}/main"* ]]
}

# ─── 7. the plan branch deleted under a surviving worktree ────────────────

@test "P074 Step 9: with plan/<id> deleted, init inside the worktree HARD-FAILS naming the plan branch, not --recreate-worktree" {
  _mk_project
  _seed_plan 1
  # Manual surgery: the branch goes, the worktree (now detached) stays
  # registered and recorded, so the Step 8 enforcer is satisfied and only the
  # base-ref resolution can fail. Warn-and-accept here would leave execution on
  # an unowned detached tree with NO task branch — done-advance would then
  # attribute a meaningless diff, which is the failure this refusal prevents.
  _in_root "git -C '$(_wt)' checkout -q --detach plan/${PLAN_ID}
            git -C '$ROOT' branch -D plan/${PLAN_ID}"
  run _init_in "$(_wt)" "$EPIC_A"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan/${PLAN_ID} does not exist"* ]]
  [[ "$output" == *"every EPIC branch here is cut from it"* ]]
  # The remedy is branch repair, and the message says so explicitly...
  [[ "$output" == *"Repair the branch"* ]]
  # ...while NOT sending the operator at a worktree that is perfectly fine.
  [[ "$output" != *"plan-state ${PLAN_ID} --recreate-worktree --reason"* ]]
  # Nothing was created on the way out.
  run bash -c "git -C '$ROOT' rev-parse --verify --quiet 'refs/heads/task/${EPIC_A}/main' || true" 3>&-
  [ -z "$output" ]
}

# ─── 8. an unusual branch inside the plan worktree names the topology ─────

@test "P074 Step 9: an unrelated branch inside the plan worktree warns naming the expected topology" {
  _mk_project
  _seed_plan 1
  _in_root "git -C '$(_wt)' checkout -q -b scratch/manual-poking"
  run _init_in "$(_wt)" "$EPIC_A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unusual branch in the plan worktree"* ]]
  [[ "$output" == *"plan/${PLAN_ID} at rest"* ]]
  [[ "$output" == *"task/${EPIC_A}/main"* ]]
}
