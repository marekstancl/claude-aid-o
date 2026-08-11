#!/usr/bin/env bats
# aid-tier: t2
# test-drift-worktree.bats — P074 Step 10: the candidate-drift check and the
# plan-final gate run are bound to the PLAN WORKTREE, not to whatever tree the
# PM happens to be standing in.
#
# THE GROUNDED FAILURE MODE UNDER TEST — and the headline case of the whole
# plan: review and c4 used to pin the OPERATOR's checkout to the frozen
# candidate ("check out plan/<id> and stay there"), and the drift detector read
# THAT tree's `git status`. So any unrelated tracked edit the PM made in their
# own checkout during a review window invalidated the review and sent the plan
# back to PLAN_FIX. With the candidate living in the plan's own worktree, the
# detector reads that worktree instead: the PM's checkout is free, and only a
# real edit to the candidate still invalidates.
#
# Cases 1-5 call `_pfsm_review_candidate_drift` DIRECTLY (aid-plan-fsm.sh is
# sourceable — its dispatcher is BASH_SOURCE-guarded), because the detector's
# contract IS the unit under test: which tree it reads, and that its
# invalidation reasons and exit codes are unchanged. Case 6 runs the real
# `--stage gates` end to end, since "the gates stamp the WORKTREE's head" can
# only be proven by the report the runner actually writes.
#
# FD-3 HYGIENE: bats reports results over fd 3; a child that inherits and holds
# it truncates the suite's TAP output (missing results still exit 0). Every
# invocation below runs with `3>&-`, and every `run` goes through a `bash -c`
# helper that can never itself be a missing command — a `run` child exiting 127
# writes a bats warning to fd 3, which with `3>&-` destroys the whole file's
# output. After any edit verify:
#   bats --tap test-drift-worktree.bats | grep -cE '^(ok|not ok)'   # == 6

load test-helpers.bash

PLAN_ID="P940"

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_FSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PLAN_FSM
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

_pf() {
  local q="" a
  for a in "$@"; do q+=" '${a}'"; done
  bash -c "cd '$ROOT' && exec bash '$PLAN_FSM'${q}" 3>&-
}

# _drift <candidate> — the detector under test, invoked through a sourced
# aid-plan-fsm.sh. Prints its reason on stdout; the exit code is the verdict
# (0 = the review still holds, 1 = invalidated).
_drift() {
  bash -c "cd '$ROOT'
           export AID_PLAN_STATE_PROJECT_ROOT='$ROOT' AID_PLAN_MANIFEST_PROJECT_ROOT='$ROOT'
           source '$PLAN_FSM'
           _pfsm_review_candidate_drift '$ROOT' '$PLAN_ID' '$1'" 3>&-
}

_candidate() { git -C "$ROOT" rev-parse "plan/${PLAN_ID}" 3>&-; }

# _mk_project — a committed checkout with a TRACKED delivery file in both
# trees (the thing an edit dirties) and the gitignored runtime area.
_mk_project() {
  mkdir -p "$ROOT/.aid-o/plans" "$ROOT/.aid-o/config" "$ROOT/.aid-o/work"
  printf '.aid-o/\n.aid-worktrees/\n' > "$ROOT/.gitignore"
  printf 'seed\n' > "$ROOT/README.md"
  printf 'delivered\n' > "$ROOT/epic-work.txt"
  # The plan-final gate stage refuses a vacuous `plan_diff` run, so the plan
  # source file has to exist (in the PRIMARY .aid-o, which is where the state
  # root resolves from either tree).
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

# _seed_plan <with_worktree:0|1> — plan branch + state + manifest, and (when
# asked) the registered, recorded execution worktree. The primary checkout is
# deliberately left on `main`, which is the whole point: after P074 nothing
# about the plan-final boundary requires the PM's tree to move.
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

# ─── 1. THE HEADLINE CASE ──────────────────────────────────────────────────

@test "P074 Step 10: an unrelated tracked edit in the PRIMARY checkout does NOT invalidate the review" {
  _mk_project
  _seed_plan 1
  # The PM carries on working in their own checkout during the review window.
  printf 'the PM is editing something else entirely\n' >> "$ROOT/README.md"
  run bash -c "git -C '$ROOT' status --porcelain --untracked-files=no" 3>&-
  [[ "$output" == *"README.md"* ]]   # the primary really IS dirty

  run _drift "$(_candidate)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── 2. the worktree still invalidates, exactly as before ──────────────────

@test "P074 Step 10: a tracked edit inside the PLAN WORKTREE invalidates, with the unchanged reason" {
  _mk_project
  _seed_plan 1
  printf 'a real change to the candidate\n' >> "$(_wt)/epic-work.txt"

  run _drift "$(_candidate)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted TRACKED changes against the candidate"* ]]
  [[ "$output" == *"epic-work.txt"* ]]
}

# ─── 3. both trees dirty at once — only the worktree is consulted ──────────

@test "P074 Step 10: with BOTH trees dirty only the worktree's paths are reported" {
  _mk_project
  _seed_plan 1
  printf 'primary-only noise\n' >> "$ROOT/README.md"
  printf 'a real change to the candidate\n' >> "$(_wt)/epic-work.txt"

  run _drift "$(_candidate)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"epic-work.txt"* ]]
  # README.md moved only in the PM's checkout, so it must not appear in the
  # invalidation reason at all.
  [[ "$output" != *"README.md"* ]]
}

# ─── 4-5. legacy plans keep today's state-root evaluation, byte for byte ───

@test "P074 Step 10 regression: a legacy plan (no worktree) still invalidates on state-root dirt" {
  _mk_project
  _seed_plan 0
  printf 'dirt in the one and only tree\n' >> "$ROOT/epic-work.txt"

  run _drift "$(_candidate)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted TRACKED changes against the candidate"* ]]
  [[ "$output" == *"epic-work.txt"* ]]
}

@test "P074 Step 10 regression: a legacy plan with a clean state root still passes" {
  _mk_project
  _seed_plan 0

  run _drift "$(_candidate)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── 6. the gates stamp the WORKTREE's head ────────────────────────────────

@test "P074 Step 10: --stage gates run in the plan worktree stamp revision.head_sha == the candidate (primary stays on main)" {
  _mk_project
  _seed_plan 1
  mkdir -p "$ROOT/.aid-o/config"
  cat > "$ROOT/.aid-o/config/execution.yaml" <<'YAML'
version: '1.0'
gates:
  bats_fsm:
    command: "true"
    required: true
    timeout_seconds: 30
    max_retries: 0
  plan_diff:
    command: "true"
    required: false
    timeout_seconds: 30
    max_retries: 0
gate_profiles:
  release:
    include:
      - bats_fsm
      - plan_diff
YAML
  # Advance the plan branch by one commit made IN THE WORKTREE, so the
  # candidate is provably NOT main's head — a report stamped from the primary
  # checkout could not possibly carry it.
  _in_root "set -e
    printf 'epic delivery\n' >> '$(_wt)/epic-work.txt'
    git -C '$(_wt)' add epic-work.txt
    git -C '$(_wt)' commit -q -m 'the EPIC delivery'"

  run _pf plan-finalize "$PLAN_ID" --stage sync --project-root "$ROOT"
  [ "$status" -eq 0 ]
  run _pf plan-finalize "$PLAN_ID" --stage freeze --project-root "$ROOT"
  [ "$status" -eq 0 ]

  local cand; cand="$(_in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh'
    plan_manifest_get ${PLAN_ID} '.plan_boundary_manifest.candidate_sha'")"
  [ -n "$cand" ]
  [ "$cand" != "$(git -C "$ROOT" rev-parse main 3>&-)" ]

  run _pf plan-finalize "$PLAN_ID" --stage gates --project-root "$ROOT"
  [ "$status" -eq 0 ]

  local run_dir; run_dir="$(_in_root "source '$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh'
    plan_manifest_get ${PLAN_ID} '.plan_boundary_manifest.plan_final_evidence_dir'")"
  run bash -c "jq -r '.revision.head_sha' '$ROOT/$run_dir/gates_report.json'" 3>&-
  [ "$status" -eq 0 ]
  [ "$output" = "$cand" ]

  # And the PM's checkout was never touched: still on main, still at main.
  run bash -c "git -C '$ROOT' symbolic-ref --short HEAD" 3>&-
  [ "$output" = "main" ]
}
