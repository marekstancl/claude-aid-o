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
  [ "$(ls "$SK"/steps/*.md | wc -l)" -eq 7 ]
}
