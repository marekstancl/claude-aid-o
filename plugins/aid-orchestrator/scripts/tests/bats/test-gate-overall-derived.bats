#!/usr/bin/env bats
# aid-tier: t2
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

@test "revision pair: 'no revision' looks like no revision on BOTH halves" {
  # Outside a repository the supervisor answers "nogit nogit". Normalizing only
  # the head left ("", "nogit") — a tree that looks like a digest and compares
  # equal across every non-repo run.
  run bash -c "source '$PLUGIN_ROOT/scripts/lib/aid-resume-artifact.sh'
               aid_gate_row_revision /tmp"
  [[ "$output" != *"nogit"* ]]
  [[ "$output" != *"none"* ]]
}
