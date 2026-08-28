#!/usr/bin/env bats
# aid-tier: t1
# test-dual-run.bats — new stack vs legacy, per calibration fixture.
# Provenance: P062 Step 7 (D1, D8 input).
#
# THE CASE THIS SUITE EXISTS FOR is legacy_unique_catch: a legacy control that
# caught something the new stack did not. D8 forbids marking such a control an
# E11 removal candidate, so a dual-run that cannot see that class is worse than
# no dual-run — it would licence deleting a control that still works.
#
# The second rule is that an EXPECTATION is not an OUTCOME. The manifest says
# what each fixture is expected to do; comparing those to each other produces a
# confident report about the plan and measures nothing. With no outcomes the
# class is `unmeasured`, never `agree`.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TOOL="$AID_PLUGIN_PATH/scripts/aid-dual-run.sh"
  MAN="$AID_PLUGIN_PATH/scripts/tests/fixtures/e10-calibration/manifest.json"
  export TOOL MAN
  OUT="$TEST_TMPDIR/dr.json"
  export OUT
}

teardown() { teardown_test_evidence_dir; }

_outcomes() { printf '%s' "$1" > "$TEST_TMPDIR/o.json"; echo "$TEST_TMPDIR/o.json"; }

@test "legacy_unique_catch is detected AND surfaces as a non-zero exit" {
  o="$(_outcomes '{"obs-20260709-06-queue-active-stale":{"old":"caught","new":"not_caught"}}')"
  run bash "$TOOL" --manifest "$MAN" --outcomes "$o" --out "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"D8 forbids"* ]]
  [ "$(jq -r '.legacy_unique_catch | length' "$OUT")" -eq 1 ]
  # The report is still written — this is a finding, not a crash.
  [ -f "$OUT" ]
}

@test "new_unique_catch is classified and does not trip the exit" {
  o="$(_outcomes '{"obs-20260708-04-steps-pending-at-done":{"old":"not_caught","new":"caught"}}')"
  run bash "$TOOL" --manifest "$MAN" --outcomes "$o" --out "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.signal.new_unique_catch' "$OUT")" -eq 1 ]
}

@test "agreement is agreement only when both sides actually ran" {
  o="$(_outcomes '{"e-047-1-original":{"old":"caught","new":"caught"}}')"
  run bash "$TOOL" --manifest "$MAN" --outcomes "$o" --out "$OUT"
  [ "$(jq -r '.signal.agree' "$OUT")" -eq 1 ]
}

@test "with no outcomes every pair is unmeasured, never agree" {
  # Two unknowns are not an agreement. This is the difference between a
  # measurement and a report about the plan.
  run bash "$TOOL" --manifest "$MAN" --out "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.signal | length' "$OUT")" -eq 0 ]
  [ "$(jq -r '.unmeasured | length' "$OUT")" -gt 0 ]
  [ "$(jq -r '.pairs[0].divergence' "$OUT")" = "unmeasured" ]
}

@test "unmeasured pairs are excluded from the signal counts, not folded into them" {
  o="$(_outcomes '{"e-047-1-original":{"old":"caught","new":"caught"}}')"
  run bash "$TOOL" --manifest "$MAN" --outcomes "$o" --out "$OUT"
  [ "$(jq -r '[.signal | to_entries[] | .value] | add' "$OUT")" -eq 1 ]
  [ "$(jq -r '.pairs | length' "$OUT")" -gt 1 ]
}

@test "the report records whether the manifest's expectation actually held" {
  # A fixture can be caught by the right layer and still contradict what the
  # dataset predicted; that is a calibration result, not a pass.
  o="$(_outcomes '{"obs-20260708-04-steps-pending-at-done":{"old":"not_caught","new":"caught"}}')"
  run bash "$TOOL" --manifest "$MAN" --outcomes "$o" --out "$OUT"
  [ "$(jq -r '.pairs[] | select(.fixture=="obs-20260708-04-steps-pending-at-done") | .expectation_held' "$OUT")" = "true" ]
}

@test "a contradicted expectation is reported as false, not hidden" {
  o="$(_outcomes '{"obs-20260708-04-steps-pending-at-done":{"old":"caught","new":"caught"}}')"
  run bash "$TOOL" --manifest "$MAN" --outcomes "$o" --out "$OUT"
  [ "$(jq -r '.pairs[] | select(.fixture=="obs-20260708-04-steps-pending-at-done") | .expectation_held' "$OUT")" = "false" ]
}

@test "excluded fixtures never enter the dual run" {
  # An ungrounded entry has no fixture to run; including it would invent a pair.
  run bash "$TOOL" --manifest "$MAN" --out "$OUT"
  [ "$(jq -r '[.pairs[] | select(.fixture == "e-044-original")] | length' "$OUT")" -eq 0 ]
}

@test "a manifest with no fixtures key is refused" {
  printf '{"something":"else"}' > "$TEST_TMPDIR/bad.json"
  run bash "$TOOL" --manifest "$TEST_TMPDIR/bad.json" --out "$OUT"
  [ "$status" -eq 2 ]
  [ ! -f "$OUT" ]
}

@test "a malformed outcomes file is refused rather than treated as empty" {
  printf 'not json' > "$TEST_TMPDIR/o.json"
  run bash "$TOOL" --manifest "$MAN" --outcomes "$TEST_TMPDIR/o.json" --out "$OUT"
  [ "$status" -eq 2 ]
  # Treating it as empty would silently downgrade a real run to `unmeasured`.
  [[ "$output" == *"not valid JSON"* ]]
}
