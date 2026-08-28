#!/usr/bin/env bats
# aid-tier: t1
# test-c4-content-verdict.bats — C4 asks what the artifact SAYS, not only whether it is there.
# Provenance: P062 Step 8 (D4).
#
# THE GAP THIS CLOSES
#   C4 verified that a required artifact was present and parseable and never
#   asked what it reported. An audit report full of blocking findings satisfied
#   "present and parseable" and the release read as ready.
#
# THE TWO AXES, AND WHY THEY ARE TWO
#   `input_state` is the OBSERVED condition; `verdict` is the DECISION. `waived`
#   is a decision, not a state — a waived row still has an observed condition —
#   and folding them into one field is what made the five states
#   unrepresentable. Keeping them apart is also what preserves the waiver
#   mechanism, which flips `blocked` -> `waived` and would have stopped matching
#   had the verdict enum grown a sixth member.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  POL="$AID_PLUGIN_PATH/scripts/aid-release-policy.sh"
  VAL="$AID_PLUGIN_PATH/scripts/aid-protocol-validate.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/release-decision.schema.json"
  export POL VAL SCHEMA
}

teardown() { teardown_test_evidence_dir; }

# Drive check_required_present directly: the aggregator's own end-to-end path
# needs a whole evidence pack, and the behaviour under test is this function's.
_run_check() {
  local id="$1" file="$2" policy="${3:-observe}"
  CONTENT_VERDICT_POLICY="$policy" bash -c '
    set -uo pipefail
    INPUTS_JSON="[]"; BLOCKERS_JSON="[]"; MODE=epic
    # shellcheck disable=SC1090
    source "$1" >/dev/null 2>&1 || true
    check_required_present "$2" "$2" "$3"
    printf "%s\t%s\n" "$INPUTS_JSON" "$BLOCKERS_JSON"
  ' _ "$POL" "$id" "$file"
}

@test "a present, parseable, PASSING artifact is present_ok" {
  printf '{"overall":"pass"}' > "$TEST_TMPDIR/gates_report.json"
  out="$(_run_check gates_report "$TEST_TMPDIR/gates_report.json")"
  inputs="${out%%$'\t'*}"
  [ "$(jq -r '.[0].input_state' <<<"$inputs")" = "present_ok" ]
  [ "$(jq -r '.[0].verdict' <<<"$inputs")" = "pass" ]
}

@test "present and parseable but FAILING is present_but_failing, not pass" {
  # The whole gap in one case: this file used to satisfy "present and parseable".
  printf '{"overall":"fail"}' > "$TEST_TMPDIR/gates_report.json"
  out="$(_run_check gates_report "$TEST_TMPDIR/gates_report.json")"
  inputs="${out%%$'\t'*}"
  [ "$(jq -r '.[0].input_state' <<<"$inputs")" = "present_but_failing" ]
  [ "$(jq -r '.[0].verdict' <<<"$inputs")" != "pass" ]
}

@test "under observe a failing content adds NO blocker — nothing in flight changes" {
  printf '{"overall":"fail"}' > "$TEST_TMPDIR/gates_report.json"
  out="$(_run_check gates_report "$TEST_TMPDIR/gates_report.json" observe)"
  blockers="${out##*$'\t'}"
  [ "$(jq -r 'length' <<<"$blockers")" -eq 0 ]
}

@test "under blocking the same artifact blocks — that is the promotion" {
  printf '{"overall":"fail"}' > "$TEST_TMPDIR/gates_report.json"
  out="$(_run_check gates_report "$TEST_TMPDIR/gates_report.json" blocking)"
  inputs="${out%%$'\t'*}"; blockers="${out##*$'\t'}"
  [ "$(jq -r '.[0].verdict' <<<"$inputs")" = "blocked" ]
  [ "$(jq -r 'length' <<<"$blockers")" -eq 1 ]
}

@test "an audit report with blocking findings is failing content" {
  printf '{"status":"pass","blocking_findings":true}' > "$TEST_TMPDIR/audit-report.json"
  out="$(_run_check audit_report "$TEST_TMPDIR/audit-report.json")"
  [ "$(jq -r '.[0].input_state' <<<"${out%%$'\t'*}")" = "present_but_failing" ]
}

@test "an id with no known content contract gets no opinion, not a guess" {
  printf '{"anything":"at all"}' > "$TEST_TMPDIR/unknown-artifact.json"
  out="$(_run_check some_unknown_id "$TEST_TMPDIR/unknown-artifact.json")"
  [ "$(jq -r '.[0].input_state' <<<"${out%%$'\t'*}")" = "present_ok" ]
}

@test "present-but-unparseable is invalid, and absent is missing — different facts" {
  printf 'not json {' > "$TEST_TMPDIR/gates_report.json"
  out="$(_run_check gates_report "$TEST_TMPDIR/gates_report.json")"
  [ "$(jq -r '.[0].input_state' <<<"${out%%$'\t'*}")" = "invalid" ]

  out="$(_run_check gates_report "$TEST_TMPDIR/nothing-here.json")"
  [ "$(jq -r '.[0].input_state' <<<"${out%%$'\t'*}")" = "missing" ]
}

@test "the verdict enum is byte-identical to before — the waiver keys on it" {
  # Extending it with present_but_failing would have stopped `blocked` -> `waived`
  # matching, which is why input_state is a separate field at all.
  run jq -r '.. | objects | select(has("verdict")) | .verdict.enum | join(",")' "$SCHEMA"
  [[ "$output" == *"pass,fail,blocked,unverifiable,waived,advisory"* ]]
}

@test "the authoritative validator accepts a well-formed release_decision" {
  # The baseline. Without it the three refusals below are satisfiable by a
  # validator that refuses everything.
  run bash "$VAL" "$AID_PLUGIN_PATH/scripts/tests/fixtures/release-decision/valid.json"
  [ "$status" -eq 0 ]
}

@test "the authoritative validator refuses an out-of-enum input_state" {
  run bash "$VAL" "$AID_PLUGIN_PATH/scripts/tests/fixtures/release-decision/invalid-nonsense-state.json"
  [ "$status" -eq 19 ]
}

@test "the validator accepts a null input_state — unclassified is legal, invented is not" {
  run bash "$VAL" "$AID_PLUGIN_PATH/scripts/tests/fixtures/release-decision/valid-null-state.json"
  [ "$status" -eq 0 ]
}

@test "the validator also refuses a row missing head_match — a hole it never checked" {
  # inputs[] has been closed by the schema all along, but this validator looked
  # only at release_ready and the D11 fields, so a malformed row reached every
  # consumer no matter what the schema said.
  run bash "$VAL" "$AID_PLUGIN_PATH/scripts/tests/fixtures/release-decision/invalid-missing-head-match.json"
  [ "$status" -eq 19 ]
}

@test "the validator refuses a verdict outside its enum" {
  run bash "$VAL" "$AID_PLUGIN_PATH/scripts/tests/fixtures/release-decision/invalid-bad-verdict.json"
  [ "$status" -eq 19 ]
}

@test "the input_state coverage gap is PINNED, so it cannot widen unnoticed" {
  # 7 of 28 add_input call sites classify their state; the rest pass null,
  # meaning "not classified yet". That is deliberate — guessing a state from a
  # call site's reason string would put a confident wrong value on rows nobody
  # has examined — but it must not be read as five-state classification
  # everywhere (cross-model review, 2026-08-15). This case makes the number
  # visible: adding a call site without classifying it FAILS here, so the gap
  # can only shrink or be consciously re-pinned.
  local pol="$AID_PLUGIN_PATH/scripts/aid-release-policy.sh"
  total="$(grep -c '^[[:space:]]*add_input ' "$pol")"
  classified="$(grep -cE '^[[:space:]]*add_input .*"(missing|stale|invalid|present_but_failing|present_ok)"' "$pol")"
  [ "$total" -eq 28 ]
  [ "$classified" -eq 7 ]
}

@test "the validator refuses a release decision with NO inputs at all" {
  # `.inputs // []` let this pass: all() over an empty array is true, so the row
  # check was satisfied by having no rows. A verdict with nothing behind it is
  # malformed.
  run bash "$VAL" "$AID_PLUGIN_PATH/scripts/tests/fixtures/release-decision/invalid-no-inputs.json"
  [ "$status" -eq 19 ]
}

@test "AGGREGATE: an unpromoted control cannot pull release_ready down" {
  # The rule per-control promotion stands or falls on. It holds by
  # construction — an unpromoted control adds no blocker — so this asserts the
  # construction rather than a filter: under observe the row is visibly failing
  # AND the blocker list is empty, which is what leaves the aggregate alone.
  printf '{"overall":"fail"}' > "$TEST_TMPDIR/gates_report.json"
  out="$(_run_check gates_report "$TEST_TMPDIR/gates_report.json" observe)"
  inputs="${out%%$'\t'*}"; blockers="${out##*$'\t'}"
  [ "$(jq -r '.[0].input_state' <<<"$inputs")" = "present_but_failing" ]
  [ "$(jq -r 'length' <<<"$blockers")" -eq 0 ]
}

@test "AGGREGATE: a promoted control DOES contribute its blocker" {
  # The complement. Without it the case above is satisfied by a control that
  # never blocks at all, which is not a promotion mechanism.
  printf '{"overall":"fail"}' > "$TEST_TMPDIR/gates_report.json"
  out="$(_run_check gates_report "$TEST_TMPDIR/gates_report.json" blocking)"
  [ "$(jq -r 'length' <<<"${out##*$'\t'}")" -eq 1 ]
}

@test "the shipped policy defaults content_verdict_policy to observe" {
  run yq -r '.content_verdict_policy' "$AID_PLUGIN_PATH/defaults/policies/release-decision-policy.yaml"
  [ "$output" = "observe" ]
}

@test "the FSM passes the policy through — the aggregator reads no policy itself" {
  run grep -q 'CONTENT_VERDICT_POLICY="\$_cvp"' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  [ "$status" -eq 0 ]
}
