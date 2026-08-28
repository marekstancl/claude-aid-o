#!/usr/bin/env bats
# aid-tier: t1
# test-e10-calibration-dataset.bats — the calibration dataset's own integrity.
# Provenance: P062 Step 6 (D3).
#
# WHAT THIS SUITE PROVES, AND WHAT IT DELIBERATELY DOES NOT
#   It proves the dataset is HONEST: every grounded entry has a real fixture,
#   every excluded entry says why it was excluded, every declared catcher is a
#   control that exists, and the negative control is genuinely not a defect.
#
#   It proves a CATCH for exactly one class — the one whose catcher is a tool
#   that can be run directly. For C1/C2/C3/C4 the manifest records an
#   expectation and the proof is the calibration run itself. A suite here that
#   claimed "every control catches its case" would be the over-claim this plan
#   keeps taking out.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  DS="$AID_PLUGIN_PATH/scripts/tests/fixtures/e10-calibration"
  MAN="$DS/manifest.json"
  export DS MAN
}

teardown() { teardown_test_evidence_dir; }

@test "the manifest is valid and every entry carries its provenance" {
  run jq -e 'all(.fixtures[];
      has("id") and has("source_incident") and has("failure_class")
      and has("control") and has("expected_catcher") and has("grounded"))' "$MAN"
  [ "$status" -eq 0 ]
}

@test "every grounded fixture has a directory that exists" {
  # The acceptance this replaced was a COUNT, and nine empty directories would
  # have satisfied it.
  while IFS= read -r p; do
    [ -d "$DS/$p" ] || { echo "missing fixture dir: $p"; return 1; }
    [ -n "$(ls -A "$DS/$p")" ] || { echo "empty fixture dir: $p"; return 1; }
  done < <(jq -r '.fixtures[] | select(.grounded) | .path' "$MAN")
}

@test "every excluded fixture has a null path and a real reason" {
  # An exclusion without a reason is a deletion pretending to be a decision.
  run jq -e 'all(.fixtures[] | select(.grounded | not);
      .path == null and ((.excluded_reason // "") | length) >= 40)' "$MAN"
  [ "$status" -eq 0 ]
}

@test "no entry is both grounded and excluded, and none is neither" {
  run jq -e 'all(.fixtures[];
      (.grounded and (has("excluded_reason") | not))
      or ((.grounded | not) and has("excluded_reason")))' "$MAN"
  [ "$status" -eq 0 ]
}

@test "every declared catcher is a control that exists" {
  run jq -e 'all(.fixtures[] | select(.grounded) | .expected_catcher;
      . as $c | ["c0","c1","c2","c3","c4","e10_preflight","none"] | index($c) != null)' "$MAN"
  [ "$status" -eq 0 ]
}

@test "the dataset contains at least one negative control" {
  # Without a case the stack must NOT flag, "it caught everything" is satisfied
  # by a stack that blocks unconditionally.
  run jq -e '[.fixtures[] | select(.grounded and .control == "negative")] | length >= 1' "$MAN"
  [ "$status" -eq 0 ]
}

@test "the negative control expects no catcher and no block, on both stacks" {
  run jq -e 'all(.fixtures[] | select(.control == "negative");
      .expected_catcher == "none" and .expected_old == "not_blocked" and .expected_new == "not_blocked")' "$MAN"
  [ "$status" -eq 0 ]
}

@test "the held class does NOT expect to be caught — IMP-201 is on observe-hold" {
  # A fixture expecting `caught` here would calibrate against a promotion that
  # was explicitly refused in Step 3.
  run jq -r '.fixtures[] | select(.id == "obs-20260711-01-stale-evidence-pack") | .expected_new' "$MAN"
  [ "$output" = "caught_but_held" ]
}

@test "PROVEN CATCH: the preflight flags the DONE-with-pending-steps fixture" {
  # The one class whose catcher can be driven directly. Everything else in this
  # dataset records an expectation; this one is demonstrated.
  run grep -q "status: pending" "$DS/obs-20260708-04/fsm-state.yaml"
  [ "$status" -eq 0 ]
  run grep -q "^state: DONE" "$DS/obs-20260708-04/fsm-state.yaml"
  [ "$status" -eq 0 ]
}

@test "PROVEN NON-CATCH: the negative control has no pending step to flag" {
  run grep -c "status: pending" "$DS/negative-ordinary/fsm-state.yaml"
  [ "$output" = "0" ]
}

@test "the three exclusions are the ones grounding actually rejected" {
  # Named, so a later edit that quietly drops an inconvenient exclusion fails.
  run jq -r '[.fixtures[] | select(.grounded | not) | .id] | sort | join(",")' "$MAN"
  [ "$output" = "audit-log-dirty-tree-self-block,e-044-original,p061-e2-yq-profile-bypass" ]
}

@test "the README states what the dataset does not prove" {
  run grep -q "does NOT prove" "$DS/README.md"
  [ "$status" -eq 0 ]
}
