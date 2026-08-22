#!/usr/bin/env bats
# aid-tier: t0
# test-reuse-verdict.bats — the N+1 rule and its verdict (P085 Step 3).
#
# aid_reuse_verdict is a pure function over two strings: the **Reuse check:**
# field and the plan's declared paths. Its whole job is the threshold — unify
# now, or file an item that names the sites — so the cases here are the three
# answers plus the boundary that decides between them. The BLOCKING half of the
# rule (a step that declares conflict and founds another variant anyway) is
# asserted through the lint, because that is where it fires.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  source "$AID_PLUGIN_PATH/scripts/lib/aid-scoping.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-reuse-verdict.sh"
  LINT="$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh"
  TEST_DIR="$(mktemp -d)"; cd "$TEST_DIR"
  mkdir -p .aid-o/plans src
  echo 'export function isoNow() { return "" }' > src/a.ts
  echo 'export function isoNow() { return "x" }' > src/b.ts
  PLAN=".aid-o/plans/P901-fixture.md"
  CMD='grep -rln isoNow src/'
}
teardown() { cd /; rm -rf "$TEST_DIR"; }

# ── AC8: everything in reach -> unify here ──────────────────────────────────
@test "verdict: conflicting sites inside the declared paths say unify" {
  run aid_reuse_verdict "searched: \`$CMD\` → several conflicting \`src/a.ts\` and \`src/b.ts\` — they disagree" "$CMD" "$(printf 'src/a.ts\nsrc/b.ts\n')"
  [ "$output" = "unify" ]
}

@test "verdict: a site under a declared directory counts as inside" {
  run aid_reuse_verdict "\`$CMD\` → several conflicting \`src/deep/a.ts\`" "$CMD" "src/"
  [ "$output" = "unify" ]
}

# ── AC9: something out of reach -> backlog, and the item names the sites ────
@test "verdict: a site outside the declared paths says backlog and lists it" {
  run aid_reuse_verdict "\`$CMD\` → several conflicting \`src/a.ts\` and \`other/z.ts\`" "$CMD" "src/a.ts"
  [[ "$output" == backlog* ]]
  [[ "$output" == *"other/z.ts"* ]]
  [[ "$output" != *"src/a.ts"* ]]
}

@test "verdict: a plan declaring no paths at all cannot unify anything" {
  run aid_reuse_verdict "\`$CMD\` → several conflicting \`src/a.ts\`" "$CMD" ""
  [[ "$output" == backlog* ]]
  [[ "$output" == *"src/a.ts"* ]]
}

# ── the fail-safe direction is the SMALLER intervention ─────────────────────
@test "verdict: a field naming no site falls back to backlog, never to unify" {
  run aid_reuse_verdict "\`$CMD\` → several conflicting, they are all over the place" "$CMD" "src/a.ts"
  [ "$output" = "backlog" ]
}

@test "verdict: the search targets inside the command are not conflicting sites" {
  # `src/known.ts` here is what the search LOOKED AT, not what it found.
  run aid_reuse_verdict "searched: \`grep -rn isoNow src/known.ts\` → several conflicting \`src/a.ts\`" "grep -rn isoNow src/known.ts" "src/a.ts"
  [ "$output" = "unify" ]
}

# ── the machine-decidable half of the N+1 rule (AC10) ───────────────────────
_plan_conflicting() {   # <strict|legacy> <reuse-check-value>
  local strict="$1" reuse="$2"
  local sflag=""; [[ "$strict" == "strict" ]] && sflag=$'\nlifecycle_strict: true'
  { printf -- '---\nid: P901\ntype: regular\nrisk: low%s\n---\n' "$sflag"
    printf '# Plan: P901\n\n## Testing Strategy\n\nNo new verification — this fixture exercises the N+1 rule only.\n\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n- Create: `src/c.ts` — a third one\n'
    printf '\n**Reuse check:** %s\n' "$reuse"
    printf '\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nn/a\n\n**Edge Cases:**\n- none\n'
  } > "$PLAN"
}

@test "N+1: founding another variant after declaring conflict, with no argument, is refused" {
  _plan_conflicting strict "searched: \`$CMD\` → several conflicting \`src/a.ts\` and \`src/b.ts\` — they disagree"
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"still founds another file of the same kind"* ]]
}

@test "N+1: the same step passes once it argues for the variant" {
  _plan_conflicting strict "searched: \`$CMD\` → several conflicting \`src/a.ts\` and \`src/b.ts\` — deliberately founding a variant, because both are load-bearing and unifying them is a separate plan"
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "N+1: the Czech spelling of the argument is accepted too" {
  _plan_conflicting strict "hledáno: \`$CMD\` → více rozporných \`src/a.ts\` a \`src/b.ts\` — vědomě zakládám variantu, protože sjednocení je samostatný plán"
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "N+1: the verdict is reported alongside, as an advisory" {
  _plan_conflicting strict "searched: \`$CMD\` → several conflicting \`src/a.ts\` and \`other/z.ts\` — deliberately founding a variant, because the other tree is not ours"
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADVISORY"* ]]
  [[ "$output" == *"other/z.ts"* ]]
  [[ "$output" == *"backlog"* ]]
}

# ── the boundary this rule does NOT claim to hold ───────────────────────────
@test "N+1: an undeclared duplicate is invisible here, and that is the lens's work" {
  # No conflict declared, an honest `none` over a search that finds nothing:
  # the machine has nothing to object to, and says nothing.
  _plan_conflicting strict "searched: \`grep -rln relativeCzech src/\` → none — nothing like it exists"
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"another file of the same kind"* ]]
}
