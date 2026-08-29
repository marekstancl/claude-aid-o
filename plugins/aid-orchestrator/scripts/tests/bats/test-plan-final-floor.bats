#!/usr/bin/env bats
# aid-tier: t0
# The plan-final gate floor is bounded by the resolved profile (WAN #14) and a
# plan with no verification_pattern owes plan_diff nothing (WAN #15).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH AID_TEST_MODE=1
  T="$(mktemp -d)"; cd "$T"
  cat > exec.yaml <<'YAML'
gate_profiles:
  release: {include: [tests_pass, plan_diff]}
gates:
  tests_pass: {required: true, command: "true"}
  tests_full_portfolio: {required: true, nightly: true, command: "true"}
  plan_diff: {required: false, command: "true"}
YAML
  source "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
}
teardown() { rm -rf "$T"; }

@test "a required gate outside the resolved profile is not owed by the plan-final run" {
  run _pfsm_plan_required_floor exec.yaml $'tests_pass\nplan_diff' ""
  [ "$status" -eq 0 ]
  [ "$output" = $'plan_diff\ntests_pass' ]
}

@test "manifest-accumulated gates and plan_diff stay in the floor" {
  run _pfsm_plan_required_floor exec.yaml $'tests_pass\nplan_diff' "security_scan_pass"
  [ "$output" = $'plan_diff\nsecurity_scan_pass\ntests_pass' ]
}

@test "a plan with no verification_pattern has nothing for plan_diff to evaluate" {
  printf '# Plan\n\n## AC\n- prose only\n' > p1.md
  printf '# Plan\n\n- AC1\n  verification_pattern: grep -q x\n' > p2.md
  ! _pfsm_plan_has_patterns p1.md
  _pfsm_plan_has_patterns p2.md
}
