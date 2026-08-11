#!/usr/bin/env bats
# aid-tier: t2
# test-plan-tier-declaration.bats — P081 Step 10: the budget on the way in.
#
# WHAT THIS SUITE PROVES: generation refuses a plan that would add an UNTIERED
# suite, and refuses nothing else. The three negatives are the point — a rule
# that also fires on adding a case to an existing suite, on a fixture path, or
# on a project that has never adopted tiers would be paid for on every plan and
# switched off within a month.
#
# Fixture plans are written with printf, never a heredoc (IMP-494 discipline —
# these carry no `@test` lines, but the convention is one rule, not two).
#
# Result count after any edit:
#   bats --tap test-plan-tier-declaration.bats | grep -cE '^(ok|not ok)'   # == 6

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  EPIC_TEMPLATE="$AID_PLUGIN_PATH/defaults/templates/epic.md"
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  export PLAN_TO_EPIC EPIC_TEMPLATE TEST_TMPDIR ROOT
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT"
  mkdir -p "$ROOT/scripts/tests/bats" "$ROOT/scripts/tests/fixtures" \
           "$ROOT/output"
  printf 'counter: 0\n' > "$ROOT/epic-counter.yaml"
  # An existing, TAGGED suite — this is what makes the tree "tiered", and what
  # a Test bullet may point at without declaring anything.
  printf '#!/usr/bin/env bats\n# aid-tier: t0\n' \
    > "$ROOT/scripts/tests/bats/test-existing.bats"
  cd "$ROOT"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# _plan <files-bullet> — a minimal one-step plan carrying that Files bullet.
_plan() {
  local f="$ROOT/plan.md"
  printf -- '---\nid: P900\ntype: plan\nstatus: approved\n---\n\n' > "$f"
  printf '# Plan: fixture\n\n## Implementation Steps\n\n' >> "$f"
  printf '### Step 1: Do a thing\n\n' >> "$f"
  printf '**Objective:** Prove the tier rule.\n\n' >> "$f"
  printf '**Files:**\n- Modify: `scripts/thing.sh` — the subject\n' >> "$f"
  printf -- '- %s\n\n' "$1" >> "$f"
  printf '**Effort:** S\n\n**AID Role:** backend\n' >> "$f"
  printf '%s\n' "$f"
}

_generate() {
  run bash "$PLAN_TO_EPIC" --plan "$1" --phase 1 --total 1 \
    --epic-template "$EPIC_TEMPLATE" --output-dir "$ROOT/output" \
    --counter-yaml "$ROOT/epic-counter.yaml" 3>&-
}

@test "1: a NEW suite with no tier stops generation, naming the step" {
  _generate "$(_plan 'Test: `scripts/tests/bats/test-brand-new.bats` — what it proves')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"step 1"* ]]
  [[ "$output" == *"no tier"* ]]
  [[ "$output" == *"test-brand-new.bats"* ]]
}

@test "2: the same bullet with a tier generates" {
  _generate "$(_plan 'Test: `scripts/tests/bats/test-brand-new.bats` (tier: t1) — what it proves')"
  [ "$status" -eq 0 ]
  [ -n "$(ls "$ROOT/output"/E-*.md 2>/dev/null)" ]
}

@test "3: an unknown tier value is refused, not silently ignored" {
  _generate "$(_plan 'Test: `scripts/tests/bats/test-brand-new.bats` (tier: t9) — what it proves')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"t9"* ]]
  [[ "$output" == *"t0/t1/t2"* ]]
}

@test "4: a bullet pointing at an EXISTING suite needs no declaration" {
  _generate "$(_plan 'Test: `scripts/tests/bats/test-existing.bats` — one more case')"
  [ "$status" -eq 0 ]
}

@test "5: a fixture is not a suite, so it is never asked for a tier" {
  _generate "$(_plan 'Test: `scripts/tests/fixtures/sample-input.json` — the input')"
  [ "$status" -eq 0 ]
}

@test "5b: a fixture with a tier-shaped parenthetical is still not a suite" {
  _generate "$(_plan 'Test: `scripts/tests/fixtures/sample-input.json` (tier: t9) — the input')"
  [ "$status" -eq 0 ]
}

@test "5c: a ROOT-relative suite path is a suite too" {
  # `tests/test-new.sh` — the ordinary shape in a consumer project. A pattern
  # anchored on `*/tests/` requires a directory before it and would never fire.
  mkdir -p "$ROOT/tests"
  _generate "$(_plan 'Test: `tests/test-brand-new.sh` — what it proves')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no tier"* ]]
}

@test "6: a project that has adopted no tiers generates exactly as before" {
  rm -f "$ROOT/scripts/tests/bats/test-existing.bats"
  _generate "$(_plan 'Test: `scripts/tests/bats/test-brand-new.bats` — what it proves')"
  [ "$status" -eq 0 ]
}
