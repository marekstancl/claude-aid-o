#!/usr/bin/env bats
# aid-tier: t2
# P103 Step 5 — the ui-design skill asks the PM only on the studio page, names no
# removed tool, and every step file exists and is routed from SKILL.md.

setup() {
  SK="$BATS_TEST_DIRNAME/../../../skills/ui-design"
  LINT="$BATS_TEST_DIRNAME/../../aid-lint-skill.sh"
  STEPS="0-start 1-product 1p-sources 1v-vision 1i-identity 1s-seo 2-structure 3-content-plan 4-references 5-directions 6-build 7-verify"
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

@test "SKILL.md names record-answer, finish and the frontend-design snapshot" {
  for s in 'aid-ui-state.sh record-answer' 'aid-ui-state.sh finish' 'references/adopted/frontend-design-SKILL.md' 'aid-ui-serve.sh studio'; do
    grep -qF -- "$s" "$SK/SKILL.md" || { echo "missing: $s"; return 1; }
  done
}

@test "5-directions.md requires three cards with the uniqueness line and names the genericity rubric" {
  f="$SK/steps/5-directions.md"
  grep -qF 'Tři karty' "$f"
  grep -qF 'uniqueness' "$f"
  grep -qF 'references/genericity-rubric.md' "$f"
  grep -qF 'aid-ui-tool.sh glyph' "$f"
}

@test "3-content-plan.md names owner, due, status and defer-content" {
  f="$SK/steps/3-content-plan.md"
  for s in owner due status 'aid-ui-state.sh defer-content' 'docs/content/facts.yaml'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
}

@test "step 0 runs the coverage check; 6-build converts images through aid-ui-tool.sh webp and records the build" {
  grep -qF 'aid-ui-coverage.sh check' "$SK/steps/0-start.md"
  grep -qF 'aid-ui-tool.sh webp' "$SK/steps/6-build.md"
  grep -qF 'aid-ui-state.sh build-record' "$SK/steps/6-build.md"
}

@test "no step file writes index.html except through aid-ui-state.sh body" {
  for f in "$SK"/steps/[1-7]*.md; do
    grep -qF 'index.html' "$f" || continue
    grep -qF 'index.html` ručně needituj' "$f" || { echo "$f"; return 1; }
  done
}

@test "1i-identity.md renders icons through the Playwright MCP and aid-ui-ico.py" {
  for s in 'browser_run_code_unsafe' 'references/brand-icons.js' 'aid-ui-ico.py --verify' 'brief-logo-favicon.md'; do
    grep -qF -- "$s" "$SK/steps/1i-identity.md" || { echo "missing: $s"; return 1; }
  done
}

@test "1-product.md names 1v, 1i, 1s in that order" {
  [ "$(grep -o '`1[vis]`' "$SK/steps/1-product.md" | tr -d '`' | tr '\n' ' ')" = "1v 1i 1s " ]
}

@test "no step or SKILL.md names a removed state verb" {
  ! grep -rnE 'await-choice|await-direction|pending-direction|require-direction|aid-ui-state.sh spend' "$SK/SKILL.md" "$SK/steps" || false
}

@test "7-verify.md writes the kvalita chapter from soulad-summary.json and brand-state.json" {
  f="$SK/steps/7-verify.md"
  for s in 'body <project> kvalita' 'soulad-summary.json' 'gate.run_at' 'chapter <project> kvalita navrh'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
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

@test "P106: SKILL.md names decide, the outcome rule and the six step titles; no overview, no Průběh anywhere" {
  grep -qF 'aid-ui-state.sh decide' "$SK/SKILL.md"
  grep -qF 'Když rozhoduje agent sám' "$SK/SKILL.md"
  grep -qF 'do 120 znaků' "$SK/SKILL.md"
  grep -qF 'Druh webu, Zadání a obsah, Vzory,' "$SK/SKILL.md"
  grep -qF 'Vzhled, Stavba, Kontrola' "$SK/SKILL.md"
  ! grep -q 'overview' "$SK/SKILL.md"
  ! grep -rq 'Průběh' "$SK/SKILL.md" "$SK/steps"
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

@test "P108: steps 1v, 3, 6 write by the adopted method and the AID bridges; 2 marks legal pages" {
  R="$SK/references"
  ! grep -q "Zakázaná prázdná slova" "$SK/steps/1v-vision.md"
  for p in adopted/marketingskills/copywriting/SKILL.md copy-rules.md 'copy-<jazyk>.md'; do
    grep -qF "$p" "$SK/steps/1v-vision.md" || { echo "1v lacks $p"; return 1; }
  done
  grep -qF "adopted/marketingskills/cro/SKILL.md" "$SK/steps/3-content-plan.md"
  for p in copywriting/SKILL.md copywriting/references/copy-frameworks.md copywriting/references/natural-transitions.md copywriting/references/ai-tells.md; do
    grep -qF "adopted/marketingskills/$p" "$SK/steps/6-build.md" || { echo "6 lacks $p"; return 1; }
  done
  grep -qF '"legal": true' "$SK/steps/2-structure.md"
  # the bridges carry their fixed headings (the skill and the review look them up by name)
  for h in "Fakta a hypotézy" "Pořadí při rozporu" "Jak číst převzaté" "Co blokuje v revizi" "Kotvy skóre person" "Právní stránky"; do
    grep -qx "## $h" "$R/copy-rules.md" || { echo "copy-rules.md lacks: $h"; return 1; }
  done
  for f in copy-cs.md copy-sk.md copy-en.md; do
    for h in "Kancelářština → běžné slovo" "Prázdná slova" "Fráze prozrazující AI text" "Oslovení" "Typografie" "Co zakázané NENÍ"; do
      grep -qx "## $h" "$R/$f" || { echo "$f lacks: $h"; return 1; }
    done
  done
}

@test "P108: the bridges carry their key rules, not just headings" {
  R="$SK/references"
  grep -qF 'jen z `docs/content/facts.yaml`' "$R/copy-rules.md"
  grep -qF 'nikdy se' "$R/copy-rules.md"                          # a hypothesis never becomes a claim
  # the conflict order: PM answer first, facts register second, product context third
  grep '^[0-9]\. ' "$R/copy-rules.md" | head -3 | tr '\n' ' ' | grep -qE '^1\. .*odpověď PM.* 2\. .*facts\.yaml.* 3\. .*product-context\.md' \
    || { grep '^[0-9]\. ' "$R/copy-rules.md" | head -3; return 1; }
  grep -qF 'otázkou ve studiu' "$R/copy-rules.md"
  grep -qF 'Skóre pod 5 je blokující' "$R/copy-rules.md"
  grep -qF 'netyka_se' "$R/copy-rules.md"
  grep -qF 'neplatí pro právní' "$R/copy-rules.md"
  for f in copy-cs.md copy-sk.md; do
    grep -q '(—)' "$R/$f"                                          # the em dash rule
    grep -qiE 'vykání|vykanie' "$R/$f"
  done
  grep -qF 'plain-english-alternatives.md' "$R/copy-en.md"
  grep -qF 'ai-tells.md' "$R/copy-en.md"
}

@test "P108: 1p runs first in step 1; 1v, 3 and 6 start with context-check" {
  # in 1-product, 1p is named before any studio question is opened
  first_q=$(grep -n 'otázk' "$SK/steps/1-product.md" | head -1 | cut -d: -f1)
  first_p=$(grep -n '1p-sources.md' "$SK/steps/1-product.md" | head -1 | cut -d: -f1)
  [ -n "$first_p" ] && { [ -z "$first_q" ] || [ "$first_p" -le "$first_q" ]; }
  for f in 1v-vision 3-content-plan 6-build; do
    sed -n '/^## Postup/,/^1\./p' "$SK/steps/$f.md" | grep -qF 'aid-ui-state.sh context-check' || { echo "$f"; return 1; }
  done
  grep -qF 'aid-ui-sources.py' "$SK/steps/1p-sources.md"
  grep -qF '`sources`' "$SK/steps/1p-sources.md"
  grep -qF '`product_context`' "$SK/steps/1p-sources.md"
}
