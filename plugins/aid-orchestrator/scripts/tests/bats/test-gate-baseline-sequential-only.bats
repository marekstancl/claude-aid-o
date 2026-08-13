#!/usr/bin/env bats
# aid-tier: t1
# P083 Step 8 — the gate-runtime baseline library is sequential-only. P078
# removed the parallel scheduler; both producers hardcode "sequential", the
# receipt schema is `enum: ["sequential"]`, and the live baseline had no
# populated non-sequential data to migrate — this deletes the dead branches
# rather than emitting them empty forever.

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  LIB="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/scripts/lib/aid-gate-runtime-baseline.sh"
  export LIB
  export AID_GATE_BASELINE_FILE="$TEST_TMPDIR/gate-runtime-baselines.yaml"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# A legacy baseline entry carrying populated recent_samples_by_context /
# percentiles_by_context — the shape a pre-P078 file could have had.
_write_legacy_fixture() {
  cat > "$AID_GATE_BASELINE_FILE" <<'EOF'
gates:
  legacy_gate:
    command_fingerprint: "sha256:f1522a14de41"
    command_template: "run legacy_gate"
    last_resolved_command: "run legacy_gate"
    samples_count: 3
    non_censored_samples_count: 3
    recent_samples:
      - {duration_ms: 100, exit_code: 0, timeout_seconds: 60, censored: false, recorded_at: "2026-01-01T00:00:00Z"}
      - {duration_ms: 200, exit_code: 0, timeout_seconds: 60, censored: false, recorded_at: "2026-01-01T00:01:00Z"}
      - {duration_ms: 300, exit_code: 0, timeout_seconds: 60, censored: false, recorded_at: "2026-01-01T00:02:00Z"}
    p50_ms: 200
    p90_ms: 300
    p95_ms: 300
    max_ms: 300
    last_duration_ms: 300
    last_exit_code: 0
    last_attempt_result: pass
    policy_result: "none"
    last_timeout_seconds: 60
    timeout_recommended_seconds: null
    run_mode_recommended: null
    retryable: true
    operator_action: null
    last_updated: "2026-01-01T00:02:00Z"
    series_reset_at: null
    recent_samples_by_context:
      observe_parallel:
        - {duration_ms: 150, exit_code: 0, timeout_seconds: 60, censored: false, recorded_at: "2026-01-01T00:00:30Z"}
    percentiles_by_context:
      observe_parallel:
        samples_count: 1
        non_censored_samples_count: 1
        p50_ms: 150
        p90_ms: 150
        p95_ms: 150
        max_ms: 150
EOF
}

@test "a legacy file with populated *_by_context reads without error and yields correct percentiles" {
  # Covers the "numbers are identical before and after" criterion: the fixture
  # is a pre-P083 entry, and every number below is read back through TODAY's
  # library code, not re-parsed out of the heredoc.
  _write_legacy_fixture

  run bash -c 'source "$1"; gate_baseline_show "legacy_gate"' _ "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"p95"* ]]

  run bash -c 'source "$1"; gate_baseline_report_json "legacy_gate"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.p95_ms' <<<"$output")" == "300" ]
  [ "$(jq -r '.samples_count' <<<"$output")" == "3" ]
  [ "$(jq -r '.non_censored_samples_count' <<<"$output")" == "3" ]

  # The stored percentiles the reader does not surface are unchanged too.
  [ "$(yq '.gates.legacy_gate.p50_ms' "$AID_GATE_BASELINE_FILE")" == "200" ]
  [ "$(yq '.gates.legacy_gate.p90_ms' "$AID_GATE_BASELINE_FILE")" == "300" ]
  [ "$(yq '.gates.legacy_gate.max_ms' "$AID_GATE_BASELINE_FILE")" == "300" ]
}

@test "a non-sequential context argument is refused by name" {
  run bash -c '
    source "$1"
    gate_baseline_update "some_gate" "cmd" "cmd" 0 100 60 "observe_parallel"
  ' _ "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"observe_parallel"* ]]
  [[ "$output" == *"only 'sequential' is accepted"* ]]
  # No entry was written for a refused call.
  run yq -e '.gates.some_gate' "$AID_GATE_BASELINE_FILE"
  [ "$status" -ne 0 ]

  run bash -c '
    source "$1"
    gate_baseline_update "some_gate" "cmd" "cmd" 0 100 60 "parallel"
  ' _ "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"'parallel'"* ]]
  [[ "$output" == *"only 'sequential' is accepted"* ]]
  run yq -e '.gates.some_gate' "$AID_GATE_BASELINE_FILE"
  [ "$status" -ne 0 ]
}

@test "a sequential write against a legacy *_by_context file succeeds and drops the legacy keys" {
  _write_legacy_fixture
  run bash -c '
    source "$1"
    gate_baseline_update "legacy_gate" "run legacy_gate" "run legacy_gate" 0 400 60
  ' _ "$LIB"
  [ "$status" -eq 0 ]

  # New sample folded in; percentiles recomputed over the FIFO window.
  run yq '.gates.legacy_gate.samples_count' "$AID_GATE_BASELINE_FILE"
  [ "$output" == "4" ]

  # The legacy sibling keys are gone after this write (P083 Step 8: the
  # write path no longer emits them at all).
  run yq -e '.gates.legacy_gate.recent_samples_by_context' "$AID_GATE_BASELINE_FILE"
  [ "$status" -ne 0 ] || [ "$(yq '.gates.legacy_gate.recent_samples_by_context' "$AID_GATE_BASELINE_FILE")" == "null" ]
  run yq -e '.gates.legacy_gate.percentiles_by_context' "$AID_GATE_BASELINE_FILE"
  [ "$status" -ne 0 ] || [ "$(yq '.gates.legacy_gate.percentiles_by_context' "$AID_GATE_BASELINE_FILE")" == "null" ]
}

@test "--help / usage text carries no stale non-sequential vocabulary" {
  run bash "$LIB"
  [[ "$output" == *"concurrency_context=sequential"* ]]
  [[ "$output" != *"observe_parallel"* ]]
}
