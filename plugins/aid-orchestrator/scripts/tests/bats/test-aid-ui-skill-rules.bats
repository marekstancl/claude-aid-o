#!/usr/bin/env bats
# aid-tier: t0
# P101 Step 5 — the ui-design skill carries the never-without-PM rules, and the
# steps after the direction choice open with the state gate.

setup() {
  SK="$BATS_TEST_DIRNAME/../../../skills/ui-design"
  LINT="$BATS_TEST_DIRNAME/../../aid-lint-skill.sh"
}

# first non-blank line under "## Postup"
postup_first() { awk '/^## Postup/{f=1; next} f && NF {print; exit}' "$1"; }

@test "SKILL.md carries MUST Rules 1-3" {
  must="$(sed -n '/^## MUST Rules/,/^## Completeness Gate/p' "$SK/SKILL.md")"
  for s in 'IMPECCABLE_QUESTION_FORCE=1' 'exit 4' 'aid-ui-serve.sh forward' 'non-interactive' 'aid-ui-state.sh pending-direction'; do
    grep -qF -- "$s" <<<"$must" || { echo "missing: $s"; return 1; }
  done
}

@test "step 3 records the direction through await-direction" {
  grep -qF 'aid-ui-state.sh await-direction' "$SK/steps/3-direction.md"
}

@test "steps 4, 5 and 6 open their Postup with require-direction" {
  for f in 4-build 5-standard 6-verify; do
    [[ "$(postup_first "$SK/steps/$f.md")" == *'aid-ui-state.sh require-direction'* ]] || { echo "$f"; return 1; }
  done
}

@test "aid-lint-skill.sh reports nothing for SKILL.md and every step" {
  for f in "$SK/SKILL.md" "$SK"/steps/*.md; do
    run bash "$LINT" "$f"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  done
  for n in 0 1 2 3 4 5 6; do ls "$SK"/steps/$n-*.md >/dev/null || return 1; done
  for f in "$SK"/steps/1?-*.md; do
    [ -e "$f" ] || continue
    grep -qF "steps/$(basename "$f")" "$SK/steps/1-product.md" || { echo "not in 1-product.md: $f"; return 1; }
  done
}

# P102 Step 2 — the text defects of the P101 dry run stay fixed.
@test "SKILL.md ends at step 6 with finish, no step 7" {
  grep -qF 'aid-ui-state.sh finish' "$SK/SKILL.md"
  ! grep -qF 'step <project> <n+1>' "$SK/SKILL.md"
  ! grep -qF 'step <project> 7' "$SK/SKILL.md"
}

@test "6-verify.md names the known-debt path and finish" {
  grep -qF 'známým dluhem' "$SK/steps/6-verify.md"
  grep -qF 'aid-ui-state.sh finish' "$SK/steps/6-verify.md"
}

@test "5-standard.md names Impeccable document merge and overwrite" {
  grep -qF 'merge' "$SK/steps/5-standard.md"
  grep -qF 'overwrite' "$SK/steps/5-standard.md"
}

@test "no step file writes index.html except through aid-ui-state.sh body" {
  # step 0 copies the template; every later step naming index.html forbids hand edits
  for f in "$SK"/steps/[1-6]-*.md; do
    grep -qF 'index.html' "$f" || continue
    grep -qF 'index.html` ručně needituj' "$f" || { echo "$f"; return 1; }
  done
}

# P102 Step 3 — step 0 records the optional parts; app references without Mobbin.
@test "0-start.md sets options through aid-ui-state.sh set" {
  grep -qF 'aid-ui-state.sh set <project> options' "$SK/steps/0-start.md"
}

@test "2-references.md names Google Play search and no Mobbin" {
  grep -qF 'play.google.com/store/search' "$SK/steps/2-references.md"
  [ "$(grep -ci mobbin "$SK/steps/2-references.md")" -eq 0 ]
}

# P102 Step 4 — sub-step 1v takes the slogan from the page and writes chapter vize.
@test "1v-vision.md takes the slogan through await-choice and writes vize through body" {
  grep -qF 'await-choice <project> --kind slogan --screen' "$SK/steps/1v-vision.md"
  grep -qF 'aid-ui-state.sh body <project> vize' "$SK/steps/1v-vision.md"
}

@test "1-product.md names 1v, 1i, 1s in that order" {
  [ "$(grep -o '`1[vis]`' "$SK/steps/1-product.md" | tr -d '`' | tr '\n' ' ')" = "1v 1i 1s " ]
}

# P102 Step 5 — sub-step 1i takes the logo from the page and renders icons through the Playwright MCP.
@test "1i-identity.md takes the logo through await-choice, names the renderer, the brief and the output check" {
  for s in 'await-choice <project> --kind logo --screen' 'browser_run_code_unsafe' 'brief-logo-favicon.md' 'Kontrola výstupu' 'aid-ui-state.sh body <project> logo'; do
    grep -qF -- "$s" "$SK/steps/1i-identity.md" || { echo "missing: $s"; return 1; }
  done
}

@test "1s-seo.md takes the pages through await-choice and writes seo through body; 3-direction.md names choices.pages" {
  grep -qF 'await-choice <project> --kind pages --screen' "$SK/steps/1s-seo.md"
  grep -qF 'aid-ui-state.sh body <project> seo' "$SK/steps/1s-seo.md"
  grep -qF 'await-choice <project> --kind pages --screen pages-<n>.html' "$SK/steps/1s-seo.md"
  ! grep -qF 'pokračuj jen s domovskou' "$SK/steps/1s-seo.md"
  grep -qF 'choices.pages' "$SK/steps/3-direction.md"
}

@test "6-verify.md runs aid-ui-seo-check.py when options.seo and writes seo through body" {
  step="$(sed -n '/^## Postup/,/^## Co PM/p' "$SK/steps/6-verify.md")"
  grep -qF 'options.seo' <<<"$step"
  grep -qF 'aid-ui-seo-check.py' <<<"$step"
  grep -qF 'aid-ui-state.sh body <project> seo' <<<"$step"
}

# P102 Step 8 — image comps: every PM choice under MUST 1, the key reaches Impeccable from step 1.
@test "SKILL.md MUST 1 names every PM choice; MUST 7 keeps the OpenAI key out of sight" {
  must1="$(sed -n '/^1\. /,/^2\. /p' <<<"$(sed -n '/^## MUST Rules/,/^## Completeness Gate/p' "$SK/SKILL.md")")"
  for s in direction 'build path' composition slogan logo pages; do
    grep -qF -- "$s" <<<"$must1" || { echo "MUST 1 missing: $s"; return 1; }
  done
  grep -qE '^7\. The OpenAI key .*services/\.env' "$SK/SKILL.md"
}

@test "1-product.md exports the key into Impeccable from init on and the PM answers the build path" {
  grep -qF "set -a; source <(grep '^OPENAI_API_KEY=' /opt/eco/services/.env); set +a" "$SK/steps/1-product.md"
  grep -qF 'od `init` dál' "$SK/steps/1-product.md"
  grep -qF 'odpovídá PM, nikdy' "$SK/steps/1-product.md"
  ! grep -rnE 'OPENAI_API_KEY=[A-Za-z0-9]' "$SK" || false
}

@test "3-direction.md handles exit 5; 4-build.md closes the composition round through await-choice and reports spend" {
  grep -qF 'exit 5' "$SK/steps/3-direction.md"
  grep -qF 'await-choice <project> --kind composition' "$SK/steps/4-build.md"
  grep -qF 'aid-ui-state.sh spend <project>' "$SK/steps/4-build.md"
}
