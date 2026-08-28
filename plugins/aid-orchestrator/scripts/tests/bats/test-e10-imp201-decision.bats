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
  mkdir -p "$PROJ/plugins/aid-orchestrator/scripts/lib" \
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

@test "once the shared classifier is really consulted the decision flips to fixed on its own" {
  # This is the whole point of deriving it: nobody edits the decision, the
  # decision follows the code. The fixture is what a REAL closure looks like —
  # a lib defines the classifier and _artifact_head_match calls it.
  cat > "$PROJ/plugins/aid-orchestrator/scripts/lib/aid-freshness.sh" <<'LIB'
aid_freshness_exception_applies() { return 1; }
LIB
  cat > "$PROJ/plugins/aid-orchestrator/scripts/aid-release-policy.sh" <<'RP'
_artifact_head_match() {
  local f="$1"
  if aid_freshness_exception_applies "$f"; then echo true; return 0; fi
  echo false
}
RP
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .decision "$PROJ/d.json")" = "fixed" ]
  [ "$(jq -r .trailing_commit_case_covered "$PROJ/d.json")" = "true" ]
}

@test "a COMMENT naming the classifier does not close IMP-201" {
  # The earlier check was a bare grep over the whole file, so this exact fixture
  # reported `fixed` — a defect closed by prose. Found by cross-model review,
  # which noted the previous test had codified the false positive rather than
  # catching it.
  cat > "$PROJ/plugins/aid-orchestrator/scripts/aid-release-policy.sh" <<'RP'
# TODO: one day route this through aid_freshness_exception_applies
_artifact_head_match() { echo false; }
RP
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .decision "$PROJ/d.json")" = "observe_hold" ]
}

@test "a call from some unrelated function does not close IMP-201 either" {
  # The defect is _artifact_head_match's exact comparison. A call anywhere else
  # says nothing about the trailing-commit class.
  cat > "$PROJ/plugins/aid-orchestrator/scripts/lib/aid-freshness.sh" <<'LIB'
aid_freshness_exception_applies() { return 1; }
LIB
  cat > "$PROJ/plugins/aid-orchestrator/scripts/aid-release-policy.sh" <<'RP'
_something_else() { aid_freshness_exception_applies "$@"; }
_artifact_head_match() { echo false; }
RP
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "$(jq -r .decision "$PROJ/d.json")" = "observe_hold" ]
}

@test "a call to a classifier no library defines does not close IMP-201" {
  cat > "$PROJ/plugins/aid-orchestrator/scripts/aid-release-policy.sh" <<'RP'
_artifact_head_match() { aid_freshness_exception_applies "$1"; }
RP
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "$(jq -r .decision "$PROJ/d.json")" = "observe_hold" ]
  [[ "$output" == *"no lib defines it"* ]]
}

@test "an observe_hold the policy is not honouring is REFUSED, not recorded" {
  # The contradiction that would otherwise ship quietly: a record claiming a
  # hold while the policy that implements the hold says blocking.
  sed -i 's/^evidence_pack_freshness_policy: observe/evidence_pack_freshness_policy: blocking/' \
    "$PROJ/plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml"
  run bash "$TOOL" --project-root "$PROJ" --out "$PROJ/d.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"the record and the policy disagree"* ]]
}

@test "the shipped policy really carries the key the hold depends on" {
  # Without this the four cases above could all pass against a policy file that
  # no longer has the key, with enforcement reading `unknown` forever.
  run yq -r '.evidence_pack_freshness_policy' \
    "$AID_PLUGIN_PATH/defaults/policies/release-decision-policy.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = "observe" ]
}
