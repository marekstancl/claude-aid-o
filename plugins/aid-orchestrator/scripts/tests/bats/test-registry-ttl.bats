#!/usr/bin/env bats
# aid-tier: t2
# E-046-1_3 Step 6 — aid-registry-ttl-guard.sh regression (Step 5).
# TTL-guard assertions: past-deadline stale, future deferral, expired deferral,
# no-deadline opt-out, active-status skip, missing registry → exit 2 (inline +
# block-style rows).
# P065 (v2.59.0): shipped-registry assertions for the c3_cross_provider_dispatch
# row (presence, full required-key set, expected value shape, totals coherence).

setup() {
  export AID_TEST_MODE=1
  TEST_TMPDIR=$(mktemp -d)
  TTL_GUARD="${BATS_TEST_DIRNAME}/../../aid-registry-ttl-guard.sh"
  REGISTRY="$TEST_TMPDIR/enforcement-registry.yaml"
  SHIPPED_REGISTRY="${BATS_TEST_DIRNAME}/../../../defaults/enforcement-registry.yaml"
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

# ── P065 C3 cross-provider dispatch bridge (v2.59.0) ────────────────────────
# The shipped registry MUST carry the c3_cross_provider_dispatch row with the
# full required-key set, so the P065 real-codex-dispatch enforcement can never
# silently drop out of the distribution.

@test "shipped registry: c3_cross_provider_dispatch row exists" {
  run yq -e '.enforcements[] | select(.id == "c3_cross_provider_dispatch") | .id' "$SHIPPED_REGISTRY"
  [ "$status" -eq 0 ]
  [[ "$output" == "c3_cross_provider_dispatch" ]]
}

@test "shipped registry: c3_cross_provider_dispatch is retired with its replacement named, not silently dropped" {
  # P096 Step 12 retired the C3 dispatch: the Codex transport serves the
  # review rounds, and the final review round is the guard that replaced it.
  run yq -e '.enforcements[] | select(.id == "c3_cross_provider_dispatch") | .status' "$SHIPPED_REGISTRY"
  [ "$status" -eq 0 ]; [[ "$output" == "removed_scoped" ]]
  run yq -e '.enforcements[] | select(.id == "c3_cross_provider_dispatch") | .replacement_guard' "$SHIPPED_REGISTRY"
  [ "$status" -eq 0 ]
  run yq -e ".enforcements[] | select(.id == \"$output\") | .status" "$SHIPPED_REGISTRY"
  [ "$status" -eq 0 ]; [[ "$output" == "active" ]]
}

@test "shipped registry: totals.enforcements matches the actual row count" {
  local declared actual
  declared=$(yq '.totals.enforcements' "$SHIPPED_REGISTRY")
  actual=$(yq '.enforcements | length' "$SHIPPED_REGISTRY")
  [ "$declared" -eq "$actual" ]
}

# ── Date override and the 2026-09-30 cohort ──────────────────────────────────

@test "TTL guard: the shipped registry is clean the day after the 2026-09-30 cohort deadline" {
  AID_TTL_TODAY=2026-10-01 run bash "$TTL_GUARD" "$SHIPPED_REGISTRY"
  [ "$status" -eq 0 ]
}

@test "TTL guard: a deferral is a date, not an exemption" {
  cat > "$REGISTRY" <<'EOF2'
version: 1
enforcements:
  - {id: cohort_row, type: 4, source: "scripts/aid-fsm.sh:1", instruction: n/a, severity: advisory, surface: internal-guard, status: planned, verdict: unmapped, deadline: "2026-09-30", deferred_until: "2026-10-31", deferred_by: "P096", deferred_reason: "P096 removes this mechanism", description: "fixture copy of a deferred row"}
EOF2
  AID_TTL_TODAY=2026-10-01 run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 0 ]
  AID_TTL_TODAY=2026-11-01 run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"id=cohort_row"* ]]
  sed -i 's/deferred_until: "2026-10-31", //' "$REGISTRY"
  AID_TTL_TODAY=2026-10-01 run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"id=cohort_row"* ]]
}

@test "TTL guard: a malformed AID_TTL_TODAY is refused" {
  AID_TTL_TODAY=tomorrow run bash "$TTL_GUARD" "$SHIPPED_REGISTRY"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ISO date"* ]]
}

@test "TTL guard: AID_TTL_TODAY without AID_TEST_MODE=1 is ignored with a warning" {
  cat > "$REGISTRY" <<'EOF2'
version: 1
enforcements:
  - {id: future_row, type: 4, source: "scripts/aid-fsm.sh:1", instruction: n/a, severity: advisory, surface: internal-guard, status: planned, verdict: unmapped, deadline: "2099-01-01", description: "stale only under the override"}
EOF2
  AID_TEST_MODE=0 AID_TTL_TODAY=2099-06-01 run bash "$TTL_GUARD" "$REGISTRY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AID_TTL_TODAY ignored"* ]]
}
