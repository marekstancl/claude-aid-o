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
}
@test "removed: plan-run on a plan with only its own queue entry refuses epic_path_removed" {
  printf 'queue:\n  - epic_id: E-950-1_1\n    status: pending\n  - epic_id: E-951-1_1\n    status: pending\n' > "$R/.aid-o/config/queue.yaml"
  run bash "$PFSM" plan-run P950 --project-root "$R"; _refused 1
  [[ "$output" == *"1 entr(ies) of the plan in .aid-o/config/queue.yaml"* ]]
}
@test "removed: a queue that holds only OTHER plans' entries, or none, does not refuse plan-run" {
  printf 'queue:\n  - epic_id: E-951-1_1\n    status: pending\n' > "$R/.aid-o/config/queue.yaml"
  run bash "$PFSM" plan-run P950 --project-root "$R"
  [[ "$output" != *"epic_path_removed"* ]]
  printf 'queue: []\n' > "$R/.aid-o/config/queue.yaml"
  run bash "$PFSM" plan-run P950 --project-root "$R"
  [[ "$output" != *"epic_path_removed"* ]]
}
@test "removed: the direct path still starts — init --direct over a direct plan's manifest entry" {
  source "$AID_PLUGIN_PATH/scripts/tests/lib/aid-test-plan-fixture.sh"
  local sf; sf="$(aid_fixture_direct_run "$R" P952 READY)"; rm -f "$sf"
  ( cd "$R/.aid-worktrees/plan-P952" && bash "$FSM" init E-952-1_1 R-E952-1 2 full plan/P952 "$(git -C "$R" rev-parse plan/P952)" "$sf" \
      --plan "$R/.aid-o/plans/P952-direct.md" --direct ) > "$BATS_TEST_TMPDIR/init.log" 2>&1 || { cat "$BATS_TEST_TMPDIR/init.log"; false; }
  [ "$(yq -r .state "$sf")" = READY ] && [ "$(yq -r .direct "$sf")" = true ]
}
