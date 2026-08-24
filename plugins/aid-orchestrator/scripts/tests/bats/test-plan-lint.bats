#!/usr/bin/env bats
# aid-tier: t2
# test-plan-lint.bats — plan-time Files-shape lint (v2.58.3; P079 Step 5).
# Unit: every violation class, the two blocking tiers + legacy tolerance, and
# the non-blocking description-path advisory.
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
  # A plan always lives inside a project. Since v2.88.2 an unresolvable project
  # root is no longer a silently skipped reuse-evidence replay but a STRICT
  # violation ("the claim stands unverified"), so a fixture in a bare tmpdir
  # fails on its environment rather than on the grammar it is testing. The
  # plan-state marker is the documented escape in lib/aid-roots.sh: a directory
  # carrying it is honoured as a project root as-given, without a git repo.
  mkdir -p .aid-o/work/plan-state
}
teardown() { rm -rf "$TEST_DIR"; }

# write a minimal plan with a given frontmatter strictness + a single step Files block
_plan() { # <file> <strict|legacy> <files-block-lines...>
  local f="$1" strict="$2"; shift 2
  local sflag=""; [[ "$strict" == "strict" ]] && sflag=$'\nlifecycle_strict: true'
  { printf -- '---\nid: P900\ntype: regular\nrisk: low%s\n---\n' "$sflag"
    # The Testing Strategy section is what a plan owes since P084 Step 4 (a
    # `Test:` bullet per step no longer is). It is here so these fixtures keep
    # testing the FILES grammar and nothing else.
    printf '# Plan: P900\n\n## Testing Strategy\n\nNo new verification — this fixture exercises the Files grammar only.\n\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n'
    printf '%s\n' "$@"
    # P085: a step with a `Create:` bullet owes a **Reuse check:**. These
    # fixtures are about the FILES grammar, so the field is present, valid and
    # boring — a search that finds nothing in an empty tmpdir.
    printf '\n**Reuse check:** searched: `find . -name no-such-component.xyz` → none — nothing exists yet\n'
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
@test "lint ERROR (P079 Step 5, was STRICT): verb+path split across two lines blocks BOTH modes" {
  # Tier raised deliberately. This shape is `- Create:` with an empty body, and
  # since P079 Step 5 generation REFUSES it by name instead of dropping the path
  # in silence — so tolerating it for legacy plans would break the promise in
  # this lint's header: a plan that passes the lint passes generation.
  _plan ps.md strict '- Create:' '  `src/split.ts` — path on the next line'
  run "$LINT" ps.md; [ "$status" -ne 0 ]
  _plan pl.md legacy '- Create:' '  `src/split.ts` — path on the next line'
  run "$LINT" pl.md; [ "$status" -ne 0 ]
  [[ "$output" == *"verb label with no path"* ]]
}

# ── indented sub-bullets are prose continuation, NOT separate entries ────────
@test "lint: an indented sub-bullet under a clean entry is ignored (not a violation)" {
  _plan p.md strict '- Modify: `src/a.ts` — does things' '  - and also this elaboration (prose)'
  run "$LINT" p.md; [ "$status" -eq 0 ]
}

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

# ── usage / IO ───────────────────────────────────────────────────────────────
@test "lint: missing file -> usage exit 2" {
  run "$LINT" /nonexistent/plan.md; [ "$status" -eq 2 ]
}

# ── INTEGRATION: lint-clean plan flows clean through the WHOLE generator chain ─
@test "integration: a lint-clean plan passes aid-plan-to-epic -> aid-epic-to-json -> contract gate" {
  _plan clean.md strict '- Create: `src/a.ts` — new file' '- Modify: `src/b.ts` (lines ~1-9) — edit'
  run "$LINT" clean.md; [ "$status" -eq 0 ]                    # lint says clean
  mkdir -p out
  # IMP-503: DoD gate resolution requires a real execution.yaml at the
  # project's state root (fail-closed). TEST_DIR is a plain tmpdir (not a
  # git repo); the plan-state marker lets aid_canonicalize_project_root
  # honour it as-given without one.
  mkdir -p .aid-o/work/plan-state .aid-o/config
  printf 'gates: {}\n' > .aid-o/config/execution.yaml
  export AID_PROJECT_ROOT="$TEST_DIR"
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
@test "P079 Step 5: the lint and generation agree on both new refusals (the seam's whole promise)" {
  # aid-plan-lint.sh's header promises "a plan that passes this lint provably
  # passes the gate". Making generation refuse a shape the lint called clean
  # would have broken exactly that, so both shapes are ERROR tier in the shared
  # classifier — asserted here as one fact, in both directions.
  local shape
  for shape in '- `src/forgotten.ts` — no verb label' '- Modify:'; do
    _plan p.md legacy '- Create: `src/a.ts` — fine' "$shape"
    run "$LINT" p.md
    [ "$status" -ne 0 ]                                       # lint refuses
    mkdir -p out && rm -rf out && mkdir -p out
    run "$P2E" --plan p.md --phase 1 --total 1 \
      --epic-template "$AID_PLUGIN_PATH/defaults/templates/epic.md" \
      --output-dir out --counter-yaml counter.yaml
    [ "$status" -ne 0 ]                                       # generation too
    [ -z "$(ls out/ 2>/dev/null)" ]
  done
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

# ── human-audience sections (P084 Step 5) ───────────────────────────────────
# The PM's page is rendered from the plan (lib/aid-plan-summary.sh), so a
# hand-written summary section inside the plan is a second copy nothing checks.

@test "AC17: all four human-audience headings are reported, each on its own line" {
  {
    printf -- '---\nid: P900\ntype: regular\nlifecycle_strict: true\n---\n'
    printf '# Plan: P900\n\n## Testing Strategy\n\nNothing new.\n\n'
    printf '## Stakeholder Brief\n\nx\n\n## Human Review Summary\n\nx\n\n'
    printf '## Executive Summary\n\nx\n\n## Shrnutí pro PM\n\nx\n\n'
    printf '### Step 1: work\n\n**Objective:** do it.\n\n**Files:**\n- Modify: `src/a.ts` — edit\n'
  } > human.md
  run "$LINT" human.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"'## Stakeholder Brief'"* ]]
  [[ "$output" == *"'## Human Review Summary'"* ]]
  [[ "$output" == *"'## Executive Summary'"* ]]
  [[ "$output" == *"'## Shrnutí pro PM'"* ]]
}

@test "AC17: a plan without them is not reported" {
  _plan clean.md strict '- Modify: `src/a.ts` — edit'
  run "$LINT" clean.md
  [ "$status" -eq 0 ]
  [[ "$output" != *"written for a human"* ]]
}
