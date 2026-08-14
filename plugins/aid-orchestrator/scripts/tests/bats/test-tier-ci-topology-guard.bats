#!/usr/bin/env bats
# aid-tier: t0
# test-tier-ci-topology-guard.bats — the topology guard's own regression tests.
#
# test-tier-ci-topology.sh asserts that no t2 suite runs on the merge path. This
# suite asserts that IT asserts it: each shape below was raised by the 2026-08-14
# cross-model review as a way to run T2 on push WITHOUT naming a suite file, and
# the first version of the guard waved three of them through. A check whose
# failure path nobody has seen is decoration.

load test-helpers.bash

setup() {
  GUARD="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/test-tier-ci-topology.sh"
  WF="$BATS_TEST_TMPDIR/workflows"
  mkdir -p "$WF"
  # A nightly that satisfies the coverage half, so every failure below is
  # attributable to the merge-path half alone.
  cat > "$WF/nightly-tests.yml" <<'YML'
name: Nightly tests
on:
  schedule:
    - cron: '0 21 * * *'
jobs:
  nightly:
    runs-on: ubuntu-latest
    steps:
      - name: portfolio
        run: plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --timing --verbose
YML
}

# _ci <run-block> — a push/PR-triggered workflow whose one job runs <run-block>.
_ci() {
  { printf 'name: CI\non:\n  push:\n    branches: [main]\njobs:\n  merge:\n    runs-on: ubuntu-latest\n    steps:\n      - name: tests\n        run: |\n'
    printf '%s\n' "$1" | sed 's/^/          /'
  } > "$WF/ci.yml"
}

_guard() { AID_TOPOLOGY_WORKFLOW_DIR="$WF" run bash "$GUARD"; }

@test "the merge path running only T0+T1 is accepted" {
  _ci 'plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t0
plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t1'
  _guard
  [ "$status" -eq 0 ]
}

@test "naming a t2 suite file on push is caught" {
  _ci 'bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats'
  _guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"is tagged t2 but is named by a job"* ]]
}

@test "--tier t2 on push is caught, though it names no suite" {
  _ci 'plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t2'
  _guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"--tier t2 on push/PR"* ]]
}

@test "an UNTIERED runner invocation on push is caught (it is the full portfolio)" {
  _ci 'plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --verbose'
  _guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNTIERED on push/PR"* ]]
}

@test "--tier t2 hidden behind a line continuation is caught" {
  _ci 'plugins/aid-orchestrator/scripts/tests/run-all-tests.sh \
  --tier t2 --verbose'
  _guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"--tier t2 on push/PR"* ]]
}

@test "a bats glob over the suite directory on push is caught" {
  _ci 'bats plugins/aid-orchestrator/scripts/tests/bats/test-*.bats'
  _guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats GLOB"* ]]
}

@test "chmod +x on the runner is NOT read as an invocation" {
  _ci 'chmod +x plugins/aid-orchestrator/scripts/tests/run-all-tests.sh
plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t0
plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t1'
  _guard
  [ "$status" -eq 0 ]
}

@test "--only and --list are not untiered portfolio runs" {
  _ci 'plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t0
plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t1
plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --only test-cheap.bats
plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --list'
  _guard
  [ "$status" -eq 0 ]
}

@test "a nightly that filters by tier leaves T2 uncovered and is caught" {
  _ci 'plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t0
plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t1'
  sed -i 's/--timing --verbose/--tier t1 --timing/' "$WF/nightly-tests.yml"
  _guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing runs the full portfolio"* ]]
}

@test "a push workflow using workflow_call indirection is refused, not skipped" {
  _ci 'plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t0'
  sed -i 's/^  push:/  workflow_call:\n  push:/' "$WF/ci.yml"
  _guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"workflow_call"* ]]
}
