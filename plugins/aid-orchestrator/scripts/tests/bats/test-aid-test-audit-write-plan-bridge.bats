#!/usr/bin/env bats
# test-aid-test-audit-write-plan-bridge.bats — P066 Step 16.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-write-plan-bridge.sh"
  OUTPUT_DIR="$TEST_TMPDIR/audit-out"
  mkdir -p "$OUTPUT_DIR"

  CATALOG="$TEST_TMPDIR/test-catalog.yaml"
  cat > "$CATALOG" <<'YAML'
schema_version: "1.0.0"
generated_at: "2026-07-30T00:00:00Z"
status: approved
run_units:
  - run_unit_id: "bats:a"
    runner: bats
    source_paths: []
    production_surfaces: []
    test_level: suite
    risk_tags: []
    profiles: [default]
    behavior_claims: []
    confidence: low
    command: {type: argv, argv: ["bats", "a.bats"]}
    runtime: {fingerprint: "sha256:000000000000"}
    parallel: {status: unknown, exclusive_resources: [], max_workers: null, internal_parallelism: false}
    isolation: {temp_workspace: unknown, fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: static_parse}
    recommendation: keep
    test_cases: []
source_pattern_mappings: []
mapping_approval: {status: proposed}
YAML
}

teardown() {
  teardown_test_evidence_dir
}

_write_valid_findings_and_brief() {
  local findings_path="${OUTPUT_DIR}/consolidated-findings.json"
  jq -n '{schema_version:"1.0.0", audit_id:"a1", generated_at:"2026-07-30T00:00:00Z", findings:[
    {finding_id:"f1", run_unit_id:"bats:a", category:"cost", severity:"high", evidence_refs:["r1"], recommendation:"fix", confidence:"medium", falsification_check:"x"}
  ]}' > "$findings_path"
  local hash
  hash="sha256:$(sha256sum "$findings_path" | cut -d' ' -f1)"
  jq -n --arg hash "$hash" '{audit_id:"a1", verdict:"remediation recommended", items:[
    {finding_id:"f1", run_unit_id:"bats:a", category:"cost", proposed_action:"fix", evidence_refs:["r1"], owner:"unassigned"}
  ], generated_from_hash:$hash}' > "${OUTPUT_DIR}/implementation-plan-brief.json"
  echo "# brief" > "${OUTPUT_DIR}/implementation-plan-brief.md"
}

@test "--write-plan and a simulated same-conversation continuation resolve to the identical validator call and verdict" {
  _write_valid_findings_and_brief
  aid_test_audit_write_plan_bridge_persist "$OUTPUT_DIR" "a1" "remediation recommended" "generate a remediation plan"

  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$CATALOG"
  local first="$output"
  [ "$status" -eq 0 ]

  # A second, independent call (simulating the same-conversation
  # continuation trigger, which resolves to this same function) MUST
  # produce the identical result — there is only one validator code path.
  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$CATALOG"
  [ "$output" = "$first" ]
  echo "$output" | jq -e '.ready == true' >/dev/null
}

@test "a clean-verdict continuation attempt returns {ready:false, reason:'no brief: audit found nothing to fix'}" {
  aid_test_audit_write_plan_bridge_persist "$OUTPUT_DIR" "a1" "clean" "no action needed"
  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$CATALOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ready == false' >/dev/null
  [[ "$output" == *"no brief: audit found nothing to fix"* ]]
}

@test "a needs-measurement-verdict continuation attempt also returns {ready:false,...} (no brief exists for it either)" {
  aid_test_audit_write_plan_bridge_persist "$OUTPUT_DIR" "a1" "needs measurement" "re-run with --mode measure"
  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$CATALOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ready == false' >/dev/null
}

@test "a stale run_unit_id (no longer in the current catalog) returns {ready:false,...} and blocks the handoff" {
  local findings_path="${OUTPUT_DIR}/consolidated-findings.json"
  jq -n '{schema_version:"1.0.0", audit_id:"a1", generated_at:"2026-07-30T00:00:00Z", findings:[
    {finding_id:"f1", run_unit_id:"bats:no-longer-exists", category:"cost", severity:"high", evidence_refs:["r1"], recommendation:"fix", confidence:"medium", falsification_check:"x"}
  ]}' > "$findings_path"
  local hash
  hash="sha256:$(sha256sum "$findings_path" | cut -d' ' -f1)"
  jq -n --arg hash "$hash" '{audit_id:"a1", verdict:"remediation recommended", items:[
    {finding_id:"f1", run_unit_id:"bats:no-longer-exists", category:"cost", proposed_action:"fix", evidence_refs:["r1"], owner:"unassigned"}
  ], generated_from_hash:$hash}' > "${OUTPUT_DIR}/implementation-plan-brief.json"
  echo "# brief" > "${OUTPUT_DIR}/implementation-plan-brief.md"
  aid_test_audit_write_plan_bridge_persist "$OUTPUT_DIR" "a1" "remediation recommended" "generate a remediation plan"

  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$CATALOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ready == false' >/dev/null
  [[ "$output" == *"stale run_unit_id"* ]]
}

@test "a stale run_unit_id result is verified (via a mock controller harness) to block any downstream /aid-plan write invocation" {
  local findings_path="${OUTPUT_DIR}/consolidated-findings.json"
  jq -n '{schema_version:"1.0.0", audit_id:"a1", generated_at:"2026-07-30T00:00:00Z", findings:[
    {finding_id:"f1", run_unit_id:"bats:gone", category:"cost", severity:"high", evidence_refs:["r1"], recommendation:"fix", confidence:"medium", falsification_check:"x"}
  ]}' > "$findings_path"
  local hash
  hash="sha256:$(sha256sum "$findings_path" | cut -d' ' -f1)"
  jq -n --arg hash "$hash" '{audit_id:"a1", verdict:"remediation recommended", items:[
    {finding_id:"f1", run_unit_id:"bats:gone", category:"cost", proposed_action:"fix", evidence_refs:["r1"], owner:"unassigned"}
  ], generated_from_hash:$hash}' > "${OUTPUT_DIR}/implementation-plan-brief.json"
  echo "# brief" > "${OUTPUT_DIR}/implementation-plan-brief.md"
  aid_test_audit_write_plan_bridge_persist "$OUTPUT_DIR" "a1" "remediation recommended" "generate a remediation plan"

  # Mock controller harness: only invoke "/aid-plan write" (here, just a
  # marker file) if the validator says ready:true.
  local marker="$TEST_TMPDIR/aid-plan-write-invoked"
  rm -f "$marker" 2>/dev/null
  local result
  result="$(aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$CATALOG")"
  if echo "$result" | jq -e '.ready == true' >/dev/null 2>&1; then
    touch "$marker"
  fi
  [ ! -f "$marker" ]
}

@test "a missing catalog_path fails closed (Codex review: previously silently skipped stale-run_unit_id check and returned ready:true)" {
  _write_valid_findings_and_brief
  aid_test_audit_write_plan_bridge_persist "$OUTPUT_DIR" "a1" "remediation recommended" "generate a remediation plan"

  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$TEST_TMPDIR/does-not-exist-catalog.yaml"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ready == false' >/dev/null
  [[ "$output" == *"cannot verify run_unit_ids"* ]]
}

@test "a malformed/unparseable catalog_path fails closed rather than falling through to ready:true" {
  _write_valid_findings_and_brief
  aid_test_audit_write_plan_bridge_persist "$OUTPUT_DIR" "a1" "remediation recommended" "generate a remediation plan"

  local bad_catalog="$TEST_TMPDIR/bad-catalog.yaml"
  printf ':::not valid yaml:::\n\tbroken' > "$bad_catalog"

  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$bad_catalog"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ready == false' >/dev/null
  [[ "$output" == *"cannot verify run_unit_ids"* ]]
}

@test "a large, realistic catalog (hundreds of run_units) is checked correctly — never a silent argv-size jq failure treated as 'nothing stale' (P066 E4 dogfood finding)" {
  # Regression: dogfooding this against the real aid-orchestrator repo's own
  # 83-run_unit catalog previously hit a real "jq: Argument list too long"
  # failure from `--argjson catalog "$catalog_json"` on the command line —
  # jq's failure produced EMPTY stdout, which the stale_id check then
  # silently treated as "no stale id found" (ready:true), never surfacing
  # the failure at all. This fixture uses 500 run_units (larger than the
  # real repo's own 83) to prove the fix handles a large catalog for real,
  # not just avoids the exact failure size seen once.
  local big_catalog="$TEST_TMPDIR/big-catalog.yaml"
  jq -n '{
    schema_version: "1.0.0", generated_at: "2026-07-30T00:00:00Z", status: "approved",
    run_units: [range(500) | {
      run_unit_id: ("bats:fixture-\(.)"), runner: "bats", source_paths: [], production_surfaces: [],
      test_level: "suite", risk_tags: [], profiles: ["default"], behavior_claims: [], confidence: "low",
      command: {type:"argv", argv:["bats", "fixture-\(.).bats"]}, runtime: {fingerprint: "sha256:000000000000"},
      parallel: {status:"unknown", exclusive_resources:[], max_workers:null, internal_parallelism:false},
      isolation: {temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
      recommendation: "keep", test_cases: []
    }],
    source_pattern_mappings: [], mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$big_catalog"

  _write_valid_findings_and_brief
  aid_test_audit_write_plan_bridge_persist "$OUTPUT_DIR" "a1" "remediation recommended" "generate a remediation plan"

  # _write_valid_findings_and_brief's brief cites "bats:a", which is NOT in
  # this 500-entry catalog — so the honest, correct result is ready:false
  # with a real stale_id (proving the check actually ran against the whole
  # 500-entry catalog), never a silent ready:true from a failed jq call.
  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$big_catalog"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Argument list too long"* ]]
  echo "$output" | jq -e '.ready == false' >/dev/null
  [[ "$output" == *"stale run_unit_id: bats:a"* ]]
}

@test "a missing durable record returns {ready:false,...} rather than erroring" {
  run aid_test_audit_write_plan_bridge_check "$OUTPUT_DIR" "$CATALOG"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ready == false' >/dev/null
}

@test "documentation states plainly this is a same-conversation convention, never a global interceptor or release-blocking mechanism" {
  grep -qi "same-conversation convention" "$AID_PLUGIN_PATH/commands/aid-audit-tests.md"
  grep -qi "never a global interceptor" "$AID_PLUGIN_PATH/commands/aid-audit-tests.md"
  grep -qi "never invokes \`/aid-plan write\`" "$AID_PLUGIN_PATH/commands/aid-audit-tests.md"
}

@test "the bridge script never invokes /aid-plan write itself (grep-verified, comments excluded)" {
  ! grep -vE '^\s*#' "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-write-plan-bridge.sh" | grep -q "aid-plan write"
}
