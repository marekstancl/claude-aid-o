#!/usr/bin/env bats
# test-protected-surface.bats — P073 Step 15: the protected path set stored at
# freeze.
#
# The protected set is the DELIVERY SURFACE the frozen review describes. Step
# 16's equivalence predicate refuses any commit touching it, so getting it
# wrong matters in both directions: too small and a delivery change rides
# through a frozen review; too large and nothing is ever equivalent.
#
# It is written in the SAME atomic mutate as the candidate pair, which is what
# makes it a property OF THIS FREEZE — a later plan.json edit cannot
# retroactively change what was protected.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  ( cd "$ROOT"
    git init -q
    git config user.email t@e.com
    git config user.name T
    git checkout -q -b main 2>/dev/null || git branch -m main
    printf 'seed\n' > README.md
    git add -A && git commit -qm seed ) >/dev/null 2>&1
  HEAD_SHA="$(cd "$ROOT" && git rev-parse HEAD)"
  export HEAD_SHA
}

teardown() {
  teardown_test_evidence_dir
}

# _pm <body> — run <body> with the manifest lib sourced, inside $ROOT.
_pm() {
  bash -c '
    set -uo pipefail
    SCRIPT_DIR="$1/scripts"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    . "$SCRIPT_DIR/lib/aid-ancillary.sh"
    cd "$2"
    eval "$3"
  ' _ "$AID_PLUGIN_PATH" "$ROOT" "$1"
}

_init_manifest() {
  _pm "plan_manifest_init P900 plan/P900 main '$HEAD_SHA' '$HEAD_SHA' plan_branch >/dev/null"
}

# _freeze <protected-file> <complete> — the freeze writer, called directly.
_freeze() {
  _pm "plan_manifest_freeze_candidate P900 '$HEAD_SHA' '$HEAD_SHA' R-P900-final-1 \
       '.aid-o/work/evidence/P900/R-P900-final-1' '2026-08-05T00:00:00Z' '$1' '$2' >/dev/null"
}

_protected() { _pm "plan_manifest_get P900 '.plan_boundary_manifest.protected_paths | join(\",\")'"; }

# ─── the set is stored, sorted and de-duplicated ──────────────────────────

@test "P073 Step 15: freeze stores the protected set, sorted and de-duplicated" {
  _init_manifest
  printf '%s\n' "scripts/b.sh" "scripts/a.sh" "scripts/a.sh" "docs/x.md" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  [ "$status" -eq 0 ]
  run _protected
  [ "$output" = "docs/x.md,scripts/a.sh,scripts/b.sh" ]
}

@test "P073 Step 15: the set lands in the SAME write as the candidate — never one without the other" {
  _init_manifest
  printf '%s\n' "scripts/a.sh" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  [ "$status" -eq 0 ]
  run _pm "plan_manifest_get P900 '.plan_boundary_manifest.candidate_sha'"
  [ "$output" = "$HEAD_SHA" ]
  run _pm "plan_manifest_get P900 '.plan_boundary_manifest.protected_paths_complete'"
  [ "$output" = "true" ]
}

@test "P073 Step 15: an EMPTY protected file still yields the lifecycle floor, and marks the set incomplete" {
  # A silently empty protected set would make every commit look ancillary.
  _init_manifest
  : > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  [ "$status" -eq 0 ]
  run _protected
  [[ "$output" == *".aid-lifecycle/manifests/P900.yaml"* ]]
  [[ "$output" == *".aid-lifecycle/receipts/P900.yaml"* ]]
  run _pm "plan_manifest_get P900 '.plan_boundary_manifest.protected_paths_complete'"
  [ "$output" = "false" ]
}

@test "P073 Step 15: paths with spaces and odd characters survive the round trip" {
  _init_manifest
  printf '%s\n' "docs/a file with spaces.md" "scripts/weird\$name.sh" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  [ "$status" -eq 0 ]
  run _pm "plan_manifest_get P900 '.plan_boundary_manifest.protected_paths[]' | tr '\n' '|'"
  [[ "$output" == *"a file with spaces.md"* ]]
  [[ "$output" == *'weird$name.sh'* ]]
}

# ─── invalidation clears the set WITH the pair ────────────────────────────

@test "P073 Step 15: invalidate clears candidate and protected set together" {
  _init_manifest
  printf '%s\n' "scripts/a.sh" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  [ "$status" -eq 0 ]
  run _pm "plan_manifest_clear_candidate P900 'the plan branch moved off the candidate' PLAN_FIX >/dev/null"
  [ "$status" -eq 0 ]
  # Read the raw manifest: plan_manifest_get renders a null field as empty, so
  # asserting on jq keeps "cleared" unambiguous.
  local mf="$ROOT/.aid-o/work/plan-state/P900/plan-boundary-manifest.json"
  run jq -r '.plan_boundary_manifest | [.candidate_sha, .protected_paths, .protected_paths_complete] | map(tostring) | join(",")' "$mf"
  [ "$output" = "null,null,null" ]
}

@test "P073 Step 15: a HALF-CLEARED manifest is rejected by validation" {
  # A protected set with no candidate would let Step 16's predicate reason
  # about a surface nobody froze.
  _init_manifest
  printf '%s\n' "scripts/a.sh" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  [ "$status" -eq 0 ]
  # Clear the whole freeze PAIR (an earlier invariant already rejects a lone
  # candidate_sha) and leave the protected set behind — the state only this
  # step's invariant catches.
  local mf="$ROOT/.aid-o/work/plan-state/P900/plan-boundary-manifest.json"
  jq '.plan_boundary_manifest.candidate_sha = null
      | .plan_boundary_manifest.candidate_frozen_at = null' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

  run _pm "plan_manifest_validate P900"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected_paths must be a non-empty array"* ]]
}

@test "P073 Step 15: a candidate with NO protected set is rejected too" {
  _init_manifest
  printf '%s\n' "scripts/a.sh" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  local mf="$ROOT/.aid-o/work/plan-state/P900/plan-boundary-manifest.json"
  jq '.plan_boundary_manifest.protected_paths = []' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _pm "plan_manifest_validate P900"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected_paths"* ]]
}

@test "P073 Step 15: a LEGACY manifest with neither field stays valid" {
  # A manifest frozen before this field existed must not become invalid;
  # Step 16 reports "equivalence unavailable" for it rather than guessing.
  _init_manifest
  printf '%s\n' "scripts/a.sh" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  local mf="$ROOT/.aid-o/work/plan-state/P900/plan-boundary-manifest.json"
  jq 'del(.plan_boundary_manifest.protected_paths) | del(.plan_boundary_manifest.protected_paths_complete)' \
    "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _pm "plan_manifest_validate P900"
  [ "$status" -eq 0 ]
}

# ─── the accepted_head invariant (used by Step 16) ────────────────────────

@test "P073 Step 15: accepted_head without its receipt binding is rejected" {
  _init_manifest
  printf '%s\n' "scripts/a.sh" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  local mf="$ROOT/.aid-o/work/plan-state/P900/plan-boundary-manifest.json"
  jq --arg h "$HEAD_SHA" '.plan_boundary_manifest.accepted_head = $h' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
  run _pm "plan_manifest_validate P900"
  [ "$status" -ne 0 ]
  [[ "$output" == *"accepted_head requires a frozen candidate and a receipt path+sha256"* ]]
}

@test "P073 Step 15: freeze resets accepted_head and its receipt binding" {
  # A re-freeze must not inherit a previous acceptance.
  _init_manifest
  printf '%s\n' "scripts/a.sh" > "$ROOT/prot.txt"
  run _freeze "$ROOT/prot.txt" true
  local mf="$ROOT/.aid-o/work/plan-state/P900/plan-boundary-manifest.json"
  run jq -r '.plan_boundary_manifest | [.accepted_head, .equivalence_receipt_path, .equivalence_receipt_sha256] | map(tostring) | join(",")' "$mf"
  [ "$output" = "null,null,null" ]
}

# ─── the six schema fields ────────────────────────────────────────────────

@test "P073 Step 15: all six new manifest fields are DECLARED in the schema, as optional" {
  local sch="$AID_PLUGIN_PATH/defaults/schemas/plan-boundary-manifest.schema.json"
  local f
  for f in source_plan_path protected_paths protected_paths_complete \
           accepted_head equivalence_receipt_path equivalence_receipt_sha256; do
    run jq -e ".properties.plan_boundary_manifest.properties.\"$f\"" "$sch"
    [ "$status" -eq 0 ]
  done
  # None of them is required — a legacy manifest must stay valid.
  run jq -r '.properties.plan_boundary_manifest.required // [] | join(",")' "$sch"
  [[ "$output" != *"protected_paths"* ]]
  [[ "$output" != *"accepted_head"* ]]
}

# ─── overlap warning at freeze ────────────────────────────────────────────

@test "P073 Step 15: an overlap between the ancillary policy and a protected path warns at freeze" {
  printf '%s\n' ".aid-o/work/evidence/P900/R-1/close-receipt.json" > "$ROOT/prot.txt"
  run _pm "aid_ancillary_overlap_warn '$ROOT/prot.txt' ."
  [ "$status" -eq 0 ]
  [[ "$output" == *"covers protected path"* ]]
  [[ "$output" == *"close-receipt.json"* ]]
}

@test "P073 Step 15: the freeze body computes the set from plan.json allowed_paths" {
  # The wiring must not be test-only: assert the freeze reads the same
  # machine-readable delivery contract the scope guard uses.
  run grep -c 'allowed_paths' "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  [ "$output" -ge 1 ]
  run grep -c 'protected set incomplete' "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  [ "$output" -ge 1 ]
}
