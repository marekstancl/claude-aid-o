#!/usr/bin/env bats
# test-aid-test-audit-consolidate.bats — P066 Step 14.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CONSOLIDATE="$AID_PLUGIN_PATH/scripts/aid-test-audit-consolidate.sh"
  AGENTS_DIR="$TEST_TMPDIR/agents"
  OUTPUT_DIR="$TEST_TMPDIR/out"
  mkdir -p "$AGENTS_DIR" "$OUTPUT_DIR"
}

teardown() {
  teardown_test_evidence_dir
}

_write_artifact() {
  local path="$1" focus="$2" wave="$3" shard_id="$4" findings_json="$5"
  jq -n --arg focus "$focus" --argjson wave "$wave" --arg shard_id "$shard_id" --argjson findings "$findings_json" \
    '{schema_version:"1.0.0", focus:$focus, wave:$wave, shard_id: (if $shard_id == "" then null else $shard_id end), findings:$findings, produced_at:"2026-07-30T00:00:00Z", producer_agent_dispatch_id:"d1"}' \
    > "$path"
}

@test "exact duplicates collapse; conflicts remain visible with unresolved_conflict:true" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"flake","severity":"low","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"},
    {"run_unit_id":"bats:b","category":"cost","severity":"high","evidence_refs":["r2"],"recommendation":"fix","confidence":"medium","falsification_check":"x"}
  ]'
  _write_artifact "$AGENTS_DIR/3-adversarial_review.json" adversarial_review 3 "" '[
    {"run_unit_id":"bats:a","category":"flake","severity":"low","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"},
    {"run_unit_id":"bats:b","category":"cost","severity":"high","evidence_refs":["r3-different"],"recommendation":"quarantine","confidence":"medium","falsification_check":"y"}
  ]'
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local findings_file="$OUTPUT_DIR/consolidated-findings.json"
  # bats:a's exact duplicate collapses to 1; bats:b's 2 conflicting
  # findings (different evidence_refs) both survive => 3 total.
  [ "$(jq '.findings | length' "$findings_file")" -eq 3 ]
  jq -e '.findings[] | select(.run_unit_id == "bats:b") | .unresolved_conflict == true' "$findings_file" >/dev/null
  jq -e '[.findings[] | select(.run_unit_id == "bats:b")] | length == 2' "$findings_file" >/dev/null
  jq -e '.findings[] | select(.run_unit_id == "bats:a") | (.unresolved_conflict // false) == false' "$findings_file" >/dev/null
}

@test "output ordering is deterministic regardless of wave-artifact arrival order" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:z","category":"cost","severity":"medium","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  _write_artifact "$AGENTS_DIR/3-adversarial_review.json" adversarial_review 3 "" '[
    {"run_unit_id":"bats:a","category":"cost","severity":"medium","evidence_refs":["r2"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local first
  first="$(jq -c '[.findings[].finding_id]' "$OUTPUT_DIR/consolidated-findings.json")"

  local output_dir2="$TEST_TMPDIR/out2"
  local agents_dir2="$TEST_TMPDIR/agents2"
  mkdir -p "$output_dir2" "$agents_dir2"
  # Same content, reversed file/arrival order.
  _write_artifact "$agents_dir2/3-adversarial_review.json" adversarial_review 3 "" '[
    {"run_unit_id":"bats:a","category":"cost","severity":"medium","evidence_refs":["r2"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  _write_artifact "$agents_dir2/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:z","category":"cost","severity":"medium","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$agents_dir2" --output-dir "$output_dir2"
  [ "$status" -eq 0 ]
  local second
  second="$(jq -c '[.findings[].finding_id]' "$output_dir2/consolidated-findings.json")"
  [ "$first" = "$second" ]
}

@test "an unsupported removal/quarantine recommendation (no falsification_check) is rejected before the report" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"quarantine","confidence":"medium","falsification_check":""}
  ]'
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falsification_check"* ]]
  [ ! -f "$OUTPUT_DIR/consolidated-findings.json" ]
}

@test "a findings set with at least one actionable (Medium+) item produces a schema-valid brief + matching .md, generated_from_hash matches the emitted findings file" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"x"}
  ]'
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$OUTPUT_DIR/implementation-plan-brief.json" ]
  [ -f "$OUTPUT_DIR/implementation-plan-brief.md" ]
  jq -e '.verdict == "remediation recommended" and (.items | length) == 1' "$OUTPUT_DIR/implementation-plan-brief.json" >/dev/null
  local expected_hash actual_hash
  expected_hash="sha256:$(sha256sum "$OUTPUT_DIR/consolidated-findings.json" | cut -d' ' -f1)"
  actual_hash="$(jq -r '.generated_from_hash' "$OUTPUT_DIR/implementation-plan-brief.json")"
  [ "$expected_hash" = "$actual_hash" ]
}

@test "an all-clean (all-low-severity) findings set produces NO brief file at all" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"flake","severity":"low","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OUTPUT_DIR/implementation-plan-brief.json" ]
  [ ! -f "$OUTPUT_DIR/implementation-plan-brief.md" ]
}

@test "a wave artifact missing a required schema field halts consolidation, naming the artifact" {
  cat > "$AGENTS_DIR/1-shard_portfolio-shard-0.json" <<'JSON'
{"schema_version":"1.0.0","focus":"shard_portfolio","wave":1,"shard_id":"shard-0","findings":[],"produced_at":"2026-07-30T00:00:00Z"}
JSON
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1-shard_portfolio-shard-0.json"* ]]
}

@test "two findings sharing run_unit_id+category+evidence_refs but differing in recommendation/severity are BOTH preserved as a conflict, never silently discarded" {
  # Regression (Codex review): an earlier version collapsed anything
  # sharing run_unit_id+category+evidence_refs via `map(.[0])`, discarding
  # the second finding even when it was NOT an exact duplicate (different
  # recommendation/severity/falsification_check) — an order-dependent data
  # loss of contradictory remediation advice.
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:x","category":"cost","severity":"high","evidence_refs":["same-ref"],"recommendation":"fix","confidence":"medium","falsification_check":"x"}
  ]'
  _write_artifact "$AGENTS_DIR/3-adversarial_review.json" adversarial_review 3 "" '[
    {"run_unit_id":"bats:x","category":"cost","severity":"medium","evidence_refs":["same-ref"],"recommendation":"keep","confidence":"low","falsification_check":"y"}
  ]'
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local findings_file="$OUTPUT_DIR/consolidated-findings.json"
  [ "$(jq '.findings | length' "$findings_file")" -eq 2 ]
  jq -e '[.findings[] | .unresolved_conflict] | all' "$findings_file" >/dev/null
}

@test "truly identical findings (every field equal) still collapse to exactly one" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:y","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"x"}
  ]'
  _write_artifact "$AGENTS_DIR/3-adversarial_review.json" adversarial_review 3 "" '[
    {"run_unit_id":"bats:y","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"x"}
  ]'
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq '.findings | length' "$OUTPUT_DIR/consolidated-findings.json")" -eq 1 ]
}

@test "an empty --wave-artifacts-dir (zero artifacts) is rejected, never reported as a clean audit" {
  # Regression (Codex review): a missing/interrupted dispatch (empty dir)
  # previously produced a schema-valid, empty findings report indistinguishable
  # from a genuinely clean audit.
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no wave artifacts found"* ]]
  [ ! -f "$OUTPUT_DIR/consolidated-findings.json" ]
}

@test "an invalid --audit-id is rejected before any file is written" {
  run "$CONSOLIDATE" --audit-id '../escape' --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [ ! -f "$OUTPUT_DIR/consolidated-findings.json" ]
}
