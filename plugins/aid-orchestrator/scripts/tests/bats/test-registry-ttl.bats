#!/usr/bin/env bats
# E-046-1_3 Step 6 — aid-registry-ttl-guard.sh regression (Step 5).
# 6 assertions: past-deadline stale, future deferral, expired deferral,
# no-deadline opt-out, active-status skip, missing registry → exit 2.

setup() {
  export AID_TEST_MODE=1
  TEST_TMPDIR=$(mktemp -d)
  TTL_GUARD="${BATS_TEST_DIRNAME}/../../aid-registry-ttl-guard.sh"
  REGISTRY="$TEST_TMPDIR/enforcement-registry.yaml"
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

@test "TTL guard: status:planned past deadline, no deferral → exit 1 (stale)" {
  # deadline is a date in the past
  cat > "$REGISTRY" <<'EOF'
version: 1
enforcements:
  - {id: stale_row, type: 1, source: "scripts/aid-fsm.sh:1", instruction: n/a, severity: advisory, surface: internal-guard, status: planned, verdict: unmapped, deadline: "2020-01-01", description: "should trigger TTL guard"}
EOF
  run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale planned row"* ]]
}

@test "TTL guard: past deadline + future deferred_until → exit 0 (deferred, not stale)" {
  cat > "$REGISTRY" <<'EOF'
version: 1
enforcements:
  - {id: deferred_row, type: 1, source: "scripts/aid-fsm.sh:1", instruction: n/a, severity: advisory, surface: internal-guard, status: planned, verdict: unmapped, deadline: "2020-01-01", deferred_until: "2099-12-31", deferred_by: "marek", deferred_reason: "far future deferral", description: "deferred row"}
EOF
  run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "TTL guard: past deadline + expired deferred_until → exit 1 (deferral expired)" {
  cat > "$REGISTRY" <<'EOF'
version: 1
enforcements:
  - {id: expired_deferral, type: 1, source: "scripts/aid-fsm.sh:1", instruction: n/a, severity: advisory, surface: internal-guard, status: planned, verdict: unmapped, deadline: "2020-01-01", deferred_until: "2021-01-01", deferred_by: "marek", deferred_reason: "expired", description: "expired deferral"}
EOF
  run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale planned row"* ]]
}

@test "TTL guard: planned row with no deadline field → exit 0 (opt-in, skipped)" {
  cat > "$REGISTRY" <<'EOF'
version: 1
enforcements:
  - {id: no_deadline_row, type: 1, source: "scripts/aid-fsm.sh:1", instruction: n/a, severity: advisory, surface: internal-guard, status: planned, verdict: unmapped, description: "no deadline field, not subject to TTL guard"}
EOF
  run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "TTL guard: status:active with deadline (past) → exit 0 (only planned rows checked)" {
  cat > "$REGISTRY" <<'EOF'
version: 1
enforcements:
  - {id: active_past_deadline, type: 1, source: "scripts/aid-fsm.sh:1", instruction: n/a, severity: advisory, surface: internal-guard, status: active, verdict: ALIGNED, deadline: "2020-01-01", description: "active rows are never subject to TTL guard"}
EOF
  run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "TTL guard: registry file not found → exit 2" {
  run bash "$TTL_GUARD" "/nonexistent/path/enforcement-registry.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "TTL guard: block-style planned + past deadline → exit 1 (stale)" {
  cat > "$REGISTRY" <<'EOF'
version: 1
enforcements:
  - id: DG-BLOCK-STALE
    type: out-of-band
    source: scripts/lib/delivery-checks/dg01-dependency-consistency.sh
    instruction: test
    severity: fail
    surface: delivery-gate
    enforcement: observe
    status: planned
    deadline: "2020-01-01"
    description: block-style stale entry
EOF
  run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale planned row"* ]]
}

@test "TTL guard: block-style planned + future deferred_until → exit 0" {
  cat > "$REGISTRY" <<'EOF'
version: 1
enforcements:
  - id: DG-BLOCK-DEFERRED
    type: out-of-band
    source: scripts/lib/delivery-checks/dg01-dependency-consistency.sh
    instruction: test
    severity: fail
    surface: delivery-gate
    enforcement: observe
    status: planned
    deadline: "2020-01-01"
    deferred_until: "2099-12-31"
    deferred_by: E050
    deferred_reason: blocking promotion deferred to E10
    description: block-style deferred entry
EOF
  run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "TTL guard: block-style planned + non-ISO deadline (promotion_phase field only) → exit 0 (no ISO deadline = opt-out)" {
  cat > "$REGISTRY" <<'EOF'
version: 1
enforcements:
  - id: DG-BLOCK-NOISODEADLINE
    type: out-of-band
    source: scripts/lib/delivery-checks/dg01-dependency-consistency.sh
    instruction: test
    severity: fail
    surface: delivery-gate
    enforcement: observe
    status: planned
    promotion_phase: E10
    description: no ISO deadline field - guard must skip this row
EOF
  run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 0 ]
}
