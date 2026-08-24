#!/usr/bin/env bats
# aid-tier: t0
# test-decision-card.bats — the card that asks the PM for a decision (P086 Step 3).
#
# THE GROUNDED FAILURE MODE: skills/communication.md has carried card 2 as a
# MUST since 2026-08-12, and a turn that asked the PM to choose with no options
# and no recommendation broke it with no consequence, because nothing read the
# card. What is proved here is that the card is now ASSEMBLED — data without
# options cannot become one — and that the same defect is caught again on the
# written card after the fact.
#
# WHAT IS NOT PROVED, DELIBERATELY: that the options are any good. Nothing here
# can tell a real choice from two restatements of one, and a check that claimed
# to would be refusing turns on taste.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  GATE="$PLUGIN_ROOT/scripts/aid-turn-gate.sh"
  TMP="$(mktemp -d)"
  # shellcheck disable=SC1090
  source "$PLUGIN_ROOT/scripts/lib/aid-decision-card.sh"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

# data <json> — writes card data and echoes its path
data() { printf '%s' "$1" > "$TMP/data.json"; echo "$TMP/data.json"; }

COMPLETE='{"lang":"cs","question":"Pustit fail-closed hned?","why_now":"Jinak vrstva nemá zuby.",
  "options":[{"key":"A","text":"Až po kanárkovi","recommended":true,"reason":"neblokovat mechanismem, o kterém nevíme, jestli běží"},
             {"key":"B","text":"Hned, s vypínačem"}],
  "risk":"Kanárek na této verzi neběžel."}'

@test "a complete card renders every mandatory line" {
  run aid_decision_card_render "$(data "$COMPLETE")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Potřebuji tvoje rozhodnutí: Pustit fail-closed hned?"* ]]
  [[ "$output" == *"Doporučení: A — Až po kanárkovi"* ]]
  [[ "$output" == *"Důvod: neblokovat"* ]]
  [[ "$output" == *"Alternativy: B — Hned, s vypínačem"* ]]
}

@test "AC8: data with no options list is refused, naming the missing field" {
  run aid_decision_card_render "$(data '{"lang":"cs","question":"Co dál?"}')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"options"* ]]
  [[ "$output" == *"at least two"* ]]
}

@test "AC8: a recommendation with no reason is refused" {
  run aid_decision_card_render "$(data '{"lang":"cs","question":"Co dál?","options":[{"key":"A","text":"jedna","recommended":true},{"key":"B","text":"druhá"}]}')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no 'reason'"* ]]
}

@test "a card that recommends nothing, or everything, is refused" {
  run aid_decision_card_render "$(data '{"lang":"cs","question":"Co dál?","options":[{"key":"A","text":"jedna"},{"key":"B","text":"druhá"}]}')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exactly one option"* ]]

  run aid_decision_card_render "$(data '{"lang":"cs","question":"Co dál?","options":[{"key":"A","text":"jedna","recommended":true,"reason":"r"},{"key":"B","text":"druhá","recommended":true,"reason":"r"}]}')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exactly one option"* ]]
}

@test "a language with no labels is refused rather than rendered in another one" {
  run aid_decision_card_render "$(data '{"lang":"de","question":"Was nun?","options":[{"key":"A","text":"eins","recommended":true,"reason":"weil"},{"key":"B","text":"zwei"}]}')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no labels"* ]]
}

@test "more than five options is capped and the card says how many it dropped" {
  local many='{"lang":"en","question":"Which?","options":[
    {"key":"A","text":"one","recommended":true,"reason":"because"},
    {"key":"B","text":"two"},{"key":"C","text":"three"},{"key":"D","text":"four"},
    {"key":"E","text":"five"},{"key":"F","text":"six"},{"key":"G","text":"seven"}]}'
  run aid_decision_card_render "$(data "$many")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(+2)"* ]]
  [[ "$output" != *"seven"* ]]
}

@test "AC9: the gate refuses an incomplete written card, with no Stop event anywhere in sight" {
  aid_decision_card_render "$(data "$COMPLETE")" "$TMP/card.md"
  # A turn that edited the card down to a bare question — the defect the gate
  # exists for, in the form it survives a killed session in.
  grep -v -e '^Doporučení' -e '^Důvod' -e '^Alternativy' "$TMP/card.md" > "$TMP/bad.md"
  run bash "$GATE" --card "$TMP/bad.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"recommendation"* ]]
  [[ "$output" == *"alternatives"* ]]
}

@test "the gate passes a complete written card" {
  aid_decision_card_render "$(data "$COMPLETE")" "$TMP/card.md"
  run bash "$GATE" --card "$TMP/card.md"
  [ "$status" -eq 0 ]
}

@test "AC10: a turn that asks for nothing does not activate the check" {
  printf 'Hotovo: vrstva hooků je na místě.\nZměnilo se: nic pro PM.\n' > "$TMP/report.md"
  run bash "$GATE" --card "$TMP/report.md"
  [ "$status" -eq 0 ]
}

@test "an alternatives line that lists nothing is the same defect as a missing one" {
  printf 'Potřebuji tvoje rozhodnutí: Co dál?\nDoporučení: A — jedna\nDůvod: protože\nAlternativy:\n' > "$TMP/empty.md"
  run bash "$GATE" --card "$TMP/empty.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lists nothing"* ]]
}

@test "the Stop rule reads the transcript and refuses an incomplete card" {
  cat > "$TMP/transcript.jsonl" <<'JSONL'
{"type":"user","message":{"content":"jak dál?"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Potřebuji tvoje rozhodnutí: Co dál?\nProč teď: protože."}]}}
JSONL
  run bash -c "printf '{\"transcript_path\":\"$TMP/transcript.jsonl\"}' | AID_HOOK_EVENT=Stop bash -c 'source \"$PLUGIN_ROOT/scripts/lib/aid-decision-card.sh\"; aid_hook_rule_decision_card'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"incomplete"* ]]
}

@test "AC10: the Stop rule does not activate on a turn that reported something" {
  cat > "$TMP/transcript.jsonl" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"text","text":"Hotovo: vrstva je na místě."}]}}
JSONL
  run bash -c "printf '{\"transcript_path\":\"$TMP/transcript.jsonl\"}' | bash -c 'source \"$PLUGIN_ROOT/scripts/lib/aid-decision-card.sh\"; aid_hook_rule_decision_card'"
  [ "$status" -eq 3 ]
  [[ "$output" == *"does not ask for a decision"* ]]
}

@test "the Stop rule with no transcript is not applicable, never a refusal" {
  run bash -c "printf '{}' | bash -c 'source \"$PLUGIN_ROOT/scripts/lib/aid-decision-card.sh\"; aid_hook_rule_decision_card'"
  [ "$status" -eq 3 ]
}
