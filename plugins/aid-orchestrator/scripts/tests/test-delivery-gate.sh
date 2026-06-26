#!/usr/bin/env bash
# =============================================================================
# test-delivery-gate.sh — Delivery Gate Engine test harness (E-050-1_1 QA Step)
#
# Tests all 12 DG check scripts against purpose-built fixtures:
#   - Every check has at least one fixture that produces a known status
#   - Every fixture output passes aid-protocol-validate.sh (via golden sample)
#   - DG-07 parent-done-pending-child: fail path + observe-pass path
#   - DG-06 removed-dep: uses temp git repo with history
#   - DG-10 framework-startup-throw: node-conditional (skips if node not in PATH)
#
# Exit: 0 if all tests pass, 1 if any fail
#
# Acceptance criteria (EPIC E-050-1_1):
#   [qa1] Each of 11 fail fixtures returns expected per-check fail/unverifiable
#         status; each DG-01..12 has at least one fixture that demonstrably fails
#   [qa2] parent-done-pending-child: DG-07 fail, but FSM observe transition
#         (pass with no pending dispatches) PASSES + would_block event
#   [qa3] delivery-gate.sample.json passes aid-protocol-validate.sh
#   [qa4] Full schema is valid JSON and covers .delivery_gate.{checks,summary}
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
CHECKS_DIR="${PLUGIN_ROOT}/plugins/aid-orchestrator/scripts/lib/delivery-checks"
VALIDATOR="${PLUGIN_ROOT}/plugins/aid-orchestrator/scripts/aid-protocol-validate.sh"
SCHEMA_FILE="${PLUGIN_ROOT}/plugins/aid-orchestrator/defaults/schemas/delivery-gate.schema.json"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/delivery"
GOLDEN_FILE="${FIXTURES_DIR}/_golden/delivery-gate.sample.json"

# Scratchpad for temp git repos (isolated, never cwd-change needed)
SCRATCHPAD="${TMPDIR:-/tmp}/aid-dg-test-$$"
mkdir -p "$SCRATCHPAD"
trap 'rm -rf "$SCRATCHPAD"' EXIT

# ---------------------------------------------------------------------------
# Test counter infrastructure
# ---------------------------------------------------------------------------
PASS=0
FAIL=0

_pass() {
  local label="$1"
  echo "PASS: ${label}"
  PASS=$(( PASS + 1 ))
}

_fail() {
  local label="$1"
  echo "FAIL: ${label}"
  FAIL=$(( FAIL + 1 ))
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    _pass "${label} (exit=${actual})"
  else
    _fail "${label} (expected exit=${expected}, got exit=${actual})"
  fi
}

assert_output_contains() {
  local label="$1" output="$2" pattern="$3"
  if echo "$output" | grep -qE "$pattern"; then
    _pass "${label} (output contains: ${pattern})"
  else
    _fail "${label} (expected output to contain: ${pattern})"
    echo "  Output was: $(echo "$output" | head -5)"
  fi
}

# ---------------------------------------------------------------------------
# Helper: run a check script, capture output and exit code
# run_check <script_name> <AID_PROJECT_ROOT> [extra env vars...] [-- argv...]
# Returns: LAST_OUTPUT, LAST_EXIT
# ---------------------------------------------------------------------------
LAST_OUTPUT=""
LAST_EXIT=0

run_check() {
  local check_script="${CHECKS_DIR}/$1"
  local project_root="$2"
  shift 2

  # Collect env assignments (k=v) before --
  local -a env_prefix=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    env_prefix+=("$1")
    shift
  done
  [[ $# -gt 0 ]] && shift  # consume "--"

  # Remaining args are argv for the check script
  local -a argv=("$@")

  LAST_EXIT=0
  if [[ ${#env_prefix[@]} -gt 0 ]]; then
    LAST_OUTPUT="$(env AID_PROJECT_ROOT="$project_root" "${env_prefix[@]}" \
      bash "$check_script" "${argv[@]}" 2>&1)" || LAST_EXIT=$?
  else
    LAST_OUTPUT="$(AID_PROJECT_ROOT="$project_root" \
      bash "$check_script" "${argv[@]}" 2>&1)" || LAST_EXIT=$?
  fi
}

# ---------------------------------------------------------------------------
# DG-01 — dependency-consistency — manifest-lock-mismatch (FAIL)
# multer is in package.json but NOT in package-lock.json
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-01: dependency-consistency ---"

FIXTURE="${FIXTURES_DIR}/manifest-lock-mismatch"
run_check "dg01-dependency-consistency.sh" "$FIXTURE"
assert_exit "dg01 manifest-lock-mismatch exit=1 (fail)" 1 "$LAST_EXIT"
assert_output_contains "dg01 output mentions multer" "$LAST_OUTPUT" "multer"

# ---------------------------------------------------------------------------
# DG-02 — build — leaf-pass-root-fail (FAIL)
# Build script exits 1 (root build failure)
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-02: build ---"

FIXTURE="${FIXTURES_DIR}/leaf-pass-root-fail"
chmod +x "${FIXTURE}/build.sh" 2>/dev/null || true
run_check "dg02-build.sh" "$FIXTURE" -- bash ./build.sh
assert_exit "dg02 leaf-pass-root-fail exit=1 (fail)" 1 "$LAST_EXIT"
assert_output_contains "dg02 output mentions build failed" "$LAST_OUTPUT" "build failed"

# ---------------------------------------------------------------------------
# DG-03 — typecheck — TS project with typecheck command that exits 1 (FAIL)
# Uses an inline temp dir with a .ts file and a failing typecheck command
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-03: typecheck ---"

TSDIR="${SCRATCHPAD}/ts-fail-dir"
mkdir -p "${TSDIR}/src"
printf 'const x: string = 42; // type error\n' > "${TSDIR}/src/broken.ts"

run_check "dg03-typecheck.sh" "$TSDIR" -- \
  bash -c 'echo "error TS2322: Type '"'"'number'"'"' is not assignable to type '"'"'string'"'"'"; exit 1'
assert_exit "dg03 typecheck-fail exit=1 (fail)" 1 "$LAST_EXIT"
assert_output_contains "dg03 output mentions typecheck failed" "$LAST_OUTPUT" "(typecheck failed|failed)"

# ---------------------------------------------------------------------------
# DG-04 — test — zero-test-workspace (UNVERIFIABLE)
# Test command exits 0 but reports "0 tests passing"
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-04: test ---"

FIXTURE="${FIXTURES_DIR}/zero-test-workspace"
chmod +x "${FIXTURE}/run-tests.sh" 2>/dev/null || true
run_check "dg04-test.sh" "$FIXTURE" -- bash ./run-tests.sh
assert_exit "dg04 zero-test-workspace exit=2 (unverifiable)" 2 "$LAST_EXIT"
assert_output_contains "dg04 output mentions unverifiable" "$LAST_OUTPUT" "unverifiable"

# ---------------------------------------------------------------------------
# DG-05 — consumer-compile — no changed paths → unverifiable
# With no AID_CHANGED_PATHS, dg05 exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-05: consumer-compile ---"

# Create a minimal fixture dir
DG05_DIR="${SCRATCHPAD}/dg05-dir"
mkdir -p "$DG05_DIR"

run_check "dg05-consumer-compile.sh" "$DG05_DIR"
assert_exit "dg05 no-changed-paths exit=2 (unverifiable)" 2 "$LAST_EXIT"
assert_output_contains "dg05 output mentions unverifiable" "$LAST_OUTPUT" "unverifiable"

# With a changed path matching src/*.ts but no argv → also unverifiable
CHANGED_FILE="${SCRATCHPAD}/changed-paths.txt"
printf 'src/index.ts\n' > "$CHANGED_FILE"

run_check "dg05-consumer-compile.sh" "$DG05_DIR" "AID_CHANGED_PATHS=${CHANGED_FILE}"
assert_exit "dg05 changed-path-no-cmd exit=2 (unverifiable)" 2 "$LAST_EXIT"
assert_output_contains "dg05 public export change detected" "$LAST_OUTPUT" "(public export change|unverifiable)"

# ---------------------------------------------------------------------------
# DG-06 — removed-dep — removed-dep-multer (FAIL)
# Needs a temp git repo with multer in initial commit, removed in HEAD
# src/upload.js still requires('multer')
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-06: removed-dep ---"

DG06_DIR="${SCRATCHPAD}/dg06-test"
mkdir -p "${DG06_DIR}/src"

# Copy upload.js from fixture
cp "${FIXTURES_DIR}/removed-dep-multer/src/upload.js" "${DG06_DIR}/src/"

# Build git history
git -C "$DG06_DIR" init -q 2>/dev/null
git -C "$DG06_DIR" config user.email "test@test.com" 2>/dev/null
git -C "$DG06_DIR" config user.name "Test" 2>/dev/null

# Initial commit: multer in package.json
printf '{"name":"test","version":"1.0.0","dependencies":{"express":"4.18.2","multer":"1.4.5"}}\n' \
  > "${DG06_DIR}/package.json"
git -C "$DG06_DIR" add -A 2>/dev/null
git -C "$DG06_DIR" commit -q -m "initial: multer present" 2>/dev/null
DG06_BASE_SHA=$(git -C "$DG06_DIR" rev-parse HEAD)

# HEAD commit: multer removed from package.json (but still in src/upload.js)
printf '{"name":"test","version":"1.0.0","dependencies":{"express":"4.18.2"}}\n' \
  > "${DG06_DIR}/package.json"
git -C "$DG06_DIR" add package.json 2>/dev/null
git -C "$DG06_DIR" commit -q -m "remove: multer removed" 2>/dev/null

run_check "dg06-removed-dep.sh" "$DG06_DIR" "AID_BASE_SHA=${DG06_BASE_SHA}"
assert_exit "dg06 removed-dep-multer exit=1 (fail)" 1 "$LAST_EXIT"
assert_output_contains "dg06 output mentions multer" "$LAST_OUTPUT" "multer"

# ---------------------------------------------------------------------------
# DG-07 — state-consistency — parent-done-pending-child (FAIL)
# fsm-state.yaml has current_step=2 < total_steps=3 at state=DONE
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-07: state-consistency ---"

FIXTURE="${FIXTURES_DIR}/parent-done-pending-child"
run_check "dg07-state-consistency.sh" "$FIXTURE" \
  "AID_EPIC_ID=E-TEST-1_1" "AID_RUN_ID=R-E-TEST-1"
assert_exit "dg07 parent-done-pending-child exit=1 (fail)" 1 "$LAST_EXIT"
assert_output_contains "dg07 output mentions non-complete child step" "$LAST_OUTPUT" "(non-complete child step|FAIL)"

# DG-07 OBSERVE PASS: a fresh dir with no fsm-state.yaml → unverifiable (not fail)
DG07_PASS_DIR="${SCRATCHPAD}/dg07-pass-dir"
mkdir -p "$DG07_PASS_DIR"
run_check "dg07-state-consistency.sh" "$DG07_PASS_DIR" \
  "AID_EPIC_ID=E-DUMMY-1_1" "AID_RUN_ID=R-DUMMY-1"
# Without state file → unverifiable (exit 2), which is the "pass" in observe mode
assert_exit "dg07 observe-pass (no state file) exit=2 (unverifiable)" 2 "$LAST_EXIT"
assert_output_contains "dg07 observe-pass output mentions unverifiable" "$LAST_OUTPUT" "unverifiable"

# DG-07 PASS: state file with step complete (current_step == total_steps)
DG07_DONE_DIR="${SCRATCHPAD}/dg07-done-dir"
mkdir -p "${DG07_DONE_DIR}/.aid-o/work/evidence/E-DONE-1_1/R-DONE-1"
cat > "${DG07_DONE_DIR}/.aid-o/work/evidence/E-DONE-1_1/R-DONE-1/fsm-state.yaml" <<'EOF'
epic_id: E-DONE-1_1
run_id: R-DONE-1
state: DONE
done_phase: release
current_step: 3
total_steps: 3
EOF
run_check "dg07-state-consistency.sh" "$DG07_DONE_DIR" \
  "AID_EPIC_ID=E-DONE-1_1" "AID_RUN_ID=R-DONE-1"
assert_exit "dg07 complete-steps exit=0 (pass)" 0 "$LAST_EXIT"
assert_output_contains "dg07 pass output" "$LAST_OUTPUT" "pass"

# ---------------------------------------------------------------------------
# DG-08 — runtime-env — runtime-matrix-conflict (FAIL)
# .nvmrc=20, package.json engines.node=">=18 <20" → conflict
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-08: runtime-env ---"

FIXTURE="${FIXTURES_DIR}/runtime-matrix-conflict"
run_check "dg08-runtime-env.sh" "$FIXTURE"
assert_exit "dg08 runtime-matrix-conflict exit=1 (fail)" 1 "$LAST_EXIT"
assert_output_contains "dg08 output mentions conflict" "$LAST_OUTPUT" "(conflict|fail)"

# DG-08 UNVERIFIABLE: no .nvmrc or .node-version
DG08_EMPTY_DIR="${SCRATCHPAD}/dg08-empty"
mkdir -p "$DG08_EMPTY_DIR"
run_check "dg08-runtime-env.sh" "$DG08_EMPTY_DIR"
assert_exit "dg08 no-baseline exit=2 (unverifiable)" 2 "$LAST_EXIT"
assert_output_contains "dg08 unverifiable output" "$LAST_OUTPUT" "unverifiable"

# ---------------------------------------------------------------------------
# DG-09 — static-coverage — vacuous-typecheck (UNVERIFIABLE)
# typecheck.sh exits 0 but outputs "Files: 0"
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-09: static-coverage ---"

FIXTURE="${FIXTURES_DIR}/vacuous-typecheck"
chmod +x "${FIXTURE}/typecheck.sh" 2>/dev/null || true
run_check "dg09-static-coverage.sh" "$FIXTURE" -- bash ./typecheck.sh
assert_exit "dg09 vacuous-typecheck exit=2 (unverifiable)" 2 "$LAST_EXIT"
assert_output_contains "dg09 output mentions vacuous" "$LAST_OUTPUT" "(unverifiable|vacuous)"

# DG-09 FAIL: typecheck command exits 1 (real type errors)
DG09_FAIL_DIR="${SCRATCHPAD}/dg09-fail"
mkdir -p "$DG09_FAIL_DIR"
run_check "dg09-static-coverage.sh" "$DG09_FAIL_DIR" -- \
  bash -c 'echo "src/index.ts:5:3 - error TS2322: Type number is not assignable"; exit 1'
assert_exit "dg09 typecheck-error exit=1 (fail)" 1 "$LAST_EXIT"

# ---------------------------------------------------------------------------
# DG-10 — startup-smoke — framework-startup-throw (FAIL)
# dist/index.js throws on startup
# Only runs if node is in PATH
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-10: startup-smoke ---"

FIXTURE="${FIXTURES_DIR}/framework-startup-throw"
if command -v node >/dev/null 2>&1; then
  # Test with argv mode: node dist/index.js — will throw and exit 1
  run_check "dg10-startup-smoke.sh" "$FIXTURE" -- node dist/index.js
  assert_exit "dg10 framework-startup-throw exit=1 (fail)" 1 "$LAST_EXIT"
  assert_output_contains "dg10 output mentions error" "$LAST_OUTPUT" "(Error:|fail)"
else
  echo "SKIP: dg10 framework-startup-throw — node not in PATH (node-required test)"
fi

# DG-10 UNVERIFIABLE: no node, no argv, no entry point
DG10_EMPTY_DIR="${SCRATCHPAD}/dg10-empty"
mkdir -p "$DG10_EMPTY_DIR"
if ! command -v node >/dev/null 2>&1; then
  run_check "dg10-startup-smoke.sh" "$DG10_EMPTY_DIR"
  assert_exit "dg10 no-node-no-entry exit=2 (unverifiable)" 2 "$LAST_EXIT"
fi

# ---------------------------------------------------------------------------
# DG-11 — build-config — build-config-absent-module (FAIL)
# vite.config.js references ./src/lib/missing-module.js which doesn't exist
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-11: build-config ---"

FIXTURE="${FIXTURES_DIR}/build-config-absent-module"
run_check "dg11-build-config.sh" "$FIXTURE"
assert_exit "dg11 build-config-absent-module exit=1 (fail)" 1 "$LAST_EXIT"
assert_output_contains "dg11 output mentions missing module" "$LAST_OUTPUT" "(missing-module|does not exist|fail)"

# DG-11 UNVERIFIABLE: no build config files
DG11_EMPTY_DIR="${SCRATCHPAD}/dg11-empty"
mkdir -p "$DG11_EMPTY_DIR"
run_check "dg11-build-config.sh" "$DG11_EMPTY_DIR"
assert_exit "dg11 no-config exit=2 (unverifiable)" 2 "$LAST_EXIT"
assert_output_contains "dg11 unverifiable output" "$LAST_OUTPUT" "unverifiable"

# ---------------------------------------------------------------------------
# DG-12 — authority — authority-contradiction (FAIL)
# .aid-o/config/execution.yaml has enforcement:blocking + status:planned
# ---------------------------------------------------------------------------
echo ""
echo "--- DG-12: authority ---"

FIXTURE="${FIXTURES_DIR}/authority-contradiction"
run_check "dg12-authority.sh" "$FIXTURE"
assert_exit "dg12 authority-contradiction exit=1 (fail)" 1 "$LAST_EXIT"
assert_output_contains "dg12 output mentions contradiction" "$LAST_OUTPUT" "(contradiction|blocking.*planned|fail)"

# DG-12 UNVERIFIABLE: no authority files
DG12_EMPTY_DIR="${SCRATCHPAD}/dg12-empty"
mkdir -p "$DG12_EMPTY_DIR"
run_check "dg12-authority.sh" "$DG12_EMPTY_DIR"
assert_exit "dg12 no-authority-files exit=2 (unverifiable)" 2 "$LAST_EXIT"
assert_output_contains "dg12 unverifiable output" "$LAST_OUTPUT" "unverifiable"

# ---------------------------------------------------------------------------
# [qa3] Golden sample passes aid-protocol-validate.sh
# ---------------------------------------------------------------------------
echo ""
echo "--- [qa3] Golden sample protocol validation ---"

if [[ ! -f "$GOLDEN_FILE" ]]; then
  _fail "golden delivery-gate.sample.json does not exist at ${GOLDEN_FILE}"
else
  GOLDEN_EXIT=0
  bash "$VALIDATOR" "$GOLDEN_FILE" >/dev/null 2>&1 || GOLDEN_EXIT=$?
  assert_exit "golden delivery-gate.sample.json passes protocol validator" 0 "$GOLDEN_EXIT"
fi

# ---------------------------------------------------------------------------
# [qa4] Schema is valid JSON covering .delivery_gate.{checks,summary}
# ---------------------------------------------------------------------------
echo ""
echo "--- [qa4] Schema validity ---"

if [[ ! -f "$SCHEMA_FILE" ]]; then
  _fail "delivery-gate.schema.json does not exist at ${SCHEMA_FILE}"
else
  SCHEMA_JSON_EXIT=0
  jq . "$SCHEMA_FILE" >/dev/null 2>&1 || SCHEMA_JSON_EXIT=$?
  assert_exit "delivery-gate.schema.json is valid JSON" 0 "$SCHEMA_JSON_EXIT"

  # Verify schema covers delivery_gate.checks
  CHECKS_PATH=$(jq -r '.properties.delivery_gate.properties.checks.type // empty' "$SCHEMA_FILE" 2>/dev/null)
  if [[ "$CHECKS_PATH" == "array" ]]; then
    _pass "schema covers .delivery_gate.checks (type=array)"
  else
    _fail "schema missing .delivery_gate.checks or wrong type (got: ${CHECKS_PATH:-empty})"
  fi

  # Verify schema covers delivery_gate.summary
  SUMMARY_PATH=$(jq -r '.properties.delivery_gate.properties.summary["$ref"] // .properties.delivery_gate.properties.summary.type // empty' "$SCHEMA_FILE" 2>/dev/null)
  if [[ -n "$SUMMARY_PATH" ]]; then
    _pass "schema covers .delivery_gate.summary"
  else
    _fail "schema missing .delivery_gate.summary reference"
  fi

  # Verify schema has delivery_gate.phase and delivery_gate.profile
  PHASE_ENUM=$(jq -r '.properties.delivery_gate.properties.phase.enum // empty' "$SCHEMA_FILE" 2>/dev/null)
  if [[ -n "$PHASE_ENUM" ]]; then
    _pass "schema covers .delivery_gate.phase with enum"
  else
    _fail "schema missing .delivery_gate.phase enum"
  fi
fi

# ---------------------------------------------------------------------------
# [qa2] DG-07 observe-mode: would_block semantics
# The parent-done-pending-child fixture triggers dg07 exit=1 (fail)
# which means in delivery context delivery_ready=false, would_block=true
# This test validates the check script directly (dispatch integration is
# tested via aid-delivery-gate.sh integration tests in test-full-pipeline.sh)
# ---------------------------------------------------------------------------
echo ""
echo "--- [qa2] DG-07 would_block semantics ---"

# Re-run the fail fixture and confirm it exits 1 (which maps to would_block=true)
FIXTURE="${FIXTURES_DIR}/parent-done-pending-child"
LAST_EXIT=0
LAST_OUTPUT="$(AID_PROJECT_ROOT="$FIXTURE" AID_EPIC_ID="E-TEST-1_1" AID_RUN_ID="R-E-TEST-1" \
  bash "${CHECKS_DIR}/dg07-state-consistency.sh" 2>&1)" || LAST_EXIT=$?

if [[ "$LAST_EXIT" -eq 1 ]]; then
  _pass "dg07 parent-done-pending-child exits 1 (→ would_block=true in dispatcher)"
else
  _fail "dg07 parent-done-pending-child expected exit=1, got exit=${LAST_EXIT}"
fi

# FSM observe transition: a state file with current_step==total_steps should PASS
LAST_EXIT=0
LAST_OUTPUT="$(AID_PROJECT_ROOT="$DG07_DONE_DIR" AID_EPIC_ID="E-DONE-1_1" AID_RUN_ID="R-DONE-1" \
  bash "${CHECKS_DIR}/dg07-state-consistency.sh" 2>&1)" || LAST_EXIT=$?

if [[ "$LAST_EXIT" -eq 0 ]]; then
  _pass "dg07 complete-steps (step==total) exits 0 (→ would_block=false in dispatcher)"
else
  _fail "dg07 complete-steps expected exit=0, got exit=${LAST_EXIT}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
TOTAL=$(( PASS + FAIL ))
echo "Results: ${PASS}/${TOTAL} passed"

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAIL: ${FAIL} test(s) failed"
  exit 1
fi

echo "PASS: all delivery gate tests passed"
exit 0
