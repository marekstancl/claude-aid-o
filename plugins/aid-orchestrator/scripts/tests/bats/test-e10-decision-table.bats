#!/usr/bin/env bats
# aid-tier: t1
# test-e10-decision-table.bats — one decision per control, from evidence.
# Provenance: P062 Step 10 (D8).
#
# THE FAILURE THIS TABLE EXISTS TO PREVENT is an absence read as good news: a
# control with no recorded false positives, because nobody measured any,
# promoted for having a clean record. Half these cases assert a refusal.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TOOL="$AID_PLUGIN_PATH/scripts/aid-e10-decision-table.sh"
  export TOOL
  OUT="$TEST_TMPDIR/dt.json"
  export OUT
  # A fully measured, fully gated baseline. Each case spoils ONE thing.
  cat > "$TEST_TMPDIR/m.json" <<'M'
{"schema_version":"aid-2.0","artifact_type":"control_metrics","c3_hook_fired":5,
 "c3_verdict_mix":{"pass":8,"fail":2,"unverifiable":1},
 "speed":{"dispatch_count":0},
 "controls":[{"control":"c0","caught_classes":["schema"],"false_done":0,
   "false_positives":0,"cost_seconds":1,"unique_detection_vs_legacy":2,
   "ground_truth":"present","evidence_refs":["e1"]}]}
M
  printf '{"pairs":[],"legacy_unique_catch":[]}' > "$TEST_TMPDIR/d.json"
  printf '{"verdict":"clean"}'        > "$TEST_TMPDIR/pf.json"
  printf '{"decision":"fixed"}'       > "$TEST_TMPDIR/i.json"
  printf '{"decision":"budget_raised"}' > "$TEST_TMPDIR/b.json"
}

teardown() { teardown_test_evidence_dir; }

_run_all() {
  bash "$TOOL" --metrics "${1:-$TEST_TMPDIR/m.json}" --dual-run "${2:-$TEST_TMPDIR/d.json}" \
    --preflight "${3:-$TEST_TMPDIR/pf.json}" --imp201 "${4:-$TEST_TMPDIR/i.json}" \
    --budget "${5:-$TEST_TMPDIR/b.json}" --out "$OUT"
}

# Rows are keyed by INVENTORY ID now, and one control may own several. These
# helpers ask by control and expect a single distinct decision across its rows,
# which is what the metrics-per-control model produces; a case that needs one
# specific row asks for it by id.
_decision() { jq -r --arg c "$1" '[.controls[] | select(.control==$c) | .decision] | unique | .[0]' "$OUT"; }
_decision_id() { jq -r --arg i "$1" '.controls[] | select(.inventory_id==$i) | .decision' "$OUT"; }

@test "a measured, gated, useful control is promoted" {
  # The baseline. Without it every refusal below is satisfiable by a table that
  # never promotes anything.
  run _run_all
  [ "$status" -eq 0 ]
  [ "$(_decision c0)" = "promote_to_blocking" ]
}

@test "an unmeasured counter defers — an absence is never a clean record" {
  jq '.controls[0].false_positives = null' "$TEST_TMPDIR/m.json" > "$TEST_TMPDIR/m2.json"
  run _run_all "$TEST_TMPDIR/m2.json"
  [ "$(_decision c0)" = "defer" ]
  [[ "$(jq -r '.controls[] | select(.control=="c0") | .reason' "$OUT")" == *"insufficient data"* ]]
}

@test "a legacy-only catch keeps the dual run and never recommends removal" {
  printf '{"pairs":[{"expected_catcher":"c0","divergence":"legacy_unique_catch"}],"legacy_unique_catch":["f1"]}' > "$TEST_TMPDIR/d2.json"
  run _run_all "$TEST_TMPDIR/m.json" "$TEST_TMPDIR/d2.json"
  [ "$(_decision c0)" = "keep_dual_run" ]
  [ "$(_decision c0)" != "remove_or_alias_in_E11_candidate" ]
}

@test "an over-budget merge path blocks promotion with its OWN outcome, not defer" {
  # defer means the data is missing; this means the data is there and the
  # project has not decided. Collapsing them would hide a project-level
  # decision inside a per-control one.
  run bash "$TOOL" --metrics "$TEST_TMPDIR/m.json" --dual-run "$TEST_TMPDIR/d.json" \
    --preflight "$TEST_TMPDIR/pf.json" --imp201 "$TEST_TMPDIR/i.json" --out "$OUT"
  [ "$(_decision c0)" = "cannot_promote_runtime_budget" ]
}

@test "a dirty bookkeeping preflight defers everything" {
  printf '{"verdict":"dirty"}' > "$TEST_TMPDIR/pf2.json"
  run _run_all "$TEST_TMPDIR/m.json" "$TEST_TMPDIR/d.json" "$TEST_TMPDIR/pf2.json"
  [ "$(_decision c0)" = "defer" ]
}

@test "an UNPROVEN preflight defers too — could-not-look is not clean" {
  printf '{"verdict":"unproven"}' > "$TEST_TMPDIR/pf3.json"
  run _run_all "$TEST_TMPDIR/m.json" "$TEST_TMPDIR/d.json" "$TEST_TMPDIR/pf3.json"
  [ "$(_decision c0)" = "defer" ]
}

@test "a missing gate artifact is not a satisfied gate" {
  run bash "$TOOL" --metrics "$TEST_TMPDIR/m.json" --dual-run "$TEST_TMPDIR/d.json" --out "$OUT"
  [ "$(jq -r '.gates.preflight' "$OUT")" = "unknown" ]
  [ "$(_decision c0)" = "defer" ]
}

@test "C3 is held while unverifiable outnumbers its verdicts" {
  cat > "$TEST_TMPDIR/m3.json" <<'M'
{"c3_verdict_mix":{"pass":1,"fail":1,"unverifiable":9},"speed":{"dispatch_count":0},
 "controls":[{"control":"c3","caught_classes":["x"],"false_done":0,"false_positives":0,
 "cost_seconds":1,"unique_detection_vs_legacy":1,"evidence_refs":["e"]}]}
M
  run _run_all "$TEST_TMPDIR/m3.json"
  [ "$(_decision c3)" = "keep_observe" ]
  [[ "$(jq -r '.controls[] | select(.control=="c3") | .reason' "$OUT" | head -1)" == *"shrugs"* ]]
}

@test "a control that caught nothing unique is a removal CANDIDATE, decided in E11" {
  jq '.controls[0].unique_detection_vs_legacy = 0 | .controls[0].caught_classes = []' \
    "$TEST_TMPDIR/m.json" > "$TEST_TMPDIR/m4.json"
  run _run_all "$TEST_TMPDIR/m4.json"
  [ "$(_decision c0)" = "remove_or_alias_in_E11_candidate" ]
  [[ "$(jq -r '.controls[] | select(.control=="c0") | .reason' "$OUT")" == *"E11"* ]]
}

@test "every row carries evidence and a reason; every decision is one of the six" {
  run _run_all
  run jq -e 'all(.controls[];
      ((.reason // "") | length) > 0
      and (.decision | IN("promote_to_blocking","keep_observe","keep_dual_run","defer",
                          "remove_or_alias_in_E11_candidate","cannot_promote_runtime_budget")))' "$OUT"
  [ "$status" -eq 0 ]
}

@test "no inventory row appears twice" {
  # Keyed by inventory id, not by control: c4 legitimately has three rows.
  run _run_all
  run jq -e '(.controls | map(.inventory_id) | unique | length) == (.controls | length)' "$OUT"
  [ "$status" -eq 0 ]
}

@test "every row carries its inventory id — the promotion step keys on it" {
  # Before this, rows were per control and the promotion step had to guess which
  # of a control's inventory rows an approval meant; it refused every
  # multi-row control forever because nothing produced the field it needed.
  run _run_all
  run jq -e 'all(.controls[]; ((.inventory_id // "") | length) > 0)' "$OUT"
  [ "$status" -eq 0 ]
}

@test "a row the inventory calls not-promotable is held, with the inventory's own reason" {
  run _run_all
  [ "$(_decision_id cp3_freshness)" = "keep_observe" ]
  [[ "$(jq -r '.controls[] | select(.inventory_id=="cp3_freshness") | .reason' "$OUT")" == *"policy file"* ]]
}

@test "c4's three rows are decided separately, not as one control" {
  # The break two reviews found: one c4 approval could not distinguish the
  # release decision from the content verdict from the held freshness check.
  run _run_all
  [ "$(jq -r '[.controls[] | select(.control=="c4")] | length' "$OUT")" -eq 3 ]
  [ "$(_decision_id c4_evidence_pack_freshness)" = "keep_observe" ]
}

@test "the human twin is rendered from the same data, never re-derived" {
  run _run_all
  [ -f "${OUT%.json}.md" ]
  grep -q "$(_decision c0)" "${OUT%.json}.md"
}

@test "a metrics file with no controls is refused" {
  printf '{"something":"else"}' > "$TEST_TMPDIR/bad.json"
  run bash "$TOOL" --metrics "$TEST_TMPDIR/bad.json" --dual-run "$TEST_TMPDIR/d.json" --out "$OUT"
  [ "$status" -eq 2 ]
  [ ! -f "$OUT" ]
}
