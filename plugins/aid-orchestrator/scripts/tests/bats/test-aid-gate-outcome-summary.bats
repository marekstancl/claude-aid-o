#!/usr/bin/env bats
# aid-tier: t1
# test-aid-gate-outcome-summary.bats — the gate-boundary card (P080 Step 11;
# card only since P099 Step 4: a gate run owes the PM no page).
#
# THE RULES THIS SUITE EXISTS FOR
#   The card follows `.overall`, never a per-gate row. A waiver is PM risk
#   acceptance, never a pass — Czech forms included. A report nobody can vouch
#   for is refused, never rendered as an empty pass. Nothing from the report
#   reaches the card without the redactor.
#
# NEGATIVE ASSERTIONS USE refute_grep, NOT `! grep`
#   `! grep -q …` cannot fail a bats case: bash exempts a `!`-inverted command
#   from `set -e` and bats' ERR trap inherits the exemption.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUN_DIR="$TEST_TMPDIR/run"
  mkdir -p "$RUN_DIR/gates"
  export RUN_DIR
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-gate-outcome-summary.sh"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixture builders ───────────────────────────────────────────────────────

# _row <gate> <result> <exit> <ms> <attempts> [reason]
_row() {
  jq -nc --arg g "$1" --arg r "$2" --argjson e "$3" --argjson d "$4" --argjson a "$5" \
    --arg why "${6:-}" \
    '{gate:$g, result:$r, reason:$why, exit_code:$e, duration_ms:$d, output:"", attempts:$a}'
}

# _report <overall> <gates_object_json> [extra_object_json]
_report() {
  local overall="$1" gates="$2" extra="${3:-{\}}"
  jq -nc --arg o "$overall" --argjson g "$gates" --argjson x "$extra" '
    {epic_id:"E-080-1_1", run_id:"run-1", overall:$o, completed_at:"2026-08-12T10:00:00Z",
     gates:$g, waived_gates:[], excluded_gates:[],
     _command_log:[{name:"tests", command:"bats scripts/tests", exit_code:0, duration_ms:1000}]} + $x'
}

_all_pass_report() {
  _report pass "$(jq -nc --argjson a "$(_row tests pass 0 90000 1)" --argjson b "$(_row lint pass 0 30000 1)" \
    '{tests:$a, lint:$b}')"
}

_write() { printf '%s\n' "$1" > "$2"; }

# _counts — the Finished card's count line.
_counts() { grep -F 'Ověřeno:' <<<"$output"; }

# ─── the two cards ──────────────────────────────────────────────────────────

@test "an all-pass report renders the Finished card with computed counts and no page" {
  _write "$(_all_pass_report)" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == Hotovo:* ]]
  [[ "$output" == *"nic neselhalo"* ]]
  # 120000 ms of gate time is 2 min — derived, not claimed.
  [[ "$(_counts)" == "Ověřeno: 2 z 2 bran za 2 min 0 s (selhalo 0, neběželo 0, prominuto 0)." ]]
  [[ "$output" != *Zastaveno:* && "$output" != *"Artifact:"* ]]
  [ -z "$(find "$RUN_DIR" -name '*.html')" ]
}

@test "a failed required gate renders the Blocked card naming the gate and the smallest recovery action" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests fail 1 5000 2)" --argjson b "$(_row lint pass 0 1000 1)" \
    '{tests:$a, lint:$b}')"
  _write "$(_report fail "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == Zastaveno:* ]]
  [[ "$output" == *"brána tests selhala (exit 1)"* ]]
  [[ "$output" == *"ověřeno 1 z 2 bran"* ]]
  # The recovery line is the gate's OWN command from _command_log — never an
  # invented remediation, because no gate definition carries one.
  [[ "$output" == *"Doporučené řešení: zopakuj bránu příkazem \`bats scripts/tests\`"* ]]
  [[ "$output" == *"aid-fsm.sh transition GATES DONE <state_file> --force --reason"* ]]
  [ -z "$(find "$RUN_DIR" -name '*.html')" ]
}

# ─── waived — the D3 rule ───────────────────────────────────────────────────

@test "a waived gate is counted as PM risk acceptance, never as a pass" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row tests waived 1 5000 3)" --argjson b "$(_row lint pass 0 1000 1)" \
    '{tests:($a + {waiver_ref:"waivers/gate-waiver-tests.json"}), lint:$b}')"
  extra='{"waived_gates":["tests"]}'
  _write "$(_report pass "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$(_counts)" == "Ověřeno: 1 z 2 bran"*"prominuto 1)." ]]
  local waived_line
  waived_line="$(grep -F 'prominut' <<<"$output" | grep -v '^Ověřeno:')"
  [ -n "$waived_line" ]
  refute_grep -qiE 'passed|prošl[aoyi]|prošel|úspěch|success' <<<"$waived_line"
  # `OK` is matched case-SENSITIVELY and as a whole word: folded to lowercase
  # it hits inside ordinary Czech words such as "krok".
  refute_grep -qE '\b(OK|PASS|PASSED)\b|✅' <<<"$waived_line"
}

@test "a waiver named only by waived_gates[] still counts — a missing row never hides it" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row lint pass 0 1000 1)" '{lint:$a}')"
  extra='{"waived_gates":["docs_updated"]}'
  _write "$(_report pass "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$(_counts)" == *"prominuto 1)." ]]
}

@test "a fail row that waived_gates names is a waiver, not also a failure (Codex, P089)" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row lint fail 1 500 1)" --argjson b "$(_row tests pass 0 1000 1)" \
    '{lint:$a, tests:$b}')"
  extra='{"waived_gates":["lint"]}'
  _write "$(_report pass "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$(_counts)" == *"(selhalo 0, neběželo 0, prominuto 1)." ]]
}

@test "a REJECTED waiver stays a failure even when waived_gates names the gate" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row lint fail 1 500 1)" \
    '{lint:($a + {waiver_rejected:"expired"})}')"
  extra='{"waived_gates":["lint"]}'
  _write "$(_report fail "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == "Zastaveno: brána lint selhala (exit 1)."* ]]
}

# ─── card selection follows .overall, never a per-row verdict ───────────────

@test "skip and profile_excluded rows select the Finished card — neither is a failure" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests pass 0 1000 1)" \
    --argjson b "$(_row lint skip 0 0 0)" \
    --argjson c "$(_row build profile_excluded 0 0 0)" \
    '{tests:$a, lint:$b, build:$c}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == Hotovo:* ]]
  [[ "$(_counts)" == *"(selhalo 0, neběželo 2, prominuto 0)." ]]
}

# P097 Step 2: version-2 rows (status/reason/waived, no `result`) classify the
# same way — the renderer reads every row through gate_row_normalize.
@test "version-2 rows (status/reason/waived) classify exactly like version-1 rows" {
  _row2() {  # <gate> <status> <reason> <waived> <exit>
    jq -nc --arg g "$1" --arg st "$2" --arg r "$3" --argjson w "$4" --argjson e "$5" \
      '{row_version:2, gate:$g, status:$st, reason:$r, waived:$w, exit_code:$e, duration_ms:10,
        started_at:"2026-09-21T10:00:00Z", completed_at:"2026-09-21T10:00:01Z", evidence:null,
        required:false, reused_from:null, output:"", attempts:1}'
  }
  local gates
  gates="$(jq -nc --argjson a "$(_row2 tests pass exit_0 false 0)" \
    --argjson b "$(_row2 lint skip exit_2 false 2)" \
    --argjson c "$(_row2 build skip not_in_profile false null)" \
    --argjson d "$(_row2 e2e fail exit_1 true 1)" \
    --argjson e "$(_row2 types fail exit_4 false 4)" \
    --argjson f "$(_row2 smoke fail missing_script false 1)" \
    '{tests:$a, lint:$b, build:$c, e2e:$d, types:$e, smoke:$f, _execution_ledger:{path:"p", duplicates:[], dispatched:1}}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$(_counts)" == "Ověřeno: 1 z 6 bran"*"(selhalo 1, neběželo 3, prominuto 1)." ]]
}

@test "a FAILING non-required gate with overall pass still selects the Finished card" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests pass 0 1000 1)" --argjson b "$(_row docs_updated fail 1 500 1)" \
    '{tests:$a, docs_updated:$b}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  # Reading the row instead would tell the PM the run is blocked while the FSM advances.
  [[ "$output" == "Hotovo: brány doběhly, 1 z nich selhalo (žádná z nich povinná)."* ]]
  [[ "$output" != *Zastaveno:* ]]
}

@test "a report with zero gates renders the Finished card with scope 0" {
  _write "$(_report pass '{}')" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == Hotovo:* ]]
  [[ "$output" == *"Ověřeno: 0 z 0 bran"* ]]
}

# ─── all three report locations, plus the escalation shape ──────────────────

@test "an explicit report path wins over the nested decoy" {
  local other="$TEST_TMPDIR/somewhere-else.json"
  _write "$(_all_pass_report)" "$other"
  _write "$(_report fail "$(jq -nc --argjson a "$(_row tests fail 1 10 1)" '{tests:$a}')")" \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "$other" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == Hotovo:* ]]
}

@test "the flat layout resolves when the nested one does not exist" {
  rm -rf "$RUN_DIR/gates"
  _write "$(_all_pass_report)" "$RUN_DIR/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == Hotovo:* ]]
}

@test "the escalation-shaped variant renders" {
  local base merged
  base="$(_all_pass_report)"
  # Exactly lib/aid-run-gates-report.sh's merge: the full pass verbatim plus a
  # separate top-level escalation key nesting the targeted attempt.
  merged="$(jq -nc --argjson full "$base" --argjson targeted "$base" \
    '$full + {escalation:{triggered_by:"targeted_tests", reason:"exit_code 11: mapping_gap", targeted_run:$targeted}}')"
  _write "$merged" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$(_counts)" == "Ověřeno: 2 z 2 bran"* ]]
}

# ─── error handling ─────────────────────────────────────────────────────────

@test "a missing report exits 1 with a one-line error" {
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no gates report found"* ]]
}

@test "an invalid report exits 1 rather than rendering wrong numbers" {
  _write 'not json at all {' "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid gates report JSON"* ]]
}

@test "a report carrying no .gates data fails closed, not as an empty profile" {
  _write '{"overall":"pass","epic_id":"E1"}' "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"carries no .gates object"* ]]
  [[ "$output" != *"0 z 0"* ]]
}

@test "a gate map whose VALUE is not an object fails closed, not into blank counters" {
  _write '{"overall":"pass","epic_id":"E1","gates":{"tests":"pass"}}' \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-object gate entries (tests)"* ]]
  [[ "$output" != *"Hotovo:"* ]]
}

@test "one malformed entry among good ones is refused by name, never silently dropped" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests pass 0 1000 1)" '{tests:$a, lint:"pass"}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-object gate entries (lint)"* ]]
  [[ "$output" != *"Ověřeno"* ]]
}

@test "a report with no .overall fails closed — a missing verdict is not a pass" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests fail 1 1000 1)" --argjson b "$(_row lint fail 1 500 1)" \
    '{tests:$a, lint:$b}')"
  _write "$(jq -c 'del(.overall)' <<<"$(_report pass "$gates")")" \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no usable .overall verdict"* ]]
  [[ "$output" != *"Hotovo:"* ]]
}

@test "an unrecognised .overall value fails closed rather than defaulting to not-blocked" {
  _write "$(jq -c '.overall = "unknown"' <<<"$(_all_pass_report)")" \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no usable .overall verdict"* ]]
}

# ─── redaction ──────────────────────────────────────────────────────────────

@test "a secret smuggled into .overall is redacted in the refusal it causes" {
  _write "$(jq -c '.overall = "ghp_0123456789abcdefghij"' <<<"$(_all_pass_report)")" \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  refute_grep 'ghp_0123456789abcdefghij' <<<"$output"
}

@test "aid_gate_outcome_redact is the callable entry point the fallback card must use" {
  run aid_gate_outcome_redact 'gate output: token=ghp_0123456789abcdefghij failed'
  [ "$status" -eq 0 ]
  [[ "$output" != *"ghp_0123456789abcdefghij"* ]]
  [[ "$output" == *"<redacted:"* ]]
}

@test "a secret in the failing gate's exit_code or name is redacted in the card" {
  local gates
  gates="$(jq -nc '{tests: {gate:"tests", result:"fail", reason:"",
                            exit_code:"ghp_ABCDEFGHIJKLMNOPQRSTUV",
                            duration_ms:5000, output:"", attempts:1}}')"
  _write "$(_report fail "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == Zastaveno:* ]]
  [[ "$output" != *"ghp_ABCDEFGHIJKLMNOPQRSTUV"* ]]
  [[ "$output" == *"<redacted:github_token>"* ]]
  gates="$(jq -nc --argjson a "$(_row "leak-ghp_0123456789abcdefghij" fail 1 10 1)" '{leaky:$a}')"
  _write "$(_report fail "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  refute_grep -qF 'ghp_0123456789abcdefghij' <<<"$output"
}

# ─── "did not run" versus "failed" is a mapping, not a guess (P089 Step 3) ──

@test "a fail row whose reason means the harness stopped it counts as not-run" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests pass 0 1000 1)" \
    --argjson b "$(_row build fail 1 0 0 service_unhealthy)" \
    '{tests:$a, build:$b}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$(_counts)" == *"(selhalo 0, neběželo 1, prominuto 0)." ]]
}

@test "a fail row with an unknown reason counts as a failure, conservatively" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests fail 1 1000 1 disk_full)" --argjson b "$(_row lint pass 0 10 1)" '{tests:$a, lint:$b}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$(_counts)" == *"(selhalo 1, neběželo 0, prominuto 0)." ]]
}

@test "a run blocked by nothing but infrastructure says so instead of reading green" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests fail 1 0 0 service_unhealthy)" '{tests:$a}')"
  _write "$(_report fail "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"neselhala žádná brána, ale 1 jich neproběhlo"* ]]
}

# ── the classification stream cannot be silenced or forged (Codex, P089) ──

@test "a _command_log entry with no name does not zero every counter" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row tests pass 0 1000 1)" '{tests:$a}')"
  extra='{"_command_log":[{"command":"bats scripts/tests"}]}'
  _write "$(_report pass "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ověřeno: 1 z 1 bran"* ]]
}

@test "a unit separator inside a gate name cannot forge a field boundary" {
  local gates
  gates="$(jq -nc '{"g": {gate:"gate\u001fpass", result:"fail", reason:"", exit_code:1, duration_ms:10, attempts:1, output:""}}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  # Still ONE failure. Read as a forged boundary, `pass` became the result.
  [[ "$(_counts)" == "Ověřeno: 0 z 1 bran"*"(selhalo 1, "* ]]
}
