#!/usr/bin/env bats
# aid-tier: t2
# test-behavior-trace.bats — behavior_trace_count gate tests (aid-fsm.sh v2.35+).
#
# Tests the structural gate in fsm_check_verifier_output that enforces
# behavior_trace_count > 0 when behavior_trace_required: true in a verifier
# output file. Gate is opt-in: absent or false → no enforcement.
#
# Sourcing strategy: aid-fsm.sh has a BASH_SOURCE guard that skips the
# bottom-of-file dispatcher when sourced, so sourcing is safe and exposes
# fsm_check_verifier_output + yaml_field into the test scope.

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1
  TMPDIR_TRACE="$(mktemp -d)"
  FSM="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/aid-fsm.sh"
  # Source aid-fsm.sh — BASH_SOURCE guard prevents dispatcher from firing.
  # shellcheck disable=SC1090
  source "$FSM"
}

teardown() {
  rm -rf "$TMPDIR_TRACE"
}

# Helper: write a minimal verifier output file that passes the basic
# fsm_check_verifier_output structural checks (_generated_by, classification,
# verdict not pending). Callers may append extra fields.
_write_base_verifier() {
  local file="$1"
  cat > "$file" <<EOF
_generated_by: aid-orchestrator:verifier@test-fixture
_generated_at: 2026-06-19T00:00:00Z
classification: RUN
verdict: pass
EOF
}

# ─── Test 1: behavior_trace_count=0 FAILS ────────────────────────────────

@test "behavior_trace: count=0 with required=true fails (exit code 1)" {
  local vo="$TMPDIR_TRACE/verifier-output.md"
  _write_base_verifier "$vo"
  cat >> "$vo" <<EOF
behavior_trace_required: true
behavior_trace_count: 0
EOF
  run fsm_check_verifier_output "$vo"
  [ "$status" -eq 1 ]
}

# ─── Test 2: behavior_trace_count=3 PASSES ───────────────────────────────

@test "behavior_trace: count=3 with required=true passes (exit code 0)" {
  local vo="$TMPDIR_TRACE/verifier-output.md"
  _write_base_verifier "$vo"
  cat >> "$vo" <<EOF
behavior_trace_required: true
behavior_trace_count: 3
EOF
  run fsm_check_verifier_output "$vo"
  [ "$status" -eq 0 ]
}

# ─── Test 3: behavior_trace_required=false PASSES regardless of count ────

@test "behavior_trace: required=false, count=0 passes (gate skipped)" {
  local vo="$TMPDIR_TRACE/verifier-output.md"
  _write_base_verifier "$vo"
  cat >> "$vo" <<EOF
behavior_trace_required: false
behavior_trace_count: 0
EOF
  run fsm_check_verifier_output "$vo"
  [ "$status" -eq 0 ]
}

# ─── Test 4: no behavior_trace_required field PASSES (default is no enforcement)

@test "behavior_trace: field absent in file passes (opt-in gate, no field = skip)" {
  local vo="$TMPDIR_TRACE/verifier-output.md"
  _write_base_verifier "$vo"
  # No behavior_trace_required line at all.
  run fsm_check_verifier_output "$vo"
  [ "$status" -eq 0 ]
}

# ─── Test 5: missing behavior_trace_count when required FAILS ─────────────

@test "behavior_trace: required=true but count field absent fails (exit code 1)" {
  local vo="$TMPDIR_TRACE/verifier-output.md"
  _write_base_verifier "$vo"
  cat >> "$vo" <<EOF
behavior_trace_required: true
EOF
  # behavior_trace_count is intentionally omitted — yaml_field returns empty.
  run fsm_check_verifier_output "$vo"
  [ "$status" -eq 1 ]
}

# ─── Test 6: behavior_trace_count=1 with required=true PASSES (boundary) ──

@test "behavior_trace: count=1 with required=true passes (boundary value)" {
  local vo="$TMPDIR_TRACE/verifier-output.md"
  _write_base_verifier "$vo"
  cat >> "$vo" <<EOF
behavior_trace_required: true
behavior_trace_count: 1
EOF
  run fsm_check_verifier_output "$vo"
  [ "$status" -eq 0 ]
}
