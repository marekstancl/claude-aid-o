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

# P113 step 4: the workshop's procedures as a layer that wins over the part of a step it names
@test "local-layer: every procedure and template under references/local is required reading of some method in sections.json" {
  # spusteni.md (P115) is the launch table aid-ui-package.py reads into the deployment brief, not a procedure of a step
  for f in $(cd "$SK" && find references/local -type f ! -name spusteni.md | sort); do
    jq -e --arg f "skills/ui-design/$f" '[.methods[] | select(type == "object") | .files[]] | index($f) != null' "$SK/sections.json" >/dev/null ||
      { echo "no method reads $f"; return 1; }
  done
  [ "$(ls "$SK"/references/local/*.md | wc -l)" -eq 8 ]
  jq -e '.methods.identity.files | index("skills/ui-design/references/local/logo-postup.md") != null' "$SK/sections.json" >/dev/null
}

@test "local-layer: every step a procedure names in its Nahrazuje line links back to that procedure; SKILL.md states the precedence" {
  for p in "$SK"/references/local/*.md; do
    [[ "$(basename "$p")" != spusteni.md ]] || continue   # the launch table, not a layered procedure
    line="$(grep -m1 '^\*\*Nahrazuje:\*\*' "$p")" || { echo "$(basename "$p"): no Nahrazuje line"; return 1; }
    grep -q '^\*\*Platí dál:\*\*' "$p" || { echo "$(basename "$p"): no Platí dál line"; return 1; }
    steps="$(grep -oE 'steps/[0-9a-z-]+\.md' <<<"$line" | sort -u)"; [ -n "$steps" ]
    for s in $steps; do
      grep -qF "references/local/$(basename "$p")" "$SK/$s" || { echo "$s does not link $(basename "$p")"; return 1; }
    done
  done
  grep -qF "Postup má přednost před tou částí kroku, kterou jmenuje" "$SK/SKILL.md"
  grep -qF "accepted_with_reservation" "$SK/SKILL.md"; grep -qF "fakta a zákon > vada" "$SK/SKILL.md"
}

@test "local-layer: nothing of the trial business or the workshop under skills/ui-design; the templates carry no contact data" {
  ! grep -rliw -e hirt "$SK"
  ! grep -rl -e '/home/claude' -e 'skilly/' -e 'reference/hirt' "$SK"
  ! grep -rnE '(\+420 ?)?[0-9]{3} ?[0-9]{3} ?[0-9]{3}\b' "$SK/references/local/vzory" "$SK/references/local/vzhled-vzor"
  ! grep -rniE 'IČO: ?[0-9]|@[a-z0-9-]+\.(cz|sk|com)' "$SK/references/local"
}

@test "local-layer: every file a procedure names resolves inside the plugin; a method receipt for a missing procedure is refused" {
  root="$(cd "$SK/../.." && pwd)"
  for p in "$SK"/references/local/*.md "$SK"/references/local/vzhled-vzor/*.md; do
    for ref in $(grep -oE '`[A-Za-z0-9_./{},-]+\.(md|yaml|json|css|html)`' "$p" | tr -d '`' | grep -v '[{}<]' | sort -u); do
      [[ "$ref" == */* || "$ref" == *.md ]] || continue
      case "$ref" in docs/*|.aid-ui/*|podklady/*|../*|*/brief.md|product-context.md|redesign.md|route.json|gen.json|otazky-klientovi.md|copy.md|tokens.css|zadani-smeru.md|pro-role.md|karta.md|structure.json|wp-sitemap.xml|sitemap.xml) continue;; esac
      for base in "$root/skills/ui-design" "$SK/references/local" "$root" "$root/skills/ui-design/references" "$SK/references/adopted/logo-design/references"; do
        [ -e "$base/$ref" ] && continue 2
      done
      echo "$(basename "$p"): $ref does not resolve"; return 1
    done
  done
  # the method receipt reads every file of the method: a procedure missing from a copy of the plugin is refused
  C="$BATS_TEST_TMPDIR/plugin"; mkdir -p "$C"; cp -r "$root/scripts" "$root/skills" "$C/"
  rm "$C/skills/ui-design/references/local/logo-postup.md"
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P"; bash "$C/scripts/aid-ui-state.sh" init "$P" >/dev/null
  run bash "$C/scripts/aid-ui-state.sh" method "$P" identity; [ "$status" -ne 0 ]; [[ "$output" == *"logo-postup.md"*"missing"* ]]
}

@test "local-layer: each place's method reads its procedure and both roles' rubrics; every layered step names its place round; D3 default" {
  chk() {   # chk <method> <procedure> <place>...
    local m="$1" pr="$2"; shift 2
    jq -e --arg m "$m" --arg f "skills/ui-design/references/local/$pr" '.methods[$m].files | index($f) != null' "$SK/sections.json" >/dev/null || { echo "$m: no $pr"; return 1; }
    for pl in "$@"; do for r in tech owner; do
      f="skills/ui-design/critic/web-local.$r.$pl.yaml"; [ "$pl" != web ] || f="skills/ui-design/critic/web-local.$r.yaml"
      jq -e --arg m "$m" --arg f "$f" '.methods[$m].files | index($f) != null' "$SK/sections.json" >/dev/null || { echo "$m: no $f"; return 1; }
    done; done
  }
  chk vision sdeleni-postup.md sdeleni; chk sources sdeleni-postup.md sdeleni; chk product_context sdeleni-postup.md sdeleni
  chk identity logo-postup.md logo; chk build pohyb-znacky.md pohyb; chk structure struktura-postup.md struktura
  chk task_map struktura-postup.md struktura; chk content_plan struktura-postup.md struktura; chk direction vzhled-postup.md vzhled
  chk approve_page kontrola-postup.md web vzhled struktura; chk handover kontrola-postup.md web vzhled struktura
  for s in 1p-sources 1v-vision 1i-identity 1s-seo 2-structure 3-content-plan 4-references 5-directions 6-build 7-verify 8-quality; do
    grep -m1 '^\*\*Vrstva dílny (P113):\*\*' "$SK/steps/$s.md" | grep -qE 'aid-ui-quality\.py round <projekt> --place (sdeleni|logo|pohyb|struktura|vzhled|web)' || { echo "$s: no place round"; return 1; }
  done
  grep -qF "výchozí doporučení, když klient" "$SK/references/local/struktura-postup.md"
  ! grep -rniE 'projekční kancel|rýsování|prolínání prostor|po obcích|výkresový list|měřítková řada|postavené domy|naše stavby|kuželkárn|283/2021|ČKAIT|\bTrading\b|název se odkryje' "$SK/references/local"
}
