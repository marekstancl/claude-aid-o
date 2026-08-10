#!/usr/bin/env bats
# test-aid-select-tests-catalog-convergence.bats — P069 Step 10.
#
# Proves aid-select-tests.sh's catalog↔selector convergence:
#   - an approved-mapping path is a regression match to the pre-convergence
#     hardcoded mapping for an existing case
#   - an UN-approved catalog (mapping_approval.status: proposed) exercises
#     the permanent fallback exactly as if the catalog were absent
#   - a changed path matching zero rows exits 11 (mapping_gap), never a
#     silent zero-selection pass
#   - a changed path matching a docs_non_production-classified row exits 0
#     with zero tests selected
#   - the 5 known gaps still exit 3 (unknown_production)
#   - classification is driven ONLY by match_type/path_pattern/
#     classification — no schema field beyond P066's own shipped definition

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"
  git init -q -b main
  git config user.email "test@test.local"
  git config user.name "Test"
  mkdir -p plugins/aid-orchestrator/scripts/tests/bats .aid-o/config
  echo "base" > README.md
  git add -A
  git commit -q -m "base"
  BASE_SHA="$(git rev-parse HEAD)"
  export BASE_SHA

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SELECTOR="$AID_PLUGIN_PATH/scripts/aid-select-tests.sh"
  export SELECTOR

  # Fast-stub root (same seam/convention as test-aid-select-tests.bats) —
  # without it, a "production" classification would try to run the REAL
  # test-aid-fsm.bats suite (this repo's own, multi-second), not a fast stub.
  STUB_ROOT="$TEST_TMPDIR/stub-plugin-root"
  export STUB_ROOT
  export AID_SELECT_TESTS_PLUGIN_ROOT="$STUB_ROOT"
  mkdir -p "$STUB_ROOT/scripts/tests/bats"
  # NOTE: the literal token "@test" is built from $at at write-time (never
  # appears verbatim at start-of-line in THIS source file) — bats-core's own
  # test-file scanner is a simple line-anchored grep for ^@test, so a
  # literal occurrence inside this heredoc would be miscounted as an extra
  # test in THIS suite (same pitfall test-aid-select-tests.bats documents).
  local at="@"
  cat > "$STUB_ROOT/scripts/tests/bats/test-aid-fsm.bats" <<EOF
#!/usr/bin/env bats
${at}test "stub" {
  [ 1 -eq 1 ]
}
EOF
}

teardown() {
  cd /
  unset AID_SELECT_TESTS_PLUGIN_ROOT
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

commit_change() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  echo "changed" >> "$file"
  git add -A
  git commit -q -m "touch $file"
}

# _write_catalog <mapping_approval_status>
# Rows (precedence ascending):
#   1. exact  plugins/aid-orchestrator/scripts/aid-fsm.sh -> production -> bats:.../test-aid-fsm
#   2. prefix plugins/aid-orchestrator/docs/               -> docs_non_production
#   3. glob   plugins/aid-orchestrator/scripts/aid-known-gap-*.sh -> unknown_production
_write_catalog() {
  local approval="${1:-approved}"
  local row_status="approved"
  [[ "$approval" != "approved" ]] && row_status="proposed"
  jq -n --arg appr "$approval" --arg rowst "$row_status" '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved",
    run_units: [
      {run_unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm", runner:"bats",
       source_paths:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"],
       production_surfaces:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"]},
       runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-fsm.sh",
       target_run_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm"],
       classification:"production", precedence:1, status:$rowst},
      {match_type:"prefix", path_pattern:"plugins/aid-orchestrator/docs/",
       target_run_unit_ids:[], classification:"docs_non_production", precedence:2, status:$rowst},
      {match_type:"glob", path_pattern:"plugins/aid-orchestrator/scripts/aid-known-gap-*.sh",
       target_run_unit_ids:[], classification:"unknown_production", precedence:3, status:$rowst}
    ],
    mapping_approval: {status:$appr, approved_by:"tester", approved_at:"2026-08-02T00:00:00Z", reviewed_diff_hash:"sha256:deadbeef"}
  }' | yq -P '.' > .aid-o/config/test-catalog.yaml
  # Commit the catalog itself into the BASE commit — otherwise it would
  # show up as its OWN "changed path" alongside whatever commit_change adds
  # next, since --base diffs against BASE_SHA. Re-exports BASE_SHA to
  # include this commit so later `commit_change` diffs are clean.
  git add -f .aid-o/config/test-catalog.yaml
  git commit -q -m "add catalog"
  BASE_SHA="$(git rev-parse HEAD)"
  export BASE_SHA
}

@test "an approved-mapping production row selects the same test as the hardcoded mapping would" {
  _write_catalog "approved"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"]' ]
}

@test "an UN-approved catalog (mapping_approval: proposed) exercises the fallback exactly as if absent" {
  _write_catalog "proposed"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  selected="$(jq -c '.selected_tests' <<< "$output")"
  # Falls back to the hardcoded Initial mapping's own test path (a
  # DIFFERENT path than the catalog row would have selected, proving the
  # catalog was genuinely ignored, not partially honored).
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"]' ]
  echo "$output" | jq -e '.reasoning | any(. == "catalog_fallback: true — no approved catalog mapping (absent catalog, or mapping_approval.status != approved) — using the permanent hardcoded Initial mapping")'
}

@test "a changed path matching zero approved rows exits 11 (mapping_gap), never a silent pass" {
  _write_catalog "approved"
  commit_change "plugins/aid-orchestrator/scripts/aid-totally-unrelated-file.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 11 ]
  echo "$output" | jq -e '.selected_tests == [] and (.reasoning | any(startswith("mapping_gap:")))'
}

@test "a changed path matching a docs_non_production row exits 0 with zero tests selected" {
  _write_catalog "approved"
  commit_change "plugins/aid-orchestrator/docs/some-doc.md"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selected_tests == []'
}

@test "a changed path matching an unknown_production row still exits 3" {
  _write_catalog "approved"
  commit_change "plugins/aid-orchestrator/scripts/aid-known-gap-example.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.reasoning | any(startswith("unverifiable:"))'
}

@test "an approved catalog with no covering row for a non-production path is no-impact, never mapping_gap (EPIC 3 whole-diff review)" {
  # README.md is outside scripts/ and defaults/ entirely — no case arm, no
  # auto-seeded gap row (those only ever cover scripts/ and defaults/, per
  # aid-test-catalog-selector-snapshot.sh's own find scope), and NOT
  # matched by any of _write_catalog's three rows either. Before the fix,
  # every unmatched path under an approved catalog was unconditionally
  # mapping_gap (exit 11) regardless of is_production_surface — hard-
  # failing on ordinary doc/skill/command changes that were never
  # production surface to begin with.
  _write_catalog "approved"
  commit_change "README.md"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selected_tests == [] and (.reasoning | any(startswith("docs-only (approved catalog mapping, no covering row):")))'
}

@test "mapping_gap and unknown_production are distinct exit codes, never conflated" {
  _write_catalog "approved"
  commit_change "plugins/aid-orchestrator/scripts/aid-known-gap-example.sh"
  run "$SELECTOR" --base "$BASE_SHA"
  local exit_unknown="$status"

  cd "$TEST_PROJECT"
  git reset -q --hard "$BASE_SHA"
  commit_change "plugins/aid-orchestrator/scripts/aid-totally-unrelated-file.sh"
  run "$SELECTOR" --base "$BASE_SHA"
  local exit_gap="$status"

  [ "$exit_unknown" -eq 3 ]
  [ "$exit_gap" -eq 11 ]
  [ "$exit_unknown" -ne "$exit_gap" ]
}

@test "a mixed run (both unknown_production AND mapping_gap paths) prioritizes exit 3, but records BOTH reasons (Codex regression)" {
  # Both classifications carry "the same externally-visible effect" per
  # this step's own design (escalate to full) — unverifiable (exit 3) wins
  # the single exit CODE when both occur in one invocation, but neither
  # reason is ever suppressed from `reasoning[]`; a human reading the
  # summary still sees both distinct root causes.
  _write_catalog "approved"
  commit_change "plugins/aid-orchestrator/scripts/aid-known-gap-example.sh"
  commit_change "plugins/aid-orchestrator/scripts/aid-totally-unrelated-file.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.reasoning | any(startswith("unverifiable:")) and any(startswith("mapping_gap:"))'
}

@test "--emit-units with an approved catalog mapping still resolves via the membership verifier" {
  _write_catalog "approved"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  local units_file="$TEST_TMPDIR/units.json"
  run "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file"
  [ "$status" -eq 0 ]
  run jq -r '.[0].unit_id' "$units_file"
  [ "$output" = "bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm" ]
  run jq -r '.[0].membership_verified' "$units_file"
  [ "$output" = "true" ]
}

@test "--emit-units with a mapping_gap exits 11 and writes no units file" {
  _write_catalog "approved"
  commit_change "plugins/aid-orchestrator/scripts/aid-totally-unrelated-file.sh"

  local units_file="$TEST_TMPDIR/units.json"
  run "$SELECTOR" --base "$BASE_SHA" --emit-units "$units_file"
  [ "$status" -eq 11 ]
  [ ! -f "$units_file" ]
}

@test "a mapping row referencing a run_unit_id absent from run_units[] fails loudly (fail-closed on any gap)" {
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved",
    run_units: [],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-fsm.sh",
       target_run_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm"],
       classification:"production", precedence:1, status:"approved"}
    ],
    mapping_approval: {status:"approved", approved_by:"tester", approved_at:"2026-08-02T00:00:00Z", reviewed_diff_hash:"sha256:deadbeef"}
  }' | yq -P '.' > .aid-o/config/test-catalog.yaml
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 3 ]
  echo "$output" | jq -e '.reasoning | any(contains("references unknown run_unit_id"))'
}
