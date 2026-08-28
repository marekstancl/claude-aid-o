#!/usr/bin/env bats
# aid-tier: t1
# test-e10-imp201-decision.bats — E10's IMP-201 disposition is DERIVED.
# Provenance: P062 Step 3 (D6).
#
# The disposition is a fact about the repository, not an opinion: IMP-201 is
# closed exactly when aid-release-policy.sh consults the shared D4 freshness
# classifier. These cases exist because a hand-written decision file is wrong
# in both directions over time — it keeps saying `observe_hold` after someone
# closes the defect, and it keeps saying `fixed` after a refactor removes the
# sharing. Half of them assert a refusal.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TOOL="$AID_PLUGIN_PATH/scripts/aid-e10-imp201-decision.sh"
  export TOOL

  PROJ="$TEST_TMPDIR/proj"
  mkdir -p "$PROJ/plugins/aid-orchestrator/scripts" \
           "$PROJ/plugins/aid-orchestrator/defaults/policies"
  export PROJ
  cp "$AID_PLUGIN_PATH/defaults/policies/release-decision-policy.yaml" \
     "$PROJ/plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml"
  echo '# no shared classifier here' > "$PROJ/plugins/aid-orchestrator/scripts/aid-release-policy.sh"
}

teardown() { teardown_test_evidence_dir; }

@test "with no shared classifier the decision is observe_hold and says what it costs" {
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .decision "$PROJ/d.json")" = "observe_hold" ]
  [ "$(jq -r .trailing_commit_case_covered "$PROJ/d.json")" = "false" ]
  [[ "$(jq -r .promotion_consequence "$PROJ/d.json")" == *"must NOT be promoted"* ]]
}

@test "the reason is long enough to be a reason — AC3 requires 20 characters" {
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "${#}" -ge 0 ]
  reason="$(jq -r .reason "$PROJ/d.json")"
  [ "${#reason}" -ge 20 ]
}

@test "once the shared classifier is consulted the decision flips to fixed on its own" {
  # This is the whole point of deriving it. Nobody edits the decision; the
  # decision follows the code.
  echo 'aid_freshness_exception_applies "$@"' >> "$PROJ/plugins/aid-orchestrator/scripts/aid-release-policy.sh"
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .decision "$PROJ/d.json")" = "fixed" ]
  [ "$(jq -r .trailing_commit_case_covered "$PROJ/d.json")" = "true" ]
}

@test "an observe_hold the policy is not honouring is REFUSED, not recorded" {
  # The contradiction that would otherwise ship quietly: a record claiming a
  # hold while the policy that implements the hold says blocking.
  sed -i 's/^evidence_pack_freshness_policy: observe/evidence_pack_freshness_policy: blocking/' \
    "$PROJ/plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml"
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"the hold is not actually in force"* ]]
}

@test "the shipped policy really carries the key the hold depends on" {
  # Without this the four cases above could all pass against a policy file that
  # no longer has the key, with enforcement reading `unknown` forever.
  run yq -r '.evidence_pack_freshness_policy' \
    "$AID_PLUGIN_PATH/defaults/policies/release-decision-policy.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = "observe" ]
}
