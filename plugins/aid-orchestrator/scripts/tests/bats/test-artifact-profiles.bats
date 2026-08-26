#!/usr/bin/env bats
# aid-tier: t0
# test-artifact-profiles.bats — a page must carry what its TYPE owes
# (P089 Step 2).
#
# The four things a machine can decide, and nothing beyond them: a required
# field is absent; the type is not one of the five; the result sentence
# disagrees with the counts it was derived from; a link block carries a file
# path. Whether the page is any GOOD is a reader's judgement and no test here
# claims otherwise.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  OUT="$TEST_EVIDENCE_DIR/page.html"
  export OUT
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-artifact-render.sh"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixtures ───────────────────────────────────────────────────────────────

# A complete `plan` page. Every case below starts here and breaks ONE thing, so
# a failure names the thing it broke rather than the fixture.
_plan_facts() {
  jq -n '{
    artifact_type: "plan",
    eyebrow: "Nový plán", title: "Plán P089", when: "26. 8. 2026",
    tiles: {
      result:     {value: "Střední ceremonie", state: "ok"},
      duration:   {value: "11"},
      scope:      {value: "23"},
      unresolved: {value: "4", state: "warn"}
    },
    items: ["Rozsah: 11 kroků"],
    deliverables: [{epic: "EPIC 1", steps: [{n: "1", text: "kontrakt", acs: "4"}]}],
    links: ["Plán P089"],
    footer: "Vyrobil test."
  }'
}

# A complete `gates` page: the four counts, and NO result tile — the renderer
# composes that one.
_gates_facts() {
  local passed="${1:-6}" failed="${2:-0}" not_run="${3:-3}" waived="${4:-0}"
  jq -n --arg p "$passed" --arg f "$failed" --arg n "$not_run" --arg w "$waived" '{
    artifact_type: "gates",
    eyebrow: "Brány", title: "Běh bran", when: "26. 8. 2026",
    outcome: {
      passed_count: ($p|tonumber), failed_count: ($f|tonumber),
      not_run_count: ($n|tonumber), waived_count: ($w|tonumber)
    },
    tiles: {duration: {value: "3 min"}},
    items: ["scope-check ověřil rozsah commitu"],
    footer: "Vyrobil test."
  }'
}

_prose() {
  jq -n '{summary: "Shrnutí.", core: "Jádro.", ask: "Přečti plán."}'
}

# ─── a required field of the type is missing ────────────────────────────────

@test "profile: a plan page without deliverables does not render" {
  local facts; facts="$(_plan_facts | jq 'del(.deliverables)')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"artifact_type 'plan' requires"* ]]
  [[ "$output" == *"deliverables"* ]]
  [ ! -f "$OUT" ]
}

@test "profile: an empty required list counts as missing, not as present" {
  local facts; facts="$(_plan_facts | jq '.items = []')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"items"* ]]
}

@test "profile: a complete plan page renders" {
  run aid_artifact_render outcome "$(_plan_facts)" "$(_prose)" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "Plán P089" "$OUT"
}

# ─── the type itself ────────────────────────────────────────────────────────

@test "profile: an unknown artifact_type is an error and names the five" {
  local facts; facts="$(_plan_facts | jq '.artifact_type = "incident"')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown artifact_type 'incident'"* ]]
  [[ "$output" == *"brainstorming"* ]]
  [ ! -f "$OUT" ]
}

@test "profile: a caller with no artifact_type still renders and says so" {
  local facts; facts="$(_plan_facts | jq 'del(.artifact_type) | del(.deliverables)')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"declares no artifact_type"* ]]
}

# ─── the result sentence is DERIVED, so it cannot disagree ──────────────────

@test "profile: zero failures never produce the language of failure" {
  run aid_artifact_render outcome "$(_gates_facts 6 0 3 0)" "$(_prose)" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "Nic neselhalo" "$OUT"
  grep -q "state-ok" "$OUT"
  # The rejected headline: "6 of 9 passed" while nothing failed.
  ! grep -q "6/9" "$OUT"
  grep -q "Neběželo" "$OUT"
}

@test "profile: failures are counted, declined and marked critical" {
  run aid_artifact_render outcome "$(_gates_facts 6 2 1 0)" "$(_prose)" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "2 brány selhaly" "$OUT"
  grep -q "state-critical" "$OUT"
}

@test "profile: a caller's own result tile is dropped, not trusted" {
  local facts; facts="$(_gates_facts 6 0 3 0 | jq '.tiles.result = {value: "6/9 prošlo", state: "ok"}')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 0 ]
  ! grep -q "6/9 prošlo" "$OUT"
  grep -q "Nic neselhalo" "$OUT"
}

@test "profile: a waiver is named on the result tile and never counted as a pass" {
  run aid_artifact_render outcome "$(_gates_facts 6 0 0 1)" "$(_prose)" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "1 prominuta" "$OUT"
  grep -q "state-warn" "$OUT"
  grep -q "6 bran" "$OUT"
}

@test "profile: a type that derives from state and carries no counts is refused" {
  local facts; facts="$(_gates_facts | jq 'del(.outcome.waived_count)')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outcome.waived_count"* ]]
}

# ─── blocks 5 and 7 name things ─────────────────────────────────────────────

@test "profile: a file path in block 5 is refused" {
  local facts; facts="$(_plan_facts | jq '.links = ["plugins/aid-orchestrator/scripts/lib/aid-artifact-render.sh"]')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"block 5 carries a file path"* ]]
}

@test "profile: a file path in block 7 is refused" {
  local facts; facts="$(_plan_facts | jq '.detail = {label: "/opt/eco/projects/aid-orchestrator/report.md"}')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"block 7 carries a file path"* ]]
}

@test "profile: a name that merely contains a slash is not a path" {
  local facts; facts="$(_plan_facts | jq '.links = ["Plán P089 — 11 kroků / 3 EPIKY"]')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 0 ]
}

@test "profile: block 5 may not repeat the detail target" {
  local facts; facts="$(_plan_facts | jq '.links = ["Plán P089"] | .detail = {label: "Plán P089"}')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"repeats the detail target"* ]]
}

# ─── the one contradiction between fields ───────────────────────────────────

@test "profile: nothing-expected may not stand beside a list of next steps" {
  local facts; facts="$(_plan_facts | jq '.next_steps = ["spusť generaci EPIKŮ"]')"
  local prose; prose="$(jq -n '{summary: "S.", core: "C.", ask: ""}')"
  run aid_artifact_render outcome "$facts" "$prose" "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing is expected while 1 next step"* ]]
}
