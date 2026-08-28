#!/usr/bin/env bats
# aid-tier: t1
# test-control-metrics.bats — the C0-C4 quality measurement.
# Provenance: P062 Step 4 (D1, D8 input).
#
# THE TWO RULES THIS SUITE EXISTS TO HOLD
#   1. NULL IS NOT ZERO. `false_done` and `false_positives` need to know what
#      SHOULD have happened. Without the calibration dataset nobody does, and a
#      0 there is a clean bill written from an empty room.
#   2. `unverifiable` IS NOT A NON-FAIL. C3's outcome mix is counted apart,
#      because a control that mostly cannot reach a verdict looks, in any
#      summary that folds those into "did not block", exactly like a control
#      that is safe to promote.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TOOL="$AID_PLUGIN_PATH/scripts/aid-control-metrics.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/control-metrics.schema.json"
  export TOOL SCHEMA
  EV="$TEST_TMPDIR/ev"
  mkdir -p "$EV/E-900-1_1/R-1"
  export EV
}

teardown() { teardown_test_evidence_dir; }

_audit() { printf '{"status":"%s","findings":[]}' "$2" > "$EV/E-900-1_1/R-1/$1"; }

@test "C3's verdict mix is counted, and unverifiable is kept apart from fail" {
  mkdir -p "$EV/a" "$EV/b" "$EV/c"
  printf '{"status":"pass"}'         > "$EV/a/audit-report.json"
  printf '{"status":"fail"}'         > "$EV/b/audit-report.json"
  printf '{"status":"unverifiable"}' > "$EV/c/audit-report.json"
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .c3_verdict_mix.pass "$TEST_TMPDIR/m.json")" -eq 1 ]
  [ "$(jq -r .c3_verdict_mix.fail "$TEST_TMPDIR/m.json")" -eq 1 ]
  [ "$(jq -r .c3_verdict_mix.unverifiable "$TEST_TMPDIR/m.json")" -eq 1 ]
}

@test "an unreadable audit report counts as unverifiable, never as absent" {
  # Dropping it would shrink the denominator, which flatters the very ratio
  # this field exists to expose.
  mkdir -p "$EV/x"
  printf 'not json at all {' > "$EV/x/audit-report.json"
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r .c3_verdict_mix.unverifiable "$TEST_TMPDIR/m.json")" -eq 1 ]
  [ "$(jq -r .c3_verdict_mix.pass "$TEST_TMPDIR/m.json")" -eq 0 ]
}

@test "without ground truth the counters are NULL, not zero" {
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.controls[0].ground_truth' "$TEST_TMPDIR/m.json")" = "absent" ]
  [ "$(jq -r '.controls[0].false_done' "$TEST_TMPDIR/m.json")" = "null" ]
  [ "$(jq -r '.controls[0].false_positives' "$TEST_TMPDIR/m.json")" = "null" ]
  # The distinction the whole rule rests on: a zero here would read as
  # "this control never missed anything".
  [ "$(jq -r '.controls[0].false_done' "$TEST_TMPDIR/m.json")" != "0" ]
}

@test "a calibration manifest flips ground_truth to present" {
  printf '{"fixtures":[{"path":"f1","source_incident":"OBS-1"}]}' > "$TEST_TMPDIR/gt.json"
  run bash "$TOOL" --evidence-root "$EV" --ground-truth "$TEST_TMPDIR/gt.json" --out "$TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.controls[0].ground_truth' "$TEST_TMPDIR/m.json")" = "present" ]
}

@test "a manifest that is not a manifest does not flip ground_truth" {
  printf '{"something":"else"}' > "$TEST_TMPDIR/gt.json"
  run bash "$TOOL" --evidence-root "$EV" --ground-truth "$TEST_TMPDIR/gt.json" --out "$TEST_TMPDIR/m.json"
  [ "$(jq -r '.controls[0].ground_truth' "$TEST_TMPDIR/m.json")" = "absent" ]
}

@test "every control gets a row even when its artifact is nowhere" {
  # A missing control is a fact about the run. Leaving the row out would
  # shorten the table and quietly change what the decision step is deciding over.
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$(jq -r '[.controls[].control] | sort | join(",")' "$TEST_TMPDIR/m.json")" = "c0,c1,c2,c3,c4" ]
}

@test "a control that flagged something has its classes counted, deduplicated" {
  mkdir -p "$EV/r1" "$EV/r2"
  printf '{"findings":[{"area":"schema"},{"area":"schema"},{"area":"wiring"}]}' > "$EV/r1/c0-plan-review.json"
  printf '{"findings":[{"area":"wiring"}]}' > "$EV/r2/c0-plan-review.json"
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$(jq -r '.controls[] | select(.control=="c0") | .caught_classes | length' "$TEST_TMPDIR/m.json")" -eq 2 ]
}

@test "Step 5: with no durations journal the wall-clock fields are NULL, not 0" {
  # An unmeasured path is not a free one. A 0 here would put "the merge path
  # costs nothing" into the artifact the decision table reads.
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.speed.merge_path_seconds' "$TEST_TMPDIR/m.json")" = "null" ]
  [ "$(jq -r '.speed.nightly_seconds' "$TEST_TMPDIR/m.json")" = "null" ]
}

@test "Step 5: Fast Mode is not_measurable, and the schema allows nothing else" {
  # IMP-506: /aid-do invokes no AID script, so a measured 0 would read as
  # "Fast Mode never escalates" — a claim about behaviour nobody made.
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$(jq -r '.speed.fast_mode' "$TEST_TMPDIR/m.json")" = "not_measurable" ]
  run jq -e '.properties.speed.properties.fast_mode.enum | length == 1' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "Step 5: the per-EPIC full-suite unit is absent from the schema on purpose" {
  # P068 pays the expensive gates once per PLAN. A field for a unit that no
  # longer runs is how a stale measurement story survives a redesign.
  run jq -e '.properties.speed.properties | has("full_suite_time") | not' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "Step 5: durations are read through the shared library, tiers included" {
  # Not a re-implementation: the journal and the tier tags own these numbers,
  # and the nightly report and the reaper already read them from there. This
  # asserts the wiring rather than the arithmetic.
  run grep -c "aid_durations_by_suite\|aid_test_tier_of" "$TOOL"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "Step 5: llm_calls stays NULL — it is not the dispatch count under another name" {
  mkdir -p "$EV/d"
  printf '{"event":"start","focus":"impl"}\n{"event":"start","focus":"verify"}\n' > "$EV/d/pending-dispatches.jsonl"
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.speed.dispatch_count' "$TEST_TMPDIR/m.json")" -eq 2 ]
  # One dispatch is not one model call. A number here would be a fabrication in
  # a field a promotion decision reads.
  [ "$(jq -r '.speed.llm_calls' "$TEST_TMPDIR/m.json")" = "null" ]
}

@test "Step 5: with no dispatch ledger the count is NULL, not a confident zero" {
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$(jq -r '.speed.dispatch_count' "$TEST_TMPDIR/m.json")" = "null" ]
}

@test "Step 5: baseline_seconds is NULL — the current merge path is not a baseline" {
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$(jq -r '.speed.baseline_seconds' "$TEST_TMPDIR/m.json")" = "null" ]
  [ "$(jq -r '.speed.e10_added_seconds' "$TEST_TMPDIR/m.json")" = "null" ]
}

@test "Step 4: c3_hook_fired is counted from dispatch records and is its own field" {
  mkdir -p "$EV/h1" "$EV/h2"
  printf '{"dispatch":{"invoked":true}}' > "$EV/h1/c3-dispatch.json"
  printf '{"dispatch":{"invoked":true}}' > "$EV/h2/c3-dispatch.json"
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  [ "$(jq -r '.c3_hook_fired' "$TEST_TMPDIR/m.json")" -eq 2 ]
  # Not inferred from the verdict mix: a hook that never fired and a hook that
  # fired and could not decide both produce no pass, and only one is a wiring
  # problem.
  [ "$(jq -r '.c3_verdict_mix.pass' "$TEST_TMPDIR/m.json")" -eq 0 ]
}

@test "the schema closes the root and the speed object, not just the control rows" {
  run jq -e '.additionalProperties == false and .properties.speed.additionalProperties == false' "$SCHEMA"
  [ "$status" -eq 0 ]
  run jq -e '(.required | index("c3_hook_fired")) != null' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "Step 9: the baseline source is P063, never a full-suite-per-EPIC run" {
  # P068 abolished that unit. Measuring a saving against a run that no longer
  # happens would be a saving against nothing.
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  pc="$(jq -r '.profile_calibration' "$TEST_TMPDIR/m.json")"
  if [ "$pc" != "null" ]; then
    [ "$(jq -r '.profile_calibration.baseline_source' "$TEST_TMPDIR/m.json")" = "p063" ]
    [ "$(jq -r '.profile_calibration.scope' "$TEST_TMPDIR/m.json")" = "aid_run_only" ]
  fi
}

@test "Step 9: the schema pins the only two honest values for source and scope" {
  # scope is aid_run_only because Fast Mode emits no profile events (IMP-506);
  # a calibration silently covering "both entry points" would be a claim about
  # a path nobody measured.
  run jq -e '.properties.profile_calibration.properties.baseline_source.enum == ["p063"]' "$SCHEMA"
  [ "$status" -eq 0 ]
  run jq -e '.properties.profile_calibration.properties.scope.enum == ["aid_run_only"]' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "Step 9: a saving computed over unmeasured gates would be a guess — null instead" {
  run jq -e '(.properties.profile_calibration.properties.savings_seconds.type | index("null")) != null' "$SCHEMA"
  [ "$status" -eq 0 ]
  run jq -e '.properties.profile_calibration.properties | has("gates_without_baseline")' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "a missing evidence root is refused, not reported as a clean measurement" {
  run bash "$TOOL" --evidence-root "$TEST_TMPDIR/nope" --out "$TEST_TMPDIR/m.json"
  [ "$status" -eq 2 ]
  [ ! -f "$TEST_TMPDIR/m.json" ]
}

@test "the artifact satisfies the canonical field names the decision table reads" {
  # The C0 finding this schema exists for: three spellings of the same fields
  # across the plan meant the decision table could not consume its own input.
  run bash "$TOOL" --evidence-root "$EV" --out "$TEST_TMPDIR/m.json"
  run jq -e 'all(.controls[];
      has("control") and has("caught_classes") and has("false_done")
      and has("false_positives") and has("cost_seconds")
      and has("unique_detection_vs_legacy"))' "$TEST_TMPDIR/m.json"
  [ "$status" -eq 0 ]
}

@test "the shipped schema forbids the field names that were drifting" {
  # additionalProperties:false is what makes the canonical names binding. A
  # schema that tolerates extras would let `caught` reappear beside
  # `caught_classes` and the drift would start again.
  run jq -e '.properties.controls.items.additionalProperties == false' "$SCHEMA"
  [ "$status" -eq 0 ]
  run jq -e '.properties.speed.properties.fast_mode.enum == ["not_measurable"]' "$SCHEMA"
  [ "$status" -eq 0 ]
}
