#!/usr/bin/env bats
# aid-tier: t0
# test-parallel-dispatch.bats — the brake comes off: a wave is run at once
# only when code says so, and a merge conflict is a retry (P087 Step 4).
#
# Real git, tiny repos. The decision is asserted on its printed word and its
# exit code (always 0 — it degrades, it never refuses); the merge is asserted
# on the tree it leaves behind, because "aborted" is a claim about a tree.

load test-helpers.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  source "$AID_PLUGIN_PATH/scripts/lib/aid-parallel-dispatch.sh"
  TEST_DIR="$(mktemp -d)"
  aid_test_mk_repo "$TEST_DIR/repo"
  cd "$TEST_DIR/repo"
  printf 'dispatch:\n  strategy: worktrees\n  max_parallel: 3\n' > orch.yaml
  printf 'dispatch:\n  max_parallel: 1\n' > brake.yaml
}
teardown() { cd /; rm -rf "$TEST_DIR"; }

# _plan <spec>...  spec = "<group>|<path>"  — a light plan with one bullet per step
_plan() {
  local n=0 spec
  { printf -- '---\nid: P905\ntype: regular\nrisk: low\n---\n# Plan: P905\n\n## Implementation Steps\n\n'
    for spec in "$@"; do
      n=$((n+1))
      printf '### Step %d: work %d\n\n**Objective:** do it.\n\n**Files:**\n- Modify: `%s` — edit\n\n**Parallel group:** %s\n\n' "$n" "$n" "${spec#*|}" "${spec%%|*}"
    done
  } > plan.md
}

@test "dispatch: AC10 — a disjoint wave is dispatched concurrently" {
  _plan 'wave-1|src/a.ts' 'wave-1|src/b.ts'
  run aid_parallel_decide plan.md orch.yaml wave-1 2 .
  [ "$status" -eq 0 ]
  [ "$output" = "concurrent slots=3" ]
}

@test "dispatch: only the wave being dispatched is judged — a collision elsewhere does not serialise it" {
  _plan 'wave-1|src/a.ts' 'wave-1|src/b.ts' 'wave-2|src/c.ts' 'wave-2|src/c.ts'
  run aid_parallel_decide plan.md orch.yaml wave-1 2 .
  [ "$output" = "concurrent slots=3" ]
  run aid_parallel_decide plan.md orch.yaml wave-2 2 .
  [[ "$output" == "serial: wave wave-2 has a collision"* ]]
}

@test "dispatch: a strategy other than worktrees is serial, whatever max_parallel says" {
  _plan 'wave-1|src/a.ts' 'wave-1|src/b.ts'
  printf 'dispatch:\n  strategy: sequential\n  max_parallel: 3\n' > seq.yaml
  run aid_parallel_decide plan.md seq.yaml wave-1 2 .
  [ "$output" = "serial: dispatch.strategy is sequential — only worktrees isolate a step" ]
}

@test "dispatch: AC8 — a colliding wave is degraded to serial with the reason, never refused" {
  _plan 'wave-1|src/a.ts' 'wave-1|src/a.ts'
  run aid_parallel_decide plan.md orch.yaml wave-1 2 .
  [ "$status" -eq 0 ]
  [[ "$output" == serial:* ]]
  [[ "$output" == *"not disjoint"* ]]
}

@test "dispatch: the brake, a wave of one, and an unrunnable check all mean serial, each with its own reason" {
  _plan 'wave-1|src/a.ts' 'wave-1|src/b.ts'
  run aid_parallel_decide plan.md brake.yaml wave-1 2 .
  [ "$output" = "serial: dispatch.max_parallel is 1" ]
  run aid_parallel_decide plan.md orch.yaml wave-1 1 .
  [[ "$output" == "serial: a wave of 1 step(s)"* ]]
  run aid_parallel_decide missing.md orch.yaml wave-1 2 .
  [ "$status" -eq 0 ]
  [[ "$output" == "serial: the wave check could not run"* ]]
}

@test "dispatch: each step gets its own worktree on its own branch, idempotently" {
  wt="$(aid_parallel_step_worktree . step_1_backend HEAD)"
  [ -d "$wt" ]
  [ "$(git -C "$wt" symbolic-ref --short HEAD)" = "step/step_1_backend" ]
  [ "$(aid_parallel_step_worktree . step_1_backend HEAD)" = "$wt" ]
  wt2="$(aid_parallel_step_worktree . step_2_frontend HEAD)"
  [ "$wt2" != "$wt" ]
  wt3="$(aid_parallel_step_worktree . step_3_qa HEAD .other-base)"
  [[ "$wt3" == */.other-base/step-step_3_qa ]]
}

@test "dispatch: a step branch left over from an earlier run is reset to the base, never reused" {
  wt="$(aid_parallel_step_worktree . step_1_backend HEAD)"
  printf 'old\n' > "$wt/old.txt"; git -C "$wt" add old.txt; git -C "$wt" commit -q -m "old run"
  git worktree remove "$wt"
  printf 'base moved\n' >> README.md; git commit -q -am "base"
  wt="$(aid_parallel_step_worktree . step_1_backend HEAD)"
  [ ! -e "$wt/old.txt" ]
  [ "$(git -C "$wt" rev-parse HEAD)" = "$(git rev-parse HEAD)" ]
}

@test "dispatch: a clean merge lands the step's commit and clears its tree" {
  wt="$(aid_parallel_step_worktree . step_1_backend HEAD)"
  printf 'a\n' > "$wt/a.txt"; git -C "$wt" add a.txt; git -C "$wt" commit -q -m "step 1"
  run aid_parallel_merge . step/step_1_backend
  [ "$status" -eq 0 ]
  [ -f a.txt ]
  [ ! -d "$wt" ]
  git show-ref --verify --quiet refs/heads/step/step_1_backend
}

@test "dispatch: AC11 — a conflicting merge is aborted, the tree is untouched, and the answer is 'repeat the step'" {
  wt="$(aid_parallel_step_worktree . step_1_backend HEAD)"
  printf 'theirs\n' > "$wt/README.md"; git -C "$wt" commit -q -am "step 1 edits README"
  printf 'ours\n' > README.md; git commit -q -am "base moved"
  before="$(git rev-parse HEAD)"
  run aid_parallel_merge . step/step_1_backend
  [ "$status" -eq 1 ]
  [[ "$output" == *"conflicts"* && "$output" == *"README.md"* && "$output" == *"repeat the step"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ "$(cat README.md)" = "ours" ]
  [ -z "$(git status --porcelain --untracked-files=no)" ]
  [ -d "$wt" ]
  # the retry: the step's tree is put back on the base that moved
  run aid_parallel_step_reset . step_1_backend HEAD
  [ "$status" -eq 0 ]
  [ "$(git -C "$wt" rev-parse HEAD)" = "$(git rev-parse HEAD)" ]
  [ "$(cat "$wt/README.md")" = "ours" ]
}

@test "dispatch: a reset never discards uncommitted work — it names the tree and refuses" {
  wt="$(aid_parallel_step_worktree . step_1_backend HEAD)"
  printf 'half done\n' > "$wt/wip.txt"
  run aid_parallel_step_reset . step_1_backend HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted work"* && "$output" == *"$wt"* ]]
  [ -f "$wt/wip.txt" ]
}

@test "dispatch: AC12 — pipeline.md no longer carries the temporary brake" {
  run grep -c 'TEMPORARY: Sequential execution enforced' "$AID_PLUGIN_PATH/skills/pipeline.md"
  [ "$output" = "0" ]
  run yq -r '.dispatch.max_parallel' "$AID_PLUGIN_PATH/defaults/orchestration.yaml"
  [ "$output" -gt 1 ]
}
