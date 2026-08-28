#!/usr/bin/env bats
# aid-tier: t1
# test-e10-calibration-dataset.bats — the calibration dataset's own integrity.
# Provenance: P062 Step 6 (D3).
#
# WHAT THIS SUITE PROVES, AND WHAT IT DELIBERATELY DOES NOT
#   It proves the manifest is well-formed and self-consistent: every grounded
#   entry names a non-empty incident, has a real fixture directory and states
#   both expected outcomes; every excluded entry says why; every declared
#   catcher is a control that exists. That is SHAPE — it is not a claim that the
#   incidents are real, which was established by the grounding pass and is
#   recorded in each entry's source_incident.
#
#   It proves a CATCH, by RUNNING the control, for exactly one class — the one
#   whose catcher can be driven directly — together with its complement, so
#   "it caught it" cannot be satisfied by a detector that flags everything. For
#   C1/C2/C3/C4 the manifest records an expectation and the proof is the
#   calibration run itself.

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

@test "the manifest is valid and every entry carries a NON-EMPTY provenance" {
  # `has()` is satisfied by a null, and `all()` is satisfied by an empty array —
  # so the earlier version of this case was green over a manifest that said
  # nothing (cross-model review, 2026-08-15). Both holes are closed.
  run jq -e '(.fixtures | length) >= 1' "$MAN"
  [ "$status" -eq 0 ]
  run jq -e 'all(.fixtures[];
      ((.id // "") | length) > 0
      and ((.source_incident // "") | length) > 0
      and ((.failure_class // "") | length) > 0
      and (.control | IN("positive","negative"))
      and ((.expected_catcher // "") | length) > 0
      and (.grounded | type == "boolean"))' "$MAN"
  [ "$status" -eq 0 ]
}

@test "every grounded fixture states BOTH expected outcomes" {
  # Without them the dual run has nothing to confirm or contradict, and
  # `expectation_held` would be meaningless.
  run jq -e 'all(.fixtures[] | select(.grounded);
      ((.expected_old // "") | length) > 0 and ((.expected_new // "") | length) > 0)' "$MAN"
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

# _project_with <fixture-subdir> — a throwaway project whose evidence is that
# fixture, so the REAL preflight can be run against it.
_project_with() {
  local fx="$1" proj="$TEST_TMPDIR/p_$fx"
  mkdir -p "$proj/.aid-o/plans" "$proj/.aid-o/work/evidence/E-900-1_1/R-FIX-1"
  : > "$proj/.aid-o/plans/P900-fixture.md"
  cp "$DS/$fx/fsm-state.yaml" "$proj/.aid-o/work/evidence/E-900-1_1/R-FIX-1/fsm-state.yaml"
  git -C "$proj" init -q 2>/dev/null || true
  git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null || true
  printf '%s' "$proj"
}

@test "PROVEN CATCH: the real preflight flags the DONE-with-pending-steps fixture" {
  # This case USED to grep the fixture it had itself written, which proved the
  # fixture contained two strings and nothing about the control (cross-model
  # review, 2026-08-15). It now runs aid-e10-preflight.sh over a project whose
  # evidence IS the fixture, and reads the verdict.
  proj="$(_project_with obs-20260708-04)"
  run bash "$AID_PLUGIN_PATH/scripts/aid-e10-preflight.sh" \
    --project-root "$proj" --out "$proj/pf.json"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.checked[] | select(.class=="steps_pending_at_done") | .status' "$proj/pf.json")" = "dirty" ]
}

@test "PROVEN NON-CATCH: the same preflight leaves the negative control alone" {
  # Without this the case above is satisfied by a preflight that flags
  # everything, which is not a detector.
  proj="$(_project_with negative-ordinary)"
  run bash "$AID_PLUGIN_PATH/scripts/aid-e10-preflight.sh" \
    --project-root "$proj" --out "$proj/pf.json"
  [ "$(jq -r '.checked[] | select(.class=="steps_pending_at_done") | .status' "$proj/pf.json")" = "clean" ]
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
