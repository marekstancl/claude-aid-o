#!/usr/bin/env bats
# aid-tier: t1
# P103 Step 2 — aid-ui-coverage.sh: item ids, map check exit codes, and a report where
# every disposition kind reads its own evidence.

setup() {
  COV="$BATS_TEST_DIRNAME/../../aid-ui-coverage.sh"
  FX="$BATS_TEST_DIRNAME/../fixtures/aid-ui/coverage"
  T="$BATS_TEST_TMPDIR"
  SPECS="$T/docs/ecosystem/specs"
  P="$T/proj"
  mkdir -p "$SPECS" "$P/.aid-o/config" "$P/docs/design"
  cp "$FX/a.md" "$FX/b.md" "$SPECS/"
  touch "$SPECS/standards-map.md"
  printf 'standards:\n  map_path: %s\n' "$SPECS/standards-map.md" > "$P/.aid-o/config/project.yaml"
  cp "$FX/map.yaml" "$FX/checks.yaml" "$T/"
  export AID_UI_COVERAGE_MAP="$T/map.yaml" AID_UI_COVERAGE_SOURCES="$FX/sources.yaml"
  A='ecosystem/specs/a.md#Standard A > Rules'
}

# state <variant> [build id] [answers json] [attestations json]
state() {
  printf '{"variant":{"type":"%s"},"build":{"id":"%s"},"answers":%s,"attestations":%s}\n' \
    "$1" "${2:-b1}" "${3:-"{}"}" "${4:-"{}"}" > "$P/docs/design/brand-state.json"
}

# gate <build id> <status of every row>
gate() {
  mkdir -p "$P/.aid-ui/verify"
  printf '{"build_id":"%s","rows":[{"check":"http_200","page":"/","viewport":390,"browser":"chromium","status":"%s"},{"check":"http_200","page":"/","viewport":1440,"browser":"webkit","status":"%s"}]}\n' \
    "$1" "$2" "$2" > "$P/.aid-ui/verify/result.json"
}

# row <item text> — the report line of that item
row() { grep -F "| $1 |" "$P/docs/design/soulad-se-standardy.md"; }

@test "extract: stable ids, duplicate suffix, table rows and bold rules, no code or header rows" {
  run bash "$COV" extract "$P"
  [ "$status" -eq 0 ]
  first="$output"
  run bash "$COV" extract "$P"
  [ "$output" = "$first" ]
  [[ "$output" == *"$A#923b9432	The page answers 200."* ]]
  [[ "$output" == *"$A#9181728b-2	Same text."* ]]
  [[ "$output" == *"The agent checks keyboard focus and the focus order."* ]]
  [[ "$output" == *"T-1 | contrast is checked"* ]]
  [[ "$output" == *"**R-9 Prose rule.** A rule written as a paragraph."* ]]
  [[ "$output" != *"not an item"* ]]
  [[ "$output" != *"Rule | Meaning"* ]]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 9 ]
}

@test "check: the fixture map covers every item -> exit 0" {
  run bash "$COV" check "$P"
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage ok: 9 items"* ]]
}

@test "check: an item missing from the map -> exit 1 naming it" {
  printf -- '- A brand new rule.\n' >> "$SPECS/b.md"
  run bash "$COV" check "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing in map: ecosystem/specs/b.md#Standard B > App#"*"A brand new rule."* ]]
}

@test "check: changed text -> exit 3 naming the item" {
  sed -i 's/The owner approves every page./The owner approves each page./' "$SPECS/a.md"
  run bash "$COV" check "$P"
  [ "$status" -eq 3 ]
  [[ "$output" == *"changed: $A#f2add2b3 -> $A#"*"The owner approves each page."* ]]
}

@test "check: a renamed heading with the same text -> exit 3 reported as moved" {
  sed -i 's/^## Table$/## Tables/' "$SPECS/a.md"
  run bash "$COV" check "$P"
  [ "$status" -eq 3 ]
  [[ "$output" == *"moved: ecosystem/specs/a.md#Standard A > Table#f14dc344 -> ecosystem/specs/a.md#Standard A > Tables#f14dc344"* ]]
}

@test "check: a removed item -> exit 1, no longer in the standard" {
  sed -i '/Deployment is out of scope/d' "$SPECS/a.md"
  run bash "$COV" check "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no longer in the standard: $A#ca072b02"* ]]
}

@test "check: a script: name not in checks.yaml -> exit 1" {
  sed -i 's/script:http_200/script:no_such_check/' "$T/map.yaml"
  run bash "$COV" check "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"script:no_such_check is not a check"* ]]
}

@test "check: na: without a reason -> exit 1" {
  sed -i 's/"na: deployment is not a goal of \/aid-ui"/"na:  "/' "$T/map.yaml"
  run bash "$COV" check "$P"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid entry $A#ca072b02"* ]]
}

@test "check: an unreadable standard -> exit 2" {
  rm "$SPECS/b.md"
  run bash "$COV" check "$P"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ecosystem/specs/b.md cannot be read"* ]]
}

@test "check: a configured map that cannot be read -> exit 2" {
  rm "$SPECS/standards-map.md"
  run bash "$COV" check "$P"
  [ "$status" -eq 2 ]
}

@test "report web: app-only items omitted, na shown with its reason, counts in the summary" {
  state web
  run bash "$COV" report "$P"
  [ "$status" -eq 0 ]
  md="$P/docs/design/soulad-se-standardy.md"
  row "Deployment is out of scope." | grep -q "nepoužito, protože deployment is not a goal of /aid-ui"
  run grep -q "Only applications have task states" "$md"
  [ "$status" -eq 1 ]
  run jq -r '[.variant, .total, .counts["nepoužito"], .counts["neověřeno"]] | @tsv' "$P/docs/design/soulad-summary.json"
  [ "$output" = "web	8	3	5" ]
}

@test "report webapp: the app-only item is listed" {
  state webapp
  run bash "$COV" report "$P"
  [ "$status" -eq 0 ]
  row "Only applications have task states." | grep -q "neověřeno"
  [ "$(jq .total "$P/docs/design/soulad-summary.json")" -eq 9 ]
}

@test "report: agent: without attestation and pm: without an answer -> neověřeno, even with a passing gate" {
  state web b1 '{"q1":{"kind":"approve_page","decision":"reject"}}'
  gate b1 pass
  bash "$COV" report "$P"
  row "The agent checks keyboard focus and the focus order." | grep -q "| neověřeno |"
  row "The owner approves every page." | grep -q "| neověřeno |"
  row "The page answers 200." | grep -q "použito, ověřil skript"
}

@test "report: an attestation -> ověřil agent; an approving pm answer of that kind -> rozhodl PM" {
  state web b1 '{"q1":{"kind":"approve_page","decision":"approve"}}' "{\"$A#0ec58950\":{\"note\":\"walked\",\"at\":\"2026-09-27\"}}"
  bash "$COV" report "$P"
  row "The agent checks keyboard focus and the focus order." | grep -q "| ověřil agent |"
  row "The owner approves every page." | grep -q "použito, rozhodl PM"
}

@test "report: a pm answer of another kind does not count" {
  state web b1 '{"q1":{"kind":"direction","decision":"choose"}}'
  bash "$COV" report "$P"
  row "The owner approves every page." | grep -q "| neověřeno |"
}

@test "report: a script: item whose gate rows belong to another build -> neověřeno" {
  state web b2
  gate b1 pass
  bash "$COV" report "$P"
  row "The page answers 200." | grep -q "| neověřeno |"
}

@test "report: a failing gate row of the current build -> nesplněno" {
  state web b1
  gate b1 fail
  bash "$COV" report "$P"
  row "The page answers 200." | grep -q "nesplněno"
}

@test "report: failing rows all under a standing PM exception -> výjimka PM with its reason; a resolved one does not count" {
  state web b1
  gate b1 fail
  jq '.exceptions = [{"selector":{"check":"http_200","page":"*","viewport":"*","browser":"*","role":"*","state":"*"},"reason":"interní nástroj"}]' \
    "$P/docs/design/brand-state.json" > "$T/s.json" && mv "$T/s.json" "$P/docs/design/brand-state.json"
  bash "$COV" report "$P"
  row "The page answers 200." | grep -q "výjimka PM: interní nástroj"
  jq -e '.counts["výjimka PM"] >= 1' "$P/docs/design/soulad-summary.json" >/dev/null
  jq '.exceptions[0].resolved = "2026-09-28"' "$P/docs/design/brand-state.json" > "$T/s.json" && mv "$T/s.json" "$P/docs/design/brand-state.json"
  bash "$COV" report "$P"
  row "The page answers 200." | grep -q "nesplněno"
}

@test "report: an option the PM left out in step 0 waives its pm: items with the reason; with the option on they stay neověřeno" {
  yq -i '(.items[] | select(.do == "pm:approve_page")).do = "pm:vision"' "$T/map.yaml"
  state web b1
  bash "$COV" report "$P"
  grep "pm:vision" "$P/docs/design/soulad-se-standardy.md" | grep -q "neověřeno"
  jq '.options = {"vision": false, "seo": true, "identity": "new"}' "$P/docs/design/brand-state.json" > "$T/s.json" && mv "$T/s.json" "$P/docs/design/brand-state.json"
  bash "$COV" report "$P"
  grep "pm:vision" "$P/docs/design/soulad-se-standardy.md" | grep -q "vynechal vizi"
}

@test "report: no variant recorded -> exit 1, nothing written" {
  echo '{}' > "$P/docs/design/brand-state.json"
  run bash "$COV" report "$P"
  [ "$status" -eq 1 ]
  [ ! -e "$P/docs/design/soulad-se-standardy.md" ]
}
