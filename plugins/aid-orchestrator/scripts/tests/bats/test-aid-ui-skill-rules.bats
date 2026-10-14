#!/usr/bin/env bats
# aid-tier: t2
# P103 Step 5 — the ui-design skill asks the PM only on the studio page, names no
# removed tool, and every step file exists and is routed from SKILL.md.

setup() {
  SK="$BATS_TEST_DIRNAME/../../../skills/ui-design"
  LINT="$BATS_TEST_DIRNAME/../../aid-lint-skill.sh"
  STEPS="0-start 1-product 1p-sources 1v-vision 1i-identity 1s-seo 2-structure 3-content-plan 4-references 5-directions 6-build 7-verify 8-quality"
}

@test "no step names Impeccable or voice-standard" {
  run grep -rli -e impeccable -e voice-standard "$SK/steps"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "every step file exists, is referenced from SKILL.md, and no other step file exists" {
  for s in $STEPS; do
    [ -f "$SK/steps/$s.md" ] || { echo "missing: $s"; return 1; }
    grep -qF "steps/$s.md" "$SK/SKILL.md" || { echo "not in SKILL.md: $s"; return 1; }
  done
  [ "$(ls "$SK"/steps/*.md | wc -l)" -eq "$(wc -w <<<"$STEPS")" ]
}

@test "aid-lint-skill.sh reports nothing for SKILL.md and every step" {
  for f in "$SK/SKILL.md" "$SK"/steps/*.md; do
    run bash "$LINT" "$f"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  done
}

@test "no step file writes index.html except through aid-ui-state.sh body" {
  for f in "$SK"/steps/[1-7]*.md; do
    grep -qF 'index.html' "$f" || continue
    grep -qF 'index.html` ručně needituj' "$f" || { echo "$f"; return 1; }
  done
}

@test "no step or SKILL.md names a removed state verb" {
  ! grep -rnE 'await-choice|await-direction|pending-direction|require-direction|aid-ui-state.sh spend' "$SK/SKILL.md" "$SK/steps" || false
}

@test "every PM-chosen write in the steps passes --answer: options, refs, chapter schvaleno, chapter-all" {
  for s in 'set <project> options' 'set <project> refs' 'set <project> variant' 'set <project> structure' 'set <project> content-plan'; do
    line="$(grep -rhF -- "$s" "$SK/steps")" || { echo "missing: $s"; return 1; }
    [[ "$line" == *'--answer <id>'* ]] || { echo "no --answer: $line"; return 1; }
  done
  ! grep -rn 'schvaleno --by' "$SK/steps" | grep -v -- '--answer' || false
  grep -qF 'chapter-all-target <project>' "$SK/steps/7-verify.md"
  grep -F 'chapter-all <project>' "$SK/steps/7-verify.md" | grep -qF -- '--answer <id'
}

@test "no step passes JSON as a single-quoted shell literal; every http.server binds 127.0.0.1" {
  ! grep -rnE "(set|--answer) [^\`]*'[[{<]" "$SK/steps" "$SK/SKILL.md" || false
  ! grep -rn 'http\.server' "$SK/steps" | grep -v -- '--bind 127.0.0.1 --directory' || false
  for f in 5-directions 6-build; do grep -qF 'kill "$pid"' "$SK/steps/$f.md" || { echo "$f"; return 1; }; done
}

@test "P106: the steps that decide without the PM record it with decide (vision facts, build, design standard)" {
  for f in 1v-vision 6-build 7-verify; do
    grep -qF 'aid-ui-state.sh decide' "$SK/steps/$f.md" || { echo "$f"; return 1; }
  done
  # every step title a step passes to decide is one of the six canonical titles
  titles="$(grep -rhoE 'decide <project> --step "[^"]+"' "$SK/steps" | sed -E 's/.*--step "([^"]+)"/\1/' | sort -u)"
  [ -n "$titles" ]
  while IFS= read -r t; do
    case "$t" in "Druh webu"|"Zadání a obsah"|"Vzory"|"Vzhled"|"Stavba"|"Kontrola") ;; *) echo "unknown step: $t"; return 1 ;; esac
  done <<<"$titles"
  # every call carries --step, --title, --outcome, --why and --source (read to the closing backtick)
  for f in 1v-vision 6-build 7-verify; do
    calls="$(tr '\n' ' ' < "$SK/steps/$f.md" | grep -oE 'aid-ui-state\.sh decide [^`]+')"
    [ -n "$calls" ] || { echo "no call in $f"; return 1; }
    while IFS= read -r c; do
      for o in --step --title --outcome --why --source; do [[ "$c" == *" $o "* ]] || { echo "$f: no $o in: $c"; return 1; }; done
    done <<<"$calls"
  done
  tr '\n' ' ' < "$SK/steps/6-build.md" | grep -qE -- '--step "Stavba" +--title "Web postaven" +--outcome "Postaveno <N> stránek[^"]*" +--why "[^"]+" +--source \.aid-ui/build\.json'
}
