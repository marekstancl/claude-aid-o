#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/lib/aid-gate-row.sh
# What a gate row keeps of a long output: the beginning and the END (where a test runner prints its result).
# Defect it catches: rows kept only the first 2000 characters, so a failing E2E gate's result was never in the
# evidence (ACTA P026, two reruns of 20 minutes only to read why).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  # shellcheck source=/dev/null
  source "$AID_PLUGIN_PATH/scripts/lib/aid-gate-row.sh"
}

@test "gate output: a short output is kept whole; a long one keeps its start and its result at the end, the cut said" {
  run aid_gate_output_excerpt "short output"
  [ "$output" = "short output" ]
  local long; long="START-building-image $(head -c 9000 /dev/zero | tr '\0' 'x') 3 failed, 277 passed"
  run aid_gate_output_excerpt "$long"
  [[ "$output" == "START-building-image"* ]]
  [[ "$output" == *"3 failed, 277 passed" ]]
  [[ "$output" == *"znaků výstupu vynecháno"* ]]
  (( ${#output} < 4100 ))
}

@test "gate output: the foreground runner, the scheduled row and a background job's row use the one rule" {
  local g="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  ! grep -nE '\$\{(output|1):0:2000\}' "$g"
  [ "$(grep -c 'aid_gate_output_excerpt' "$g")" -ge 2 ]
  grep -q 'aid_gate_output_excerpt "\$raw"' "$AID_PLUGIN_PATH/scripts/lib/aid-gate-row.sh"
}
