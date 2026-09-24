#!/usr/bin/env bats
# aid-tier: t2
# test-artifact-profiles.bats — a page must carry what its TYPE owes
# (P089 Step 2).
#
# The things a machine can decide, and nothing beyond them: a required field
# is absent; the type is not one of the three; a link block carries a file
# path; block 6 contradicts the next steps. Whether the page is any GOOD is a reader's judgement and no test here
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

@test "profile: an unknown artifact_type is an error and names the three" {
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

# ─── the whole caller set, not one caller at a time ─────────────────────────
#
# WHY THESE ARE HERE AND NOT IN EACH CALLER'S OWN SUITE. Both claims below are
# about the SET: "no production caller is left on the typeless path" and "the
# caps are the renderer's, not each caller's". A per-caller suite can only ever
# say something about its own caller, and a fifth caller added tomorrow would
# arrive with its own green suite and no one noticing.

@test "every production caller of aid_artifact_render declares an artifact_type" {
  local lib="$AID_PLUGIN_PATH/scripts/lib"
  local callers=() f
  while IFS= read -r f; do
    # The renderer itself defines the function; it does not call it.
    [[ "$(basename "$f")" == "aid-artifact-render.sh" ]] && continue
    callers+=("$f")
  done < <(grep -rl 'aid_artifact_render ' "$lib" --include='*.sh')

  # Three since P099: plan, plan close, brainstorming.
  [ "${#callers[@]}" -eq 3 ]
  for f in "${callers[@]}"; do
    grep -q 'artifact_type' "$f" || {
      echo "no artifact_type in $(basename "$f") — it is still on the transitional typeless path" >&2
      return 1
    }
  done
}

@test "the caps are the renderer's numbers, and no caller builds its own list markup" {
  [ "$_AID_ARTIFACT_CAP_ITEMS" -eq 5 ]
  [ "$_AID_ARTIFACT_CAP_NEXT" -eq 3 ]
  [ "$_AID_ARTIFACT_CAP_LINKS" -eq 5 ]
  [ "$_AID_ARTIFACT_CAP_SENTENCE" -eq 220 ]
  [ "$_AID_ARTIFACT_CAP_SUMMARY" -eq 320 ]

  # A caller that emitted its own <li> would route around every cap above.
  # This is what per-caller repetition of an over-limit fixture would actually
  # be probing for, said once and over the whole set.
  local lib="$AID_PLUGIN_PATH/scripts/lib" f
  while IFS= read -r f; do
    [[ "$(basename "$f")" == "aid-artifact-render.sh" ]] && continue
    refute_grep -qE '<(li|ul|ol)[ >]' "$f"
  done < <(grep -rl 'aid_artifact_render ' "$lib" --include='*.sh')
}

@test "an over-limit page is cut and says how much it dropped" {
  local facts
  facts="$(_plan_facts | jq '
    .items = ["a","b","c","d","e","f","g","h","i"]
    | .links = ["Plán A","Plán B","Plán C","Plán D","Plán E","Plán F","Plán G"]')"
  run aid_artifact_render outcome "$facts" "$(_prose)" "$OUT"
  [ "$status" -eq 0 ]
  # 5 items + 5 links + the one deliverable step, which is a DELIBERATE
  # exception to the item cap: block 4b lists every step, because a collapsed
  # tail hides exactly the part a PM opens the page to judge (see the renderer).
  [ "$(grep -oF '<li>' "$OUT" | wc -l)" -eq 11 ]
  grep -qF 'a dalších 4 v technickém detailu' "$OUT"
  grep -qF 'a dalších 2 v technickém detailu' "$OUT"
}
