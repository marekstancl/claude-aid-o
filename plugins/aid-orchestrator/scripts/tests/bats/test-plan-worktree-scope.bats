#!/usr/bin/env bats
# aid-tier: t0
# test-plan-worktree-scope.bats — phase working copies for brainstorming and
# generation (P086 Step 6).
#
# THE GROUNDED FAILURE MODE: only implementation had a tree of its own, so two
# planning streams shared one index and one HEAD, and generation is the phase
# that commits. What is proved here is that each phase gets its own checkout,
# that two streams therefore never share one, and — just as important — that a
# tree git will not hand out degrades to the primary checkout with a warning
# instead of stopping the stream.
#
# NOT PROVED HERE, DELIBERATELY: that state is isolated. It is not, by design.
# `.aid-o/` is gitignored and lib/aid-roots.sh resolves it to the primary
# checkout from any tree, so runs, evidence and the plan-id counter stay
# shared. The test below asserts that shared resolution rather than pretending
# to a separation the design rejects.
#
# FD-3 HYGIENE: every plan-FSM invocation runs with `3>&-` — a child holding
# bats' result descriptor truncates the suite's TAP output.

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_FSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  unset AID_PROJECT_ROOT
  _mk_project "$ROOT"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && chmod -R u+rwX "$TEST_TMPDIR" 2>/dev/null
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_mk_project() {
  local d="$1"
  mkdir -p "$d/.aid-o/config" "$d/.aid-o/work"
  printf '.aid-o/\n.aid-worktrees/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed project"
  )
}

scratch() { # scratch <plan_id> <flags...>
  run bash "$PLAN_FSM" plan-scratch "$@" --project-root "$ROOT" 3>&-
}

@test "AC18: brainstorming gets its own copy and leaves the primary checkout untouched" {
  local head_before; head_before="$(git -C "$ROOT" rev-parse HEAD)"
  scratch P900 --phase brainstorm
  [ "$status" -eq 0 ]
  [ "$output" = "$ROOT/.aid-worktrees/brainstorm-P900" ]
  [ -d "$output" ]
  [ "$(git -C "$output" symbolic-ref --short HEAD)" = "brainstorm/P900" ]
  [ "$(git -C "$ROOT" symbolic-ref --short HEAD)" = "main" ]
  [ "$(git -C "$ROOT" rev-parse HEAD)" = "$head_before" ]
}

@test "two streams of the same phase never share a tree" {
  scratch P900 --phase brainstorm
  local first="$output"
  scratch P901 --phase brainstorm
  [ "$status" -eq 0 ]
  [ "$output" != "$first" ]
  [ -d "$first" ]
  [ -d "$output" ]
}

@test "brainstorming and generation of one plan are separate trees" {
  scratch P900 --phase brainstorm
  local b="$output"
  scratch P900 --phase generation
  [ "$status" -eq 0 ]
  [ "$output" != "$b" ]
  [ "$(git -C "$output" symbolic-ref --short HEAD)" = "generation/P900" ]
}

@test "asking twice for the same copy is idempotent, not an error" {
  scratch P900 --phase generation
  local first="$output"
  scratch P900 --phase generation
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "AC19 (the half that is real): state resolves to the primary checkout from inside the copy" {
  # The counter, the runs and the evidence must NOT fork per stream. `.aid-o/`
  # is gitignored, so it is not even checked out here — this asserts the
  # resolution that makes the shared-state half of the design true.
  scratch P900 --phase brainstorm
  local wt="$output"
  [ ! -d "$wt/.aid-o" ]
  run bash -c "cd '$wt' && source '$AID_PLUGIN_PATH/scripts/lib/aid-roots.sh' && aid_state_root"
  [ "$status" -eq 0 ]
  [ "$(cd "$output" && pwd -P)" = "$(cd "$ROOT" && pwd -P)" ]
}

@test "AC20: a copy git will not create warns and hands back the primary checkout" {
  # The branch is already checked out somewhere else — git refuses a second
  # checkout of it, which is the realistic way this fails.
  git -C "$ROOT" worktree add -b generation/P900 "$TEST_TMPDIR/elsewhere" main >/dev/null 2>&1
  scratch P900 --phase generation
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" = "$ROOT" ]]
  [[ "$output" == *"runs in the primary checkout"* ]]
}

@test "a foreign directory at the copy's path is reported, never deleted" {
  mkdir -p "$ROOT/.aid-worktrees/brainstorm-P900"
  printf 'somebody else\n' > "$ROOT/.aid-worktrees/brainstorm-P900/keep.txt"
  scratch P900 --phase brainstorm
  [ "$status" -eq 0 ]
  [ -f "$ROOT/.aid-worktrees/brainstorm-P900/keep.txt" ]
  [[ "$output" == *"never deletes a directory it did not create"* ]]
}

@test "a plan with no number gets no copy and says so" {
  scratch roadmap --phase brainstorm
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" = "$ROOT" ]]
  [[ "$output" == *"not a numbered plan"* ]]
  [ ! -d "$ROOT/.aid-worktrees" ]
}

@test "--release removes the copy and leaves its branch alone" {
  scratch P900 --phase generation
  local wt="$output"
  scratch P900 --phase generation --release
  [ "$status" -eq 0 ]
  [ ! -d "$wt" ]
  run git -C "$ROOT" show-ref --verify --quiet refs/heads/generation/P900
  [ "$status" -eq 0 ]
}

@test "--release refuses to discard uncommitted work" {
  scratch P900 --phase generation
  local wt="$output"
  printf 'work in progress\n' > "$wt/WIP.md"
  scratch P900 --phase generation --release
  [ "$status" -eq 0 ]
  [ -f "$wt/WIP.md" ]
  [[ "$output" == *"uncommitted work"* ]]
}

@test "an unknown phase is a usage error, not a silent fallback to the primary checkout" {
  scratch P900 --phase design
  [ "$status" -eq 2 ]
  [[ "$output" == *"brainstorm"* ]]
}
