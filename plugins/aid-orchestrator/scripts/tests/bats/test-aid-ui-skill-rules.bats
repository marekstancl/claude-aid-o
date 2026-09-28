#!/usr/bin/env bats
# aid-tier: t2
# P103 Step 5 — the ui-design skill asks the PM only on the studio page, names no
# removed tool, and every step file exists and is routed from SKILL.md.

setup() {
  SK="$BATS_TEST_DIRNAME/../../../skills/ui-design"
  LINT="$BATS_TEST_DIRNAME/../../aid-lint-skill.sh"
  STEPS="0-start 1-product 1v-vision 1i-identity 1s-seo 2-structure 3-content-plan 4-references 5-directions 6-build 7-verify"
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
