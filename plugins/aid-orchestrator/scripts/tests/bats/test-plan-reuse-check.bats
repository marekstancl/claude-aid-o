#!/usr/bin/env bats
# aid-tier: t0
# test-plan-reuse-check.bats — the `**Reuse check:**` field (P085 Steps 1-2).
#
# Two things are asserted, and they are different: the GRAMMAR of the field
# (a replayable read-only search command plus one of four results) and its
# ENFORCEMENT by aid-plan-lint.sh (blocking for a lifecycle_strict plan, a loud
# advisory for a legacy one). A separate suite from test-plan-lint.bats because
# that one owns the Files grammar and its fixtures say nothing about reuse.
#
# Everything here is text plus a grep over a two-file fixture tree: t0.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  LINT="$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh"
  TEST_DIR="$(mktemp -d)"; cd "$TEST_DIR"
  # A workspace, because the lint replays the declared search FROM the project
  # root it resolves out of the plan's location — no `.aid-o/`, no replay.
  mkdir -p .aid-o/plans src
  echo 'export function isoNow() { return new Date().toISOString(); }' > src/known.ts
  PLAN=".aid-o/plans/P900-fixture.md"
}
teardown() { cd /; rm -rf "$TEST_DIR"; }

# _plan <strict|legacy> <verb-bullet> [reuse-check-value]
# One step; the third argument, when given, becomes its **Reuse check:** field.
_plan() {
  local strict="$1" bullet="$2" reuse="${3-}"
  local sflag=""; [[ "$strict" == "strict" ]] && sflag=$'\nlifecycle_strict: true'
  { printf -- '---\nid: P900\ntype: regular\nrisk: low%s\n---\n' "$sflag"
    printf '# Plan: P900\n\n## Testing Strategy\n\nNo new verification — this fixture exercises the Reuse check field only.\n\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n'
    printf '%s\n' "$bullet"
    [[ -n "$reuse" ]] && printf '\n**Reuse check:** %s\n' "$reuse"
    printf '\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nn/a\n\n**Edge Cases:**\n- none\n'
  } > "$PLAN"
}

# ── AC1: a founding step with no field is refused ───────────────────────────
@test "reuse: Create: step without a Reuse check field is refused (strict)" {
  _plan strict '- Create: `src/new.ts` — new thing'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no **Reuse check:** field"* ]]
}

# ── AC2: prose is not evidence, and the message says what is expected ───────
@test "reuse: a field with no search command is refused and names the shape" {
  _plan strict '- Create: `src/new.ts` — new thing' 'I looked around and found nothing like it'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"names no search command"* ]]
}

@test "reuse: a command that pipes or chains is refused by name" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `grep -rn isoNow src/ | wc -l` → none — nothing'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"pipes, redirects or chains"* ]]
}

@test "reuse: a command outside the read-only search vocabulary is not run" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `cat src/known.ts` → none — nothing'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"names no search command"* ]]
}

@test "reuse: a flag that runs another program is refused by name" {
  # The tool allowlist is not the boundary on its own — `find -exec`,
  # `rg --pre` and `--config` are the ways out of it.
  _plan strict '- Create: `src/new.ts` — new' 'searched: `rg --pre ./anything isoNow src/` → none — nothing'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"runs another program"* ]]
}

@test "reuse: a field stating no result is refused" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `grep -rn isoNow src/` — did not really conclude'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"states no result"* ]]
}

# ── AC3: a step that founds nothing owes nothing ────────────────────────────
@test "reuse: a step with no Create: bullet does not owe the field" {
  _plan strict '- Modify: `src/known.ts` — edit'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

# ── AC4: all four results are valid, and the replay agrees with each ────────
@test "reuse: result 'none' passes when the search really finds nothing" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `grep -rn relativeCzech src/` → none — nothing like it exists yet'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "reuse: result 'one match' passes when the search finds one" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `grep -rln isoNow src/` → one match `src/known.ts` — it formats, this parses'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "reuse: result 'several matching' passes and keeps the canonical choice" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `grep -rn isoNow src/` → several matching `src/known.ts` — canonical is the newest, this one'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

@test "reuse: the Czech spellings of the four results are accepted" {
  _plan strict '- Create: `src/new.ts` — new' 'hledáno: `grep -rn relativeCzech src/` → nic — nic takového zatím není'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
}

# ── the replay: a claim that contradicts what the command returns ───────────
@test "reuse: 'none' over a command that finds something today is refused" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `grep -rn isoNow src/` → none — nothing like it exists'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"the evidence and the claim disagree"* ]]
}

@test "reuse: a claim of one match over a command that finds nothing is refused" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `grep -rn relativeCzech src/` → one match `src/known.ts` — close enough'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"the evidence and the claim disagree"* ]]
}

@test "reuse: a command that does not run here is refused as stale evidence" {
  _plan strict '- Create: `src/new.ts` — new' 'searched: `grep -rn isoNow no-such-dir/` → none — nothing'
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not run here"* ]]
}

# ── AC5/AC6: the two tiers ──────────────────────────────────────────────────
@test "reuse: a legacy plan without the field passes with a loud advisory" {
  _plan legacy '- Create: `src/new.ts` — new thing'
  run "$LINT" "$PLAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN legacy]"* ]]
  [[ "$output" == *"no **Reuse check:** field"* ]]
}

# ── the obligation is band-independent ──────────────────────────────────────
@test "reuse: a light-band plan owes the field too" {
  # `light` is what a plan touching only ordinary source code classifies as —
  # and founding a duplicate is exactly what a small plan does.
  _plan strict '- Create: `src/new.ts` — new thing'
  band="$(bash "$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh" --plan "$PLAN" --project-root "$TEST_DIR" --classify-only 2>/dev/null)"
  [ "$band" = "light" ]
  run "$LINT" "$PLAN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no **Reuse check:** field"* ]]
}
