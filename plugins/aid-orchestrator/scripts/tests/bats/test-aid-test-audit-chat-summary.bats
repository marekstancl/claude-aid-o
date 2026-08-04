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
  [[ "$output" == *"## 1. What to do now"* ]]
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
  # The findings list moved into the technical-evidence appendix (P072 Step 19).
  reason_lines="$(echo "$output" | sed -n '/\*\*Findings\*\*/,/\*\*Changed:\*\*/p' | grep -cE '^[0-9]+\.')"
  [ "$reason_lines" -eq 1 ]
}

@test "a malformed findings file produces an explicit failure statement, never a fabricated clean verdict" {
  local f="$TEST_TMPDIR/bad.json"
  echo "not valid json {{{" > "$f"
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete cleanly"* ]]
}

@test "a normal completed audit persists a durable-record.json (Codex review: render_chat_summary previously had no production caller of the persist function)" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"n/a"}]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  local record="$TEST_TMPDIR/durable-record.json"
  [ -f "$record" ]
  jq -e '.audit_id == "a1"' "$record" >/dev/null
  jq -e '.verdict == "remediation recommended"' "$record" >/dev/null
}

@test "a clean-verdict audit also persists a durable-record.json (so a continuation attempt has something to check against)" {
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  jq -e '.verdict == "clean"' "$TEST_TMPDIR/durable-record.json" >/dev/null
}

@test "a persist failure fails the whole render, never printing a successful-looking chat verdict with no durable record behind it (PM whole-EPIC-3 review)" {
  local f="$TEST_TMPDIR/readonly-dir/findings.json"
  mkdir -p "$TEST_TMPDIR/readonly-dir"
  _write_findings "$f" '[{"finding_id":"f1","run_unit_id":"bats:a","category":"cost","severity":"high","evidence_refs":["r1"],"recommendation":"fix","confidence":"medium","falsification_check":"n/a"}]'
  chmod 500 "$TEST_TMPDIR/readonly-dir"
  run aid_test_audit_render_chat_summary "$f"
  chmod 700 "$TEST_TMPDIR/readonly-dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete cleanly"* ]]
  [[ "$output" != *"**Verdict:**"* ]]
  [ ! -f "$TEST_TMPDIR/readonly-dir/durable-record.json" ]
}

@test "final chat output contains all six sections plus the evidence appendix, in order" {
  # The ORDER is the contract: a reader must meet the decision before the
  # evidence. The five-part predecessor led with a verdict and a severity list,
  # so the answer to "what should I do" had to be assembled by the reader.
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]

  local expected=(
    "## 1. What to do now"
    "## 2. What to fix, merge, split or remove"
    "## 3. What can run in parallel"
    "## 4. What must remain serial"
    "## 5. Test time now, and after the proposed work"
    "## 6. What is not proved yet"
    "### Technical evidence"
  )
  local prev=0 pos h
  for h in "${expected[@]}"; do
    [[ "$output" == *"$h"* ]] || { echo "missing section: $h" >&2; false; }
    pos="$(printf '%s' "$output" | grep -n -F -m1 "$h" | cut -d: -f1)"
    [ "$pos" -gt "$prev" ] || { echo "section out of order: $h" >&2; false; }
    prev="$pos"
  done
}

@test "every heading renders even when its section is empty" {
  # A missing heading reads as an omission. "Nothing here" is a finding and
  # has to be said.
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[]'
  run aid_test_audit_render_chat_summary "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 3. What can run in parallel"* ]]
  [[ "$output" == *"## 6. What is not proved yet"* ]]
}

# ─── What an adversarial review of the renderer found ──────────────────────
#
# This text is the only thing most users read. Every case below is a state
# that produced a CONFIDENT, COMPLETE-LOOKING message over an audit that had
# decided nothing, or that said two contradictory things at once.

_decision() {
  jq -n --argjson pc "$2" --arg st "${3:-complete}" \
    '{schema_version:"aid-test-audit-decision-v1", audit_id:"a1", audit_status:$st,
      current_runtime:{kind:"unknown", duration_ms:null, scope:["bats:a"]},
      actions:[], parallelization:{lanes:[], smallest_safe_pilot:null}, unresolved:[],
      portfolio_coverage:{inventory_count:1, assigned_count:1, disposition_count:1,
                          missing_run_unit_ids:[], duplicate_run_unit_ids:[]},
      portfolio_change:$pc}
     + (if $st == "incomplete" then {incomplete_reason:"coverage_mismatch"} else {} end)' > "$1"
}

_pc() {
  jq -nc --argjson rm "${1:-[]}" --argjson mg "${2:-[]}" \
    '{current_run_units:1, proposed_run_units:1, keep:[], rewrite_unit:[],
      merge_groups:$mg, remove:$rm,
      runtime_before_ms:null, runtime_after_ms:null, impact_kind:"unknown"}'
}

@test "a FULL audit with no decision artifact is refused, never rendered as 'no action needed'" {
  # The single most misleading sentence this renderer can emit: a confident
  # all-clear over an audit that decided nothing.
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[]'
  run aid_test_audit_render_chat_summary "$f" "nothing" "full" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete cleanly"* ]]
  [[ "$output" != *"No action needed"* ]]
}

@test "a decision artifact that does not validate is refused, not read past" {
  # `{}` used to sail through: every query returned null and every null became
  # an affirmative default.
  local f="$TEST_TMPDIR/findings.json" d="$TEST_TMPDIR/bad.json"
  _write_findings "$f" '[]'
  echo '{}' > "$d"
  run aid_test_audit_render_chat_summary "$f" "nothing" "full" "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid or incompatible"* ]]
  [[ "$output" != *"reached a decision it can defend"* ]]
}

@test "'clean' never coexists with an explicit removal instruction" {
  # Findings said nothing; the decision said remove a test. Section 1 said
  # "No action needed." directly above "Remove (1)".
  local f="$TEST_TMPDIR/findings.json" d="$TEST_TMPDIR/d.json"
  _write_findings "$f" '[]'
  _decision "$d" "$(_pc '["bats:legacy"]')"
  run aid_test_audit_render_chat_summary "$f" "nothing" "full" "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remove 1 unit(s)"* ]]
  [[ "$output" != *"No action needed"* ]]
  [[ "$output" != *"**Verdict:** clean"* ]]
}

@test "merge groups keep their BOUNDARIES — two pairs are not one group of four" {
  # Flattened, `Merge (4): a, b, c, d` reads as a single four-unit merge: a
  # different instruction, and an unsafe one to execute.
  local f="$TEST_TMPDIR/findings.json" d="$TEST_TMPDIR/d.json"
  _write_findings "$f" '[]'
  _decision "$d" "$(_pc '[]' '[["bats:a","bats:b"],["bats:c","bats:d"]]')"
  run aid_test_audit_render_chat_summary "$f" "nothing" "full" "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"group 1: bats:a, bats:b"* ]]
  [[ "$output" == *"group 2: bats:c, bats:d"* ]]
  [[ "$output" != *"Merge (4)"* ]]
}

@test "an INCOMPLETE audit labels its later sections provisional" {
  # `audit_status: incomplete` protected only section 1, so partial removals
  # and lanes below it read exactly like instructions from a finished audit.
  local f="$TEST_TMPDIR/findings.json" d="$TEST_TMPDIR/d.json"
  _write_findings "$f" '[]'
  _decision "$d" "$(_pc '["bats:legacy"]')" incomplete
  run aid_test_audit_render_chat_summary "$f" "nothing" "full" "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Provisional"* ]]
  [[ "$output" == *"did not finish"* ]]
}

@test "an incomplete audit NAMES the units it never decided" {
  # The list was computed and then never rendered, so the text said "decide
  # the units listed above" with no such list anywhere.
  local f="$TEST_TMPDIR/findings.json" d="$TEST_TMPDIR/d.json"
  _write_findings "$f" '[]'
  _decision "$d" "$(_pc '[]')" incomplete
  jq '.portfolio_coverage.missing_run_unit_ids = ["bats:u1","bats:u2"]' "$d" > "$d.tmp" && mv "$d.tmp" "$d"
  run aid_test_audit_render_chat_summary "$f" "nothing" "full" "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bats:u1"* ]]
  [[ "$output" == *"unexamined, not as healthy"* ]]
}

@test "an incomplete audit's runtime figure is marked as not decision-grade" {
  local f="$TEST_TMPDIR/findings.json" d="$TEST_TMPDIR/d.json"
  _write_findings "$f" '[]'
  _decision "$d" "$(_pc '[]')" incomplete
  jq '.portfolio_change.runtime_before_ms = 40000
      | .portfolio_change.runtime_after_ms = 25000
      | .portfolio_change.impact_kind = "estimated"' "$d" > "$d.tmp" && mv "$d.tmp" "$d"
  run aid_test_audit_render_chat_summary "$f" "nothing" "full" "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT a decision-grade"* ]]
}

@test "a durable-record persist failure is explained on STDOUT, not only stderr" {
  # This function's stdout IS the user-facing turn. A failure explained only on
  # stderr leaves the caller presenting nothing, or an earlier success message.
  local f="$TEST_TMPDIR/findings.json"
  _write_findings "$f" '[]'
  chmod a-w "$TEST_TMPDIR"
  run aid_test_audit_render_chat_summary "$f"
  chmod u+w "$TEST_TMPDIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not complete cleanly"* ]]
}
