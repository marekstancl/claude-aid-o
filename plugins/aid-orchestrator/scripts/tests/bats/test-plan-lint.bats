#!/usr/bin/env bats
# aid-tier: t2
# test-plan-lint.bats — plan-time Files-shape lint (v2.58.3; P079 Step 5).
# Unit: every violation class, the two blocking tiers + legacy tolerance, and
# the non-blocking description-path advisory.
# Integration: lint-clean plan flows through the former EPIC generator -> the former EPIC-to-plan.json converter
# -> contract gate with all three agreeing (proves the lint and the generator do
# not have a different reality), and the preflight fail-fasts BEFORE any write.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  LINT="$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh"
  GATE="$AID_PLUGIN_PATH/scripts/gates/aid-contract-validate.sh"
  TEST_DIR="$(mktemp -d)"; cd "$TEST_DIR"
  # A plan always lives inside a project. Since v2.88.2 an unresolvable project
  # root is no longer a silently skipped reuse-evidence replay but a STRICT
  # violation ("the claim stands unverified"), so a fixture in a bare tmpdir
  # fails on its environment rather than on the grammar it is testing. The
  # plan-state marker is the documented escape in lib/aid-roots.sh: a directory
  # carrying it is honoured as a project root as-given, without a git repo.
  mkdir -p .aid-o/work/plan-state
  source "$AID_PLUGIN_PATH/scripts/tests/lib/aid-test-plan-fixture.sh"
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
    printf '# Plan: P900\n\n## Testing Strategy\n\nNo new verification — this fixture exercises the Files grammar only.\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n'
    printf '%s\n' "$@"
    # P085: a step with a `Create:` bullet owes a **Reuse check:**. These
    # fixtures are about the FILES grammar, so the field is present, valid and
    # boring — a search that finds nothing in an empty tmpdir.
    printf '\n**Reuse check:** searched: `find . -name no-such-component.xyz` → none — nothing exists yet\n'
    printf '\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nn/a\n\n**Edge Cases:**\nn/a\n'
  } > "$f"
  # P109: a strict plan names its brief; these fixtures test other things
  [[ "$strict" == "strict" ]] && aid_fixture_write_brief "$TEST_DIR" "$f" >/dev/null
  return 0
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
@test "no-epic: a plan without an EPIC marker lints clean (P114: one plan = one run)" {
  _plan p.md strict '- Create: `src/a.ts` — new'
  sed -i '/^\*\*EPIC 1: Steps 1-1\*\*$/d' p.md
  ! grep -q '^\*\*EPIC' p.md
  run "$LINT" p.md; echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" != *"EPIC"* ]]
}
@test "no-epic: a plan that still carries EPIC markers (any form) gets one ADVISORY that they are ignored, never a finding" {
  _plan p.md strict '- Create: `src/a.ts` — new'
  sed -i 's/^### Step 1: work$/**EPIC 1**\n\n### Step 1: work/' p.md; grep -q '^\*\*EPIC 1\*\*$' p.md
  run "$LINT" p.md; echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" == *"[ADVISORY] EPIC markers"*"are ignored since AID 3.0.0"* ]]
  [ "$(grep -c 'EPIC markers' <<< "$output")" -eq 1 ]
}
@test "lint: an EPIC line quoted in a fenced block is an example, not a declaration" {
  _plan p.md strict '- Create: `src/a.ts` — new'
  printf '\n```markdown\n**EPIC 1**\n```\n' >> p.md
  run "$LINT" p.md; [ "$status" -eq 0 ]
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

# ── INTEGRATION: the preflight fail-fasts BEFORE any EPIC/counter write ──────

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

# ── IMP-517: a suite named only in prose (P089 Step 11) ─────────────────────
#
# ADVISORY, deliberately. The lint's exit code is unchanged in every case
# below; what is asserted is the line, and its absence where the name is
# already declared or already exists.

# _plan_ts <file> <testing-strategy-body…> — a lint-clean plan whose Testing
# Strategy is whatever the caller says.
_plan_ts() {
  local f="$1"; shift
  { printf -- '---\nid: P900\ntype: regular\nrisk: low\n---\n'
    printf '# Plan: P900\n\n## Testing Strategy\n\n'
    printf '%s\n' "$@"
    printf '\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n'
    printf -- '- Modify: `src/b.ts` (lines ~1-9) — edit\n'
    printf '\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nn/a\n\n**Edge Cases:**\nn/a\n'
  } > "$f"
}

@test "IMP-517: a suite named only in prose is reported, advisory" {
  _plan_ts p.md 'Nová sada `test-nothing-writes-it.bats` pokryje obě větve.'
  run "$LINT" p.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-nothing-writes-it.bats"* ]]
  [[ "$output" == *"[ADVISORY]"* ]]
  [[ "$output" == *"is in no \`Test:\` bullet"* ]]
}

@test "IMP-517: the same name declared in a Test: bullet is not reported" {
  { printf -- '---\nid: P900\ntype: regular\nrisk: low\n---\n'
    printf '# Plan: P900\n\n## Testing Strategy\n\nNová sada `test-declared.bats` pokryje obě větve.\n'
    printf '\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n**Files:**\n'
    printf -- '- Test: `scripts/tests/bats/test-declared.bats`\n'
    printf '\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nn/a\n\n**Edge Cases:**\nn/a\n'
  } > p.md
  run "$LINT" p.md
  [ "$status" -eq 0 ]
  [[ "$output" != *"is in no \`Test:\` bullet"* ]]
}

@test "IMP-517: a suite that already exists is not a promise" {
  mkdir -p suites
  : > suites/test-already-here.bats
  _plan_ts p.md 'Rozšíříme `test-already-here.bats` o dva případy.'
  run "$LINT" p.md
  [ "$status" -eq 0 ]
  [[ "$output" != *"test-already-here.bats\` is named in"* ]]
}

@test "IMP-517: a suite named in a STEP, not in the strategy, is not scanned" {
  # The section ends at `### Step`. Without that, a plan whose Testing Strategy
  # is its last `##` section had every step's prose read as strategy.
  { printf -- '---\nid: P900\ntype: regular\nrisk: low\n---\n'
    printf '# Plan: P900\n\n## Testing Strategy\n\nBez nové sady.\n'
    printf '\n**EPIC 1: Steps 1-1**\n\n### Step 1: work\n\n**Objective:** implement the thing properly for this step.\n\n'
    printf 'Prozaicka zminka o `test-only-in-a-step.bats`.\n\n**Files:**\n'
    printf -- '- Modify: `src/b.ts` (lines ~1-9) — edit\n'
    printf '\n**Architecture Context:**\nn/a\n\n**Error Handling:**\nn/a\n\n**Edge Cases:**\nn/a\n'
  } > p.md
  run "$LINT" p.md
  [ "$status" -eq 0 ]
  [[ "$output" != *"test-only-in-a-step.bats"* ]]
}

@test "IMP-517: a name inside a fenced block is an illustration, not a promise" {
  _plan_ts p.md 'Postup:' '' '```bash' 'bats scripts/tests/bats/test-illustration.bats' '```'
  run "$LINT" p.md
  [ "$status" -eq 0 ]
  [[ "$output" != *"test-illustration.bats"* ]]
}

# ── AID Role is a closed set ─────────────────────────────────────────────────
_plan_role() { # <file> <role>
  _plan "$1" legacy '- Create: `src/a.ts` — new'
  printf '\n**AID Role:** %s\n' "$2" >> "$1"
}
@test "lint: a valid AID Role passes" {
  _plan_role p.md backend
  run "$LINT" p.md; [ "$status" -eq 0 ]
}
@test "lint ERROR: an AID Role outside the closed set (fullstack) blocks before generation" {
  _plan_role p.md fullstack
  AID_QUIET=0 run "$LINT" p.md; [ "$status" -ne 0 ]
  [[ "$output" == *"AID Role 'fullstack' is not an AID role"* ]]
}
@test "lint ERROR: the colon-less header '**AID Role** fullstack' is checked too (generation accepts that form)" {
  _plan p.md legacy '- Create: `src/a.ts` — new'
  printf '\n**AID Role** fullstack\n' >> p.md
  run "$LINT" p.md; [ "$status" -ne 0 ]
}
@test "lint ERROR: a role with trailing words ('backend and frontend') is one value, and not a role" {
  _plan_role p.md 'backend and frontend'
  run "$LINT" p.md; [ "$status" -ne 0 ]
}

# ── another repository's file named only in prose (agents P009, 27. 9. 2026) ──
@test "lint advisory: a foreign absolute path only in a step's prose is reported; declared in that step's Files it is not" {
  _plan p.md strict '- Modify: `src/a.ts` — edit'
  printf '\n**Implementation Detail:** also fix `/opt/eco/docs/docs/agents/freelo.md` via amend-scope.\n' >> p.md
  run "$LINT" p.md
  [[ "$output" == *'`/opt/eco/docs/docs/agents/freelo.md` names another repository'* ]]
  _plan q.md strict '- Modify: `src/a.ts` — edit' '- Modify: `/opt/eco/docs/docs/agents/freelo.md` — the page'
  printf '\n**Implementation Detail:** also fix `/opt/eco/docs/docs/agents/freelo.md`.\n' >> q.md
  run "$LINT" q.md
  [[ "$output" != *"names another repository"* ]]
}

@test "lint advisory: another step's declaration does not cover a step's prose mention" {
  _plan p.md strict '- Modify: `src/a.ts` — edit'
  printf '\n**Error Handling:** see `/opt/eco/docs/x.md`.\n\n### Step 2: docs\n\n**Files:**\n- Modify: `/opt/eco/docs/x.md` — page\n' >> p.md
  run "$LINT" p.md
  [ "$(grep -c 'names another repository' <<< "$output")" -eq 1 ]
  grep 'names another repository' <<< "$output" | grep -q '### Step 1: work$' 
}

# ─── P107 Step 2: the verification-only marker belongs on Test: bullets only ───
@test "lint ERROR: the verification-only marker on a Modify: bullet blocks; on a Test: bullet it passes" {
  _plan p.md strict '- Modify: `src/b.ts` — verification-only, delete before plan-final'
  run "$LINT" p.md; [ "$status" -ne 0 ]
  [[ "$output" == *"verification-only marker allowed on Test: bullets only"* ]]
  _plan p.md strict '- Test: `t/x.bats` — ověřovací, smazat před koncem plánu: a one-off measurement'
  run "$LINT" p.md; [ "$status" -eq 0 ]
}

# ── P109 Step 2: the plan carries the brief ──────────────────────────────────
# The P014 pair: the brief of the comparative experiment and the plan that
# dropped its point 2 (fixtures/zadani/). Defect: a plan that quietly drops or
# rewrites a point of the brief, which nothing compared in P014.
_p014() {
  mkdir -p .aid-o/plans
  cp "$AID_PLUGIN_PATH/scripts/tests/fixtures/zadani/p014-zadani.md" .aid-o/plans/P014-zadani.md
  sed "s/SHA_OF_THE_BRIEF/$(sha256sum .aid-o/plans/P014-zadani.md | cut -d' ' -f1)/" \
    "$AID_PLUGIN_PATH/scripts/tests/fixtures/zadani/p014-plan.md" > .aid-o/plans/P014-plan.md
}
# A strict plan with a brief generated from its own criteria, then broken per case.
_bound() { _plan p.md strict '- Modify: `src/a.ts` — edit'; }

@test "zadani: the P014 plan fails the lint naming AC2" {
  _p014
  run "$LINT" .aid-o/plans/P014-plan.md --only zadani
  [ "$status" -eq 1 ]
  [[ "$output" == *"AC2 missing or rewritten"* ]]
  [[ "$output" == *"neznámá hodnota v konfiguraci skončí chybou při startu"* ]]
}

@test "zadani: a plan carrying every point verbatim passes; a rewritten block fails" {
  _bound
  run "$LINT" p.md --only zadani
  [ "$status" -eq 0 ]
  sed -i '0,/expected_exit: 0/s//expected_exit: 1/' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"AC1 missing or rewritten"* ]]
}

@test "zadani: a point no step closes, and a Zavírá naming AC99, are refused" {
  _bound
  sed -i 's/^\*\*Zavírá:\*\* AC1$/**Zavírá:** AC99/' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]
  [[ "$output" == *"names AC99, which the brief does not have"* ]]
  [[ "$output" == *"AC1 of the brief is closed by no step"* ]]
}

@test "zadani: a step of a brief-bound plan without Zavírá is refused; the same step in a plan without a brief is not" {
  _bound
  sed -i '/^\*\*Zavírá:\*\*/d' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"has no **Zavírá:** field"* ]]
  _plan q.md legacy '- Modify: `src/a.ts` — edit'
  run "$LINT" q.md --only zadani
  [ "$status" -eq 0 ]
}

@test "zadani: a wrong zadani_sha256 and a brief path outside the project are refused" {
  _bound
  sed -i 's/^zadani_sha256: .*/zadani_sha256: 0000/' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"is not the sha of"* ]]
  _bound
  sed -i 's#^zadani: .*#zadani: ../outside-zadani.md#' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"path escapes the project"* ]]
}

@test "zadani-required: a lifecycle_strict plan without zadani: is refused, a legacy one only warned" {
  _bound
  sed -i '/^zadani/d' p.md
  run "$LINT" p.md
  [ "$status" -eq 1 ]; [[ "$output" == *"strict plan without zadani:"* ]]
  _plan q.md legacy '- Modify: `src/a.ts` — edit'
  AID_QUIET=0 run "$LINT" q.md
  [ "$status" -eq 0 ]; [[ "$output" == *"[WARN legacy] plan names no brief"* ]]
}

@test "odvozeno: ## Architecture without Odvozeno z: is refused, with it accepted" {
  _bound
  printf '\n## Architecture\n\nOne reader.\n' >> p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"## Architecture does not open with **Odvozeno z:** AC<n>"* ]]
  sed -i 's/^One reader\.$/**Odvozeno z:** AC1\n\nOne reader./' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 0 ]
}

@test "zadani: zadani_verze absent or not the brief's verze is refused" {
  _bound
  sed -i '/^zadani_verze:/d' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"zadani_verze '<absent>' is not a positive integer"* ]]
  _bound
  sed -i 's/^zadani_verze: .*/zadani_verze: 2/' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"zadani_verze 2 but the brief"* ]]
}

@test "zadani: Zavírá naming a criterion the brief does not have (the plan's own included), or out of grammar, is refused" {
  _bound
  # AC2 is the plan's own here: generated briefs carry AC1 only
  awk '/^## Acceptance Criteria/ { print; print ""; print "- [ ] AC2: the plan adds its own"; print "  ```yaml"; print "  verification_pattern:"; print "    type: cmd"; print "    cmd: \"true\""; print "    expected_exit: 0"; print "  ```"; next } 1' p.md > p2 && mv p2 p.md
  sed -i 's/^\*\*Zavírá:\*\* AC1$/**Zavírá:** AC1, AC2/' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"names AC2, which the brief does not have"* ]]
  _bound
  sed -i 's/^\*\*Zavírá:\*\* AC1$/**Zavírá:** AC1 AC1/' p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"is not \"AC<n>[, AC<m>]\" or \"—\""* ]]
}

@test "odvozeno: a line that names no AC number is refused" {
  _bound
  printf '\n## Data Model\n\n**Odvozeno z:** ACbanana\n' >> p.md
  run "$LINT" p.md --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"## Data Model does not open with"* ]]
}

# ── P112 Step 4: an absolute path into an undeclared repository ───────────────
# outside the project (a repository inside it is repo_root_invalid); bats removes BATS_TEST_TMPDIR
_other_repo() { O="$BATS_TEST_TMPDIR/other"; mkdir -p "$O"; git -C "$O" init -q -b main; git -C "$O" -c user.email=t@t -c user.name=T commit -q --allow-empty -m init; }
_declare() { sed -i "0,/^risk: low/s||risk: low\nrepo_roots: [{name: other, path: $O}]|" p.md; }
_ac_cmd() { printf '\n## Acceptance Criteria\n\n- [ ] AC1: it is there\n  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "%s"\n    expected_exit: 0\n  ```\n' "$1" >> p.md; }

@test "lint-foreign: a Files bullet into a git repository repo_roots does not declare is an error" {
  _other_repo; _plan p.md strict "- Modify: \`$O/page.md\` — edit"
  run bash "$LINT" p.md
  [ "$status" -ne 0 ]; [[ "$output" == *"ERROR foreign_repo_undeclared: $O/page.md lies in $O"*"next:"*"(pipeline.md §When AID refuses: foreign_repo_undeclared)"* ]]
}
@test "lint-foreign: the same path with the repository declared in repo_roots passes" {
  _other_repo; _plan p.md strict "- Modify: \`$O/page.md\` — edit"; _declare
  run bash "$LINT" p.md; echo "$output"
  [ "$status" -eq 0 ]; [[ "$output" != *"foreign_repo_undeclared"* ]]
}
@test "lint-foreign: a criterion's cmd reading a file in the undeclared repository is an error" {
  _other_repo; _plan p.md strict '- Modify: `src/a.ts` — edit'; _ac_cmd "grep -q x $O/page.md"
  run bash "$LINT" p.md
  [ "$status" -ne 0 ]; [[ "$output" == *"ERROR foreign_repo_undeclared: $O/page.md"* ]]
}
@test "lint-foreign: a path outside any git repository (/tmp-like) is not judged" {
  mkdir -p "$TEST_DIR/nogit"; _plan p.md strict '- Modify: `src/a.ts` — edit'; _ac_cmd "test -d $TEST_DIR/nogit/x"
  run bash "$LINT" p.md; echo "$output"
  [[ "$output" != *"foreign_repo_undeclared"* ]]   # (the fixture's own brief binding fails on the appended criterion, not on this)
}
@test "lint-foreign: a path into the project's own .aid-worktrees/ worktree is the project (same common dir)" {
  git init -q -b main .; git -c user.email=t@t -c user.name=T commit -q --allow-empty -m seed
  git worktree add -q -b plan/x .aid-worktrees/plan-x
  _plan p.md strict "- Modify: \`$TEST_DIR/.aid-worktrees/plan-x/src/a.ts\` — edit"
  run bash "$LINT" p.md; echo "$output"
  [[ "$output" != *"foreign_repo_undeclared"* ]]
}
@test "lint-foreign: a YAML example in prose that is no criterion is not judged" {
  _other_repo; _plan p.md strict '- Modify: `src/a.ts` — edit'
  printf '\n## Notes\n\n```yaml\ncmd: "grep x %s/page.md"\n```\n' "$O" >> p.md
  run bash "$LINT" p.md; echo "$output"
  [ "$status" -eq 0 ]; [[ "$output" != *"foreign_repo_undeclared"* ]]
}
@test "lint-foreign: a path whose directory cannot be read is an advisory, not judged" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  mkdir -p "$TEST_DIR/locked/in"; chmod 000 "$TEST_DIR/locked"
  _plan p.md strict '- Modify: `src/a.ts` — edit'; _ac_cmd "test -f $TEST_DIR/locked/in/f"
  run bash "$LINT" p.md; chmod 755 "$TEST_DIR/locked"; echo "$output"
  [[ "$output" == *"[ADVISORY]"*"cannot be read"*"not judged for repo_roots"* ]]
  [[ "$output" != *"foreign_repo_undeclared"* ]]
}
