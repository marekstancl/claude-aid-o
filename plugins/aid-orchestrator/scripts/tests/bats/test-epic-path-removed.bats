#!/usr/bin/env bats
# aid-tier: t1
# test-epic-path-removed.bats — 3.0.0 (P114): the EPIC path is gone and every
# way into it answers epic_path_removed with the way out (finish the run on
# 2.118.x, or close the plan and start a NEW plan), before any lock or write.
# Defect caught: an old input meeting "unknown command" or half-deleted code.

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"; FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  R="$BATS_TEST_TMPDIR/p"; mkdir -p "$R/.aid-o/plans" "$R/.aid-o/config"
  git -C "$R" init -q -b main; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  printf 'gates: {}\n' > "$R/.aid-o/config/execution.yaml"
  printf -- '---\nid: P950\n---\n# Plan\n\n### Step 1: one\n\n**AID Role:** backend\n' > "$R/.aid-o/plans/P950-x.md"
  echo seed > "$R/seed"; git -C "$R" add -A; git -C "$R" commit -qm seed
  cd "$R"; export AID_PROJECT_ROOT="$R"
}

# _refused — the shared answer: the code, the suffix and both ways out
_refused() {
  [ "$status" -eq "${1:-2}" ]
  [[ "$output" == *"epic_path_removed"* && "$output" == *"(pipeline.md §When AID refuses: epic_path_removed)"* ]]
  [[ "$output" == *"next: "*"2.118.x"*"NEW plan"* ]]
}

@test "removed: epic-start refuses epic_path_removed with the way out" {
  run bash "$PFSM" epic-start P950 E-950-1_1 --project-root "$R"; _refused
}
@test "removed: epic-merge-to-plan refuses epic_path_removed" {
  run bash "$PFSM" epic-merge-to-plan P950 E-950-1_1 --project-root "$R"; _refused
}
@test "removed: next-epic refuses epic_path_removed" {
  run bash "$PFSM" next-epic P950 --project-root "$R"; _refused
}
@test "removed: epic-base refuses epic_path_removed" {
  run bash "$PFSM" epic-base P950 E-950-1_1 --project-root "$R"; _refused
}
@test "removed: queue-revalidate refuses epic_path_removed and writes nothing" {
  run bash "$FSM" queue-revalidate E-950-1_1; _refused
  [ ! -e "$R/.aid-o/work" ]
}
@test "removed: plan-run on a plan with an EPIC file refuses epic_path_removed" {
  mkdir -p "$R/.aid-o/tasks"; echo x > "$R/.aid-o/tasks/E-950-1_1-old.md"
  run bash "$PFSM" plan-run P950 --project-root "$R"; _refused 1
  [[ "$output" == *"E-950-1_1-old.md"* ]]
  [ ! -e "$R/.aid-o/work/evidence/P950" ]          # refused before any lock or write
}
@test "removed: plan-run on a plan with only its own queue entry refuses epic_path_removed" {
  printf 'queue:\n  - epic_id: E-950-1_1\n    status: pending\n  - epic_id: E-951-1_1\n    status: pending\n' > "$R/.aid-o/config/queue.yaml"
  run bash "$PFSM" plan-run P950 --project-root "$R"; _refused 1
  [[ "$output" == *"1 entr(ies) of the plan in .aid-o/config/queue.yaml"* ]]
  [ ! -e "$R/.aid-o/work/evidence/P950" ]
}
@test "removed: a queue that holds only OTHER plans' entries, or none, does not refuse plan-run" {
  printf 'queue:\n  - epic_id: E-951-1_1\n    status: pending\n' > "$R/.aid-o/config/queue.yaml"
  run bash "$PFSM" plan-run P950 --project-root "$R"
  [[ "$output" != *"epic_path_removed"* ]]
  [ -f "$R/.aid-o/work/evidence/P950/generation/transaction.json" ]   # it went past the check and opened its transaction
  rm -rf "$R/.aid-o/work"
  printf 'queue: []\n' > "$R/.aid-o/config/queue.yaml"
  run bash "$PFSM" plan-run P950 --project-root "$R"
  [[ "$output" != *"epic_path_removed"* ]]
  [ -f "$R/.aid-o/work/evidence/P950/generation/transaction.json" ]
}
@test "removed: the direct path still starts — init --direct over a direct plan's manifest entry" {
  source "$AID_PLUGIN_PATH/scripts/tests/lib/aid-test-plan-fixture.sh"
  local sf; sf="$(aid_fixture_direct_run "$R" P952 READY)"; rm -f "$sf"
  ( cd "$R/.aid-worktrees/plan-P952" && bash "$FSM" init E-952-1_1 R-E952-1 2 full plan/P952 "$(git -C "$R" rev-parse plan/P952)" "$sf" \
      --plan "$R/.aid-o/plans/P952-direct.md" --direct ) > "$BATS_TEST_TMPDIR/init.log" 2>&1 || { cat "$BATS_TEST_TMPDIR/init.log"; false; }
  [ "$(yq -r .state "$sf")" = READY ] && [ "$(yq -r .direct "$sf")" = true ]
}

# _old_entry <plan> — a plan_branch plan whose manifest holds an EPIC-path
# entry written by 2.118.x (a task branch, proven on plan/<id>), the shape an
# update to 3.0.0 finds.
_old_entry() {
  local pid="$1" nnn="${1#P}" tip
  printf -- '---\nid: %s\n---\n# Plan\n\n### Step 1: one\n\n**AID Role:** backend\n' "$pid" > "$R/.aid-o/plans/${pid}-old.md"
  git -C "$R" add -f .aid-o/plans >/dev/null 2>&1; git -C "$R" commit -qm "old plan" >/dev/null 2>&1 || true
  bash "$PFSM" plan-start "$pid" --mode plan_branch --project-root "$R" --declared-epics "E-${nnn}-1_1" >/dev/null 2>&1 || return 1
  tip="$(git -C "$R" rev-parse "plan/${pid}")"; git -C "$R" branch "task/E-${nnn}-1_1/main" "$tip"
  ( export AID_PLAN_MANIFEST_PROJECT_ROOT="$R"; source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh"
    plan_manifest_add_epic "$pid" "E-${nnn}-1_1" "R-E${nnn}-1" "task/E-${nnn}-1_1/main" "$tip" "plan/${pid}" ".aid-o/work/evidence/E-${nnn}-1_1/R-E${nnn}-1" proven >/dev/null )
}

@test "removed: init without --direct for an EPIC of a declared plan refuses epic_path_removed before any write" {
  _old_entry P953
  local sf="$R/.aid-o/work/evidence/E-953-1_1/R-E953-1/fsm-state.yaml"
  run bash "$FSM" init E-953-1_1 R-E953-1 1 full task/E-953-1_1/main "$(git -C "$R" rev-parse plan/P953)" "$sf"; _refused
  [ ! -e "$R/.aid-o/work/evidence/E-953-1_1/R-E953-1/fsm-state.yaml" ]
  # with --force too: refused before --force writes its audit record (Codex, step 7)
  run bash "$FSM" init E-953-1_1 R-E953-1 1 full task/E-953-1_1/main "$(git -C "$R" rev-parse plan/P953)" "$sf" --force --reason "an old run forced through the removed path"; _refused
  [ ! -e "$R/.aid-o/work/evidence/E-953-1_1" ]
  [ -z "$(git -C "$R" branch --show-current | grep '^task/')" ]
}
@test "removed: done-advance on an old EPIC run's state refuses epic_path_removed" {
  _old_entry P954
  local sf="$R/.aid-o/work/evidence/E-954-1_1/R-E954-1/fsm-state.yaml"; mkdir -p "$(dirname "$sf")"
  printf 'epic_id: E-954-1_1\nrun_id: R-E954-1\nstate: DONE\ndone_phase: review\nbranch: task/E-954-1_1/main\npm_decision: merge\n' > "$sf"
  run bash "$FSM" done-advance review release "$sf"; _refused
  [ "$(yq -r .done_phase "$sf")" = review ]
  # a plan-less run (no plan id in its EPIC id) is the FSM's own harness, never refused
  local sh="$R/.aid-o/work/evidence/E-test/R-1/fsm-state.yaml"; mkdir -p "$(dirname "$sh")"
  printf 'epic_id: E-test\nrun_id: R-1\nstate: DONE\ndone_phase: review\nbranch: task/E-test/main\npm_decision: merge\n' > "$sh"
  run bash "$FSM" done-advance review release "$sh"
  [[ "$output" != *epic_path_removed* ]]
}
@test "removed: epic-complete without --direct refuses; --abandon still ends an old entry with a task branch" {
  _old_entry P955
  run bash "$PFSM" epic-complete P955 E-955-1_1 --project-root "$R"; _refused
  run bash "$PFSM" epic-complete P955 E-955-1_1 --abandon --reason "left over from 2.118.x" --project-root "$R"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.plan_boundary_manifest.epic_runs[0] | .status + " " + .task_branch' "$R/.aid-o/work/plan-state/P955/plan-boundary-manifest.json")" = "abandoned task/E-955-1_1/main" ]
}
@test "removed: plan-close --administrative still closes a plan whose manifest holds an old entry with a task branch" {
  _old_entry P956
  run bash "$PFSM" plan-close P956 --administrative --reason "the EPIC path was removed in 3.0.0; closed by hand" --project-root "$R"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(yq -r .plan_state "$R/.aid-o/work/plan-state/P956/plan-state.yaml")" = CLOSED ]
}

