#!/usr/bin/env bats
# test-tier-gate-routing.bats — P081 Step 6: the merge path lost the portfolio.
#
# WHAT THIS SUITE PROVES, against the REAL execution.yaml rather than a
# fixture — because the claim being made is about this project's actual merge
# path, and a fixture would prove it about a file nobody runs:
#
#   * no merge-path profile includes a gate that runs the whole portfolio;
#   * every merge-path gate that invokes the portfolio runner names a tier;
#   * the nightly command and the nightly WORKFLOW have not drifted apart;
#   * `release_quarantine` is still exactly `release` minus the quarantinable
#     gate — the set equality `aid-plan-fsm.sh plan-finalize --stage gates`
#     refuses to run without, and which this plan's own rewrite had to keep
#     true rather than break in the same commit.
#
# Result count after any edit:
#   bats --tap test-tier-gate-routing.bats | grep -cE '^(ok|not ok)'   # == 7

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TREE_ROOT="$(cd "$PLUGIN/../.." && pwd)"
  # Read from the TREE this suite lives in. `.aid-o/work/` is gitignored, but
  # `.aid-o/config/` is force-tracked in this repo (164 files under `.aid-o/`
  # are in the index), so the merge path's own configuration travels with the
  # commit and this assertion is real in a fresh CI checkout too — not a skip
  # that reads green forever.
  EXEC_YAML="$TREE_ROOT/.aid-o/config/execution.yaml"
  TEMPLATE="$PLUGIN/defaults/execution.yaml"
  WORKFLOW="$TREE_ROOT/.github/workflows/nightly-tests.yml"
  export PLUGIN TREE_ROOT EXEC_YAML TEMPLATE WORKFLOW
}

_need_project_config() {
  [ -f "$EXEC_YAML" ] || fail "this project's .aid-o/config/execution.yaml is missing — it is a tracked file and the merge path cannot be checked without it"
}

# The profiles a merge actually passes through. `p064-closure` is a historical
# one-off closure profile and the two `*_quarantine` profiles are substitutes,
# each asserted on its own terms below.
MERGE_PATH_PROFILES="quick targeted standard full release"

# `gate_profiles:`, not `profiles:` — the live config's own key. An earlier
# version of this suite read `.profiles.`, which yq resolves to nothing with
# exit 0, so three of these cases asserted over an EMPTY list and passed while
# proving nothing. Hence `_include_or_die`: every read of a profile is checked
# for non-emptiness before anything is concluded from it.
_include() { yq -r ".gate_profiles.\"$1\".include[]" "$EXEC_YAML"; }
_command() { yq -r ".gates.\"$1\".command // \"\"" "$EXEC_YAML"; }

# _include_or_die <profile> — the include list, or a failed test.
_include_or_die() {
  local out; out="$(_include "$1")"
  [[ -n "$out" ]] || fail "profile '$1' has an empty or unreadable include[] in $EXEC_YAML"
  printf '%s\n' "$out"
}

@test "1: no merge-path profile runs the whole portfolio" {
  _need_project_config
  for p in $MERGE_PATH_PROFILES; do
    inc="$(_include_or_die "$p")"
    [[ "$inc" != *"shell_pipeline_smoke"* ]] || fail "profile $p still includes shell_pipeline_smoke"
    [[ "$inc" != *"bats_boundary"* ]] || fail "profile $p still includes bats_boundary"
  done
}

@test "2: every merge-path gate that runs the runner names a tier" {
  _need_project_config
  for p in $MERGE_PATH_PROFILES; do
    while IFS= read -r gate; do
      [[ -n "$gate" ]] || continue
      cmd="$(_command "$gate")"
      if [[ "$cmd" == *"run-all-tests.sh"* ]]; then
        [[ "$cmd" == *"--tier "* ]] || fail "gate $gate (profile $p) runs the portfolio runner with no --tier"
      fi
      # The old whole-directory glob must not come back by another name.
      [[ "$cmd" != *"tests/bats/*.bats"* ]] || fail "gate $gate (profile $p) globs the whole bats directory"
    done < <(_include_or_die "$p")
  done
}

@test "3: bats_all is the T0+T1 selection and stays required" {
  _need_project_config
  cmd="$(_command bats_all)"
  [[ "$cmd" == *"--tier t0"* ]]
  [[ "$cmd" == *"--tier t1"* ]]
  [[ "$cmd" != *"--tier t2"* ]]
  [ "$(yq -r '.gates.bats_all.required' "$EXEC_YAML")" = "true" ]
}

@test "4: the nightly gate runs the WHOLE portfolio and measures while it runs" {
  _need_project_config
  cmd="$(_command shell_pipeline_smoke)"
  # No tier filter: a T2-only nightly would never prove the whole portfolio
  # green in one place, and its --timing pass would refresh only T2 durations —
  # leaving the lint unable to catch a T0 suite that grew.
  [[ "$cmd" != *"--tier"* ]]
  [[ "$cmd" == *"--timing"* ]]
  [[ "$cmd" == *"--include-delegated"* ]]
}

@test "5: the nightly workflow has not drifted from the nightly gate" {
  [ -f "$WORKFLOW" ]
  run grep -E 'schedule:|workflow_dispatch:' "$WORKFLOW"
  [ "$status" -eq 0 ]
  wf="$(grep -A 3 'run-all-tests.sh' "$WORKFLOW" | tr '\n' ' ')"
  for flag in "--timing" "--include-delegated"; do
    [[ "$wf" == *"$flag"* ]] || fail "the nightly workflow does not pass $flag"
  done
  [[ "$wf" != *"--tier"* ]] || fail "the nightly workflow filters by tier; it must run the whole portfolio"
}

@test "6: release_quarantine is still exactly release minus bats_all" {
  _need_project_config
  expected="$(_include_or_die release | grep -v '^bats_all$' | sort | tr '\n' ' ')"
  actual="$(_include_or_die release_quarantine | sort | tr '\n' ' ')"
  [ -n "$expected" ]
  [ "$expected" = "$actual" ]
}

@test "7: the shipped template teaches tiers, not the whole portfolio" {
  cmd="$(yq -r '.gates.tests_pass.command' "$TEMPLATE")"
  [[ "$cmd" == *"--tier t0"* ]]
  [[ "$cmd" == *"--tier t1"* ]]
  grep -q 'aid-tier:' "$TEMPLATE"
}
