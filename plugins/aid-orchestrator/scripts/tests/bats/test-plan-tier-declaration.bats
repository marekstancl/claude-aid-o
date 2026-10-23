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
#   bats --tap test-plan-tier-declaration.bats | grep -cE '^(ok|not ok)'   # == 13

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  export TEST_TMPDIR ROOT
  unset AID_PROJECT_ROOT
  aid_test_mk_repo "$ROOT"
  mkdir -p "$ROOT/scripts/tests/bats" "$ROOT/scripts/tests/fixtures"
  # An existing, TAGGED suite — this is what makes the tree "tiered", and what
  # a Test bullet may point at without declaring anything.
  printf '#!/usr/bin/env bats\n# aid-tier: t0\n' \
    > "$ROOT/scripts/tests/bats/test-existing.bats"
  # IMP-503: DoD gate resolution requires a real execution.yaml at the
  # project's state root (fail-closed). An empty gates: mapping is a valid
  # outcome; this fixture just needs to exist and parse.
  mkdir -p "$ROOT/.aid-o/config"
  printf 'gates: {}\n' > "$ROOT/.aid-o/config/execution.yaml"
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

# _generate — what plan-run does before it builds anything (P114: the EPIC
# generator is gone): readiness (the plan lint inside it) and the shared
# plan.json reader, which refuses a NEW suite without its tier.
# (No CP1 round: readiness and the plan.json reader do not read one, and since 2.116 a round is not even
# prepared over a plan readiness refuses — seeding one made every refusal case fail in setup, 3.7.0-3.9.0.)
_generate() {
  run bash -c 'bash "$AID_PLUGIN_PATH/scripts/aid-generation-readiness.sh" "$1" --total 1 --project-root "$ROOT" \
    && source "$AID_PLUGIN_PATH/scripts/lib/common.sh" && source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-json.sh" \
    && aid_plan_json_steps_from_plan "$1" >/dev/null' _ "$1" 3>&-
}

@test "1: a NEW suite with no tier stops generation, naming the line" {
  _generate "$(_plan 'Test: `scripts/tests/bats/test-brand-new.bats` — what it proves')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plan.md:17: ERROR"* ]]   # the lint inside generation names the line (P100: one rule, author and generator)
  [[ "$output" == *"declare its tier"* ]]
  [[ "$output" == *"test-brand-new.bats"* ]]
}

@test "1b: the plan lint reports the same rule, so the author meets it before generation" {
  local plan; plan="$(_plan 'Test: `scripts/tests/bats/test-brand-new.bats` — what it proves')"
  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh" "$plan"
  [[ "$output" == *"a Test bullet naming a NEW suite must declare its tier"* ]]
  plan="$(_plan 'Test: `scripts/tests/bats/test-existing.bats` — one more case')"
  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-lint.sh" "$plan"
  [[ "$output" != *"declare its tier"* ]]
}

@test "2: the same bullet with a tier generates" {
  _generate "$(_plan 'Test: `scripts/tests/bats/test-brand-new.bats` (tier: t1) — what it proves')"
  [ "$status" -eq 0 ]
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
  [[ "$output" == *"declare its tier"* ]]
}

@test "6: a project that has adopted no tiers generates exactly as before" {
  rm -f "$ROOT/scripts/tests/bats/test-existing.bats"
  _generate "$(_plan 'Test: `scripts/tests/bats/test-brand-new.bats` — what it proves')"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# P084 Step 4 — the Test: bullet is optional, the Testing Strategy is not.
#
# The two rules pull in opposite directions on purpose: a step owes no test
# item, but a plan owes a stated strategy, and a NEW suite still owes its tier.
# ---------------------------------------------------------------------------

# _plan_no_test — the same minimal plan, with no `Test:` bullet at all.
_plan_no_test() {
  local f="$ROOT/plan.md"
  printf -- '---\nid: P900\ntype: plan\nstatus: approved\n---\n\n' > "$f"
  printf '# Plan: fixture\n\n## Testing Strategy\n\n' >> "$f"
  printf 'One case in the existing t0 suite — the behaviour is the parser, not the wiring.\n\n' >> "$f"
  printf '## Implementation Steps\n\n' >> "$f"
  printf '### Step 1: Do a thing\n\n' >> "$f"
  printf '**Objective:** Prove a step needs no Test bullet.\n\n' >> "$f"
  printf '**Files:**\n- Modify: `scripts/thing.sh` — the subject\n\n' >> "$f"
  printf '**Effort:** S\n\n**AID Role:** backend\n' >> "$f"
  printf '%s\n' "$f"
}

@test "7: a step with NO Test bullet generates" {
  _generate "$(_plan_no_test)"
  [ "$status" -eq 0 ]
}

@test "8: a strict plan with no Testing Strategy stops generation" {
  plan="$(_plan_no_test)"
  # Strict cohort: the lifecycle model these plans opt into is where the
  # requirement bites. Legacy plans get the same finding as an advisory.
  sed -i 's/^status: approved$/status: approved\nlifecycle_strict: true/' "$plan"
  sed -i '/^## Testing Strategy$/,+2d' "$plan"
  # No review can be seeded for it (the review's own lint refuses it first),
  # so readiness — what plan-run runs before anything — is asked directly.
  run bash "$AID_PLUGIN_PATH/scripts/aid-generation-readiness.sh" "$plan" --total 1 --project-root "$ROOT" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"Testing Strategy"* ]]
}

@test "9: a legacy plan with no Testing Strategy still generates, loudly" {
  plan="$(_plan_no_test)"
  sed -i '/^## Testing Strategy$/,+2d' "$plan"
  _generate "$plan"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Testing Strategy"* ]]
}
