#!/usr/bin/env bats
# aid-tier: t1
# test-control-enforcement.bats — the shared per-control enforcement resolver.
# Provenance: P062 Step 11; kept when the E10 calibration tooling was removed
# (2026-08-29) because six shipped readers still go through this resolver.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-control-enforcement.sh"; export LIB
  POL="$TEST_TMPDIR/policies"; mkdir -p "$POL"; export POL
  cp "$AID_PLUGIN_PATH"/defaults/policies/*.yaml "$POL/"
}

teardown() { teardown_test_evidence_dir; }

@test "the resolver returns the per-control value over the file default" {
  yq -i '.controls.c1_delivery_gate.enforcement = "blocking"' "$POL/delivery-gate.yaml"
  run bash -c 'source "$1"; aid_control_enforcement "$2" c1_delivery_gate' _ "$LIB" "$POL/delivery-gate.yaml"
  [ "$output" = "blocking" ]
  run bash -c 'source "$1"; aid_control_enforcement "$2" c2_semantic_review' _ "$LIB" "$POL/delivery-gate.yaml"
  [ "$output" = "observe" ]
}

@test "a malformed override is not an override — it neither promotes nor demotes" {
  yq -i '.enforcement = "blocking"' "$POL/delivery-gate.yaml"
  yq -i '.controls.c1_delivery_gate.enforcement = "blokcing"' "$POL/delivery-gate.yaml"
  run bash -c 'source "$1"; aid_control_enforcement "$2" c1_delivery_gate' _ "$LIB" "$POL/delivery-gate.yaml"
  [ "$output" = "blocking" ]
}

@test "a missing policy file resolves to observe, never to blocking" {
  run bash -c 'source "$1"; aid_control_enforcement "$2" c1_delivery_gate' _ "$LIB" "$POL/does-not-exist.yaml"
  [ "$output" = "observe" ]
}

@test "all six readers in the shipped code go through the shared resolver" {
  n="$(grep -c 'aid_control_enforcement' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh")"
  [ "$n" -ge 6 ]
  run grep -q 'aid_control_enforcement' "$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh"
  [ "$status" -eq 0 ]
}
