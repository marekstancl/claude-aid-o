#!/usr/bin/env bats
# aid-tier: t2
# test-release-policy-surface-check.bats — P061 D8 bootstrap surface rule regression guard.
# See scripts/tests/release-policy-surface-check.sh header for the full rule + rationale.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"   # .../plugins/aid-orchestrator
  CHECK="$PLUGIN_ROOT/scripts/tests/release-policy-surface-check.sh"
}

@test "negative: aid-run-gates.sh change does NOT select release-policy suite" {
  run bash "$CHECK" "plugins/aid-orchestrator/scripts/aid-run-gates.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == "not-relevant" ]]
}

@test "negative: aid-fsm.sh + aid-run.md + pipeline.md change does NOT select release-policy suite" {
  run bash "$CHECK" \
    "plugins/aid-orchestrator/scripts/aid-fsm.sh" \
    "plugins/aid-orchestrator/commands/aid-run.md" \
    "plugins/aid-orchestrator/skills/pipeline.md"
  [ "$status" -eq 1 ]
  [[ "$output" == "not-relevant" ]]
}

@test "positive: aid-release-policy.sh change MUST select release-policy suite" {
  run bash "$CHECK" "plugins/aid-orchestrator/scripts/aid-release-policy.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"relevant"* ]]
}

@test "positive: fixtures/release-policy/ change MUST select release-policy suite" {
  run bash "$CHECK" "plugins/aid-orchestrator/scripts/tests/fixtures/release-policy/pack/gates_report.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"relevant"* ]]
}

@test "positive: aid-evidence-verify.sh change MUST select release-policy suite" {
  run bash "$CHECK" "plugins/aid-orchestrator/scripts/aid-evidence-verify.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"relevant"* ]]
}

@test "mixed diff: one relevant path among several irrelevant ones still selects the suite" {
  run bash "$CHECK" \
    "plugins/aid-orchestrator/scripts/aid-run-gates.sh" \
    "plugins/aid-orchestrator/scripts/aid-release-policy.sh" \
    "plugins/aid-orchestrator/commands/aid-run.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"relevant"* ]]
}

@test "fail-safe: zero changed paths defaults to relevant (run the suite when in doubt)" {
  run bash "$CHECK"
  [ "$status" -eq 0 ]
  [[ "$output" == "relevant"* ]]
}
