#!/usr/bin/env bats
# test-aid-scheduler-overlay-approve.bats — P069 Step 5.
#
# A reviewed, hash-confirmed approval force-tracks
# test-scheduler-parallel-overlay.yaml (verified via `git ls-files
# --error-unmatch`, same pattern as test-catalog-force-tracked.bats); a
# stale-fingerprint promotion is rejected at approval time, naming the
# specific run_unit_id.

load test-helpers.bash

setup() {
  export TZ=UTC
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  APPROVE="$AID_PLUGIN_PATH/scripts/aid-scheduler-overlay-approve.sh"
  setup_test_evidence_dir
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"

  cat > "$TEST_PROJECT_ROOT/.gitignore" <<'EOF'
.aid-o/
**/.aid-o/
EOF
  git add .gitignore
  git commit -q -m "add gitignore"

  jq -n '{
    schema_version: "1.0.0", generated_at: "2026-08-02T00:00:00Z", status: "approved",
    run_units: [
      {run_unit_id:"bats:a", runner:"bats", source_paths:["a.bats"], production_surfaces:["a.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv",argv:["bats","a.bats"]}, runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
       parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"

  PROPOSED="$TEST_TMPDIR/overlay.proposed.json"
  jq -n '{schema_version:"1.0.0", status:"proposed", overlay:[
    {run_unit_id:"bats:a", promoted_status:"safe", catalog_fingerprint_at_promotion:"sha256:aaaaaaaaaaaa", promoted_at:"2026-08-02T00:00:00Z", evidence_run_id:"iso-1"}
  ]}' > "$PROPOSED"
}

teardown() {
  teardown_test_evidence_dir
}

_display_hash() {
  bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" | grep -oE 'sha256:[a-f0-9]+' | tail -1
}

@test "display-only invocation (no --confirm-overlay) writes nothing" {
  run bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml" ]
}

@test "a matching --confirm-overlay hash publishes and force-tracks the overlay" {
  local hash; hash="$(_display_hash)"
  run bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" --confirm-overlay "$hash"
  [ "$status" -eq 0 ]

  local approved="$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml"
  [ -f "$approved" ]
  git -C "$TEST_PROJECT_ROOT" ls-files --error-unmatch .aid-o/config/test-scheduler-parallel-overlay.yaml

  run yq '.overlay[0].run_unit_id' "$approved"
  [ "$output" = "bats:a" ]
  run yq '.status' "$approved"
  [ "$output" = "approved" ]

  # The blanket ignore rule still applies to a sibling untracked file.
  touch "$TEST_PROJECT_ROOT/.aid-o/config/other-untracked-file.yaml"
  git -C "$TEST_PROJECT_ROOT" check-ignore .aid-o/config/other-untracked-file.yaml
}

@test "a mismatched/wrong --confirm-overlay hash is refused, re-displaying the diff, writes nothing" {
  run bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" --confirm-overlay "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reviewed_diff_hash"* ]]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml" ]
}

@test "a stale-fingerprint promotion is rejected at approval time, naming the specific run_unit_id" {
  jq '.overlay[0].catalog_fingerprint_at_promotion = "sha256:0123456789ab"' "$PROPOSED" > "$PROPOSED.tmp" && mv "$PROPOSED.tmp" "$PROPOSED"
  run bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bats:a"* ]]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml" ]

  # Even with a hash a PM might guess/compute, the stale check runs BEFORE
  # any hash comparison — still refused.
  run bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" --confirm-overlay "sha256:anything"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bats:a"* ]]
}

@test "a proposed document with two entries for the same run_unit_id is rejected (Codex regression)" {
  jq '.overlay += [{run_unit_id:"bats:a", promoted_status:"constrained", catalog_fingerprint_at_promotion:"sha256:aaaaaaaaaaaa", promoted_at:"2026-08-02T00:00:01Z", evidence_run_id:"iso-2"}]' \
    "$PROPOSED" > "$PROPOSED.tmp" && mv "$PROPOSED.tmp" "$PROPOSED"
  run bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bats:a"* ]]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml" ]
}

@test "changing promoted_at after obtaining a review hash invalidates that hash (Codex regression)" {
  local hash; hash="$(_display_hash)"
  jq '.overlay[0].promoted_at = "2099-01-01T00:00:00Z"' "$PROPOSED" > "$PROPOSED.tmp" && mv "$PROPOSED.tmp" "$PROPOSED"
  run bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" --confirm-overlay "$hash"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reviewed_diff_hash"* ]]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml" ]
}

@test "a second approval round upserts a new promotion without disturbing an existing one for a different unit" {
  local hash; hash="$(_display_hash)"
  bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" --confirm-overlay "$hash" >/dev/null

  jq -n '{schema_version:"1.0.0", status:"proposed", overlay:[
    {run_unit_id:"bats:c", promoted_status:"constrained", catalog_fingerprint_at_promotion:"sha256:cccccccccccc", promoted_at:"2026-08-02T00:00:00Z", evidence_run_id:"iso-2"}
  ]}' > "$TEST_TMPDIR/overlay2.proposed.json"
  # bats:c isn't in the catalog fixture — extend it so the fingerprint check passes.
  yq -o=json '.' "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" | jq \
    '.run_units += [{run_unit_id:"bats:c", runner:"bats", source_paths:["c.bats"], production_surfaces:["c.bats"], test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium", command:{type:"argv",argv:["bats","c.bats"]}, runtime:{fingerprint:"sha256:cccccccccccc"}, parallel:{status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false}, isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"}, recommendation:"keep", test_cases:[]}]' \
    | yq -P '.' > "$TEST_TMPDIR/catalog2.yaml"
  mv "$TEST_TMPDIR/catalog2.yaml" "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"

  PROPOSED="$TEST_TMPDIR/overlay2.proposed.json"
  local hash2; hash2="$(_display_hash)"
  run bash "$APPROVE" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" --confirm-overlay "$hash2"
  [ "$status" -eq 0 ]

  local approved="$TEST_PROJECT_ROOT/.aid-o/config/test-scheduler-parallel-overlay.yaml"
  run yq '.overlay | length' "$approved"
  [ "$output" = "2" ]
  run yq '.overlay[] | select(.run_unit_id == "bats:a") | .promoted_status' "$approved"
  [ "$output" = "safe" ]
  run yq '.overlay[] | select(.run_unit_id == "bats:c") | .promoted_status' "$approved"
  [ "$output" = "constrained" ]
}
