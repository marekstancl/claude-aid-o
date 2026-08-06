#!/usr/bin/env bats
# test-aid-test-content-scan.bats — mechanical content checks run every audit.
#
# These findings existed exactly once, made by hand after the owner asked where
# they were. Mechanical work is never again left to an analyst's diligence.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SCAN="$PLUGIN_DIR/scripts/aid-test-content-scan.sh"
  PROJ="$TEST_TMPDIR/proj"; mkdir -p "$PROJ/tests" "$PROJ/.aid-o/config"
  OUT="$TEST_TMPDIR/content-scan.json"
}
teardown() { teardown_test_evidence_dir; }

@test "identical test names in two files are reported as a duplicate pair" {
  printf '@test "the same behaviour" { true; }\n@test "another" { true; }\n' > "$PROJ/tests/a.bats"
  printf '@test "the same behaviour" { true; }\n@test "different" { true; }\n' > "$PROJ/tests/b.bats"
  run bash "$SCAN" --project-root "$PROJ" --output "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.duplicate_pairs' "$OUT")" = "1" ]
  [ "$(jq -r '.checks.duplicate_test_cases[0].shared_cases' "$OUT")" = "1" ]
}

@test "a suite asserting only exit codes is flagged; a validator suite is marked legitimate" {
  local i body=""
  for i in 1 2 3 4 5 6; do body+='@test "t'$i'" { run true
  [ "$status" -eq 0 ]
}
'; done
  printf '%s' "$body" > "$PROJ/tests/test-weak.bats"
  printf '%s' "$body" > "$PROJ/tests/test-thing-schema.bats"
  run bash "$SCAN" --project-root "$PROJ" --output "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.weak_oracle_files' "$OUT")" = "2" ]
  [ "$(jq -r '[.checks.weak_oracle[] | select(.file | endswith("test-weak.bats")) | .likely_legitimate][0]' "$OUT")" = "false" ]
  [ "$(jq -r '[.checks.weak_oracle[] | select(.file | endswith("schema.bats")) | .likely_legitimate][0]' "$OUT")" = "true" ]
}

@test "a file run directly by one gate AND reachable from a pool gate is an overlap candidate" {
  printf '@test "x" { true; }\n' > "$PROJ/tests/test-core.bats"
  cat > "$PROJ/.aid-o/config/execution.yaml" <<'YAML'
gates:
  core_direct:
    command: bats tests/test-core.bats
  all_pool:
    command: bash scripts/aid-bats-parallel-lane.sh --pool-only
YAML
  run bash "$SCAN" --project-root "$PROJ" --output "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.gate_overlap_candidates' "$OUT")" -ge 1 ]
  [ "$(jq -r '.checks.gate_overlap[0].gate_direct' "$OUT")" = "core_direct" ]
}

@test "a test file no inventory unit references is named, not lost" {
  printf '@test "x" { true; }\n' > "$PROJ/tests/test-known.bats"
  printf '@test "y" { true; }\n' > "$PROJ/tests/test-orphan.bats"
  printf '{"schema_version":"1.0.0","generated_at":"t","runner_families":["bats"],"entries":[{"run_unit_id":"bats:tests/test-known","runner":"bats","adapter":"bats","confidence":"medium"}]}' > "$TEST_TMPDIR/inv.json"
  run bash "$SCAN" --project-root "$PROJ" --inventory "$TEST_TMPDIR/inv.json" --output "$OUT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.counts.unreferenced' "$OUT")" = "1" ]
  [[ "$(jq -r '.checks.unreferenced_tests[0].file' "$OUT")" == *"test-orphan"* ]]
}
