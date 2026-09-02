#!/usr/bin/env bats
# aid-tier: t0
#
# epic-start reads the run id; it does not invent one.
#
# ACTA, 2026-08-31: `aid-json-to-run.sh --run-id R-E020-2` created the FSM state
# and the evidence under that id, and epic-start recorded `R-<epic>-plan` in the
# manifest instead. `epic-complete` then could not find its own run, and the
# EPIC could not be finished without a manual repair.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FSM="$PLUGIN_ROOT/scripts/aid-plan-fsm.sh"
}

@test "the invented default is gone from the source" {
  ! grep -q 'run_id_opt:-R-\${epic_id}-plan' "$FSM"
}

@test "with no run on disk and no --run-id, epic-start refuses and says why" {
  local block
  block="$(sed -n '/THE RUN ID IS READ, NOT INVENTED/,/local task_branch/p' "$FSM")"
  [[ "$block" == *"no run exists on disk and no --run-id was given"* ]]
  [[ "$block" == *"epic-start no longer invents one"* ]]
  [[ "$block" == *"exit 1"* ]]
}

@test "exactly one run on disk is adopted; several is a refusal naming them" {
  local block
  block="$(sed -n '/THE RUN ID IS READ, NOT INVENTED/,/local task_branch/p' "$FSM")"
  [[ "$block" == *'1) run_id="${_found[0]}"'* ]]
  [[ "$block" == *"runs exist on disk"* ]]
  [[ "$block" == *"pass --run-id to say which one"* ]]
}

@test "an explicit --run-id still wins over anything on disk" {
  local block
  block="$(sed -n '/THE RUN ID IS READ, NOT INVENTED/,/local task_branch/p' "$FSM")"
  [[ "$block" == *'local run_id="${run_id_opt:-}"'* ]]
  [[ "$block" == *'if [[ -z "$run_id" ]]; then'* ]]
}
