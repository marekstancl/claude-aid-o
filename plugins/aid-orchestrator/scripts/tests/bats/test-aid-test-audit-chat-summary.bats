#!/usr/bin/env bats
# test-aid-test-audit-chat-summary.bats — P066 Step 15.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-test-audit-chat-summary.sh"
}

teardown() {
  teardown_test_evidence_dir
}

_write_findings() {
  local path="$1" findings_json="$2"
  jq -n --argjson f "$findings_json" '{schema_version:"1.0.0", audit_id:"a1", generated_at:"2026-07-30T00:00:00Z", findings:$f}' > "$path"
}

@test "clean verdict: no findings at all" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Verdict:** clean"* ]]
  [[ "$output" == *"**Changed:**"* ]]
  [[ "$output" == *"**Next action:**"* ]]
  [[ "$output" == *"**Residual risk"* ]]
  [[ "$output" == *"No PM decision required."* ]]
}

@test "clean verdict: only low-severity 'keep' findings" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"flake","severity":"low","evidence_refs":["r1"],"recommendation":"keep","confidence":"medium","falsification_check":"n/a"}]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Verdict:** clean"* ]]
}

@test "needs measurement verdict: a finding recommends 'measure', nothing actionable yet" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"cost","severity":"medium","evidence_refs":["r1"],"recommendation":"measure","confidence":"low","falsification_check":"n/a"}]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Verdict:** needs measurement"* ]]
  [[ "$output" == *"--mode measure"* ]]
}

@test "remediation recommended verdict: a Medium+ finding recommends fix/quarantine/etc" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"n/a"}]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Verdict:** remediation recommended"* ]]
  [[ "$output" == *"vytvoř plán oprav"* ]]
}

@test "a static-mode-only run can still reach 'remediation recommended' from static analysis alone (no measurement dependency in the classifier)" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"structure","severity":"critical","evidence_refs":["static-grep-r1"],"recommendation":"split","confidence":"high","falsification_check":"n/a"}]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Verdict:** remediation recommended"* ]]
}

@test "a zero-PM-decision fixture still includes an explicit 'no PM decision required' line" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"n/a"}]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No PM decision required."* ]]
}

@test "unresolved conflicts surface as an explicit PM-decision-needed residual risk" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"n/a","unresolved_conflict":true}]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs a PM decision"* ]]
}

@test "verdict classification is deterministic and reproducible from the same findings file" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"n/a"}]'
  run aid_test_audit_render_chat_summary "$f"
  local first="$output"
  run aid_test_audit_render_chat_summary "$f"
  [ "$output" = "$first" ]
}

@test "a missing findings file produces an explicit failure statement, never a fabricated clean verdict" {
  run aid_test_audit_render_chat_summary "$TEST_TMPDIR/does-not-exist.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete cleanly"* ]]
  [[ "$output" != *"**Verdict:** clean"* ]]
}

@test "a syntactically-valid-JSON-but-wrong-shape findings file (findings: {} instead of an array) fails closed, never a fabricated clean verdict" {
  # Regression (Codex review): a bare `.findings` extraction previously let
  # a wrong-shape document (schema-invalid but valid JSON) slip through and
  # be treated as empty, producing a fabricated "clean" verdict over a
  # corrupted/incompatible consolidation output.
  local f="$TEST_TMPDIR/wrong-shape.json"
  jq -n '{schema_version:"1.0.0", audit_id:"x", generated_at:"2026-07-30T00:00:00Z", findings:{}}' > "$f"
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete cleanly"* ]]
  [[ "$output" != *"**Verdict:** clean"* ]]
}

@test "a sparse result set (1 real finding) gets exactly 1 real reason, never padded/fabricated to reach a minimum count" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"n/a"}]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  local reason_lines
  reason_lines="$(echo "$output" | sed -n '/\*\*Reasons:\*\*/,/\*\*Changed:\*\*/p' | grep -cE '^[0-9]+\.')"
  [ "$reason_lines" -eq 1 ]
}

@test "a malformed findings file produces an explicit failure statement, never a fabricated clean verdict" {
  local f="$TEST_TMPDIR/bad.json"
  echo "not valid json {{{" > "$f"
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete cleanly"* ]]
}

@test "final chat output contains all 5 parts for every verdict" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[]'
  run aid_test_audit_render_chat_summary "$f"
  [[ "$output" == *"**Verdict:**"* ]]
  [[ "$output" == *"**Reasons:**"* ]]
  [[ "$output" == *"**Changed:**"* ]]
  [[ "$output" == *"**Next action:**"* ]]
  [[ "$output" == *"**Residual risk"* ]]
}
