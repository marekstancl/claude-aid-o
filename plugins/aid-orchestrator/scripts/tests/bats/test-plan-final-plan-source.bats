#!/usr/bin/env bats
# aid-tier: t0
# The plan-final run judges the CANDIDATE's copy of the plan (ACTA #33), the
# state root's only as a fallback, and says which.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH AID_TEST_MODE=1
  T="$(mktemp -d)"; mkdir -p "$T/root/.aid-o/plans" "$T/wt/.aid-o/plans"
  source "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
}
teardown() { rm -rf "$T"; }

@test "candidate copy wins over the state root copy" {
  printf 'old\n' > "$T/root/.aid-o/plans/P900-x.md"; printf 'new\n' > "$T/wt/.aid-o/plans/P900-x.md"
  run _pfsm_plan_file_for_gates "$T/root" "$T/wt" P900
  [ "$status" -eq 0 ]; [ "$output" = "$T/wt/.aid-o/plans/P900-x.md	candidate" ]
}

@test "no copy in the worktree (gitignored .aid-o) falls back to the state root and says so" {
  printf 'only\n' > "$T/root/.aid-o/plans/P900-x.md"
  run _pfsm_plan_file_for_gates "$T/root" "$T/wt" P900
  [ "$output" = "$T/root/.aid-o/plans/P900-x.md	state_root" ]
  run _pfsm_say_plan_inputs gates "$T/root/.aid-o/plans/P900-x.md" state_root "$T/root/.aid-o/config/execution.yaml"
  [[ "$output" == *"state root (no copy in the candidate worktree)"* && "$output" == *"execution.yaml = "* && "$output" == *"NOT read"* ]]
}

@test "a legacy plan (troot == root) and a missing plan behave as before" {
  printf 'x\n' > "$T/root/.aid-o/plans/P900-x.md"
  run _pfsm_plan_file_for_gates "$T/root" "$T/root" P900
  [ "$output" = "$T/root/.aid-o/plans/P900-x.md	state_root" ]
  run _pfsm_plan_file_for_gates "$T/root" "$T/wt" P901
  [ "$status" -eq 1 ]; [ -z "$output" ]
}
