#!/usr/bin/env bats
# aid-tier: t2
# test-ci-floor.bats — tests for the CI plan-boundary-required-check logic
# E-046-2_3 Step 7 — verifies the shell script extracted from
# defaults/ci/plan-boundary-required-check.yml behaves correctly.
# Tests run the CI check logic in a temp directory (simulating repo root).

setup() {
  TMP=$(mktemp -d)
  export TMP
  mkdir -p "$TMP/.aid-o/reports"

  # Extract the CI check shell logic into a standalone script.
  cat > "$TMP/ci-check.sh" << 'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
MANIFESTS=$(find .aid-o/reports -name '*-boundary.md' 2>/dev/null || true)
if [[ -z "$MANIFESTS" ]]; then
  echo "No plan boundary manifests found — skipping check (no completed plans)"
  exit 0
fi
FAILED=0
for manifest in $MANIFESTS; do
  if ! grep -q 'boundary_complete: true' "$manifest"; then
    echo "FAIL: $manifest — boundary_complete is not true"
    FAILED=1
  fi
  delivery=$(grep 'delivery_report:' "$manifest" | sed 's/.*delivery_report: //' | tr -d '"' | tr -d "'")
  if [[ -n "$delivery" && ! -f ".aid-o/reports/$delivery" ]]; then
    echo "FAIL: $manifest — referenced delivery report .aid-o/reports/$delivery not found"
    FAILED=1
  fi
done
if [[ "$FAILED" -eq 1 ]]; then
  echo "Plan boundary check failed — see above"
  exit 1
fi
echo "All plan boundary manifests valid"
SCRIPT
  chmod +x "$TMP/ci-check.sh"
}

teardown() {
  rm -rf "$TMP"
}

# ── Test 1: no boundary manifests -> exit 0 ──────────────────────────────

@test "CI floor: no boundary manifests -> exit 0 (no completed plans)" {
  # .aid-o/reports/ is empty — no *-boundary.md files
  cd "$TMP"
  run bash "$TMP/ci-check.sh"
  [ "$status" -eq 0 ]
}

# ── Test 2: valid manifest + delivery present -> exit 0 ──────────────────

@test "CI floor: manifest with boundary_complete: true + delivery present -> exit 0" {
  cat > "$TMP/.aid-o/reports/P046-boundary.md" << 'MANIFEST'
boundary_complete: true
delivery_report: P046-delivery.md
MANIFEST
  touch "$TMP/.aid-o/reports/P046-delivery.md"
  cd "$TMP"
  run bash "$TMP/ci-check.sh"
  [ "$status" -eq 0 ]
}

# ── Test 3: manifest missing boundary_complete: true -> exit 1 ───────────

@test "CI floor: manifest missing boundary_complete: true -> exit 1" {
  cat > "$TMP/.aid-o/reports/P046-boundary.md" << 'MANIFEST'
boundary_complete: false
delivery_report: P046-delivery.md
MANIFEST
  touch "$TMP/.aid-o/reports/P046-delivery.md"
  cd "$TMP"
  run bash "$TMP/ci-check.sh"
  [ "$status" -ne 0 ]
}

# ── Test 4: manifest references missing delivery report -> exit 1 ─────────

@test "CI floor: manifest references missing delivery report -> exit 1" {
  cat > "$TMP/.aid-o/reports/P046-boundary.md" << 'MANIFEST'
boundary_complete: true
delivery_report: P046-delivery.md
MANIFEST
  # Intentionally do NOT create P046-delivery.md
  cd "$TMP"
  run bash "$TMP/ci-check.sh"
  [ "$status" -ne 0 ]
}
