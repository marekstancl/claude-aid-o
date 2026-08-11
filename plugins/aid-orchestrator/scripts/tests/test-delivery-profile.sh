#!/usr/bin/env bash
# aid-tier: t2
# =============================================================================
# test-delivery-profile.sh — Tests for aid-delivery-profile.sh resolver
#
# Tests:
#   T1  resolve_profile → "plugin-bash" for this repo (aid-orchestrator)
#   T2  resolve_profile → "unverifiable" for empty temp dir
#   T3  resolve_profile → union or first match for npm+plugin dir
#   T4  select_commands plugin-bash dg04 → non-empty (bats test runner)
#   T5  select_commands plugin-bash dg02 → empty (no build step)
#   T6  select_commands unverifiable dg04 → empty
#   T7  malformed policy YAML → exit 1 (no implicit fallback)
#   T8  select_commands plugin-bash dg01 → empty (skip: legacy_no_child_rows)
#
# Exit: 0 if all tests pass, 1 if any fail
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
PROFILE_LIB="${LIB_DIR}/aid-delivery-profile.sh"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"  # aid-orchestrator repo root
POLICY_FILE="${PLUGIN_ROOT}/plugins/aid-orchestrator/defaults/policies/delivery-gate.yaml"

# ---------------------------------------------------------------------------
# Test infrastructure
# ---------------------------------------------------------------------------
pass=0
fail=0

_pass() {
  echo "PASS: $1"
  pass=$((pass + 1))
}

_fail() {
  echo "FAIL: $1"
  fail=$((fail + 1))
}

# Source the library under test
# shellcheck source=../lib/aid-delivery-profile.sh
if ! source "$PROFILE_LIB" 2>/dev/null; then
  echo "FATAL: could not source ${PROFILE_LIB}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Temp dir setup (auto-cleaned on exit)
# ---------------------------------------------------------------------------
TMPDIR_BASE="${TMPDIR:-/tmp}/aid-delivery-profile-test-$$"
mkdir -p "$TMPDIR_BASE"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ---------------------------------------------------------------------------
# T1: resolve_profile returns "plugin-bash" (or union containing it) for this repo
# ---------------------------------------------------------------------------
# This repo has:
#   plugins/aid-orchestrator/.claude-plugin/plugin.json  (exists)
#   plugins/aid-orchestrator/scripts/aid-fsm.sh          (exists)
# Both detect conditions for plugin-bash are met.
#
# The repo also has package.json with "workspaces", so npm-workspaces also matches.
# Result is the union "npm-workspaces+plugin-bash" — both profiles match.
# T1 accepts either "plugin-bash" or any union containing "plugin-bash".

RESULT=$(DELIVERY_GATE_POLICY="$POLICY_FILE" resolve_profile "$PLUGIN_ROOT" 2>&1)
if [[ "$RESULT" == "plugin-bash" || "$RESULT" == *"plugin-bash"* ]]; then
  _pass "T1: resolve_profile returns '${RESULT}' (contains plugin-bash) for aid-orchestrator repo"
else
  _fail "T1: resolve_profile returned '${RESULT}', expected 'plugin-bash' or union containing it"
fi

# ---------------------------------------------------------------------------
# T2: resolve_profile returns "unverifiable" for empty temp dir
# ---------------------------------------------------------------------------
EMPTY_DIR="${TMPDIR_BASE}/empty"
mkdir -p "$EMPTY_DIR"

RESULT=$(DELIVERY_GATE_POLICY="$POLICY_FILE" resolve_profile "$EMPTY_DIR" 2>&1)
if [[ "$RESULT" == "unverifiable" ]]; then
  _pass "T2: resolve_profile returns 'unverifiable' for empty directory"
else
  _fail "T2: resolve_profile returned '${RESULT}', expected 'unverifiable'"
fi

# ---------------------------------------------------------------------------
# T3: resolve_profile union — dir with package.json (workspaces) AND plugin.json
#
# Detection order in policy: npm-workspaces first, plugin-bash second.
# Both detect conditions match → union "npm-workspaces+plugin-bash".
# ---------------------------------------------------------------------------
UNION_DIR="${TMPDIR_BASE}/union"
mkdir -p "${UNION_DIR}/plugins/aid-orchestrator/.claude-plugin"
mkdir -p "${UNION_DIR}/plugins/aid-orchestrator/scripts"
# Create detect files for npm-workspaces
cat > "${UNION_DIR}/package.json" <<'EOF'
{"name": "test", "workspaces": ["packages/*"]}
EOF
# Create detect files for plugin-bash
echo '{}' > "${UNION_DIR}/plugins/aid-orchestrator/.claude-plugin/plugin.json"
touch "${UNION_DIR}/plugins/aid-orchestrator/scripts/aid-fsm.sh"

RESULT=$(DELIVERY_GATE_POLICY="$POLICY_FILE" resolve_profile "$UNION_DIR" 2>&1)
# Union should include both profiles joined with "+"
if [[ "$RESULT" == *"npm-workspaces"* && "$RESULT" == *"plugin-bash"* ]]; then
  _pass "T3: resolve_profile returns union '${RESULT}' for dir with both ecosystems"
elif [[ "$RESULT" == "npm-workspaces" || "$RESULT" == "plugin-bash" ]]; then
  # First-match-wins also acceptable if policy changes to single-match semantics
  _pass "T3: resolve_profile returns first match '${RESULT}' for dir with both ecosystems (acceptable)"
else
  _fail "T3: resolve_profile returned '${RESULT}', expected union or first match containing npm-workspaces and/or plugin-bash"
fi

# ---------------------------------------------------------------------------
# T4: select_commands plugin-bash dg04 → non-empty (test runner)
# ---------------------------------------------------------------------------
mapfile -t CMD_ARRAY < <(select_commands "$POLICY_FILE" "plugin-bash" "dg04" 2>&1)
if [[ ${#CMD_ARRAY[@]} -gt 0 && "${CMD_ARRAY[0]}" != "" ]]; then
  _pass "T4: select_commands plugin-bash dg04 returns non-empty array: [${CMD_ARRAY[*]}]"
else
  _fail "T4: select_commands plugin-bash dg04 returned empty array (expected test runner command)"
fi

# ---------------------------------------------------------------------------
# T5: select_commands plugin-bash dg02 → empty (no build step; skip_reason: not_required)
# ---------------------------------------------------------------------------
mapfile -t CMD_ARRAY < <(select_commands "$POLICY_FILE" "plugin-bash" "dg02" 2>&1)
if [[ ${#CMD_ARRAY[@]} -eq 0 || ( ${#CMD_ARRAY[@]} -eq 1 && "${CMD_ARRAY[0]}" == "" ) ]]; then
  _pass "T5: select_commands plugin-bash dg02 returns empty array (no build step)"
else
  _fail "T5: select_commands plugin-bash dg02 returned non-empty: [${CMD_ARRAY[*]}] (expected empty)"
fi

# ---------------------------------------------------------------------------
# T6: select_commands unverifiable <any_check> → empty
# ---------------------------------------------------------------------------
mapfile -t CMD_ARRAY < <(select_commands "$POLICY_FILE" "unverifiable" "dg04" 2>&1)
if [[ ${#CMD_ARRAY[@]} -eq 0 || ( ${#CMD_ARRAY[@]} -eq 1 && "${CMD_ARRAY[0]}" == "" ) ]]; then
  _pass "T6: select_commands unverifiable dg04 returns empty array"
else
  _fail "T6: select_commands unverifiable dg04 returned non-empty: [${CMD_ARRAY[*]}]"
fi

# ---------------------------------------------------------------------------
# T7: malformed policy YAML → resolve_profile exits 1
# ---------------------------------------------------------------------------
MALFORMED_POLICY="${TMPDIR_BASE}/malformed.yaml"
cat > "$MALFORMED_POLICY" <<'EOF'
version: 1
profiles:
  bad-profile:
    detect:
      - file: [this: is: invalid
    commands: {
EOF

# Run in subshell so exit doesn't kill this script
if DELIVERY_GATE_POLICY="$MALFORMED_POLICY" resolve_profile "$PLUGIN_ROOT" >/dev/null 2>&1; then
  _fail "T7: resolve_profile with malformed policy should exit 1, but exited 0"
else
  _pass "T7: resolve_profile with malformed policy exits non-zero (no implicit profile)"
fi

# ---------------------------------------------------------------------------
# T8: select_commands plugin-bash dg01 → empty (skip: legacy_no_child_rows)
# ---------------------------------------------------------------------------
mapfile -t CMD_ARRAY < <(select_commands "$POLICY_FILE" "plugin-bash" "dg01" 2>&1)
if [[ ${#CMD_ARRAY[@]} -eq 0 || ( ${#CMD_ARRAY[@]} -eq 1 && "${CMD_ARRAY[0]}" == "" ) ]]; then
  _pass "T8: select_commands plugin-bash dg01 returns empty array (skip: legacy_no_child_rows)"
else
  _fail "T8: select_commands plugin-bash dg01 returned non-empty: [${CMD_ARRAY[*]}] (expected empty)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total=$((pass + fail))
echo ""
echo "Results: ${pass}/${total} passed"

if [[ "$fail" -gt 0 ]]; then
  echo "FAIL: ${fail} test(s) failed"
  exit 1
fi

echo "PASS: all tests passed"
exit 0
