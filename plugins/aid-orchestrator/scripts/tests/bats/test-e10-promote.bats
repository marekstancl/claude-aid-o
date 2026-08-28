#!/usr/bin/env bats
# aid-tier: t1
# test-e10-promote.bats — per-control promotion, and everything that refuses it.
# Provenance: P062 Step 11 (D8, D5, D6).
#
# The claim this suite has to make provable is "only the approved controls were
# promoted". Before Step 11 it could not even be STATED: each policy file had
# one global switch, so promoting any control promoted all of its siblings.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TOOL="$AID_PLUGIN_PATH/scripts/aid-e10-promote.sh"
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-control-enforcement.sh"
  INV="$AID_PLUGIN_PATH/defaults/policies/control-inventory.yaml"
  export TOOL LIB INV
  POL="$TEST_TMPDIR/policies"; mkdir -p "$POL"; export POL
  cp "$AID_PLUGIN_PATH"/defaults/policies/*.yaml "$POL/"
  printf '{"verdict":"clean"}'  > "$TEST_TMPDIR/pf.json"
  printf '{"decision":"fixed"}' > "$TEST_TMPDIR/i.json"
  _table '{"control":"c1","decision":"promote_to_blocking","reason":"r","evidence_refs":["e"]}'
}

teardown() { teardown_test_evidence_dir; }

_table() { printf '{"artifact_type":"e10_decision_table","controls":[%s]}' "$1" > "$TEST_TMPDIR/dt.json"; }
_run() { bash "$TOOL" --decision-table "$TEST_TMPDIR/dt.json" --preflight "$TEST_TMPDIR/pf.json" \
           --imp201 "$TEST_TMPDIR/i.json" --inventory "$INV" --policy-dir "$POL" "$@"; }

@test "a dirty preflight refuses everything, and nothing is written" {
  printf '{"verdict":"dirty"}' > "$TEST_TMPDIR/pf.json"
  run _run --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"Nothing was promoted"* ]]
  run yq -r '.controls // "none"' "$POL/delivery-gate.yaml"
  [ "$output" = "none" ]
}

@test "an UNPROVEN preflight refuses too, and says why it is not a clean result" {
  printf '{"verdict":"unproven"}' > "$TEST_TMPDIR/pf.json"
  run _run --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not RUN"* ]]
}

@test "a missing preflight is not a satisfied gate" {
  run bash "$TOOL" --decision-table "$TEST_TMPDIR/dt.json" --inventory "$INV" --policy-dir "$POL" --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing gate is not a satisfied gate"* ]]
}

@test "the default is a DRY RUN — the last step of the plan is not the easiest to trigger" {
  run _run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry run"* ]]
  run yq -r '.controls // "none"' "$POL/delivery-gate.yaml"
  [ "$output" = "none" ]
}

@test "--apply promotes ONLY the approved control, leaving its sibling in observe" {
  # The whole point of Step 11. c1_delivery_gate and c2_semantic_review live in
  # different files, but review-profiles.yaml holds TWO c2 controls — promoting
  # one must not promote the other.
  _table '{"control":"c1","decision":"promote_to_blocking","reason":"r","evidence_refs":["e"]}'
  run _run --apply
  [ "$status" -eq 0 ]
  [ "$(yq -r '.controls.c1_delivery_gate.enforcement' "$POL/delivery-gate.yaml")" = "blocking" ]
  [ "$(yq -r '.controls.c2_semantic_review.enforcement // "unset"' "$POL/review-profiles.yaml")" = "unset" ]
  # And the file-wide default is untouched — a promotion is per control.
  [ "$(yq -r '.enforcement' "$POL/delivery-gate.yaml")" = "observe" ]
}

@test "the resolver returns the per-control value over the file default" {
  yq -i '.controls.c1_delivery_gate.enforcement = "blocking"' "$POL/delivery-gate.yaml"
  run bash -c 'source "$1"; aid_control_enforcement "$2" c1_delivery_gate' _ "$LIB" "$POL/delivery-gate.yaml"
  [ "$output" = "blocking" ]
  run bash -c 'source "$1"; aid_control_enforcement "$2" c2_semantic_review' _ "$LIB" "$POL/delivery-gate.yaml"
  [ "$output" = "observe" ]
}

@test "a malformed override is not an override — it neither promotes nor demotes" {
  # The file-wide default stands, because a typo must not silently promote OR
  # silently demote. That the FILE default can itself be `blocking` is the
  # PRE-EXISTING behaviour of this switch, not something per-control promotion
  # introduced: a project that sets it deliberately keeps getting it, and
  # changing that would quietly demote controls elsewhere. What Step 11 owes is
  # that the PROMOTION MECHANISM never sets it — see the next case.
  yq -i '.enforcement = "blocking"' "$POL/delivery-gate.yaml"
  yq -i '.controls.c1_delivery_gate.enforcement = "blokcing"' "$POL/delivery-gate.yaml"
  run bash -c 'source "$1"; aid_control_enforcement "$2" c1_delivery_gate' _ "$LIB" "$POL/delivery-gate.yaml"
  [ "$output" = "blocking" ]
}

@test "promotion NEVER writes a file-wide default — only the per-control key" {
  # Otherwise one approval would promote every control in that file through the
  # back door, which is the thing this step exists to make impossible.
  _table '{"control":"c1","decision":"promote_to_blocking","reason":"r","evidence_refs":["e"]}'
  before="$(yq -r '.enforcement' "$POL/delivery-gate.yaml")"
  run _run --apply
  [ "$status" -eq 0 ]
  [ "$(yq -r '.enforcement' "$POL/delivery-gate.yaml")" = "$before" ]
  [ "$(yq -r '.controls.c1_delivery_gate.enforcement' "$POL/delivery-gate.yaml")" = "blocking" ]
}

@test "a hand-authored decision table is refused — the apparatus is not a formality" {
  printf '{"controls":[{"control":"c1","decision":"promote_to_blocking"}]}' > "$TEST_TMPDIR/dt.json"
  run _run --apply
  [ "$status" -eq 2 ]
  [[ "$output" == *"not an e10_decision_table"* ]]
}

@test "an ambiguous control that maps to several promotable rows is refused" {
  # Approving `c4` must not flip both the release decision and the content
  # verdict. One approval, one control.
  _table '{"control":"c4","decision":"promote_to_blocking","reason":"r","evidence_refs":["e"]}'
  run _run --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"names none of them"* ]]
}

@test "naming the inventory row promotes exactly that row" {
  _table '{"control":"c4","decision":"promote_to_blocking","reason":"r","evidence_refs":["e"],"inventory_ids":["c4_content_verdict"]}'
  run _run --apply
  [ "$status" -eq 0 ]
  [ "$(yq -r '.controls.c4_content_verdict.enforcement' "$POL/release-decision-policy.yaml")" = "blocking" ]
  [ "$(yq -r '.controls.c4_release_decision.enforcement // "unset"' "$POL/release-decision-policy.yaml")" = "unset" ]
}

@test "every cannot-tell path resolves to observe, never to blocking" {
  run bash -c 'source "$1"; aid_control_enforcement /does/not/exist c1_delivery_gate' _ "$LIB"
  [ "$output" = "observe" ]
  printf 'not: [valid: yaml' > "$POL/broken.yaml"
  run bash -c 'source "$1"; aid_control_enforcement "$2" c1_delivery_gate' _ "$LIB" "$POL/broken.yaml"
  [ "$output" = "observe" ]
}

@test "a control the inventory calls not-promotable is refused with its reason" {
  _table '{"control":"c4","decision":"promote_to_blocking","reason":"r","evidence_refs":["e"],"inventory_ids":["c4_evidence_pack_freshness"]}'
  run _run --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"IMP-201"* ]]
}

@test "CP3 freshness is refused because it has no policy file at all" {
  # It lives in an FSM route, not a policy file — the cost that was named when
  # the per-control design was chosen, and it is enforced rather than forgotten.
  run yq -r '.controls[] | select(.id == "cp3_freshness") | .promotable' "$INV"
  [ "$output" = "false" ]
  run yq -r '.controls[] | select(.id == "cp3_freshness") | .policy_file' "$INV"
  [ "$output" = "null" ]
}

@test "a decision that is not promote_to_blocking is skipped, not quietly applied" {
  _table '{"control":"c1","decision":"keep_observe","reason":"r","evidence_refs":["e"]}'
  run _run --apply
  [ "$status" -eq 0 ]
  [ "$(yq -r '.controls // "none"' "$POL/delivery-gate.yaml")" = "none" ]
}

@test "a control with no inventory row is refused, never guessed at" {
  _table '{"control":"c9","decision":"promote_to_blocking","reason":"r","evidence_refs":["e"]}'
  run _run --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"no row in the control inventory"* ]]
}

@test "every inventory row names a concrete reader" {
  # A control whose reader is unnamed cannot be promoted independently of its
  # siblings, and the inventory exists to make that checkable.
  # Counted, not asserted with a yq predicate this yq build does not parse —
  # `yq -e 'all(...)'` fails with a syntax error here, which would have made
  # this case pass or fail for a reason unrelated to the data.
  run bash -c 'yq -r "[.controls[] | select((.reader // \"\") == \"\")] | length" "$1"' _ "$INV"
  [ "$output" = "0" ]
  run bash -c 'yq -r ".controls | length" "$1"' _ "$INV"
  [ "$output" -ge 8 ]
}

@test "every not-promotable row carries a reason" {
  run bash -c 'yq -r "[.controls[] | select(.promotable == false) | select((.not_promotable_reason // \"\") | length < 20)] | length" "$1"' _ "$INV"
  [ "$output" = "0" ]
  # And there really ARE not-promotable rows, so the count above is not zero
  # because the filter matched nothing.
  run bash -c 'yq -r "[.controls[] | select(.promotable == false)] | length" "$1"' _ "$INV"
  [ "$output" -ge 2 ]
}

@test "all six readers in the shipped code go through the shared resolver" {
  # Five in aid-fsm.sh plus the C0 contract gate in aid-auto-pipeline.sh. A
  # private copy is how two of them end up disagreeing in the blocking
  # direction.
  n="$(grep -c 'aid_control_enforcement' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh")"
  [ "$n" -ge 6 ]
  run grep -q 'aid_control_enforcement' "$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh"
  [ "$status" -eq 0 ]
}
