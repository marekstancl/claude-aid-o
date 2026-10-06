#!/usr/bin/env bats
# aid-tier: t0
# The independent critic (P107): the prompt is assembled by code from the
# interim's brief and purpose sections (never a cost figure), and the answer's
# shape is checked by code — two headings, at most five `**N.` items, no
# verdict outside level 2, every item answered once by the author, an accepted
# row naming what it was checked against. Defect it catches: a critic run that
# silently degrades to the first agents run ("do not build", no purpose).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH AID_TEST_MODE=1
  T="$(mktemp -d)"; P="$T/proj"
  mkdir -p "$P/.aid-o/work/plan-state" "$P/.aid-o/plans"
  git -C "$P" init -q
  export AID_PROJECT_ROOT="$P"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-critic.sh"
  cat > "$P/.aid-o/work/interim-P9.md" <<'EOF'
# Interim P9

## Zadání PM
- "chci kritika, který respektuje YAGNI"

## Účel a co je v sázce
1 040 nálezů, žádný neubírá.
Cena kol: 27,94 USD.
Přibylo 121 testů.
A 200 tokenů navíc.

## Návrh
Krok 1: role. Krok 2: skript.
EOF
  printf -- '---\nid: P9\n---\n# Plan: x\n' > "$P/.aid-o/plans/P9-x.md"
  D="$P/.aid-o/work/evidence/P9/critic"
}
teardown() { rm -rf "$T"; }

_answer() {  # <moment> <level1 body> [level2 body]
  mkdir -p "$D/$1"
  { echo "# Kritik"; echo; echo "### Úroveň 1 — Kritika návrhu, jak je zadaný"; echo; printf '%b\n' "$2"; echo
    echo "### Úroveň 2 — K zamyšlení: rozsah"; echo; printf '%b\n' "${3:-Tohle je námět pro PM. Nic k rozsahu nemám.}"; } > "$D/$1/critic.md"
}
_response() {  # <moment> <rows...>
  local m="$1"; shift
  { echo "| # | výtka | verdikt | kde |"; echo "|---|---|---|---|"; for r in "$@"; do echo "$r"; done; } > "$D/$m/critic-response.md"
}

@test "prepare: brief, purpose and proposal go in verbatim, cost lines are stripped and counted, the assumption sentence is there" {
  run aid_critic_prepare P9 --moment brainstorm
  [ "$status" -eq 0 ]; [[ "$output" == "$D/brainstorm/prompt.md" ]]
  grep -q 'chci kritika, který respektuje YAGNI' "$D/brainstorm/prompt.md"
  grep -q '1 040 nálezů' "$D/brainstorm/prompt.md"
  grep -q 'Krok 1: role' "$D/brainstorm/prompt.md"
  grep -q 'Předpokládej, že se to staví.' "$D/brainstorm/prompt.md"
  ! grep -q 'USD' "$D/brainstorm/prompt.md"
  ! grep -q 'tokenů' "$D/brainstorm/prompt.md"
  grep -q '2 cost line(s) stripped' "$D/brainstorm/prompt.md"
  ! grep -q '^name: critic' "$D/brainstorm/prompt.md"   # role frontmatter is not pasted
}

@test "prepare refuses an interim without the purpose section, and one with a duplicated brief heading" {
  sed -i '/^## Účel a co je v sázce/,/^## Návrh/{/^## Návrh/!d}' "$P/.aid-o/work/interim-P9.md"
  run aid_critic_prepare P9 --moment brainstorm
  [ "$status" -eq 3 ]; [[ "$output" == *'no "## Účel a co je v sázce" section'* ]]
  printf '\n## Účel a co je v sázce\nx\n\n## Zadání PM\n- dup\n' >> "$P/.aid-o/work/interim-P9.md"
  run aid_critic_prepare P9 --moment brainstorm
  [ "$status" -eq 3 ]; [[ "$output" == *'2 "## Zadání PM" headings'* ]]
  sed -i '/^## Zadání PM/,/^## /{/^## Účel/!d}' "$P/.aid-o/work/interim-P9.md"
  run aid_critic_prepare P9 --moment brainstorm
  [ "$status" -eq 3 ]; [[ "$output" == *'no "## Zadání PM" section'* ]]
}

@test "check: a plan edited between prepare and check is recorded as the one revision; rebind is then refused as a second" {
  aid_critic_prepare P9 --moment plan >/dev/null
  _answer plan 'Nenašel jsem nic.'; _response plan
  echo "edited" >> "$P/.aid-o/plans/P9-x.md"
  run aid_critic_check P9 --moment plan
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *"recorded as the one revision"* ]]
  [ "$(jq -r .plan_sha256_revised "$D/plan/check.json")" = "$(sha256sum "$P/.aid-o/plans/P9-x.md" | cut -d' ' -f1)" ]
  [ "$(jq -r .revised_before_check "$D/plan/check.json")" = true ]
  grep -q '"event":"critic_rebound"' "$P/.aid-o/work/evidence/P9/timeline.jsonl"
  echo "edited again" >> "$P/.aid-o/plans/P9-x.md"
  run aid_critic_rebind P9 --plan "$P/.aid-o/plans/P9-x.md"
  [ "$status" -eq 5 ]; [[ "$output" == *"already rebound"* ]]
  # a check that fails on form records no revision
  aid_critic_prepare P9 --moment plan >/dev/null
  _answer plan 'Nenašel jsem nic.'; _response plan
  echo "edited" >> "$P/.aid-o/plans/P9-x.md"; sed -i '/Úroveň 2/d' "$D/plan/critic.md"
  run aid_critic_check P9 --moment plan
  [ "$status" -eq 5 ]; [ "$(jq -r '.plan_sha256_revised // "none"' "$D/plan/check.json")" = none ]
}

@test "prepare at the plan moment names the plan file and points at the brainstorm answer; a second run supersedes the first" {
  run aid_critic_prepare P9 --moment plan
  [ "$status" -eq 0 ]
  grep -q 'P9-x.md' "$D/plan/prompt.md"; grep -q 'critic/brainstorm/' "$D/plan/prompt.md"
  run aid_critic_prepare P9 --moment plan
  [ "$status" -eq 0 ]
  run aid_critic_prepare P9 --moment plan
  [ "$status" -eq 0 ]
  [ "$(ls -d "$D"/plan.superseded-* | wc -l)" -eq 2 ]
  [ "$(jq -r .plan_sha256 "$D/plan/prepare.json")" = "$(sha256sum "$P/.aid-o/plans/P9-x.md" | cut -d' ' -f1)" ]
}

@test "check: a valid pair passes and writes check.json with the hashes and the timeline event" {
  aid_critic_prepare P9 --moment plan >/dev/null
  _answer plan '**1. Slib bez krytí.**\n- doloženo\n**2. Chybí případ.**\n- dojem'
  _response plan '| 1 | slib | PŘIJATO | `skills/x.md` |' '| 2 | případ | odmítnuto | není náš případ |'
  run aid_critic_check P9 --moment plan
  [ "$status" -eq 0 ]; [[ "$output" == *"2 item(s)"* ]]
  [ "$(jq -r .passed "$D/plan/check.json")" = "true" ]
  [ "$(jq -r .level1_items "$D/plan/check.json")" = "2" ]
  [ "$(jq -r .plan_sha256 "$D/plan/check.json")" = "$(sha256sum "$P/.aid-o/plans/P9-x.md" | cut -d' ' -f1)" ]
  [ "$(jq -r .response_sha256 "$D/plan/check.json")" = "$(sha256sum "$D/plan/critic-response.md" | cut -d' ' -f1)" ]
  [ "$(jq -r .level2_empty "$D/plan/check.json")" = "true" ]
  grep -q '"event":"critic_checked"' "$P/.aid-o/work/evidence/P9/timeline.jsonl"
}

@test "check refuses: a missing heading, six items, items not in the **N. form" {
  aid_critic_prepare P9 --moment brainstorm >/dev/null
  mkdir -p "$D/brainstorm"; printf '### Úroveň 1 — x\n**1. a**\n' > "$D/brainstorm/critic.md"
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"missing heading: level 2"* ]]
  _answer brainstorm '**1. a**\n**2. b**\n**3. c**\n**4. d**\n**5. e**\n**6. f**'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"6 items, at most five"* ]]
  _answer brainstorm '1. a\n2. b'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"prescribed item format"* ]]
  [ "$(jq -r .passed "$D/brainstorm/check.json")" = "false" ]
  _answer brainstorm '**2. a**\n**1. b**'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"numbered [2 1], expected 1..2"* ]]
  _answer brainstorm ''
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"level 1 is blank"* ]]
  _answer brainstorm 'Tohle je jedna věta, která neříká výsledek.'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"prescribed item format"* ]]
  { echo "### Úroveň 2 — x"; echo "nic"; echo "### Úroveň 1 — y"; echo "**1. a**"; } > "$D/brainstorm/critic.md"
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"level 2 comes before level 1"* ]]
}

@test "check refuses a verdict outside level 2 in any spelling or prefix, and allows the phrase inside level 2" {
  aid_critic_prepare P9 --moment brainstorm >/dev/null
  for line in 'Nestavět tohle.' '**2. Do not build the second half.**' '- nedělat krok 3'; do
    _answer brainstorm "**1. a**\n${line}"
    _response brainstorm '| 1 | a | odmítnuto | proč |'
    run aid_critic_check P9 --moment brainstorm
    [ "$status" -eq 5 ]; [[ "$output" == *"a verdict outside level 2"* ]]
  done
  _answer brainstorm '**1. a**' 'Námět pro PM: menší rozsah — nestavět krok 3 hned, odložit.'
  _response brainstorm '| 1 | a | odmítnuto | proč |'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 0 ]
}

@test "check refuses a response with a duplicated or unknown row number, a missing row, or an accepted row without a checked file" {
  aid_critic_prepare P9 --moment brainstorm >/dev/null
  _answer brainstorm '**1. a**\n**2. b**'
  _response brainstorm '| 1 | a | PŘIJATO | `x.sh` |' '| 1 | a | PŘIJATO | `x.sh` |'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"rows [1 1] do not answer items [1 2]"* ]]
  _response brainstorm '| 1 | a | PŘIJATO | `x.sh` |' '| 3 | c | PŘIJATO | `x.sh` |'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"[1 3]"* ]]
  _response brainstorm '| 1 | a | PŘIJATO | `x.sh` |'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"[1] do not answer items [1 2]"* ]]
  _response brainstorm '| 1 | a | PŘIJATO | někde v plánu |' '| 2 | b | odmítnuto | proč |'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"names no checked file or command"* ]]
  _response brainstorm '| 1 | a `x.sh` | PŘIJATO | někde v plánu |' '| 2 | b | odmítnuto | proč |'
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"names no checked file or command"* ]]
  rm "$D/brainstorm/critic-response.md"
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 5 ]; [[ "$output" == *"did not write"* ]]
}

@test "check: a one-sentence empty level 1 passes with level1_empty and zero rows" {
  aid_critic_prepare P9 --moment brainstorm >/dev/null
  _answer brainstorm 'Nenašel jsem nic, co by návrh při platnosti zadání nedodal.'
  _response brainstorm
  run aid_critic_check P9 --moment brainstorm
  [ "$status" -eq 0 ]; [[ "$output" == *"level1_empty=true"* ]]
  [ "$(jq -r .level1_empty "$D/brainstorm/check.json")" = "true" ]
}

@test "check without a prepared prompt or without the critic's answer says so" {
  run aid_critic_check P9 --moment plan
  [ "$status" -eq 2 ]; [[ "$output" == *"nothing prepared"* ]]
  aid_critic_prepare P9 --moment plan >/dev/null
  run aid_critic_check P9 --moment plan
  [ "$status" -eq 4 ]; [[ "$output" == *"did not write"* ]]
}

@test "rebind: after a passed plan-moment check the revised plan's hash is recorded once; refused without a passed check, after a response edit, or a second time" {
  aid_critic_prepare P9 --moment plan >/dev/null
  run aid_critic_rebind P9 --plan "$P/.aid-o/plans/P9-x.md"
  [ "$status" -eq 2 ]; [[ "$output" == *"no check to rebind"* ]]
  _answer plan '**1. Slib.**'; _response plan '| 1 | s | PŘIJATO | `x.md` |'
  aid_critic_check P9 --moment plan >/dev/null
  echo "revised for item 1" >> "$P/.aid-o/plans/P9-x.md"
  run aid_critic_rebind P9 --plan "$P/.aid-o/plans/P9-x.md"
  [ "$status" -eq 0 ]
  [ "$(jq -r .plan_sha256_revised "$D/plan/check.json")" = "$(sha256sum "$P/.aid-o/plans/P9-x.md" | cut -d' ' -f1)" ]
  grep -q '"event":"critic_rebound"' "$P/.aid-o/work/evidence/P9/timeline.jsonl"
  run aid_critic_rebind P9 --plan "$P/.aid-o/plans/P9-x.md"
  [ "$status" -eq 5 ]; [[ "$output" == *"already rebound"* ]]
}
