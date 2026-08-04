#!/usr/bin/env bash
# aid-test-catalog-selector-mappings.sh — the ONE derivation of
# `source_pattern_mappings[]` from a fresh selector snapshot.
#
# WHY THIS FILE EXISTS
#   The scanner wrote `source_pattern_mappings: []` unconditionally, while the
#   approver re-derived the real mapping set from a fresh selector snapshot and
#   refused to approve anything that did not reproduce it. So in this repository
#   a freshly-proposed catalog could never be approved by the sanctioned path —
#   producer and consumer disagreed about the same field, which is the same
#   defect class as the inventory's `entries[]`/`run_units[]` split, found in
#   the same audit.
#
#   The fix is NOT to teach the scanner to build the same thing a second time.
#   The derivation is not trivial — a snapshot, a classification correction, and
#   auto-seeded gap rows — and a second implementation of it would drift from
#   the first the way every other duplicated authority in this plan did. There
#   is one function, and both sides call it.
#
# DOGFOOD SCOPE
#   aid-test-catalog-selector-snapshot.sh is hardcoded to this plugin's own repo
#   layout, so this derivation only applies where that layout exists. Everywhere
#   else `aid_test_catalog_selector_applies` is false and the correct mapping
#   set is the empty one — not a failure, because no equivalent
#   consumer-project selector exists yet.

# aid_test_catalog_selector_applies <project_root>
#   True when the dogfood selector this derivation reads actually exists.
aid_test_catalog_selector_applies() {
  [[ -f "${1%/}/plugins/aid-orchestrator/scripts/aid-select-tests.sh" ]]
}

# aid_test_catalog_expected_mappings <project_root> <snapshot_script>
#   Prints the canonical `source_pattern_mappings[]` array for this project.
#   Returns non-zero if the snapshot could not be produced — never an empty
#   array, because "the selector could not be read" and "the selector maps
#   nothing" must not look alike.
aid_test_catalog_expected_mappings() {
  local project_root="$1" snapshot_script="$2"
  local snapshot_json
  snapshot_json="$(bash "$snapshot_script" --project-root "$project_root" 2>/dev/null)" || return 1
  [[ -n "$snapshot_json" ]] || return 1

  # A row derived from a REAL, targeted case arm (non-empty target_run_unit_ids)
  # is always production, whatever the snapshot's own probe-path heuristic says
  # about it — that heuristic only recognises scripts/ and defaults/ as
  # production roots and was never taught about lib/ui-fidelity/**. Corrected
  # here, at the consumption layer; the snapshot script's own parsing is never
  # touched.
  local expected existing gaps
  expected="$(jq -c '
    [.source_pattern_mappings[]
     | if ((.target_run_unit_ids | length) > 0) then .classification = "production" else . end]
  ' <<<"$snapshot_json")" || return 1

  # Selector gaps become exact-match `unknown_production` rows — Step 10's own
  # real classification — rather than being left absent, which Step 10 would
  # read as a mapping_gap instead. A path that already has an explicit row is
  # skipped: it would be sorted first and make the seeded row unreachable,
  # silently defeating the never-left-absent guarantee.
  existing="$(jq -c '[.[].path_pattern]' <<<"$expected")" || return 1
  gaps="$(jq -c --argjson existing "$existing" '
    [.findings[] | select(.category == "selector-gap")
     | (.evidence_refs[0] | sub("^selector-snapshot:"; "")) as $p
     | select(($existing | index($p)) == null)
     | { match_type: "exact",
         path_pattern: $p,
         target_run_unit_ids: [],
         classification: "unknown_production",
         precedence: 1000,
         status: "proposed" }]
  ' <<<"$snapshot_json")" || return 1

  jq -c --argjson gaps "$gaps" '. + $gaps | sort_by([.precedence, .path_pattern])' <<<"$expected"
}

# aid_test_catalog_canon_mappings
#   Canonical comparison form, read from stdin. Sorted by
#   (precedence, path_pattern) BEFORE this is applied — precedence ordering
#   changes real matching behaviour across different values, while path_pattern
#   only breaks ties within one value. The literal precedence number and each
#   row's own status are excluded: neither is what this comparison is about, and
#   including precedence made two semantically identical sets compare unequal
#   merely because tied rows were listed in a different order.
aid_test_catalog_canon_mappings() {
  jq -cS '[.[] | {match_type, path_pattern, target_run_unit_ids: (.target_run_unit_ids | sort), classification}]'
}
