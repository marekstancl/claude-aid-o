#!/usr/bin/env bash
# =============================================================================
# test-c0-contract.sh — C0 Plan Contract Gate test harness (E-053-1_1 QA Step 6)
#
# Tests aid-c0-contract.sh (contract + review subcommands) against purpose-built
# fixtures in fixtures/c0/. Covers:
#   T1  clean-plan contract subcommand
#   T2  clean-plan review subcommand (observe, exit 0)
#   T3  cycle-plan review emits cycle finding
#   T4  dup-identifier review emits identifier finding
#   T5  p045-style lens scan aggregates blockers
#   T6  clean-low-risk all lenses absent, exit 0
#   T7  blocking-mode review: note that aid-c0-contract.sh is observe-only;
#       blocking enforcement lives in aid-auto-pipeline.sh (pipeline-level only).
#       This test verifies the review still exits 0 regardless of defects.
#   T8  protocol-v2 envelope validation on contract-manifest + plan-review
#   T9  clean-plan golden diff (structural shape of contract-manifest.json)
#
# Exit: 0 if all tests pass, 1 if any fail
#
# Requirements: bash 4.0+, jq, sha256sum
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
C0_SCRIPT="${PLUGIN_ROOT}/plugins/aid-orchestrator/scripts/aid-c0-contract.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/c0"

# Scratchpad for temp git repos (isolated, never need cwd change)
SCRATCHPAD="$(mktemp -d)"
trap 'rm -rf "$SCRATCHPAD"' EXIT

# ---------------------------------------------------------------------------
# Test counter infrastructure
# ---------------------------------------------------------------------------
PASS=0
FAIL=0

_pass() {
  local label="$1"
  echo "  PASS: ${label}"
  PASS=$(( PASS + 1 ))
}

_fail() {
  local label="$1"
  echo "  FAIL: ${label}"
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

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    _pass "${label} (file exists)"
  else
    _fail "${label} (file not found: ${path})"
  fi
}

assert_jq() {
  local label="$1" file="$2" query="$3" expected="$4"
  local actual
  actual="$(jq -r "$query" "$file" 2>/dev/null || echo "__JQ_ERROR__")"
  if [[ "$actual" == "$expected" ]]; then
    _pass "${label} (jq ${query} == ${expected})"
  else
    _fail "${label} (jq ${query}: expected '${expected}', got '${actual}')"
  fi
}

assert_jq_nonempty() {
  local label="$1" file="$2" query="$3"
  local actual
  actual="$(jq -r "$query" "$file" 2>/dev/null || echo "__JQ_ERROR__")"
  if [[ -n "$actual" && "$actual" != "null" && "$actual" != "__JQ_ERROR__" && "$actual" != "[]" ]]; then
    _pass "${label} (jq ${query} is non-empty)"
  else
    _fail "${label} (jq ${query} is empty/null/error; got: '${actual}')"
  fi
}

assert_jq_length_ge() {
  local label="$1" file="$2" query="$3" min="$4"
  local actual_len
  actual_len="$(jq -r "${query} | length" "$file" 2>/dev/null || echo "0")"
  if [[ "$actual_len" -ge "$min" ]]; then
    _pass "${label} (jq ${query} length=${actual_len} >= ${min})"
  else
    _fail "${label} (jq ${query} length=${actual_len} < ${min})"
  fi
}

# ---------------------------------------------------------------------------
# Helper: create a temp git repo (required by aid-c0-contract.sh for HEAD sha)
# Sets up an initialized git repo at <dir> with a single commit.
# ---------------------------------------------------------------------------
_make_git_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q 2>/dev/null
  git -C "$repo_dir" config user.email "test@test.com" 2>/dev/null
  git -C "$repo_dir" config user.name "Test" 2>/dev/null
  # Need at least one commit for HEAD sha
  printf '# test\n' > "${repo_dir}/README.md"
  git -C "$repo_dir" add README.md 2>/dev/null
  git -C "$repo_dir" commit -q -m "init" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Helper: run aid-c0-contract.sh, capture output and exit code
# Sets LAST_OUTPUT and LAST_EXIT
# ---------------------------------------------------------------------------
LAST_OUTPUT=""
LAST_EXIT=0

run_c0() {
  LAST_EXIT=0
  LAST_OUTPUT="$(bash "$C0_SCRIPT" "$@" 2>&1)" || LAST_EXIT=$?
}

# ---------------------------------------------------------------------------
# T1: clean-plan — contract subcommand
# ---------------------------------------------------------------------------
echo ""
echo "--- T1: clean-plan — contract subcommand ---"

T1_GIT="${SCRATCHPAD}/t1-git"
T1_C0="${SCRATCHPAD}/t1-c0"
_make_git_repo "$T1_GIT"
# Copy plan.json into git repo so git rev-parse works from plan_dir
cp "${FIXTURES_DIR}/clean-plan/plan.json" "${T1_GIT}/plan.json"

run_c0 contract "${T1_GIT}/plan.json" "$T1_C0"
assert_exit "T1 contract exit" 0 "$LAST_EXIT"

assert_file_exists "T1 plan-graph.json created" "${T1_C0}/plan-graph.json"
assert_file_exists "T1 contract-manifest.json created" "${T1_C0}/contract-manifest.json"

# plan-graph assertions
assert_jq_length_ge "T1 topological_order has 2 entries" \
  "${T1_C0}/plan-graph.json" \
  '.plan_graph.topological_order // .topological_order' 2

assert_jq "T1 cycles is empty array" \
  "${T1_C0}/plan-graph.json" \
  '(.plan_graph.cycles // .cycles) | length' "0"

# contract-manifest assertions
assert_jq_nonempty "T1 contract-manifest has bindings key" \
  "${T1_C0}/contract-manifest.json" \
  '.contract_manifest.bindings // .bindings'

assert_jq "T1 consumption_proof state == pending_slot" \
  "${T1_C0}/contract-manifest.json" \
  '.contract_manifest.consumption_proof.state // .consumption_proof.state' "pending_slot"

# ---------------------------------------------------------------------------
# T2: clean-plan — review subcommand (observe, always exit 0)
# ---------------------------------------------------------------------------
echo ""
echo "--- T2: clean-plan — review subcommand ---"

# Re-use T1 c0 dir (already has contract artifacts from T1)
T2_C0="$T1_C0"

run_c0 review "${FIXTURES_DIR}/clean-plan/plan.md" "$T2_C0"
assert_exit "T2 review exit" 0 "$LAST_EXIT"

assert_file_exists "T2 plan-review.json created" "${T2_C0}/plan-review.json"

# plan-review structural assertions
assert_jq_nonempty "T2 plan-review has plan_review key" \
  "${T2_C0}/plan-review.json" \
  '.plan_review'

assert_jq_nonempty "T2 structural_checks array present" \
  "${T2_C0}/plan-review.json" \
  '.plan_review.structural_checks'

# plan_graph_topo should pass (clean plan has no cycles)
assert_jq "T2 plan_graph_topo check status" \
  "${T2_C0}/plan-review.json" \
  '.plan_review.structural_checks[] | select(.id == "plan_graph_topo") | .status' "pass"

# ---------------------------------------------------------------------------
# T3: cycle-plan — review emits cycle finding
# ---------------------------------------------------------------------------
echo ""
echo "--- T3: cycle-plan — review emits cycle finding ---"

T3_GIT="${SCRATCHPAD}/t3-git"
T3_C0="${SCRATCHPAD}/t3-c0"
_make_git_repo "$T3_GIT"
cp "${FIXTURES_DIR}/cycle-plan/plan.json" "${T3_GIT}/plan.json"

run_c0 contract "${T3_GIT}/plan.json" "$T3_C0"
assert_exit "T3 contract exit" 0 "$LAST_EXIT"

run_c0 review "${FIXTURES_DIR}/cycle-plan/plan.md" "$T3_C0"
assert_exit "T3 review exit (observe mode)" 0 "$LAST_EXIT"

assert_file_exists "T3 plan-review.json created" "${T3_C0}/plan-review.json"

# plan_graph_topo should be observe (cycles detected)
assert_jq "T3 plan_graph_topo status is observe" \
  "${T3_C0}/plan-review.json" \
  '.plan_review.structural_checks[] | select(.id == "plan_graph_topo") | .status' "observe"

# Cycles count in plan-graph should be > 0
T3_CYCLES="$(jq -r '(.plan_graph.cycles // .cycles) | length' "${T3_C0}/plan-graph.json" 2>/dev/null || echo "0")"
if [[ "$T3_CYCLES" -gt 0 ]]; then
  _pass "T3 plan-graph.json has cycles (count=${T3_CYCLES})"
else
  _fail "T3 plan-graph.json expected cycles > 0, got ${T3_CYCLES}"
fi

# ---------------------------------------------------------------------------
# T4: dup-identifier — review emits identifier finding
# ---------------------------------------------------------------------------
echo ""
echo "--- T4: dup-identifier — review emits identifier finding ---"

T4_GIT="${SCRATCHPAD}/t4-git"
T4_C0="${SCRATCHPAD}/t4-c0"
_make_git_repo "$T4_GIT"
cp "${FIXTURES_DIR}/dup-identifier/plan.json" "${T4_GIT}/plan.json"

run_c0 contract "${T4_GIT}/plan.json" "$T4_C0"
assert_exit "T4 contract exit" 0 "$LAST_EXIT"

run_c0 review "${FIXTURES_DIR}/dup-identifier/plan.md" "$T4_C0"
assert_exit "T4 review exit (observe mode)" 0 "$LAST_EXIT"

assert_file_exists "T4 plan-review.json created" "${T4_C0}/plan-review.json"

# identifier_domain check should be observe (duplicate step IDs in plan.md table)
assert_jq "T4 identifier_domain status is observe" \
  "${T4_C0}/plan-review.json" \
  '.plan_review.structural_checks[] | select(.id == "identifier_domain") | .status' "observe"

# findings[] should be non-empty (identifier_domain adds to findings)
assert_jq_length_ge "T4 findings non-empty" \
  "${T4_C0}/plan-review.json" \
  '.plan_review.findings' 1

# ---------------------------------------------------------------------------
# T5: p045-style — lens scan aggregates blockers
# ---------------------------------------------------------------------------
echo ""
echo "--- T5: p045-style — lens scan aggregates blockers ---"

T5_GIT="${SCRATCHPAD}/t5-git"
T5_C0="${SCRATCHPAD}/t5-c0"
_make_git_repo "$T5_GIT"
cp "${FIXTURES_DIR}/p045-style/plan.json" "${T5_GIT}/plan.json"

# Copy prefilled lens files into the c0 evidence dir
mkdir -p "$T5_C0"
cp "${FIXTURES_DIR}/p045-style/prefilled-lenses/"*.md "$T5_C0/"

run_c0 contract "${T5_GIT}/plan.json" "$T5_C0"
assert_exit "T5 contract exit" 0 "$LAST_EXIT"

run_c0 review "${FIXTURES_DIR}/p045-style/plan.md" "$T5_C0"
assert_exit "T5 review exit (observe mode)" 0 "$LAST_EXIT"

assert_file_exists "T5 plan-review.json created" "${T5_C0}/plan-review.json"

# lens_findings should have >= 3 entries with count > 0
T5_BLOCKERS_COUNT="$(jq '[.plan_review.lens_findings[] | select(.count > 0)] | length' "${T5_C0}/plan-review.json" 2>/dev/null || echo "0")"
if [[ "$T5_BLOCKERS_COUNT" -ge 3 ]]; then
  _pass "T5 lens_findings has ${T5_BLOCKERS_COUNT} entries with stop_rule_blockers > 0 (>= 3)"
else
  _fail "T5 expected >= 3 lens_findings with blockers, got ${T5_BLOCKERS_COUNT}"
fi

# lens_dispatch_observed should be non-empty (e.g. "4/5" — 4 lenses found)
assert_jq_nonempty "T5 lens_dispatch_observed is non-empty" \
  "${T5_C0}/plan-review.json" \
  '.plan_review.lens_dispatch_observed'

# ---------------------------------------------------------------------------
# T6: clean-low-risk — all lenses absent, exit 0, valid artifacts
# ---------------------------------------------------------------------------
echo ""
echo "--- T6: clean-low-risk — all lenses absent, exit 0 ---"

T6_GIT="${SCRATCHPAD}/t6-git"
T6_C0="${SCRATCHPAD}/t6-c0"
_make_git_repo "$T6_GIT"
cp "${FIXTURES_DIR}/clean-low-risk/plan.json" "${T6_GIT}/plan.json"
# No lens files copied — all absent

run_c0 contract "${T6_GIT}/plan.json" "$T6_C0"
assert_exit "T6 contract exit" 0 "$LAST_EXIT"

run_c0 review "${FIXTURES_DIR}/clean-low-risk/plan.md" "$T6_C0"
assert_exit "T6 review exit" 0 "$LAST_EXIT"

assert_file_exists "T6 plan-review.json created" "${T6_C0}/plan-review.json"
assert_file_exists "T6 contract-manifest.json exists" "${T6_C0}/contract-manifest.json"
assert_file_exists "T6 plan-graph.json exists" "${T6_C0}/plan-graph.json"

# All 5 lens_findings should have verdict "absent" (no lens files present)
T6_ABSENT_COUNT="$(jq '[.plan_review.lens_findings[] | select(.verdict == "absent")] | length' "${T6_C0}/plan-review.json" 2>/dev/null || echo "0")"
if [[ "$T6_ABSENT_COUNT" -eq 5 ]]; then
  _pass "T6 all 5 lens_findings have verdict=absent"
else
  _fail "T6 expected 5 absent lens_findings, got ${T6_ABSENT_COUNT}"
fi

# lens_dispatch_observed should be "0/5" (no lenses found)
assert_jq "T6 lens_dispatch_observed is 0/5" \
  "${T6_C0}/plan-review.json" \
  '.plan_review.lens_dispatch_observed' "0/5"

# ---------------------------------------------------------------------------
# T7: blocking-mode — review exits 0 (observe-only tool)
# Note: aid-c0-contract.sh is observe-only by design. Blocking enforcement
# is pipeline-level (aid-auto-pipeline.sh reads c0_contract_policy and acts
# on plan-review.json findings). The review subcommand never exits non-zero
# due to findings, regardless of any external policy setting.
# ---------------------------------------------------------------------------
echo ""
echo "--- T7: blocking-mode — review always exits 0 (observe-only) ---"

T7_GIT="${SCRATCHPAD}/t7-git"
T7_C0="${SCRATCHPAD}/t7-c0"
_make_git_repo "$T7_GIT"
cp "${FIXTURES_DIR}/blocking-mode/plan.json" "${T7_GIT}/plan.json"

# Copy prefilled lens files
mkdir -p "$T7_C0"
cp "${FIXTURES_DIR}/blocking-mode/prefilled-lenses/"*.md "$T7_C0/"

run_c0 contract "${T7_GIT}/plan.json" "$T7_C0"
assert_exit "T7 contract exit" 0 "$LAST_EXIT"

# Even with defects (cycle + dup ID + blocker lenses), review exits 0
run_c0 review "${FIXTURES_DIR}/blocking-mode/plan.md" "$T7_C0"
assert_exit "T7 review exits 0 (observe-only, blocking is pipeline-level)" 0 "$LAST_EXIT"

assert_file_exists "T7 plan-review.json created" "${T7_C0}/plan-review.json"

# Verify the review DID find defects (to prove it's not a vacuous pass)
T7_FINDINGS="$(jq '.plan_review.findings | length' "${T7_C0}/plan-review.json" 2>/dev/null || echo "0")"
T7_SC_OBSERVE="$(jq '[.plan_review.structural_checks[] | select(.status == "observe")] | length' "${T7_C0}/plan-review.json" 2>/dev/null || echo "0")"
if [[ "$T7_FINDINGS" -gt 0 || "$T7_SC_OBSERVE" -gt 0 ]]; then
  _pass "T7 review found defects (findings=${T7_FINDINGS}, observe_checks=${T7_SC_OBSERVE}) but still exited 0"
else
  _fail "T7 expected review to find defects, but found none (blocking-mode plan has cycle + dup ID)"
fi

# ---------------------------------------------------------------------------
# T8: protocol-v2 envelope validation
# ---------------------------------------------------------------------------
echo ""
echo "--- T8: protocol-v2 envelope validation ---"

# Validate contract-manifest.json has all required protocol v2 fields
# Re-use T1 artifacts
T8_CM="${T1_C0}/contract-manifest.json"
T8_PR="${T1_C0}/plan-review.json"

for field in schema_version artifact_type producer created_at control_protocol; do
  VAL="$(jq -r ".${field} // empty" "$T8_CM" 2>/dev/null || true)"
  if [[ -n "$VAL" && "$VAL" != "null" ]]; then
    _pass "T8 contract-manifest has ${field}"
  else
    _fail "T8 contract-manifest missing ${field}"
  fi
done

# Verify schema_version == "aid-2.0"
assert_jq "T8 contract-manifest schema_version" "$T8_CM" '.schema_version' "aid-2.0"
assert_jq "T8 contract-manifest artifact_type" "$T8_CM" '.artifact_type' "contract_manifest"

# plan-review.json protocol v2 fields
for field in schema_version artifact_type producer created_at; do
  VAL="$(jq -r ".${field} // empty" "$T8_PR" 2>/dev/null || true)"
  if [[ -n "$VAL" && "$VAL" != "null" ]]; then
    _pass "T8 plan-review has ${field}"
  else
    _fail "T8 plan-review missing ${field}"
  fi
done

assert_jq "T8 plan-review schema_version" "$T8_PR" '.schema_version' "aid-2.0"
assert_jq "T8 plan-review artifact_type" "$T8_PR" '.artifact_type' "plan_review"
assert_jq "T8 plan-review status" "$T8_PR" '.status' "pass"

# Both artifacts must be valid JSON
for artifact in "$T8_CM" "$T8_PR"; do
  if jq . "$artifact" >/dev/null 2>&1; then
    _pass "T8 $(basename "$artifact") is valid JSON"
  else
    _fail "T8 $(basename "$artifact") is NOT valid JSON"
  fi
done

# ---------------------------------------------------------------------------
# T9: clean-plan golden diff
# ---------------------------------------------------------------------------
echo ""
echo "--- T9: clean-plan golden diff ---"

GOLDEN="${FIXTURES_DIR}/clean-plan/_golden/expected-contract-manifest.json"
ACTUAL="${T1_C0}/contract-manifest.json"

assert_file_exists "T9 golden file exists" "$GOLDEN"
assert_file_exists "T9 actual contract-manifest exists" "$ACTUAL"

# Structural checks: both have required keys
for key in schema_version artifact_type producer contract_manifest; do
  GOLDEN_HAS="$(jq "has(\"${key}\")" "$GOLDEN" 2>/dev/null || echo "false")"
  ACTUAL_HAS="$(jq "has(\"${key}\")" "$ACTUAL" 2>/dev/null || echo "false")"
  if [[ "$GOLDEN_HAS" == "true" && "$ACTUAL_HAS" == "true" ]]; then
    _pass "T9 both golden and actual have top-level key '${key}'"
  elif [[ "$GOLDEN_HAS" != "true" ]]; then
    _fail "T9 golden missing top-level key '${key}'"
  else
    _fail "T9 actual missing top-level key '${key}' (golden has it)"
  fi
done

# contract_manifest sub-keys
for sub_key in bindings consumption_proof manifest_hash; do
  ACTUAL_HAS_SUB="$(jq ".contract_manifest | has(\"${sub_key}\")" "$ACTUAL" 2>/dev/null || echo "false")"
  if [[ "$ACTUAL_HAS_SUB" == "true" ]]; then
    _pass "T9 contract_manifest.${sub_key} present in actual"
  else
    _fail "T9 contract_manifest.${sub_key} missing from actual"
  fi
done

# consumption_proof.state must match
assert_jq "T9 consumption_proof.state == pending_slot" \
  "$ACTUAL" '.contract_manifest.consumption_proof.state' "pending_slot"

# Hash values must match between golden and actual (deterministic)
GOLDEN_MHASH="$(jq -r '.contract_manifest.manifest_hash' "$GOLDEN" 2>/dev/null || echo "")"
ACTUAL_MHASH="$(jq -r '.contract_manifest.manifest_hash' "$ACTUAL" 2>/dev/null || echo "")"
if [[ -n "$GOLDEN_MHASH" && "$GOLDEN_MHASH" == "$ACTUAL_MHASH" ]]; then
  _pass "T9 manifest_hash matches golden (${GOLDEN_MHASH})"
else
  _fail "T9 manifest_hash mismatch: golden='${GOLDEN_MHASH}' actual='${ACTUAL_MHASH}'"
fi

GOLDEN_BHASH="$(jq -r '.contract_manifest.bindings[0].hash' "$GOLDEN" 2>/dev/null || echo "")"
ACTUAL_BHASH="$(jq -r '.contract_manifest.bindings[0].hash' "$ACTUAL" 2>/dev/null || echo "")"
if [[ -n "$GOLDEN_BHASH" && "$GOLDEN_BHASH" == "$ACTUAL_BHASH" ]]; then
  _pass "T9 binding[0].hash matches golden"
else
  _fail "T9 binding[0].hash mismatch: golden='${GOLDEN_BHASH}' actual='${ACTUAL_BHASH}'"
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

echo "PASS: all C0 contract gate tests passed"
exit 0
