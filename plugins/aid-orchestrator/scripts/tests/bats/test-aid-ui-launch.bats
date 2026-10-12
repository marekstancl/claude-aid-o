#!/usr/bin/env bats
# aid-tier: t1
# P113a step 7 - aid-ui-launch.py: the launch inputs of the type on one card; public facts recorded with source and
# date, the rest supplied by the client; one answer confirms the found ones and turns everything missing into open
# items with owner and due date, critical ones blocking publication; an answer to an older list or a used one counts
# for nothing.

setup() {
  SC="$BATS_TEST_DIRNAME/../.."; L="$SC/aid-ui-launch.py"; P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P"
  export AID_UI_STATE_DIR="$BATS_TEST_TMPDIR/st"
  "$SC/aid-ui-state.sh" init "$P" >/dev/null
  ST="$P/docs/design/brand-state.json"
}
answer() {   # answer <qid> <decision> [target]
  jq --arg q "$1" --arg d "$2" --arg t "${3:-$(python3 "$L" question "$P" | jq -r .target)}" \
    '.answers[$q] = {kind: "launch_inputs", decision: $d, target: $t, comment: "x"}' "$ST" > "$ST.t" && mv "$ST.t" "$ST"
}

@test "card, lookups with source and date, the question, one confirmation into open items" {
  run python3 "$L" card "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '(.items | length) == 7 and (.items[] | select(.id == "company") | .status == "needed") and (.items[] | select(.id == "photos") | .status == "client")' "$P/.aid-ui/launch.json" >/dev/null
  run python3 "$L" record "$P" photos --value x --source y --date 2026-10-12; [ "$status" -eq 1 ]   # the client's, not looked up
  run python3 "$L" record "$P" company --value "IČO 12345678" --source "https://www.orsr.sk/x"; [ "$status" -eq 2 ]
  python3 "$L" record "$P" company --value "Coufal Clinic s.r.o., IČO 12345678" --source "https://www.orsr.sk/x" --date 2026-10-12 >/dev/null
  python3 "$L" card "$P" >/dev/null   # a refresh keeps what was found
  jq -e '.items[] | select(.id == "company") | .status == "found" and .date == "2026-10-12"' "$P/.aid-ui/launch.json" >/dev/null
  q="$(python3 "$L" question "$P")"
  jq -e '.kind == "launch_inputs" and .part == "podklady" and (.target | startswith("launch@")) and (.body | contains("orsr.sk")) and (.body | contains("bez toho web nezveřejníme"))' <<<"$q" >/dev/null
  # an answer for an older list does not count; a return changes nothing and is used once
  answer old approve "launch@0000"; run python3 "$L" confirm "$P" --answer old; [ "$status" -eq 1 ]; [[ "$output" == *"not for this list"* ]]
  answer r1 return; run python3 "$L" confirm "$P" --answer r1; [ "$status" -eq 0 ]; [ "$(jq '.open_items // [] | length' "$ST")" -eq 0 ]
  run python3 "$L" confirm "$P" --answer r1; [ "$status" -eq 1 ]; [[ "$output" == *"already used"* ]]
  answer a1 approve; run python3 "$L" confirm "$P" --answer a1; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.items[] | select(.id == "company") | .status == "confirmed"' "$P/.aid-ui/launch.json" >/dev/null
  yq -e '.launch_company.value == "Coufal Clinic s.r.o., IČO 12345678" and .launch_company.source == "https://www.orsr.sk/x" and .launch_company.read_at == "2026-10-12" and .launch_company.confirmed_by == "klient"' "$P/docs/content/facts.yaml" >/dev/null
  # six missing items became open items, all critical (an unconfirmed fact is only ever a critical item); the form is the agent's
  jq -e '(.open_items | length) == 6 and ([.open_items[] | select(.critical)] | length) == 6 and (.open_items[] | select(.text | startswith("Příjem zpráv")) | .owner == "agent")
         and (.open_items[] | select(.text | startswith("Ceník")) | .critical == true) and ([.open_items[] | .due | test("^[0-9]{4}-")] | all)' "$ST" >/dev/null
  # a second card run keeps the items' open-item ids; no duplicate items on a later confirmation
  python3 "$L" card "$P" >/dev/null; answer a2 approve; python3 "$L" confirm "$P" --answer a2 >/dev/null
  [ "$(jq '.open_items | length' "$ST")" -eq 6 ]
}
