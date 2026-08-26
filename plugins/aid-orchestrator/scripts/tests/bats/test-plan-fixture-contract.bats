#!/usr/bin/env bats
# aid-tier: t1
# test-plan-fixture-contract.bats — seeding a plan makes it GENERATION-READY,
# proven by running the real generation entry point.
#
# THE PROTECTION THIS IS. Three times in three weeks a fail-closed precondition
# was added to EPIC generation (2026-08-05 the plan must be committed, 08-14 a
# real execution.yaml, 08-24 a rendered PM page). Each time the merge-path
# fixtures were updated and the ~15 `aid-tier: t2` ones were not — so the
# breakage surfaced in a nightly days later and was repaired file by file.
#
# A grep rule would not have caught any of them. THIS does: it seeds through the
# shared helper and then invokes the real generator, so a FOURTH precondition
# fails here, on the merge path, in one place — instead of fifteen times at
# night. (Design reviewed cross-model, 2026-08-26; this test is the review's
# central ask.)

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FIXTURES="$AID_PLUGIN_PATH/scripts/tests/fixtures"
  PLAN_TO_EPIC="$AID_PLUGIN_PATH/scripts/aid-plan-to-epic.sh"
  export FIXTURES PLAN_TO_EPIC
  TEST_TMPDIR="$(mktemp -d)"; export TEST_TMPDIR
  unset AID_PROJECT_ROOT
}

teardown() { cd /; [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"; return 0; }

# _repo <dir> [tracked] — a committed workspace. `tracked` leaves `.aid-o/` OUT
# of .gitignore, which is the shape where generation requires a committed plan.
_repo() {
  local d="$1" tracked="${2:-}"
  mkdir -p "$d/.aid-o/config" "$d/.aid-o/plans" "$d/.aid-o/work/evidence"
  [[ -n "$tracked" ]] || printf '.aid-o/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  ( cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A && git commit -q -m "seed" )
}

@test "CONTRACT: a seeded plan passes the REAL generation entry point (tracked .aid-o)" {
  local d="$TEST_TMPDIR/tracked"; _repo "$d" tracked
  run aid_fixture_seed_plan "$d" "$FIXTURES/multi-phase-plan-numeric.md" P099-multi.md
  [ "$status" -eq 0 ]
  # The generator is what decides whether the seeding was enough. If a FOURTH
  # precondition lands, this line is where it is reported.
  cd "$d"
  run bash "$PLAN_TO_EPIC" --plan "$d/.aid-o/plans/P099-multi.md" --phase 1 --total 3 --plugin-dir "$AID_PLUGIN_PATH"
  [[ "$output" != *"has no current PM page"* ]]
  [[ "$output" != *"not committed on main"* ]]
  [[ "$output" != *"cannot resolve the project's execution.yaml"* ]]
}

@test "CONTRACT: the same holds when .aid-o is gitignored — no commit is required" {
  local d="$TEST_TMPDIR/ignored"; _repo "$d"
  run aid_fixture_seed_plan "$d" "$FIXTURES/multi-phase-plan-numeric.md" P099-multi.md
  [ "$status" -eq 0 ]
  # Nothing was committed: the plan is deliberately unshared, which the
  # committed-source preflight's own message names as legitimate.
  run git -C "$d" log --oneline
  [ "$(grep -c '' <<<"$output")" -eq 1 ]
  cd "$d"
  run bash "$PLAN_TO_EPIC" --plan "$d/.aid-o/plans/P099-multi.md" --phase 1 --total 3 --plugin-dir "$AID_PLUGIN_PATH"
  [[ "$output" != *"has no current PM page"* ]]
}

@test "a renderable plan gets a real page, and the production obligation accepts it" {
  local d="$TEST_TMPDIR/page"; _repo "$d"
  aid_fixture_seed_plan "$d" "$FIXTURES/multi-phase-plan-numeric.md" P099-multi.md >/dev/null
  [ -s "$d/.aid-o/work/evidence/P099/plan-summary-artifact.html" ]
  run bash -c 'cd "$1"; source "$AID_PLUGIN_PATH/scripts/lib/aid-artifact-obligation.sh"
    aid_artifact_obligation_check "$1/.aid-o/plans/P099-multi.md"' _ "$d"
  [ "$status" -eq 0 ]
}

@test "editing the plan after seeding INVALIDATES it — and re-seeding restores it" {
  # Convergent, not mtime-smart: the first cut `touch`ed the page so it would
  # out-date the plan, which is the fixture cheating at the check it exists to
  # satisfy. Seed-then-edit must break exactly as it breaks in production.
  local d="$TEST_TMPDIR/edit"; _repo "$d"
  aid_fixture_seed_plan "$d" "$FIXTURES/multi-phase-plan-numeric.md" P099-multi.md >/dev/null
  sleep 1
  printf '\n<!-- a later edit -->\n' >> "$d/.aid-o/plans/P099-multi.md"
  run bash -c 'cd "$1"; source "$AID_PLUGIN_PATH/scripts/lib/aid-artifact-obligation.sh"
    aid_artifact_obligation_check "$1/.aid-o/plans/P099-multi.md"' _ "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"OLDER than the plan"* ]]

  aid_fixture_seed_plan "$d" "$d/.aid-o/plans/P099-multi.md" P099-multi.md >/dev/null
  run bash -c 'cd "$1"; source "$AID_PLUGIN_PATH/scripts/lib/aid-artifact-obligation.sh"
    aid_artifact_obligation_check "$1/.aid-o/plans/P099-multi.md"' _ "$d"
  [ "$status" -eq 0 ]
}

@test "an unrenderable plan owes no page — the helper says so and does not invent one" {
  local d="$TEST_TMPDIR/unrenderable"; _repo "$d"
  printf -- '---\nid: P900\n---\n\nnothing a renderer can use\n' > "$TEST_TMPDIR/P900.md"
  run aid_fixture_seed_plan "$d" "$TEST_TMPDIR/P900.md" P900.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"no page is owed"* ]] || [ ! -e "$d/.aid-o/work/evidence/P900/plan-summary-artifact.html" ]
}

@test "the helper REFUSES an ambiguous fixture rather than half-seeding it" {
  local d="$TEST_TMPDIR/refuse"; _repo "$d"
  run aid_fixture_seed_plan "$d" "$FIXTURES/multi-phase-plan-numeric.md" not-a-plan.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"P<number>"* ]]
  run aid_fixture_seed_plan "$d" "$TEST_TMPDIR/does-not-exist.md" P099.md
  [ "$status" -eq 2 ]
  run aid_fixture_seed_plan "$d" "$FIXTURES/multi-phase-plan-numeric.md" "sub/P099.md"
  [ "$status" -eq 2 ]
}
