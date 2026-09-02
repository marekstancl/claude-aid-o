#!/usr/bin/env bats
# aid-tier: t0
#
# The run verdict is derived from the gate rows, once, at the end.
#
# ACTA and WAN both reported `overall: pass` on runs whose required gates had
# failed (2026-08-27 .. 09-01). `overall` is assigned in seven branches inside
# the gate loop; a path reaching none of them left the initial "pass" standing.
# Those branches remain the fast path — this is the authority over them.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  RUNNER="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
}

@test "the derivation block exists and keys on result=fail AND required=true" {
  local block
  block="$(sed -n '/the verdict is DERIVED from the rows/,/local completed_at/p' "$RUNNER")"
  [ -n "$block" ]
  [[ "$block" == *'.value.result? // "") == "fail"'* ]]
  [[ "$block" == *'.value.required? // false) == true'* ]]
  [[ "$block" == *'overall="fail"'* ]]
}

@test "a waived gate is deliberately not counted as a failure" {
  local block
  block="$(sed -n '/the verdict is DERIVED from the rows/,/local completed_at/p' "$RUNNER")"
  [[ "$block" != *'"waived"'* ]] || [[ "$block" == *'waived'*'not a failure'* ]]
}

@test "gate rows carry required, so the verdict has something to re-derive from" {
  # The field is written inside a double-quoted shell string, so the file
  # literally contains the backslashes: \"required\": \$req
  grep -q 'required.*: .*req' "$RUNNER"
  grep -q 'argjson req' "$RUNNER"
}

@test "rows that cannot be counted are reported, never blessed as a pass" {
  local block
  block="$(sed -n '/the verdict is DERIVED from the rows/,/local completed_at/p' "$RUNNER")"
  [[ "$block" == *"could not re-derive the verdict"* ]]
  [[ "$block" == *"unconfirmed"* ]]
}

@test "the correction is logged, not silent" {
  local block
  block="$(sed -n '/the verdict is DERIVED from the rows/,/local completed_at/p' "$RUNNER")"
  [[ "$block" == *"gate_overall_corrected"* ]]
}

@test "revision pair: 'no revision' looks like no revision on BOTH halves" {
  # Outside a repository the supervisor answers "nogit nogit". Normalizing only
  # the head left ("", "nogit") — a tree that looks like a digest and compares
  # equal across every non-repo run.
  run bash -c "source '$PLUGIN_ROOT/scripts/lib/aid-resume-artifact.sh'
               aid_gate_row_revision /tmp"
  [[ "$output" != *"nogit"* ]]
  [[ "$output" != *"none"* ]]
}
