#!/usr/bin/env bats
# aid-tier: t0
# Every agent card under agents/ carries a name, a model the Agent tool knows
# and an effort the harness reads (P107 Step 5). Defect it catches: a card
# dispatched on a model or effort the harness refuses — after the plan was
# generated and the step is already running. The shape of the text is what the
# PM reads and approves; nothing here lints it.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  CARDS=("$AID_PLUGIN_PATH"/agents/*.md)
}

_fm() { sed -n '2,/^---$/p' "$1" | sed '$d'; }   # the frontmatter lines between the dashes

@test "five cards remain, each with a name that matches its file" {
  [ "${#CARDS[@]}" -eq 5 ]
  local c; for c in "${CARDS[@]}"; do
    [ "$(_fm "$c" | sed -n 's/^name: *//p')" = "$(basename "$c" .md)" ]
  done
}

@test "every card names a model in {sonnet, opus, fable} and an effort in {low, medium, high}" {
  local c m e; for c in "${CARDS[@]}"; do
    m="$(_fm "$c" | sed -n 's/^model: *//p')"; e="$(_fm "$c" | sed -n 's/^effort: *//p')"
    case "$m" in sonnet|opus|fable) ;; *) echo "$c: model '$m'"; false ;; esac
    case "$e" in low|medium|high) ;; *) echo "$c: effort '$e'"; false ;; esac
  done
}

@test "the code-writing cards run on sonnet, the reviewer and the scanner on opus (PM 2026-09-30)" {
  local c; for c in implementer implementer-light gate-fixer; do
    [ "$(_fm "$AID_PLUGIN_PATH/agents/$c.md" | sed -n 's/^model: *//p')" = sonnet ]
  done
  for c in reviewer-light project-scanner; do
    [ "$(_fm "$AID_PLUGIN_PATH/agents/$c.md" | sed -n 's/^model: *//p')" = opus ]
  done
  [ "$(_fm "$AID_PLUGIN_PATH/agents/implementer.md" | sed -n 's/^effort: *//p')" = high ]
}

@test "a card with an unknown model is what this suite refuses (proved on a copy)" {
  local t; t="$(mktemp -d)"; cp "$AID_PLUGIN_PATH/agents/implementer.md" "$t/x.md"
  sed -i 's/^model: sonnet/model: gpt-6/' "$t/x.md"
  run bash -c "sed -n '2,/^---\$/p' '$t/x.md' | sed -n 's/^model: *//p'"
  [ "$output" = "gpt-6" ]
  case "$output" in sonnet|opus|fable) false ;; *) true ;; esac
  rm -rf "$t"
}
