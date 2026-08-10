#!/usr/bin/env bats
# test-plan-lint.bats — plan-time Files-shape lint (v2.58.3).
# Unit: every violation class + two-tier severity + legacy tolerance.
# Integration: lint-clean plan flows through aid-plan-to-epic -> aid-epic-to-json
# -> contract gate with all three agreeing (proves the lint and the generator do
# not have a different reality), and the preflight fail-fasts BEFORE any write.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  LINT="$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh"
  P2E="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  E2J="$AID_PLUGIN_PATH/scripts/aid-epic-to-json.sh"
  GATE="$AID_PLUGIN_PATH/scripts/gates/aid-contract-validate.sh"
  TEST_DIR="$(mktemp -d)"; cd "$TEST_DIR"
}
teardown() { rm -rf "$TEST_DIR"; }

# write a minimal plan with a given frontmatter strictness + a single step Files block
_plan() { # <file> <strict|legacy> <files-block-lines...>
  local f="$1" strict="$2"; shift 2
  local sflag=""; [[ "$strict" == "strict" ]] && sflag=$'\nlifecycle_strict: true'
  { printf -- '---\nid: P900\ntype: regular\nrisk: low%s\n---\n' "$sflag"
    printf '# Plan: P900\n\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n'
    printf '%s\n' "$@"
    printf '\n**Architecture Context:**\nn/a\n'
  } > "$f"
}

# ── clean canonical forms => PASS ────────────────────────────────────────────
@test "lint: canonical Files entries pass (strict)" {
  _plan p.md strict '- Create: `src/a.ts` — new' '- Modify: `src/b.ts` (lines ~1-9) — edit' '- Test: `t/x.bats`' '- Modify: `a.md` + `b.md` — dual'
  run "$LINT" p.md; [ "$status" -eq 0 ]
}

# ── ERROR-tier (gate-breaking) => blocks in BOTH strict and legacy ───────────
@test "lint ERROR: prose-only (fallback bad-shape) blocks even legacy" {
  _plan p.md legacy '- Modify: the 6 remaining version files.'
  run "$LINT" p.md; [ "$status" -ne 0 ]
}
@test "lint ERROR: bold-wrapped bullet blocks even legacy" {
  _plan p.md legacy '- **Modify: `.gitignore` — un-ignore:** the bare rule'
  run "$LINT" p.md; [ "$status" -ne 0 ]
}
@test "lint ERROR: parenthetical-note bullet blocks even legacy" {
  _plan p.md legacy '- (Schema support for `x` is already in Step 4 — no change.)'
  run "$LINT" p.md; [ "$status" -ne 0 ]
}
@test "lint ERROR: a word before the backtick path blocks even legacy" {
  _plan p.md legacy '- Test: extend `scripts/x.sh` (or a yq assertion) to check'
  run "$LINT" p.md; [ "$status" -ne 0 ]
}
@test "lint ERROR: comma-separated backtick paths blocks even legacy (ambiguous-entry, not silent narrowing)" {
  _plan p.md legacy '- Modify: `src/a.ts`, `src/b.ts`'
  run "$LINT" p.md
  [ "$status" -ne 0 ]
  [[ "$output" == *"unparsed text after a path"* ]]
}
@test "lint ERROR: conjunction-joined backtick paths (no ' + ') blocks even legacy" {
  _plan p.md legacy '- Modify: `src/a.ts` and `src/b.ts`'
  run "$LINT" p.md
  [ "$status" -ne 0 ]
}

# ── STRICT-tier (cleaner-OK, non-canonical) => strict blocks, legacy advisory ─
@test "lint STRICT: non-(lines) parenthetical blocks strict, passes legacy" {
  _plan ps.md strict '- Modify: `file.md` (both spots: foo) — desc'
  run "$LINT" ps.md; [ "$status" -ne 0 ]           # strict: blocked
  _plan pl.md legacy '- Modify: `file.md` (both spots: foo) — desc'
  run "$LINT" pl.md; [ "$status" -eq 0 ]           # legacy: advisory, non-blocking
}
@test "lint STRICT: path without backticks blocks strict, passes legacy" {
  _plan ps.md strict '- Modify: src/nobacktick.ts — no backticks'
  run "$LINT" ps.md; [ "$status" -ne 0 ]
  _plan pl.md legacy '- Modify: src/nobacktick.ts — no backticks'
  run "$LINT" pl.md; [ "$status" -eq 0 ]
}
@test "lint STRICT: verb+path split across two lines (dropped path) blocks strict, passes legacy" {
  _plan ps.md strict '- Create:' '  `src/split.ts` — path on the next line'
  run "$LINT" ps.md; [ "$status" -ne 0 ]
  _plan pl.md legacy '- Create:' '  `src/split.ts` — path on the next line'
  run "$LINT" pl.md; [ "$status" -eq 0 ]
}

# ── indented sub-bullets are prose continuation, NOT separate entries ────────
@test "lint: an indented sub-bullet under a clean entry is ignored (not a violation)" {
  _plan p.md strict '- Modify: `src/a.ts` — does things' '  - and also this elaboration (prose)'
  run "$LINT" p.md; [ "$status" -eq 0 ]
}

# ── usage / IO ───────────────────────────────────────────────────────────────
# ── P079 Step 5 (IMP-480): the drop shape the live P076 run actually hit ─────
#
# Its Files bullet was CANONICAL and parsed cleanly; the second path lived in
# the bullet's DESCRIPTION, so it never reached allowed_paths and the
# implementer was forbidden to touch a file the step's own plan assigned it.
# Advisory, never blocking — a description path is as often a reference as a
# forgotten scope entry.

@test "P079 Step 5: a path named only in a bullet's description is reported (the live P076 shape) and never blocks" {
  _plan p.md strict '- Test: `plugins/x/tests/test-skill-lint.sh` — run over all modified cards; plus a grep test in `plugins/x/tests/bats/test-instruction-closure.bats` asserting every agent card references the shared section.'
  run "$LINT" p.md
  [ "$status" -eq 0 ]                                   # advisory, not a block
  [[ "$output" == *"ADVISORY"* ]]
  [[ "$output" == *"test-instruction-closure.bats"* ]]
  [[ "$output" != *"test-skill-lint.sh\` is named only"* ]]   # the declared path is not flagged
}

@test "P079 Step 5: declared paths, directories and placeholders in a description are NOT flagged" {
  _plan p.md strict \
    '- Modify: `src/a.ts` + `src/b.ts` — b is edited alongside a.' \
    '- Modify: `src/c.ts` — writes into `<evidence_dir>/jobs/` and reads `some/dir/`.'
  run "$LINT" p.md
  [ "$status" -eq 0 ]
  [[ "$output" != *"ADVISORY"* ]]
}

@test "lint: missing file -> usage exit 2" {
  run "$LINT" /nonexistent/plan.md; [ "$status" -eq 2 ]
}

# ── INTEGRATION: lint-clean plan flows clean through the WHOLE generator chain ─
@test "integration: a lint-clean plan passes aid-plan-to-epic -> aid-epic-to-json -> contract gate" {
  _plan clean.md strict '- Create: `src/a.ts` — new file' '- Modify: `src/b.ts` (lines ~1-9) — edit'
  run "$LINT" clean.md; [ "$status" -eq 0 ]                    # lint says clean
  mkdir -p out
  run "$P2E" --plan clean.md --phase 1 --total 1 \
    --epic-template "$AID_PLUGIN_PATH/defaults/templates/epic.md" \
    --output-dir out --counter-yaml counter.yaml
  [ "$status" -eq 0 ]                                          # generation succeeds
  local epic; epic="$(ls out/E-*.md | head -1)"; [ -n "$epic" ]
  run "$E2J" --epic "$epic" --schema "$AID_PLUGIN_PATH/defaults/templates/plan.schema.json" \
    --output-dir aidout --plan-source clean.md
  [ "$status" -eq 0 ]                                          # EPIC.md -> plan.json OK
  local pj; pj="$(echo "$output" | jq -r '.plan_json')"; [ -f "$pj" ]
  run "$GATE" "$pj" "$epic"
  [ "$status" -eq 0 ]                                          # contract gate agrees: clean
  [[ "$(echo "$output" | jq -r '.result')" == "pass" ]]
}

# ── INTEGRATION: the preflight fail-fasts BEFORE any EPIC/counter write ──────
@test "integration: a strict plan with an ERROR entry is blocked by the preflight; NO EPIC written, NO counter bumped" {
  _plan dirty.md strict '- Modify: the 6 remaining version files.'
  mkdir -p out
  run "$P2E" --plan dirty.md --phase 1 --total 1 \
    --epic-template "$AID_PLUGIN_PATH/defaults/templates/epic.md" \
    --output-dir out --counter-yaml counter.yaml
  [ "$status" -eq 7 ]                                         # documented lint-fail code (NOT a bare set -e exit 1)
  [[ "$output" == *"ERROR"* ]]                                # the violation is actually listed (not silent)
  [[ "$output" == *"Generation readiness failed"* ]]         # + the error_exit reason
  [ -z "$(ls out/ 2>/dev/null)" ]                             # NO EPIC file written
  [ ! -f counter.yaml ]                                       # counter not created/bumped
}

# ── INTEGRATION: lint ERROR set == what the contract gate would reject ───────
@test "integration: an ERROR entry the lint blocks is ALSO one the contract gate rejects (same reality)" {
  # legacy plan so the preflight does not abort generation on this strict-only fixture;
  # the ERROR here is bad-shape, which is gate-breaking regardless of mode.
  _plan dirty.md legacy '- Modify: the 6 remaining version files.'
  run "$LINT" dirty.md --legacy; [ "$status" -ne 0 ]          # lint: ERROR (blocks even legacy)
}

# ── REGRESSION: a comma-separated multi-path entry fails EPIC generation
# outright rather than silently narrowing allowed_paths to the first path
# (the historical bug this test guards against). Legacy plan, so this proves
# the fail-closed behavior is NOT gated behind lifecycle_strict.
@test "P079 Step 5: an UNLABELLED Files bullet fails generation by name instead of vanishing" {
  # The lint calls this bad-shape and blocks it too; generation is the
  # defense-in-depth half, because a plan can reach the generator without the
  # preflight (direct invocation, an older plan, a --force path).
  _plan dirty.md legacy '- Create: `src/a.ts` — fine' '- `src/forgotten.ts` — no verb label'
  mkdir -p out
  run "$P2E" --plan dirty.md --phase 1 --total 1 \
    --epic-template "$AID_PLUGIN_PATH/defaults/templates/epic.md" \
    --output-dir out --counter-yaml counter.yaml
  [ "$status" -ne 0 ]
  [[ "$output" == *"src/forgotten.ts"* ]]                     # named, not counted
  [ -z "$(ls out/ 2>/dev/null)" ]
}

@test "P079 Step 5: a Files bullet with a verb but no path fails generation instead of producing an empty entry" {
  _plan dirty.md legacy '- Create: `src/a.ts` — fine' '- Modify:'
  mkdir -p out
  run "$P2E" --plan dirty.md --phase 1 --total 1 \
    --epic-template "$AID_PLUGIN_PATH/defaults/templates/epic.md" \
    --output-dir out --counter-yaml counter.yaml
  [ "$status" -ne 0 ]
  [[ "$output" == *"verb but no path"* ]]
  [ -z "$(ls out/ 2>/dev/null)" ]
}

@test "integration: comma-separated Files entry fails aid-plan-to-epic generation (legacy plan), never silently narrows" {
  _plan dirty.md legacy '- Modify: `src/a.ts`, `src/b.ts`'
  mkdir -p out
  run "$P2E" --plan dirty.md --phase 1 --total 1 \
    --epic-template "$AID_PLUGIN_PATH/defaults/templates/epic.md" \
    --output-dir out --counter-yaml counter.yaml
  [ "$status" -ne 0 ]
  [ -z "$(ls out/ 2>/dev/null)" ]                             # NO EPIC file silently written with narrowed scope
}
