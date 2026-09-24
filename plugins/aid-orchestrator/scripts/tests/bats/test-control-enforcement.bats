#!/usr/bin/env bats
# aid-tier: t0
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
  yq -i '.controls.c2_semantic_review.enforcement = "blocking"' "$POL/semantic-review.yaml"
  run bash -c 'source "$1"; aid_control_enforcement "$2" c2_semantic_review' _ "$LIB" "$POL/semantic-review.yaml"
  [ "$output" = "blocking" ]
  run bash -c 'source "$1"; aid_control_enforcement "$2" c2_review_profile' _ "$LIB" "$POL/semantic-review.yaml"
  [ "$output" = "observe" ]
}

@test "a malformed override is not an override — it neither promotes nor demotes" {
  yq -i '.enforcement = "blocking"' "$POL/semantic-review.yaml"
  yq -i '.controls.c2_semantic_review.enforcement = "blokcing"' "$POL/semantic-review.yaml"
  run bash -c 'source "$1"; aid_control_enforcement "$2" c2_semantic_review' _ "$LIB" "$POL/semantic-review.yaml"
  [ "$output" = "blocking" ]
}

@test "a missing policy file resolves to observe, never to blocking" {
  run bash -c 'source "$1"; aid_control_enforcement "$2" c2_semantic_review' _ "$LIB" "$POL/does-not-exist.yaml"
  [ "$output" = "observe" ]
}

@test "every reader in the shipped code goes through the shared resolver" {
  # The assertion is the INVARIANT, not a headcount of files: aid-fsm.sh is the
  # only caller left (aid-auto-pipeline.sh stopped reading the policy when CP1
  # became the generation gate, and this case kept naming it long afterwards),
  # and nothing anywhere reads a control's enforcement without the resolver.
  grep -q 'aid_control_enforcement' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  # no shipped script parses `.controls.*.enforcement` on its own
  run grep -rln --include='*.sh' "controls\..*\.enforcement" "$AID_PLUGIN_PATH/scripts"
  [ "$output" = "" ] || [ "$output" = "$AID_PLUGIN_PATH/scripts/lib/aid-control-enforcement.sh" ]
}
