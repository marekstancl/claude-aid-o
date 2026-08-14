#!/usr/bin/env bats
# aid-tier: t1
# test-aid-gate-outcome-summary.bats — fixtures for the gate/waiver outcome
# renderer (P080 Step 11).
#
# TESTABILITY BOUNDARY, STATED EXPLICITLY
#   aid_gate_outcome_render writes an artifact BODY and prints a chat card.
#   It never publishes. Publication through the Artifact tool is the
#   controller's live, session-level act, wired in commands/aid-run.md and
#   skills/pipeline.md — nothing in this suite covers or claims it.
#
# THE RULE THIS SUITE EXISTS FOR
#   A waiver is PM risk acceptance, never a pass. The waiver's own rendered
#   result item carries `waived` and carries NO pass label — Czech forms
#   included, because these surfaces are Czech and `passed` alone was a guard
#   against a word the renderer would never have written anyway.
#
# NEGATIVE ASSERTIONS USE refute_grep, NOT `! grep`
#   `! grep -q …` cannot fail a bats case: bash exempts a `!`-inverted command
#   from `set -e` and bats' ERR trap inherits the exemption. Every `! grep`
#   line in this file was inert. See refute_grep in test-helpers.bash.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUN_DIR="$TEST_TMPDIR/run"
  mkdir -p "$RUN_DIR/gates" "$RUN_DIR/waivers"
  export RUN_DIR
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-gate-outcome-summary.sh"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixture builders ───────────────────────────────────────────────────────

# _row <gate> <result> <exit> <ms> <attempts>
_row() {
  jq -nc --arg g "$1" --arg r "$2" --argjson e "$3" --argjson d "$4" --argjson a "$5" \
    '{gate:$g, result:$r, reason:"", exit_code:$e, duration_ms:$d, output:"", attempts:$a}'
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

# _pos <file> <needle> — byte offset of the first occurrence, the same
# order-assert technique test-aid-artifact-render.bats uses for the 7 blocks.
_pos() { grep -abo -F -e "$2" "$1" | head -1 | cut -d: -f1; }

# _assert_seven_blocks <body> — the ecosystem block order, structurally.
_assert_seven_blocks() {
  local f="$1" p1 p2 p3 p4 p5 p6 p7
  p1="$(_pos "$f" '<header class="masthead">')"
  p2="$(_pos "$f" '<section class="tiles">')"
  p3="$(_pos "$f" '<h2>Shrnutí</h2>')"
  p4="$(_pos "$f" '<h2>Jádro</h2>')"
  p5="$(_pos "$f" '<h2>Čeho se to týká</h2>')"
  p6="$(_pos "$f" '<h2>Co se čeká ode mě</h2>')"
  p7="$(_pos "$f" 'class="golink"')"
  for v in "$p1" "$p2" "$p3" "$p4" "$p5" "$p6" "$p7"; do [ -n "$v" ]; done
  [ "$p1" -lt "$p2" ]; [ "$p2" -lt "$p3" ]; [ "$p3" -lt "$p4" ]
  [ "$p4" -lt "$p5" ]; [ "$p5" -lt "$p6" ]; [ "$p6" -lt "$p7" ]
}

BODY() { printf '%s' "$RUN_DIR/gate-outcome-artifact.html"; }

# ─── fixture class 1: all pass ──────────────────────────────────────────────

@test "an all-pass report renders the Finished card and computed tile counts" {
  _write "$(_all_pass_report)" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]

  [[ "$output" == Hotovo:* ]]
  [[ "$output" == *"2 z 2 prošlo"* ]]
  [[ "$output" != *Zastaveno:* ]]
  [[ "${output##*$'\n'}" == "Artifact: $(BODY)" ]]

  # Tiles are DERIVED: 120000 ms of gate time is 2 min, not a claim.
  grep -qF '<span class="v">2/2 prošlo</span>' "$(BODY)"
  grep -qF '<span class="k">Trvalo</span><span class="v">2 min 0 s</span>' "$(BODY)"
  grep -qF '<span class="k">Rozsah</span><span class="v">2</span>' "$(BODY)"
  grep -qF '<span class="k">Neuzavřeno</span><span class="v">0</span>' "$(BODY)"
}

@test "the rendered artifact carries all seven blocks in the standard's order" {
  _write "$(_all_pass_report)" "$RUN_DIR/gates/gates_report.json"
  aid_gate_outcome_render "" "$RUN_DIR"
  _assert_seven_blocks "$(BODY)"
}

# ─── fixture class 2: a failed required gate ────────────────────────────────

@test "a failed required gate renders the Blocked card naming the gate and the smallest recovery action" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests fail 1 5000 2)" --argjson b "$(_row lint pass 0 1000 1)" \
    '{tests:$a, lint:$b}')"
  _write "$(_report fail "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]

  [[ "$output" == Zastaveno:* ]]
  [[ "$output" == *"brána tests selhala (exit 1)"* ]]
  # The recovery line is the gate's OWN command from _command_log — never an
  # invented remediation, because no gate definition carries one.
  [[ "$output" == *"Doporučené řešení: zopakuj bránu příkazem \`bats scripts/tests\`"* ]]
  [[ "$output" == *"aid-fsm.sh transition GATES DONE <state_file> --force --reason"* ]]

  grep -qF '<span class="v">1/2 prošlo</span>' "$(BODY)"
  grep -qF '<span class="k">Neuzavřeno</span><span class="v">1</span>' "$(BODY)"
}

# ─── fixture class 3: waived — the D3 rule ──────────────────────────────────

@test "a waived gate renders as PM risk acceptance, never as a pass" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row tests waived 1 5000 3)" --argjson b "$(_row lint pass 0 1000 1)" \
    '{tests:($a + {waiver_ref:"waivers/gate-waiver-tests.json"}), lint:$b}')"
  extra='{"waived_gates":["tests"]}'
  _write "$(_report pass "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]

  grep -qF 'brána tests: waived — PM převzal riziko' "$(BODY)"
  [[ "$output" == *"waived"* ]]

  # "NEVER AS A PASS" IS A CLAIM ABOUT LABELS, NOT ABOUT ONE ENGLISH WORD.
  # This used to forbid only the literal `passed`, on surfaces that are written
  # in Czech throughout — a row labelled `prošla` would have satisfied it while
  # saying exactly the thing the case is named for. The negative is now scoped
  # to the waived gate's own result item (the page is one long line, so the
  # unit is the <li>, and a document-wide grep would collide with the entirely
  # legitimate "1/2 prošlo" count tile) and covers the Czech forms.
  local waived_li
  waived_li="$(grep -oE '<li>[^<]*</li>' "$(BODY)" | grep -F 'waived')"
  [[ "$waived_li" == *"tests"* ]]
  refute_grep -qiE 'passed|prošl[aoyi]|prošel|úspěch|success' <<<"$waived_li"
  # `OK` is matched case-SENSITIVELY and as a whole word: folded to lowercase
  # it hits inside ordinary Czech words such as "krok".
  refute_grep -qE '\b(OK|PASS|PASSED)\b|✅' <<<"$waived_li"

  local waived_card
  waived_card="$(grep -F 'waived' <<<"$output")"
  [ -n "$waived_card" ]
  refute_grep -qiE 'passed|prošl[aoyi]|prošel|úspěch|success' <<<"$waived_card"
  refute_grep -qE '\b(OK|PASS|PASSED)\b|✅' <<<"$waived_card"

  # A waived gate is unresolved, not a pass: 1 of 2 actually passed.
  grep -qF '<span class="v">1/2 prošlo</span>' "$(BODY)"
  grep -qF '<span class="k">Neuzavřeno</span><span class="v">1</span>' "$(BODY)"
}

@test "the report alone carries the waiver — no waiver directory is passed at all" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row tests waived 1 5000 3)" '{tests:$a}')"
  extra='{"waived_gates":["tests"]}'
  _write "$(_report pass "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  rm -rf "$RUN_DIR/waivers"

  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  grep -qF 'brána tests: waived — PM převzal riziko' "$(BODY)"
  refute_grep -qF 'passed' "$(BODY)"
}

@test "a waiver named only by waived_gates[] still renders — a missing row never hides it" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row lint pass 0 1000 1)" '{lint:$a}')"
  extra='{"waived_gates":["docs_updated"]}'
  _write "$(_report pass "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  grep -qF 'brána docs_updated: waived — PM převzal riziko' "$(BODY)"
}

@test "the waiver receipt enriches the line but is never the source of the waiver" {
  local gates extra
  gates="$(jq -nc --argjson a "$(_row tests waived 1 5000 1)" '{tests:$a}')"
  extra='{"waived_gates":["tests"]}'
  _write "$(_report pass "$gates" "$extra")" "$RUN_DIR/gates/gates_report.json"
  jq -nc '{gate_id:"tests", authorized_by:"PM", reason:"flaky suite, fixed in the next EPIC", expires_at:null, consumed:{at:null, by_run:null}}' \
    > "$RUN_DIR/waivers/gate-waiver-tests.json"

  run aid_gate_outcome_render "" "$RUN_DIR" "$RUN_DIR/waivers"
  [ "$status" -eq 0 ]
  grep -qF 'flaky suite, fixed in the next EPIC' "$(BODY)"
  grep -qF 'waived — PM převzal riziko' "$(BODY)"
}

@test "a rejected waiver renders in the failed section with its verdict word, never as waived-ok" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests fail 1 5000 1)" \
    '{tests:($a + {waiver_rejected:"expired"})}')"
  _write "$(_report fail "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]

  grep -qF 'brána tests: selhala (exit 1), výjimka zamítnuta — expired' "$(BODY)"
  [[ "$output" == Zastaveno:* ]]
  grep -qF '<span class="v">0/1 prošlo</span>' "$(BODY)"
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
  grep -qF 'brána lint: přeskočena' "$(BODY)"
  grep -qF 'brána build: mimo profil' "$(BODY)"
  grep -qF '<span class="k">Neuzavřeno</span><span class="v">0</span>' "$(BODY)"
}

@test "a FAILING non-required gate with overall pass still selects the Finished card" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests pass 0 1000 1)" --argjson b "$(_row docs_updated fail 1 500 1)" \
    '{tests:$a, docs_updated:$b}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]

  # The card follows .overall. Reading the row instead would tell the PM the
  # run is blocked while the FSM advances.
  [[ "$output" == Hotovo:* ]]
  [[ "$output" != *Zastaveno:* ]]
  grep -qF 'brána docs_updated: selhala (exit 1)' "$(BODY)"
}

@test "a retried gate surfaces its attempts in the core list, not in the tiles" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests pass 0 1000 3)" '{tests:$a}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  aid_gate_outcome_render "" "$RUN_DIR"

  grep -qF 'brána tests: prošla až na 3. pokus' "$(BODY)"
  grep -qF '<span class="k">Neuzavřeno</span><span class="v">0</span>' "$(BODY)"
}

# ─── edge: an empty profile ─────────────────────────────────────────────────

@test "a report with zero gates renders the Finished card, scope 0 and the explicit note" {
  _write "$(_report pass '{}')" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]

  [[ "$output" == Hotovo:* ]]
  [[ "$output" == *"0 z 0 prošlo"* ]]
  grep -qF '<span class="k">Rozsah</span><span class="v">0</span>' "$(BODY)"
  grep -qF 'profil nespustil žádnou bránu' "$(BODY)"
  _assert_seven_blocks "$(BODY)"
}

# ─── all three report locations, plus the escalation shape ──────────────────

@test "an explicit report path wins, and the provenance footer names it" {
  local other="$TEST_TMPDIR/somewhere-else.json"
  _write "$(_all_pass_report)" "$other"
  _write "$(_report fail "$(jq -nc --argjson a "$(_row tests fail 1 10 1)" '{tests:$a}')")" \
    "$RUN_DIR/gates/gates_report.json"

  run aid_gate_outcome_render "$other" "$RUN_DIR"
  [ "$status" -eq 0 ]
  # The explicit path was rendered, not the nested decoy.
  [[ "$output" == Hotovo:* ]]
  grep -qF "Zdroj: $other." "$(BODY)"
}

@test "the nested layout resolves when no explicit path is given" {
  _write "$(_all_pass_report)" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  grep -qF "Zdroj: $RUN_DIR/gates/gates_report.json." "$(BODY)"
}

@test "the flat layout resolves when the nested one does not exist" {
  rm -rf "$RUN_DIR/gates"
  _write "$(_all_pass_report)" "$RUN_DIR/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  grep -qF "Zdroj: $RUN_DIR/gates_report.json." "$(BODY)"
}

@test "the escalation-shaped variant renders and names the escalation" {
  local base merged
  base="$(_all_pass_report)"
  # Exactly lib/aid-run-gates-report.sh's merge: the full pass verbatim plus a
  # separate top-level escalation key nesting the targeted attempt.
  merged="$(jq -nc --argjson full "$base" --argjson targeted "$base" \
    '$full + {escalation:{triggered_by:"targeted_tests", reason:"exit_code 11: mapping_gap", targeted_run:$targeted}}')"
  _write "$merged" "$RUN_DIR/gates/gates_report.json"

  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 0 ]
  grep -qF 'eskalace targeted → full: exit_code 11: mapping_gap' "$(BODY)"
  grep -qF "Zdroj: $RUN_DIR/gates/gates_report.json." "$(BODY)"
}

# ─── error handling ─────────────────────────────────────────────────────────

@test "a missing report exits 1 with a one-line error and writes no artifact" {
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no gates report found"* ]]
  [ ! -f "$(BODY)" ]
}

@test "an invalid report exits 1 rather than rendering wrong numbers" {
  _write 'not json at all {' "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid gates report JSON"* ]]
}

@test "a report carrying no .gates data fails closed, not as an empty profile" {
  # `.gates` defaulted to `{}` made "no gate data in this file" read exactly
  # like the legitimate empty profile above — a confident "0 z 0 prošlo" over a
  # report nobody could vouch for. The two are different facts.
  _write '{"overall":"pass","epic_id":"E1"}' "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"carries no .gates object"* ]]
  [[ "$output" != *"0 z 0 prošlo"* ]]
  [ ! -f "$(BODY)" ]
}

@test "a gate map whose VALUE is not an object fails closed, not into blank counters" {
  # The outer-type check let this through: `.gates` IS an object. The row
  # conversion then died on it ("Cannot index string with string") and its
  # status was never read, so every counter came out empty and the card printed
  # `Hotovo: brány doběhly,  z  prošlo.` with exit 0 — a pass claimed over a
  # gate set nobody could enumerate.
  _write '{"overall":"pass","epic_id":"E1","gates":{"tests":"pass"}}' \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-object gate entries (tests)"* ]]
  [[ "$output" != *"Hotovo:"* ]]
  [[ "$output" != *" z  prošlo"* ]]
  [ ! -f "$(BODY)" ]
}

@test "one malformed entry among good ones is refused by name, never silently dropped" {
  local gates
  gates="$(jq -nc --argjson a "$(_row tests pass 0 1000 1)" '{tests:$a, lint:"pass"}')"
  _write "$(_report pass "$gates")" "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-object gate entries (lint)"* ]]
  # Never "1 z 1 prošlo" — dropping the row it cannot read would have counted a
  # one-gate pass over a two-gate report.
  [[ "$output" != *"prošlo"* ]]
  [ ! -f "$(BODY)" ]
}

@test "a report with no .overall fails closed — a missing verdict is not a pass" {
  # The card follows `.overall` and nothing else, so its ABSENCE decided the
  # message: `.overall // "unknown"` is not "fail", so blocked stayed 0 and a
  # report of two failing gates printed `Hotovo: brány doběhly`. The runner
  # writes exactly "pass" or "fail" (aid-run-gates.sh:2454, and :2613 for the
  # merged escalation shape); anything else is a report nobody can vouch for.
  local gates
  gates="$(jq -nc --argjson a "$(_row tests fail 1 1000 1)" --argjson b "$(_row lint fail 1 500 1)" \
    '{tests:$a, lint:$b}')"
  _write "$(jq -c 'del(.overall)' <<<"$(_report pass "$gates")")" \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no usable .overall verdict"* ]]
  [[ "$output" != *"Hotovo:"* ]]
  [ ! -f "$(BODY)" ]
}

@test "an unrecognised .overall value fails closed rather than defaulting to not-blocked" {
  _write "$(jq -c '.overall = "unknown"' <<<"$(_all_pass_report)")" \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no usable .overall verdict"* ]]
  [[ "$output" != *"Hotovo:"* ]]
  [ ! -f "$(BODY)" ]
}

@test "a secret smuggled into .overall is redacted in the refusal it causes" {
  _write "$(jq -c '.overall = "ghp_0123456789abcdefghij"' <<<"$(_all_pass_report)")" \
    "$RUN_DIR/gates/gates_report.json"
  run aid_gate_outcome_render "" "$RUN_DIR"
  [ "$status" -eq 1 ]
  refute_grep 'ghp_0123456789abcdefghij' <<<"$output"
}

# ─── the fallback path's redactor is callable, and it redacts ───────────────

@test "aid_gate_outcome_redact is the callable entry point the fallback card must use" {
  run aid_gate_outcome_redact 'gate output: token=ghp_0123456789abcdefghij failed'
  [ "$status" -eq 0 ]
  [[ "$output" != *"ghp_0123456789abcdefghij"* ]]
  [[ "$output" == *"<redacted:"* ]]
}

@test "a secret in the failing gate's exit_code is redacted in the CHAT CARD" {
  # exit_code is a passthrough of a report field, not a number this file
  # computed, so it is input like any other. The card redacted the gate name and
  # the reproduction command beside it and printed this one verbatim.
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
}

@test "a secret reaching the renderer through a gate name is redacted and counted" {
  local gates
  gates="$(jq -nc --argjson a "$(_row "leak-ghp_0123456789abcdefghij" fail 1 10 1)" '{leaky:$a}')"
  _write "$(_report fail "$gates")" "$RUN_DIR/gates/gates_report.json"
  aid_gate_outcome_render "" "$RUN_DIR"

  refute_grep -qF 'ghp_0123456789abcdefghij' "$(BODY)"
  grep -qE 'Redigováno tajemství: [1-9]' "$(BODY)"
}
