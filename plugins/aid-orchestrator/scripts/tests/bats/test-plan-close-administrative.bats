#!/usr/bin/env bats
# aid-tier: t0
#
# `plan-close --administrative` — closing a plan that has no evidence chain.
#
# The PM asked for this for two real cases (2026-09-02): a plan written in AID
# but developed outside it, and a plugin defect that strands a plan for hours.
# ACTA's P019 showed why `--force` cannot serve either: force unlocks a CHECK
# over data that is real, and there the data was absent or said `fail`, so
# forcing would have meant inventing a candidate, a run id and a verdict. The
# reporting agent refused to fabricate them even with the PM's blessing.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FSM="$PLUGIN_ROOT/scripts/aid-plan-fsm.sh"
}

@test "the flag exists and is documented as different from --force" {
  grep -q -- '--administrative) _PFSM_ADMIN_CLOSE=1' "$FSM"
  local block
  block="$(sed -n '/ADMINISTRATIVE CLOSE — a different thing from --force/,/--administrative)/p' "$FSM")"
  [[ "$block" == *"unlocks a CHECK over data that is real"* ]]
  [[ "$block" == *"fabricating evidence"* ]]
}

@test "--administrative and --force are refused together" {
  local block
  block="$(sed -n '/An administrative close is a PM decision on the record/,/^  fi/p' "$FSM")"
  [[ "$block" == *"say different things"* ]]
  [[ "$block" == *"pick one"* ]]
  [[ "$block" == *"exit 2"* ]]
}

@test "a reason of at least 20 characters is required" {
  local block
  block="$(sed -n '/An administrative close is a PM decision on the record/,/^  fi/p' "$FSM")"
  [[ "$block" == *'lt 20'* ]]
  [[ "$block" == *"recorded verbatim"* ]]
}

@test "it records what could not be confirmed instead of asserting it" {
  grep -q '_PFSM_ADMIN_MISSING=' "$FSM"
  grep -q 'what could not be confirmed' "$FSM"
}

@test "the close never reads as an ordinary one" {
  grep -q 'CLOSED ADMINISTRATIVELY' "$FSM"
  grep -q 'closed_administrative' "$FSM"
  local block
  block="$(sed -n '/CLOSED ADMINISTRATIVELY/,/elif/p' "$FSM")"
  [[ "$block" == *"does not count as it"* ]]
}

@test "no candidate, run id or verdict is written by this path" {
  local block
  block="$(sed -n '/ADMINISTRATIVE CLOSE: .* is being closed WITHOUT evidence/,/ccrc=0/p' "$FSM")"
  [[ "$block" == *"nothing below fabricates a candidate"* ]]
}
