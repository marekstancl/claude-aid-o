#!/usr/bin/env bats
# test-catalog-confirm-mapping.bats — P066 Step 17 (+ EPIC 3 whole-diff
# re-staging fix-loop).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CONFIRM_SCRIPT="$AID_PLUGIN_PATH/scripts/aid-test-catalog-confirm-mapping.sh"
  APPROVE_SCRIPT="$AID_PLUGIN_PATH/scripts/aid-test-catalog-approve.sh"

  cat > "$TEST_PROJECT_ROOT/.gitignore" <<'EOF'
.aid-o/
**/.aid-o/
EOF
  git add .gitignore
  git commit -q -m "add gitignore"

  CATALOG="$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  PROPOSED="$TEST_TMPDIR/test-catalog.proposed.yaml"
  cat > "$PROPOSED" <<'YAML'
schema_version: "1.0.0"
generated_at: "2026-07-30T00:00:00Z"
status: proposed
run_units: []
source_pattern_mappings:
  - match_type: exact
    path_pattern: "plugins/aid-orchestrator/scripts/aid-run-gates.sh"
    target_run_unit_ids: ["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates"]
    classification: production
    precedence: 1
    status: proposed
mapping_approval: {status: proposed}
YAML

  # Precondition this script documents: an already-approved (force-tracked)
  # catalog must exist first.
  "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" >/dev/null
}

teardown() {
  teardown_test_evidence_dir
}

_current_hash() {
  run "$CONFIRM_SCRIPT" --project-root "$TEST_PROJECT_ROOT"
  echo "$output" | grep -oE 'sha256:[0-9a-f]+' | tail -1
}

@test "no --confirm-mapping only displays the diff and hash, makes no changes" {
  run "$CONFIRM_SCRIPT" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reviewed_diff_hash: sha256:"* ]]
  run yq -o=json '.mapping_approval.status' "$CATALOG"
  [[ "$output" == *"proposed"* ]]
}

@test "confirming with the correct, currently-displayed hash sets mapping_approval.status: approved and flips every row" {
  local hash
  hash="$(_current_hash)"
  run "$CONFIRM_SCRIPT" --project-root "$TEST_PROJECT_ROOT" --confirm-mapping "$hash" --approved-by "pm"
  [ "$status" -eq 0 ]

  run yq -o=json '.' "$CATALOG"
  echo "$output" | jq -e '.mapping_approval.status == "approved"' >/dev/null
  echo "$output" | jq -e '.mapping_approval.approved_by == "pm"' >/dev/null
  echo "$output" | jq -e '[.source_pattern_mappings[] | select(.status != "approved")] | length == 0' >/dev/null
}

@test "confirming re-stages the catalog — a commit right after confirming captures mapping_approval:approved, not the stale approve.sh-staged blob (PM whole-EPIC-3 review, real gap)" {
  local hash
  hash="$(_current_hash)"
  run "$CONFIRM_SCRIPT" --project-root "$TEST_PROJECT_ROOT" --confirm-mapping "$hash"
  [ "$status" -eq 0 ]
  [[ "$output" == *"re-staged"* ]]

  # Index and working tree must agree immediately after confirming.
  git -C "$TEST_PROJECT_ROOT" diff --quiet -- .aid-o/config/test-catalog.yaml

  # A commit of ONLY what's staged must contain the confirmed mapping —
  # never the pre-confirmation (mapping:proposed) blob approve.sh staged.
  git -C "$TEST_PROJECT_ROOT" commit -q -m "confirm mapping"
  run bash -c "git -C '$TEST_PROJECT_ROOT' show HEAD:.aid-o/config/test-catalog.yaml | yq -o=json '.'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mapping_approval.status == "approved"' >/dev/null
  echo "$output" | jq -e '[.source_pattern_mappings[] | select(.status != "approved")] | length == 0' >/dev/null
}

@test "confirming without a git repository succeeds locally and says so plainly, never claiming 'tracked'" {
  local bare_dir="$TEST_TMPDIR/bare-project"
  mkdir -p "$bare_dir"
  local bare_proposed="$TEST_TMPDIR/bare-proposed.yaml"
  cp "$PROPOSED" "$bare_proposed"
  "$APPROVE_SCRIPT" --proposed "$bare_proposed" --project-root "$bare_dir" >/dev/null

  local hash
  run "$CONFIRM_SCRIPT" --project-root "$bare_dir"
  hash="$(echo "$output" | grep -oE 'sha256:[0-9a-f]+' | tail -1)"

  run "$CONFIRM_SCRIPT" --project-root "$bare_dir" --confirm-mapping "$hash"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a git repository"* ]]
  [[ "$output" != *"re-staged"* ]]
}

@test "confirming with a stale or wrong hash is rejected and re-prints the diff, never silently proceeds" {
  run "$CONFIRM_SCRIPT" --project-root "$TEST_PROJECT_ROOT" --confirm-mapping "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match"* ]]
  [[ "$output" == *"reviewed_diff_hash: sha256:"* ]]

  run yq -o=json '.mapping_approval.status' "$CATALOG"
  [[ "$output" == *"proposed"* ]]
}

@test "a mapping row added after confirmation reverts to proposed and blocks a bare re-use of the old hash" {
  local hash
  hash="$(_current_hash)"
  run "$CONFIRM_SCRIPT" --project-root "$TEST_PROJECT_ROOT" --confirm-mapping "$hash"
  [ "$status" -eq 0 ]

  # Add a new row directly (simulating a re-scan) — its status is proposed
  # by construction (schema forbids an approved row unless the document-root
  # gate is approved, but a NEW row starts proposed regardless).
  local updated
  updated="$(yq -o=json '.' "$CATALOG")"
  updated="$(jq -c '.source_pattern_mappings += [{match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-fsm.sh", target_run_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm"], classification:"production", precedence:2, status:"proposed"}]' <<<"$updated")"
  yq -P '.' <<<"$updated" > "$CATALOG"

  # The row set genuinely changed since the hash was computed — re-using the
  # OLD hash must be rejected regardless of the document's own approval state.
  run "$CONFIRM_SCRIPT" --project-root "$TEST_PROJECT_ROOT" --confirm-mapping "$hash"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match"* ]]
}

@test "a match_type or precedence change alone (no row added/removed) still invalidates a stale hash (Codex review: previously excluded from the hash)" {
  local hash
  hash="$(_current_hash)"

  local updated
  updated="$(yq -o=json '.' "$CATALOG")"
  updated="$(jq -c '.source_pattern_mappings[0].match_type = "prefix"' <<<"$updated")"
  yq -P '.' <<<"$updated" > "$CATALOG"

  run "$CONFIRM_SCRIPT" --project-root "$TEST_PROJECT_ROOT" --confirm-mapping "$hash"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match"* ]]
}

@test "--project-root is required, must exist, and a project with no approved catalog fails loudly" {
  run "$CONFIRM_SCRIPT"
  [ "$status" -eq 2 ]
  run "$CONFIRM_SCRIPT" --project-root "$TEST_TMPDIR/does-not-exist-dir"
  [ "$status" -eq 3 ]

  local no_catalog_dir="$TEST_TMPDIR/no-catalog-project"
  mkdir -p "$no_catalog_dir"
  run "$CONFIRM_SCRIPT" --project-root "$no_catalog_dir"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no approved catalog found"* ]]
}
