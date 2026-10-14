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
# Since 3.0.0 no task branch is cut any more (a plan runs as one run on
# plan/<id>, test-plan-run.bats); the cases left here guard the foreign-worktree skip and
# the plan-less run in the primary checkout.
#
# FD-3 HYGIENE: bats reports results over fd 3; a child that inherits and holds
# it truncates the suite's TAP output (missing results still exit 0). Every
# invocation below runs with `3>&-`, and every `run` goes through a `bash -c`
# helper that can never itself be a missing command — a `run` child exiting 127
# writes a bats warning to fd 3, which with `3>&-` destroys the whole file's
# output. After any edit verify:
#   bats --tap test-worktree-topology.bats | grep -cE '^(ok|not ok)'   # == 2

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
