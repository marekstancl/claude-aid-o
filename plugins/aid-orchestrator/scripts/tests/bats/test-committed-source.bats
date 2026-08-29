#!/usr/bin/env bats
# aid-tier: t2
# test-committed-source.bats — P073 Step 11: the committed-source preflight
# (P083).
#
# The gap was end-to-end. aid-auto-pipeline.sh checked only that the plan file
# existed on disk; cmd_plan_start never saw a path at all; and the
# clean-worktree preflight runs with `--untracked-files=no`, so a plan that was
# never `git add`ed was invisible to every layer. Generation then created a
# plan branch, task branches and a lifecycle manifest, with the manifest's
# source_plan_sha binding the whole plan to bytes that existed in exactly one
# worktree.
#
# The gitignored carve-out is deliberate, not a loophole: this repository
# gitignores `.aid-o/plans/`, so a hard tracked-only rule would break the
# plugin's own dogfood workflow.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PFSM
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  ( cd "$ROOT"
    git init -q
    git config user.email t@e.com
    git config user.name T
    git checkout -q -b main 2>/dev/null || git branch -m main
    mkdir -p .aid-o/plans docs
    printf 'seed\n' > README.md
    git add -A && git commit -qm seed )
  REASON="the plan is deliberately unshared for this spike and the PM accepts the binding"
  export REASON
}

teardown() {
  teardown_test_evidence_dir
}

_pf() { ( cd "$ROOT" && bash "$PFSM" "$@" ); }

# _no_mutation — proof that the refusal happened BEFORE any git write.
_no_mutation() {
  local branches manifests
  branches="$( cd "$ROOT" && git branch --list 'plan/*' )"
  [ -z "$branches" ] || { echo "a plan branch was created: $branches" >&2; return 1; }
  manifests="$( find "$ROOT/.aid-lifecycle" -name '*.yaml' 2>/dev/null | wc -l | tr -d ' ' )"
  [ "$manifests" = "0" ] || { echo "a lifecycle manifest was created" >&2; return 1; }
  return 0
}

# ─── tracked plan, not committed ──────────────────────────────────────────

@test "v2.95.5 (WAN #1): a TRACKED but uncommitted plan is COMMITTED on main by plan-start itself" {
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md )

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [[ "$output" == *"committed .aid-o/plans/plan.md on main"* ]]
  [[ "$output" != *"source plan is not committed on main"* ]]
  [ "$( cd "$ROOT" && git show main:.aid-o/plans/plan.md )" = "# Plan" ]
  # only that path went into the commit
  [ "$( cd "$ROOT" && git show --stat --format= main | grep -c '|' )" = "1" ]
}

@test "v2.95.5 (WAN #1): an UNTRACKED plan on disk is committed too, and the plan branch carries it" {
  printf '# Plan untracked\n' > "$ROOT/.aid-o/plans/plan.md"
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [[ "$output" == *"committed .aid-o/plans/plan.md on main"* ]]
  [ "$( cd "$ROOT" && git show main:.aid-o/plans/plan.md )" = "# Plan untracked" ]
  if ( cd "$ROOT" && git rev-parse --verify --quiet plan/P900 >/dev/null ); then
    [ "$( cd "$ROOT" && git show plan/P900:.aid-o/plans/plan.md )" = "# Plan untracked" ]
  fi
}

@test "P073 Step 11: a plan committed on ANOTHER branch is still refused — the check is target-branch specific" {
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT"
    git checkout -q -b side
    git add .aid-o/plans/plan.md && git commit -qm "plan on side"
    git checkout -q main )
  # Back on main the blob exists only on `side`, and git removed the directory
  # with it (an empty `docs/` was never tracked), so both have to be recreated
  # — otherwise the fixture would be testing "file missing", not "committed on
  # the wrong branch".
  mkdir -p "$ROOT/.aid-o/plans"
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  # here the checkout IS on main, so plan-start commits the worktree bytes
  [[ "$output" == *"committed .aid-o/plans/plan.md on main"* ]]
  [ "$( cd "$ROOT" && git show main:.aid-o/plans/plan.md )" = "# Plan" ]
}

@test "v2.95.5 (WAN #1): from a checkout NOT on main plan-start does not commit — the old refusal speaks, with the reason" {
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git checkout -q -b side )
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"only from a checkout ON main"* ]]
  [[ "$output" == *"not committed on main"* ]]
  _no_mutation
}

# ─── committed but edited ─────────────────────────────────────────────────

@test "P073 Step 11: a committed plan EDITED in the worktree is refused — byte equality, not mere presence" {
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md && git commit -qm "plan" )
  printf '# Plan\n\nAn edit that was never committed.\n' > "$ROOT/.aid-o/plans/plan.md"

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  # the edit is the PM's current text: it is committed, the stale blob is history
  [[ "$output" == *"committed .aid-o/plans/plan.md on main"* ]]
  [[ "$( cd "$ROOT" && git show main:.aid-o/plans/plan.md )" == *"never committed"* ]]
}

@test "P073 Step 11: even a WHITESPACE-only difference is refused (byte equality is the point)" {
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md && git commit -qm "plan" )
  printf '# Plan\n\n' > "$ROOT/.aid-o/plans/plan.md"

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [[ "$output" == *"committed .aid-o/plans/plan.md on main"* ]]
}

# ─── committed and identical ──────────────────────────────────────────────

@test "P073 Step 11: a committed, identical plan PASSES the preflight" {
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md && git commit -qm "plan" )

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  # plan-start may still fail later on this bare fixture's lifecycle identity;
  # what matters here is that it did NOT fail on the source-plan preflight.
  [[ "$output" != *"not committed on main"* ]]
  [[ "$output" != *"differs from the worktree copy"* ]]
}

@test "v2.95.5 (WAN #1): a plan OUTSIDE .aid-o/plans is never auto-committed — the refusal speaks" {
  printf '# Plan\n' > "$ROOT/docs/plan.md"
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/docs/plan.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not committed on main"* ]]
  [[ "$output" != *"committed docs/plan.md"* ]]
  _no_mutation
}

@test "v2.95.5 (WAN #1): a staged copy that differs from the file on disk is not chosen for the PM" {
  printf '# Plan v1\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md )
  printf '# Plan v2\n' > "$ROOT/.aid-o/plans/plan.md"
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"differs from the file on disk"* ]]
  [ "$( cd "$ROOT" && git show :.aid-o/plans/plan.md )" = "# Plan v1" ]   # staging untouched
  _no_mutation
}

# ─── the gitignored carve-out ─────────────────────────────────────────────

@test "P073 Step 11: a GITIGNORED plan proceeds, and says which binding is in force" {
  printf '.aid-o/\n' > "$ROOT/.gitignore"
  ( cd "$ROOT" && git add .gitignore && git commit -qm "ignore .aid-o" )
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [[ "$output" == *"plan_source_binding: source_plan_sha"* ]]
  [[ "$output" == *"gitignored"* ]]
  [[ "$output" != *"not committed on main"* ]]
}

# ─── legacy callers and the force route ───────────────────────────────────

@test "P073 Step 11: WITHOUT --plan-file the behaviour is unchanged (legacy callers keep working)" {
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md )

  run _pf plan-start P900 --mode legacy_epic_release_mode
  [[ "$output" != *"not committed on main"* ]]
  [[ "$output" != *"plan_source_binding"* ]]
}

@test "P073 Step 11: --plan-file naming a nonexistent path is refused by name" {
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/docs/nope.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
  _no_mutation
}

@test "P073 Step 11: the preflight is FORCEABLE — a PM who accepts an unshared source proceeds with a receipt" {
  # the one case plan-start does not commit for you: a checkout off main
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md && git checkout -q -b side )

  run _pf plan-start P900 --mode legacy_epic_release_mode \
      --plan-file "$ROOT/.aid-o/plans/plan.md" --force --force-reason "$REASON"
  # The check still printed its own recovery first.
  [[ "$output" == *"not committed on main"* ]]
  [[ "$output" == *"FORCE: bypassing precondition 'committed_source_plan'"* ]]
  local w; w="$(find "$ROOT/.aid-o" -name 'waiver-plan-plan-start-*.json' 2>/dev/null | head -1)"
  [ -n "$w" ]
  [[ "$(jq -r '.bypassed_preconditions | join(",")' "$w")" == *"committed_source_plan"* ]]
}

# ─── the registry entry the plan requires at step completion ──────────────

@test "P073 Step 11: the preflight is registered in the enforcement registry" {
  run yq -e '.enforcements[] | select(.id == "plan_source_committed_preflight") | .status' \
      "$AID_PLUGIN_PATH/defaults/enforcement-registry.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = "active" ]
  run yq -e '.enforcements[] | select(.id == "plan_source_committed_preflight") | .severity' \
      "$AID_PLUGIN_PATH/defaults/enforcement-registry.yaml"
  [ "$output" = "blocking" ]
}

# ─── scope: what the preflight must NOT refuse ────────────────────────────
# A first cut resolved the repository from the PLAN's own directory and hard-
# failed whenever no target branch resolved. That refused every plan living
# outside the workspace and broke all 18 full-pipeline fixtures. Only a plan
# INSIDE this workspace's repository has a target-branch relationship to
# verify; the rest are skipped WITH A LOG LINE, never silently.

@test "P073 Step 11: a plan living OUTSIDE the workspace repository is not refused" {
  local outside="$BATS_TEST_TMPDIR/shared-library"
  mkdir -p "$outside"
  printf '# Plan\n' > "$outside/plan.md"

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$outside/plan.md"
  [[ "$output" == *"lives outside this workspace's repository"* ]]
  [[ "$output" != *"not committed on"* ]]
}

@test "P073 Step 11: a workspace that is not a git repository is not refused" {
  local nogit="$BATS_TEST_TMPDIR/nogit"
  mkdir -p "$nogit"
  printf '# Plan\n' > "$nogit/plan.md"

  run bash "$PFSM" plan-start P900 --mode legacy_epic_release_mode \
      --project-root "$nogit" --plan-file "$nogit/plan.md"
  [[ "$output" != *"not committed on"* ]]
}

@test "P073 Step 11: a tracked-eligible plan with NO target branch is refused, naming the remedy" {
  # This one MUST still refuse: the plan is inside the repo and not ignored,
  # so its availability is verifiable in principle and simply is not proven.
  ( cd "$ROOT" && git checkout -q -b other && git branch -D main -q )
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md )

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
  [[ "$output" == *"gitignore the plan if it is deliberately unshared"* ]]
  _no_mutation
}

@test "P073 Step 11: the pipeline preflight logs which binding is in force on every skip path" {
  # The skips are informative, never silent — that is what keeps the carve-outs
  # auditable rather than a hole nobody can see.
  run grep -c 'plan_source_binding' "$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh"
  [ "$output" -ge 3 ]
}

# ─── Codex-review findings on the first cut of this step ──────────────────

@test "P073 Step 11 (review finding 1): a repo-path SYMLINK pointing outside the repo is refused, not exempted" {
  # Deciding containment on the CANONICAL path let this take the "lives
  # outside" skip: a plan invoked through a repository path, with a valid
  # target branch, could still bind the lifecycle to local-only bytes — which
  # is exactly the unshared source this check exists to refuse.
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"
  printf '# Plan\n' > "$outside/plan.md"
  ln -s "$outside/plan.md" "$ROOT/.aid-o/plans/plan.md"

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"resolves through a symlink"* ]]
  [[ "$output" == *"outside the repository"* ]]
  _no_mutation
}

@test "P073 Step 11 (review finding 1): a symlink pointing INSIDE the repo is fine" {
  # Only an escaping symlink is a problem; an internal one still names bytes
  # the repository contains.
  printf '# Plan\n' > "$ROOT/docs/real.md"
  ( cd "$ROOT" && git add docs/real.md && git commit -qm "plan" )
  ln -s "$ROOT/docs/real.md" "$ROOT/.aid-o/plans/plan.md"

  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/.aid-o/plans/plan.md"
  [[ "$output" != *"resolves through a symlink"* ]]
}

@test "P073 Step 11 (review finding 2): --project-root away from CWD gives the SAME verdict as the pipeline" {
  # plan_abs was resolved against the caller's CWD while git ran with -C "$root"
  # on the caller's original relative argument, so git tested a doubled path: a
  # genuinely ignored plan missed its deliberate skip and was refused as absent
  # from the target branch. The same plan must not depend on the entry point.
  printf '.aid-o/\n' > "$ROOT/.gitignore"
  ( cd "$ROOT" && git add .gitignore && git commit -qm "ignore .aid-o" )
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"

  # Invoked from the PARENT of the repo, with a relative --project-root.
  run bash -c "cd '$(dirname "$ROOT")' && bash '$PFSM' plan-start P900 \
      --mode legacy_epic_release_mode \
      --project-root '$(basename "$ROOT")' \
      --plan-file '$(basename "$ROOT")/.aid-o/plans/plan.md'"
  [[ "$output" == *"is gitignored"* ]]
  [[ "$output" != *"not committed on"* ]]
}

@test "P073 Step 11 (review finding 2): a committed plan verifies identically from a foreign CWD" {
  printf '# Plan\n' > "$ROOT/.aid-o/plans/plan.md"
  ( cd "$ROOT" && git add .aid-o/plans/plan.md && git commit -qm "plan" )

  run bash -c "cd '$(dirname "$ROOT")' && bash '$PFSM' plan-start P900 \
      --mode legacy_epic_release_mode \
      --project-root '$(basename "$ROOT")' \
      --plan-file '$(basename "$ROOT")/.aid-o/plans/plan.md'"
  [[ "$output" != *"not committed on"* ]]
  [[ "$output" != *"differs from the worktree copy"* ]]
}
