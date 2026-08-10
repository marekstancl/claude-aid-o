#!/usr/bin/env bats
# test-selector-mappings-real-seed.bats — P069 Step 11.
#
# Proves aid-test-catalog-approve.sh's new pre-approval zero-gap
# re-verification (dogfood-only, gated on
# plugins/aid-orchestrator/scripts/aid-select-tests.sh existing under
# --project-root):
#   - approving a correctly-seeded proposed catalog succeeds, and its
#     source_pattern_mappings[] reproduce every current selector selection
#     result (a production row + an unknown_production row per real gap)
#   - a newly-introduced gap (a file the proposal predates) blocks
#     approval, naming it explicitly
#   - a row whose target_run_unit_ids is non-empty but mis-classified as
#     docs_non_production is corrected/detected as drift (production is
#     required), proving the docs_non_production-with-real-targets fix
#   - a project with NO dogfood aid-select-tests.sh present is entirely
#     unaffected by this re-verification (existing P066 behavior preserved)

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  APPROVE_SCRIPT="$AID_PLUGIN_PATH/scripts/aid-test-catalog-approve.sh"

  cat > "$TEST_PROJECT_ROOT/.gitignore" <<'EOF'
.aid-o/
**/.aid-o/
EOF
  git add .gitignore
  git commit -q -m "add gitignore"

  # A minimal but structurally faithful dogfood aid-select-tests.sh — the
  # selector-snapshot script extracts map_path_to_tests()/
  # is_production_surface() VERBATIM via sed, so these must be real,
  # well-formed bash function bodies, matching the real script's shape.
  mkdir -p "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/scripts/tests/bats"
  cat > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/scripts/aid-select-tests.sh" <<'SCRIPT'
#!/usr/bin/env bash
PLUGIN_PREFIX="plugins/aid-orchestrator"
map_path_to_tests() {
  local p="$1"
  case "$p" in
    "${PLUGIN_PREFIX}/scripts/aid-foo.sh")
      printf 'bats\t%s/scripts/tests/bats/test-aid-foo.bats\n' "$PLUGIN_PREFIX"
      ;;
    *)
      return 0
      ;;
  esac
}
is_production_surface() {
  local p="$1"
  case "$p" in
    "${PLUGIN_PREFIX}/scripts/"*|"${PLUGIN_PREFIX}/defaults/"*) return 0 ;;
    *) return 1 ;;
  esac
}
SCRIPT

  # A real gap: a production-surface .sh file with no mapping case arm.
  echo "gap" > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/scripts/aid-gap-example.sh"
  git add -A
  git commit -q -m "add dogfood fixture"

  SNAPSHOT="$AID_PLUGIN_PATH/scripts/aid-test-catalog-selector-snapshot.sh"
  # Sanity: confirm the fixture actually reproduces the expected shape
  # before any test relies on it.
  snapshot_out="$(bash "$SNAPSHOT" --project-root "$TEST_PROJECT_ROOT")"
  export snapshot_out
}

teardown() {
  teardown_test_evidence_dir
}

@test "a correctly-seeded proposed catalog (production row + unknown_production gap row) is approved" {
  PROPOSED="$TEST_TMPDIR/test-catalog.proposed.yaml"
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"proposed",
    run_units: [
      {run_unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo", runner:"bats",
       source_paths:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"],
       production_surfaces:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"]},
       runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-foo.sh",
       target_run_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo"],
       classification:"production", precedence:1, status:"proposed"},
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-gap-example.sh",
       target_run_unit_ids:[], classification:"unknown_production", precedence:1000, status:"proposed"},
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-select-tests.sh",
       target_run_unit_ids:[], classification:"unknown_production", precedence:1000, status:"proposed"}
    ],
    mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$PROPOSED"

  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" ]
  run yq '.status' "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  [ "$output" = "approved" ]
}

@test "a proposal missing a NEWLY-introduced gap row is blocked, naming the gap explicitly" {
  PROPOSED="$TEST_TMPDIR/test-catalog.proposed.yaml"
  # This proposal predates aid-gap-example.sh — only the production row.
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"proposed",
    run_units: [
      {run_unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo", runner:"bats",
       source_paths:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"],
       production_surfaces:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"]},
       runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-foo.sh",
       target_run_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo"],
       classification:"production", precedence:1, status:"proposed"}
    ],
    mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$PROPOSED"

  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" ]
  [[ "$output" == *"aid-gap-example.sh"* ]]
}

@test "a real, targeted row mis-classified as docs_non_production is rejected as drift" {
  PROPOSED="$TEST_TMPDIR/test-catalog.proposed.yaml"
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"proposed",
    run_units: [
      {run_unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo", runner:"bats",
       source_paths:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"],
       production_surfaces:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"]},
       runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-foo.sh",
       target_run_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo"],
       classification:"docs_non_production", precedence:1, status:"proposed"},
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-gap-example.sh",
       target_run_unit_ids:[], classification:"unknown_production", precedence:1000, status:"proposed"},
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-select-tests.sh",
       target_run_unit_ids:[], classification:"unknown_production", precedence:1000, status:"proposed"}
    ],
    mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$PROPOSED"

  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" ]
  [[ "$output" == *"drift"* ]]
}

@test "two tied-precedence gap rows listed in a different order still compare equal (Codex regression)" {
  # A second gap: a further production-surface .sh file with no case arm.
  echo "gap2" > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/scripts/aid-gap-second.sh"
  git -C "$TEST_PROJECT_ROOT" add -A
  git -C "$TEST_PROJECT_ROOT" commit -q -m "add second gap"

  PROPOSED="$TEST_TMPDIR/test-catalog.proposed.yaml"
  # Both gap rows share precedence 1000 (the auto-seed convention) — listed
  # here in the OPPOSITE order from how the snapshot would naturally emit
  # them (alphabetically: aid-gap-example before aid-gap-second before
  # aid-select-tests) — must still be accepted as equivalent.
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"proposed",
    run_units: [
      {run_unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo", runner:"bats",
       source_paths:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"],
       production_surfaces:["plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo.bats"]},
       runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-select-tests.sh",
       target_run_unit_ids:[], classification:"unknown_production", precedence:1000, status:"proposed"},
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-gap-second.sh",
       target_run_unit_ids:[], classification:"unknown_production", precedence:1000, status:"proposed"},
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-gap-example.sh",
       target_run_unit_ids:[], classification:"unknown_production", precedence:1000, status:"proposed"},
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-foo.sh",
       target_run_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-foo"],
       classification:"production", precedence:1, status:"proposed"}
    ],
    mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$PROPOSED"

  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "the gap-row seeding jq excludes a path that already has an explicit mapping row (Codex regression)" {
  # Unit-level: the real selector never emits a selector-gap finding for a
  # path already covered by a case arm (verified), so this shadowed-row
  # state cannot be reproduced through the full CLI pipeline — this
  # exercises the exact exclusion expression aid-test-catalog-approve.sh
  # uses, in isolation, proving it drops a finding whose path duplicates an
  # existing row instead of emitting an unreachable second row for it.
  snapshot_json='{
    "source_pattern_mappings": [
      {"path_pattern":"plugins/aid-orchestrator/scripts/aid-foo.sh","target_run_unit_ids":[],"classification":"docs_non_production"}
    ],
    "findings": [
      {"category":"selector-gap","evidence_refs":["selector-snapshot:plugins/aid-orchestrator/scripts/aid-foo.sh"]},
      {"category":"selector-gap","evidence_refs":["selector-snapshot:plugins/aid-orchestrator/scripts/aid-gap-example.sh"]}
    ]
  }'
  expected_mappings_json="$(jq -c '
    [.source_pattern_mappings[] | if ((.target_run_unit_ids | length) > 0) then .classification = "production" else . end]
  ' <<<"$snapshot_json")"
  existing_patterns_json="$(jq -c '[.[].path_pattern]' <<<"$expected_mappings_json")"
  gap_rows_json="$(jq -c --argjson existing "$existing_patterns_json" '
    [.findings[] | select(.category == "selector-gap") |
      (.evidence_refs[0] | sub("^selector-snapshot:"; "")) as $p
      | select(($existing | index($p)) == null)
      | { match_type: "exact", path_pattern: $p, target_run_unit_ids: [],
          classification: "unknown_production", precedence: 1000, status: "proposed" }
    ]
  ' <<<"$snapshot_json")"

  run jq -r 'length' <<<"$gap_rows_json"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run jq -r '.[0].path_pattern' <<<"$gap_rows_json"
  [ "$output" = "plugins/aid-orchestrator/scripts/aid-gap-example.sh" ]
}

@test "a project with no dogfood aid-select-tests.sh is entirely unaffected by this re-verification" {
  # Simulate a genuine non-aid-orchestrator consumer project.
  rm -rf "$TEST_PROJECT_ROOT/plugins"
  git -C "$TEST_PROJECT_ROOT" add -A
  git -C "$TEST_PROJECT_ROOT" commit -q -m "remove dogfood fixture (simulate consumer project)"

  PROPOSED="$TEST_TMPDIR/test-catalog.proposed.yaml"
  jq -n '{schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"proposed", run_units:[], source_pattern_mappings:[], mapping_approval:{status:"proposed"}}' \
    | yq -P '.' > "$PROPOSED"

  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" ]
}
