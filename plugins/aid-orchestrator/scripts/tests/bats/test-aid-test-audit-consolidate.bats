#!/usr/bin/env bats
# test-aid-test-audit-consolidate.bats — P066 Step 14 (+ EPIC 3 whole-diff
# completeness fix-loop).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CONSOLIDATE="$AID_PLUGIN_PATH/scripts/aid-test-audit-consolidate.sh"
  AGENTS_DIR="$TEST_TMPDIR/agents"
  OUTPUT_DIR="$TEST_TMPDIR/out"
  mkdir -p "$AGENTS_DIR" "$OUTPUT_DIR"
  MANIFEST_ENTRIES_FILE="$TEST_TMPDIR/manifest-entries.ndjson"
  MANIFEST_PATH="$TEST_TMPDIR/dispatch-manifest.json"
  : > "$MANIFEST_ENTRIES_FILE"
}

teardown() {
  teardown_test_evidence_dir
}

# _write_artifact <path> <focus> <wave> <shard_id> <findings_json> [dispatch_id]
#   Writes the artifact file AND records its matching dispatch-manifest
#   entry (same wave/focus/shard_id/producer_agent_dispatch_id/path) into
#   MANIFEST_ENTRIES_FILE — call _write_manifest afterwards to assemble the
#   real manifest CONSOLIDATE requires.
_write_artifact() {
  local path="$1" focus="$2" wave="$3" shard_id="$4" findings_json="$5" dispatch_id="${6:-d1}"
  jq -n --arg focus "$focus" --argjson wave "$wave" --arg shard_id "$shard_id" --argjson findings "$findings_json" --arg did "$dispatch_id" \
    '{schema_version:"1.0.0", focus:$focus, wave:$wave, shard_id: (if $shard_id == "" then null else $shard_id end), findings:$findings, produced_at:"2026-07-30T00:00:00Z", producer_agent_dispatch_id:$did}' \
    > "$path"
  jq -nc --arg focus "$focus" --argjson wave "$wave" --arg shard_id "$shard_id" --arg artifact_path "$path" --arg did "$dispatch_id" \
    '{wave:$wave, focus:$focus, shard_id:(if $shard_id=="" then null else $shard_id end), artifact_path:$artifact_path, producer_agent_dispatch_id:$did}' \
    >> "$MANIFEST_ENTRIES_FILE"
}

# _declare_manifest_entry_only — records an EXPECTED entry with no
# corresponding artifact file ever written (simulates a missing/never-
# produced wave artifact).
_declare_manifest_entry_only() {
  local artifact_path="$1" focus="$2" wave="$3" shard_id="$4" dispatch_id="${5:-d1}"
  jq -nc --arg focus "$focus" --argjson wave "$wave" --arg shard_id "$shard_id" --arg artifact_path "$artifact_path" --arg did "$dispatch_id" \
    '{wave:$wave, focus:$focus, shard_id:(if $shard_id=="" then null else $shard_id end), artifact_path:$artifact_path, producer_agent_dispatch_id:$did}' \
    >> "$MANIFEST_ENTRIES_FILE"
}

_write_manifest() {
  local audit_id="${1:-a1}"
  jq -n --arg audit_id "$audit_id" --slurpfile entries "$MANIFEST_ENTRIES_FILE" \
    '{audit_id:$audit_id, max_concurrent_agents:4, entries:$entries}' > "$MANIFEST_PATH"
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
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
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
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local first
  first="$(jq -c '[.findings[].finding_id]' "$OUTPUT_DIR/consolidated-findings.json")"

  local output_dir2="$TEST_TMPDIR/out2"
  local agents_dir2="$TEST_TMPDIR/agents2"
  local manifest_entries2="$TEST_TMPDIR/manifest-entries2.ndjson"
  local manifest_path2="$TEST_TMPDIR/dispatch-manifest2.json"
  mkdir -p "$output_dir2" "$agents_dir2"
  MANIFEST_ENTRIES_FILE="$manifest_entries2"
  : > "$MANIFEST_ENTRIES_FILE"
  # Same content, reversed file/arrival order.
  _write_artifact "$agents_dir2/3-adversarial_review.json" adversarial_review 3 "" '[
    {"run_unit_id":"bats:a","category":"cost","severity":"medium","evidence_refs":["r2"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  _write_artifact "$agents_dir2/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:z","category":"cost","severity":"medium","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  jq -n --arg audit_id a1 --slurpfile entries "$MANIFEST_ENTRIES_FILE" \
    '{audit_id:$audit_id, max_concurrent_agents:4, entries:$entries}' > "$manifest_path2"
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$agents_dir2" --dispatch-manifest "$manifest_path2" --output-dir "$output_dir2"
  [ "$status" -eq 0 ]
  local second
  second="$(jq -c '[.findings[].finding_id]' "$output_dir2/consolidated-findings.json")"
  [ "$first" = "$second" ]
}

@test "an unsupported removal/quarantine recommendation (no falsification_check) is rejected before the report" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"quarantine","confidence":"medium","falsification_check":""}
  ]'
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"falsification_check"* ]]
  [ ! -f "$OUTPUT_DIR/consolidated-findings.json" ]
}

@test "a findings set with at least one actionable (Medium+) item produces a schema-valid brief + matching .md, generated_from_hash matches the emitted findings file" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"x"}
  ]'
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
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
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OUTPUT_DIR/implementation-plan-brief.json" ]
  [ ! -f "$OUTPUT_DIR/implementation-plan-brief.md" ]
}

@test "a Medium+ finding recommending 'measure' (not fix/split/merge/remove/quarantine) produces NO brief — matching the chat renderer's own 'needs measurement' verdict (Codex whole-EPIC review)" {
  # Regression: a severity-only filter previously still emitted a
  # remediation-recommended brief for this exact findings set, even though
  # aid-test-audit-chat-summary.sh's _tacs_classify_verdict classifies it
  # as "needs measurement" — a contradictory brief on disk the chat verdict
  # never authorized.
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"cost","severity":"medium","evidence_refs":["r1"],"recommendation":"measure","confidence":"low","falsification_check":"n/a"}
  ]'
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OUTPUT_DIR/implementation-plan-brief.json" ]
  [ ! -f "$OUTPUT_DIR/implementation-plan-brief.md" ]
}

@test "a Medium+ finding recommending 'keep' produces NO brief — matching the chat renderer's own 'clean' verdict" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"flake","severity":"high","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$OUTPUT_DIR/implementation-plan-brief.json" ]
  [ ! -f "$OUTPUT_DIR/implementation-plan-brief.md" ]
}

@test "a mix of an actionable Medium+ finding and a non-actionable Medium+ 'measure' finding still produces a brief containing ONLY the actionable item" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"x"},
    {"run_unit_id":"bats:b","category":"cost","severity":"medium","evidence_refs":["r2"],"recommendation":"measure","confidence":"low","falsification_check":"n/a"}
  ]'
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "$OUTPUT_DIR/implementation-plan-brief.json" ]
  jq -e '(.items | length) == 1 and .items[0].run_unit_id == "bats:a"' "$OUTPUT_DIR/implementation-plan-brief.json" >/dev/null
}

@test "a wave artifact missing a required schema field halts consolidation, naming the artifact" {
  cat > "$AGENTS_DIR/1-shard_portfolio-shard-0.json" <<'JSON'
{"schema_version":"1.0.0","focus":"shard_portfolio","wave":1,"shard_id":"shard-0","findings":[],"produced_at":"2026-07-30T00:00:00Z"}
JSON
  _declare_manifest_entry_only "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
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
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
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
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ "$(jq '.findings | length' "$OUTPUT_DIR/consolidated-findings.json")" -eq 1 ]
}

@test "an empty --wave-artifacts-dir (zero artifacts) is rejected, never reported as a clean audit" {
  # Regression (Codex review): a missing/interrupted dispatch (empty dir)
  # previously produced a schema-valid, empty findings report indistinguishable
  # from a genuinely clean audit. Now expressed via a manifest that declares
  # a real entry which was simply never produced.
  _declare_manifest_entry_only "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected wave artifact missing"* ]]
  [ ! -f "$OUTPUT_DIR/consolidated-findings.json" ]
}

@test "an invalid --audit-id is rejected before any file is written" {
  run "$CONSOLIDATE" --audit-id '../escape' --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$TEST_TMPDIR/nonexistent-manifest.json" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [ ! -f "$OUTPUT_DIR/consolidated-findings.json" ]
}

@test "a dispatch manifest declaring zero entries is rejected — nothing to consolidate" {
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"zero entries"* ]]
}

@test "a single schema-valid Wave 1 artifact with no Wave 3 (adversarial review) declared as missing by the manifest is rejected — never a false clean audit (PM whole-EPIC-3 review)" {
  # This is the exact scenario the PM's review found: one valid Wave 1
  # artifact alone must NOT be enough to produce a clean consolidated
  # report/chat verdict when the manifest declares a mandatory Wave 3 that
  # was never produced.
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"flake","severity":"low","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  _declare_manifest_entry_only "$AGENTS_DIR/3-adversarial_review.json" adversarial_review 3 ""
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected wave artifact missing"* ]]
  [[ "$output" == *"3-adversarial_review.json"* ]] || [[ "$output" == *"adversarial_review"* ]]
  [ ! -f "$OUTPUT_DIR/consolidated-findings.json" ]
}

@test "an artifact file present but NOT declared by any manifest entry is rejected, never silently folded into the report" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[
    {"run_unit_id":"bats:a","category":"flake","severity":"low","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}
  ]'
  _write_artifact "$AGENTS_DIR/3-adversarial_review.json" adversarial_review 3 "" '[]'
  # Manifest only declares wave 1 — the adversarial_review file exists but
  # is never declared.
  jq -nc '{wave:1, focus:"shard_portfolio", shard_id:"shard-0", artifact_path:"'"$AGENTS_DIR"'/1-shard_portfolio-shard-0.json", producer_agent_dispatch_id:"d1"}' > "$MANIFEST_ENTRIES_FILE"
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not declared by any entry"* ]]
  [[ "$output" == *"3-adversarial_review.json"* ]]
}

@test "an artifact with the right filename but wrong wave/focus/producer_agent_dispatch_id (substituted-in artifact) is rejected" {
  # The artifact file itself carries producer_agent_dispatch_id "d1", but
  # the manifest entry declares a DIFFERENT expected id ("d-expected") for
  # that same path — simulating a substituted/stale artifact left over
  # under the right filename.
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[]' "d1"
  jq -nc '{wave:1, focus:"shard_portfolio", shard_id:"shard-0", artifact_path:"'"$AGENTS_DIR"'/1-shard_portfolio-shard-0.json", producer_agent_dispatch_id:"d-expected"}' > "$MANIFEST_ENTRIES_FILE"
  _write_manifest a1
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match its dispatch-manifest entry"* ]]
}

@test "a dispatch-manifest whose audit_id does not match --audit-id is rejected" {
  _write_artifact "$AGENTS_DIR/1-shard_portfolio-shard-0.json" shard_portfolio 1 shard-0 '[]'
  _write_manifest "a-different-audit"
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$MANIFEST_PATH" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match --audit-id"* ]]
}

@test "--dispatch-manifest is required and a nonexistent path is rejected" {
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
  run "$CONSOLIDATE" --audit-id a1 --wave-artifacts-dir "$AGENTS_DIR" --dispatch-manifest "$TEST_TMPDIR/nonexistent.json" --output-dir "$OUTPUT_DIR"
  [ "$status" -ne 0 ]
}
