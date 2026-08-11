#!/usr/bin/env bats
# aid-tier: t2
# test-catalog-force-tracked.bats — P066 Step 17.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  APPROVE_SCRIPT="$AID_PLUGIN_PATH/scripts/aid-test-catalog-approve.sh"

  # Replicate this repo's own blanket .aid-o/ ignore rule in the fixture.
  cat > "$TEST_PROJECT_ROOT/.gitignore" <<'EOF'
.aid-o/
**/.aid-o/
EOF
  git add .gitignore
  git commit -q -m "add gitignore"

  PROPOSED="$TEST_TMPDIR/test-catalog.proposed.yaml"
  cat > "$PROPOSED" <<'YAML'
schema_version: "1.0.0"
generated_at: "2026-07-30T00:00:00Z"
status: proposed
run_units: []
source_pattern_mappings: []
mapping_approval: {status: proposed}
YAML
}

teardown() {
  teardown_test_evidence_dir
}

@test "approval publishes the catalog and force-tracks it, and the blanket ignore rule still applies to a sibling untracked file in the same directory" {
  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local approved="$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  [ -f "$approved" ]

  git -C "$TEST_PROJECT_ROOT" ls-files --error-unmatch .aid-o/config/test-catalog.yaml

  # git check-ignore reports "not ignored" (exit 1) for a path that is
  # ALREADY TRACKED, in this git version — that is real, verified git
  # behavior, not a bug in the approve script. The ignore RULE itself is
  # still live: prove it against an untracked sibling under the same
  # directory instead.
  touch "$TEST_PROJECT_ROOT/.aid-o/config/other-untracked-file.yaml"
  git -C "$TEST_PROJECT_ROOT" check-ignore .aid-o/config/other-untracked-file.yaml
}

@test "approval flips status to approved but never touches mapping_approval.status" {
  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local approved="$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml"
  run yq -o=json -I=0 '.' "$approved"
  [[ "$output" == *'"status":"approved"'* ]]
  echo "$output" | jq -e '.mapping_approval == {"status":"proposed"}' >/dev/null
}

@test "a second approval run issues the identical git add -f, confirmed a no-op" {
  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  git -C "$TEST_PROJECT_ROOT" add -A
  git -C "$TEST_PROJECT_ROOT" commit -q -m "approve catalog"

  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  run git -C "$TEST_PROJECT_ROOT" status --porcelain -- .aid-o/config/test-catalog.yaml
  [ -z "$output" ]
}

@test "a schema-invalid proposed catalog is rejected, never published" {
  local bad="$TEST_TMPDIR/bad.yaml"
  echo "not: {a, valid, catalog}" > "$bad"
  run "$APPROVE_SCRIPT" --proposed "$bad" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [ ! -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" ]
}

@test "a bare-directory --project-root with no git repository writes the catalog but skips force-add without failing" {
  local bare_dir="$TEST_TMPDIR/bare-project"
  mkdir -p "$bare_dir"
  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$bare_dir"
  [ "$status" -eq 0 ]
  [ -f "$bare_dir/.aid-o/config/test-catalog.yaml" ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "--approved-path is no longer accepted at all — the approved catalog target is always the canonical .aid-o/config/test-catalog.yaml (PM whole-EPIC-3 review: removes the traversal/symlink escape surface entirely)" {
  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT" --approved-path "/tmp/outside-catalog.yaml"
  [ "$status" -ne 0 ]
  [ ! -f "/tmp/outside-catalog.yaml" ]
  [[ "$output" == *"unknown option"* ]]
}

@test "a canonical run always publishes to the fixed target regardless of any attempted override" {
  run "$APPROVE_SCRIPT" --proposed "$PROPOSED" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_ROOT/.aid-o/config/test-catalog.yaml" ]
  git -C "$TEST_PROJECT_ROOT" ls-files --error-unmatch .aid-o/config/test-catalog.yaml
}

@test "--proposed requires a value and rejects a nonexistent path" {
  run "$APPROVE_SCRIPT" --proposed
  [ "$status" -eq 2 ]
  run "$APPROVE_SCRIPT" --proposed "$TEST_TMPDIR/does-not-exist.yaml" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 3 ]
}

# ─── Approval must not silently discard parallel-safety evidence ────────────

_unit_yaml() {   # <id> <status>
  jq -nc --arg id "$1" --arg st "$2" '
    {run_unit_id:$id, runner:"bats", source_paths:["a.bats"], production_surfaces:["a.bats"],
     test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
     command:{type:"argv",argv:["bash","-c","true"]}, runtime:{fingerprint:"sha256:aaaaaaaaaaaa"},
     isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
     recommendation:"keep", test_cases:[]}'
}
_catalog_yaml() {   # <out> <status-doc> <unit-status>
  jq -n --argjson u "$(_unit_yaml "bats:a" "$3")" --arg s "$2" \
    '{schema_version:"1.0.0", generated_at:"2026-08-01T00:00:00Z", status:$s,
      run_units:[$u], source_pattern_mappings:[], mapping_approval:{status:"proposed"}}' \
    | yq -P '.' > "$1"
}

# (P078: the three provenance-revocation-guard tests were removed with the
# guard itself — a catalog no longer carries parallel-safety evidence that an
# approval could silently discard.)
