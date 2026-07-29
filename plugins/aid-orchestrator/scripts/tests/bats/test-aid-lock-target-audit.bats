#!/usr/bin/env bats
# test-aid-lock-target-audit.bats — P066 Step 7.
#
# Confirms every flock/.lock usage the Step 4 scanner reports for the
# previously-unaudited bats suites resolves inside per-test isolation scope
# (a relative path under the fixture cwd `setup_test_evidence_dir` cd's into,
# never a hardcoded absolute/shared path) — read from a REAL inventory.json,
# never a hand-maintained file list.
#
# Grounded finding (this audit, 2026-07-29): none of the 4 files' reported
# lock_usage[] targets are a real runtime isolation hazard. test-aid-fsm.bats'
# two genuine `.aid-o/metrics/gate-runtime-baselines.yaml.lock` references are
# relative paths under $TEST_PROJECT_ROOT (a fresh mktemp per test, via
# setup_test_evidence_dir — verified against that helper's own source). The
# remaining matches across all 4 files are grep noise from Step 4's
# necessarily-coarse static heuristic: code comments mentioning "flock"/
# ".lock", and fixture DATA strings (`.aid-o/metrics/*.lock`, "package-lock.
# json", "$f") being tested by gitignore-backfill/invalidation-map as glob
# patterns — not this test process's own lock coordination. No rebind is
# needed in any of the 4 files; this is the plan's own anticipated no-op
# outcome ("a no-op if this step's audit finds every target already
# compliant").

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
}

teardown() {
  teardown_test_evidence_dir
}

@test "every reported lock_usage[] target across the 4 audited files is a relative/variable reference, never a hardcoded absolute shared path" {
  local out_dir="$TEST_TMPDIR/lock-audit-out"
  run "$AID_PLUGIN_PATH/scripts/aid-test-inventory.sh" \
    --project-root "$AID_PLUGIN_PATH" --audit-id "lock-audit" --output-dir "$out_dir"
  [ "$status" -eq 0 ]
  [ -f "$out_dir/inventory.json" ]

  local targets
  targets="$(jq -r '
    .entries[]
    | select(.run_unit_id | test("test-aid-emit-dispatch$|test-aid-gitignore-backfill$|test-invalidation-map$|test-aid-fsm$"))
    | .isolation.lock_usage[].lock_target
  ' "$out_dir/inventory.json")"

  # The audited file list itself comes from inventory.json's entries, never
  # a hardcoded list — this just names which of THOSE entries this step's
  # scope covers (the 4 previously-unaudited files named in the plan).
  local audited_count
  audited_count="$(jq -r '
    [.entries[] | select(.run_unit_id | test("test-aid-emit-dispatch$|test-aid-gitignore-backfill$|test-invalidation-map$|test-aid-fsm$"))] | length
  ' "$out_dir/inventory.json")"
  [ "$audited_count" -eq 4 ]

  local bad=0
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    if [[ "$t" == /* ]]; then
      echo "hardcoded absolute lock target found: $t" >&2
      bad=1
    fi
  done <<<"$targets"
  [ "$bad" -eq 0 ]
}

@test "test-aid-fsm.bats' genuine .lock references are relative paths under the per-test fixture project root" {
  local out_dir="$TEST_TMPDIR/lock-audit-out2"
  run "$AID_PLUGIN_PATH/scripts/aid-test-inventory.sh" \
    --project-root "$AID_PLUGIN_PATH" --audit-id "lock-audit-2" --output-dir "$out_dir"
  [ "$status" -eq 0 ]

  local fsm_targets
  fsm_targets="$(jq -r '
    .entries[] | select(.run_unit_id | test("test-aid-fsm$")) | .isolation.lock_usage[].lock_target
  ' "$out_dir/inventory.json")"
  echo "$fsm_targets" | grep -q "gate-runtime-baselines.yaml.lock"

  # setup_test_evidence_dir (this repo's own shared bats fixture helper,
  # sourced by test-aid-fsm.bats) cd's into a fresh mktemp TEST_PROJECT_ROOT
  # per test — verified directly against its own source, not assumed.
  grep -q 'cd "\$TEST_PROJECT_ROOT"' "$AID_PLUGIN_PATH/scripts/tests/bats/test-helpers.bash"
  grep -q 'TEST_TMPDIR=\$(mktemp -d)' "$AID_PLUGIN_PATH/scripts/tests/bats/test-helpers.bash"
}
