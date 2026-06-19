#!/usr/bin/env bash
# =============================================================================
# test-cp1-gate.sh — Unit tests for aid-cp1-gate.sh
#
# Tests:
#   1. high-risk fixture without 3 lens outputs + adjudicator verdict FAILS EPIC generation
#   2. high-risk fixture with all CP1-deep evidence and no accepted blockers PASSES
#   3. accepted blocker without command/artifact + file:line evidence is rejected by adjudicator
#      (adjudicator gate catches non-empty accepted_blockers)
#   4. after 2 auto-revisions, a surviving stop-rule blocker causes gate to fail
#      (simulated via adjudicator file with accepted_blockers present)
#   5. trivial low-risk fixture still passes gate unchanged
#   6. plan with high-risk pattern in body is treated as high-risk even without frontmatter tag
#   7. plan with risk: low but high-risk patterns matched still requires evidence (pattern wins)
#
# Exit codes: 0=all passed, 1=one or more tests failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
GATE_SCRIPT="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-cp1-gate.sh"

# ---------------------------------------------------------------------------
# Test accounting
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ---------------------------------------------------------------------------
# Temp dir cleanup
# ---------------------------------------------------------------------------
TMPDIR_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pass() {
  TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$(( TESTS_FAILED + 1 ))
  echo "  FAIL: $1 -- $2"
}

run_test() {
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  echo ""
  echo "TEST: $1"
}

# Create a temporary project root with .aid-o structure
make_project_root() {
  local name="$1"
  local proj="$TMPDIR_ROOT/$name"
  mkdir -p "$proj/.aid-o/work/evidence"
  echo "$proj"
}

# Create evidence dir for a given plan_id
make_evidence_dir() {
  local proj="$1"
  local plan_id="$2"
  local dir="${proj}/.aid-o/work/evidence/${plan_id}/cp1-deep"
  mkdir -p "$dir"
  echo "$dir"
}

# Write all 4 required evidence files (empty/passing content)
write_passing_evidence() {
  local ev_dir="$1"
  cat > "${ev_dir}/cp1-lens-security.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: high
EOF
  cat > "${ev_dir}/cp1-lens-correctness.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: high
EOF
  cat > "${ev_dir}/cp1-lens-architectural.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: high
EOF
  cat > "${ev_dir}/cp1-adjudicator.md" <<'EOF'
accepted_blockers: []
rejected_blockers: []
verdict: pass
revision_count: 0
EOF
}

# Write a plan file with given id, risk field (optional), and body
write_plan() {
  local path="$1"
  local plan_id="$2"
  local risk_field="$3"  # e.g. "risk: high" or "" for absent
  local body="$4"

  {
    echo "---"
    echo "id: ${plan_id}"
    echo "type: plan"
    echo "status: draft"
    [[ -n "$risk_field" ]] && echo "$risk_field"
    echo "---"
    echo ""
    echo "# Plan: Test Plan"
    echo ""
    echo "## Context"
    echo ""
    echo "Test plan for CP1 gate tests."
    echo ""
    echo "## Implementation Steps"
    echo ""
    echo "### Step 1: Do something"
    echo ""
    echo "**Objective:** Do something."
    echo ""
    echo "$body"
  } > "$path"
}

# ---------------------------------------------------------------------------
# Guard: gate script must exist
# ---------------------------------------------------------------------------
if [[ ! -f "$GATE_SCRIPT" ]]; then
  echo "ERROR: Gate script not found: $GATE_SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# TEST 1: High-risk fixture without evidence files FAILS
# ---------------------------------------------------------------------------
run_test "High-risk plan without CP1-deep evidence fails gate"

proj1="$(make_project_root "t1")"
plan1="$TMPDIR_ROOT/t1-plan.md"
write_plan "$plan1" "P001" "risk: high" "Some plan content."

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan1" --project-root "$proj1" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "high-risk plan without evidence exits non-zero (exit=$gate_exit)"
else
  fail "high-risk plan without evidence exits non-zero" "got exit=0, expected non-zero"
fi

if echo "$gate_out" | grep -q "Missing"; then
  pass "error output mentions missing files"
else
  fail "error output mentions missing files" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 2: High-risk fixture with all evidence and no accepted blockers PASSES
# ---------------------------------------------------------------------------
run_test "High-risk plan with complete passing evidence passes gate"

proj2="$(make_project_root "t2")"
plan2="$TMPDIR_ROOT/t2-plan.md"
write_plan "$plan2" "P002" "risk: high" "Some high-risk plan content."

ev2="$(make_evidence_dir "$proj2" "P002")"
write_passing_evidence "$ev2"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan2" --project-root "$proj2" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -eq 0 ]]; then
  pass "high-risk plan with complete evidence exits 0"
else
  fail "high-risk plan with complete evidence exits 0" "got exit=$gate_exit, output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 3: Adjudicator with non-empty accepted_blockers causes gate failure
# (simulates a blocker without proper evidence being accepted — adjudicator
#  would reject vague blockers, but if it did accept one the gate enforces it)
# ---------------------------------------------------------------------------
run_test "Adjudicator with non-empty accepted_blockers fails gate"

proj3="$(make_project_root "t3")"
plan3="$TMPDIR_ROOT/t3-plan.md"
write_plan "$plan3" "P003" "risk: high" "Some content with authenticate call."

ev3="$(make_evidence_dir "$proj3" "P003")"
write_passing_evidence "$ev3"
# Overwrite adjudicator with a non-empty accepted_blockers
cat > "${ev3}/cp1-adjudicator.md" <<'EOF'
accepted_blockers:
  - id: SEC-001
    description: "auth bypass via direct db query in login handler at auth.py:42"
    artifact: "auth.py:42"
    evidence: "def login(): db.query(...) without token check"
rejected_blockers: []
verdict: revise
revision_count: 1
EOF

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan3" --project-root "$proj3" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "adjudicator with accepted_blockers causes gate failure (exit=$gate_exit)"
else
  fail "adjudicator with accepted_blockers causes gate failure" "got exit=0, expected non-zero"
fi

if echo "$gate_out" | grep -qi "blocker\|resolve\|unresolved"; then
  pass "error output mentions blockers or resolution"
else
  fail "error output mentions blockers or resolution" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 4: revision_count >= 2 + accepted_blockers = gate fails (PM escalation required)
# ---------------------------------------------------------------------------
run_test "After 2 revisions, surviving accepted_blockers still fails gate"

proj4="$(make_project_root "t4")"
plan4="$TMPDIR_ROOT/t4-plan.md"
write_plan "$plan4" "P004" "risk: high" "Uses pydantic BaseModel for validation."

ev4="$(make_evidence_dir "$proj4" "P004")"
write_passing_evidence "$ev4"
# Adjudicator shows revision_count=2 (max reached) but accepted_blockers still present
cat > "${ev4}/cp1-adjudicator.md" <<'EOF'
accepted_blockers:
  - id: ARCH-001
    description: "direct coupling between payment handler and DB layer at billing.py:88"
    artifact: "billing.py:88"
    evidence: "charge() calls db.session directly, bypassing service layer"
rejected_blockers: []
verdict: revise
revision_count: 2
EOF

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan4" --project-root "$proj4" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "revision_count=2 with accepted_blockers fails gate (PM escalation required)"
else
  fail "revision_count=2 with accepted_blockers fails gate" "got exit=0, expected non-zero"
fi

# ---------------------------------------------------------------------------
# TEST 5: Low-risk (risk: low) plan passes gate without evidence
# ---------------------------------------------------------------------------
run_test "Low-risk plan (risk: low) passes gate without any evidence files"

proj5="$(make_project_root "t5")"
plan5="$TMPDIR_ROOT/t5-plan.md"
# Low-risk: update docs, no patterns match
write_plan "$plan5" "P005" "risk: low" "Update the README file and add documentation."

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan5" --project-root "$proj5" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -eq 0 ]]; then
  pass "low-risk plan passes gate without evidence (exit=0)"
else
  fail "low-risk plan passes gate without evidence" "got exit=$gate_exit, output: $gate_out"
fi

if echo "$gate_out" | grep -qi "not required\|low-risk"; then
  pass "output confirms CP1-deep not required for low-risk plan"
else
  fail "output confirms CP1-deep not required for low-risk plan" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 6: Plan with high-risk pattern in body (no frontmatter tag) is high-risk
# ---------------------------------------------------------------------------
run_test "Plan with authenticate in body is treated as high-risk"

proj6="$(make_project_root "t6")"
plan6="$TMPDIR_ROOT/t6-plan.md"
# No risk: field, but body contains auth pattern
write_plan "$plan6" "P006" "" "Call verify_token to authenticate the user before processing."

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan6" --project-root "$proj6" 2>&1)" || gate_exit=$?

# Should fail because no evidence dir
if [[ "$gate_exit" -ne 0 ]]; then
  pass "plan with high-risk body pattern fails gate when evidence absent"
else
  fail "plan with high-risk body pattern fails gate when evidence absent" "got exit=0"
fi

# Now provide the evidence and it should pass
ev6="$(make_evidence_dir "$proj6" "P006")"
write_passing_evidence "$ev6"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan6" --project-root "$proj6" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -eq 0 ]]; then
  pass "plan with high-risk body pattern passes gate when evidence present"
else
  fail "plan with high-risk body pattern passes gate when evidence present" "got exit=$gate_exit, output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 7: risk: low in frontmatter does NOT exempt plan when body has high-risk patterns
# Pattern match wins — risk: low only exempts when no patterns are found.
# ---------------------------------------------------------------------------
run_test "Plan with risk: low still requires CP1-deep when body contains high-risk patterns"

proj7="$(make_project_root "t7")"
plan7="$TMPDIR_ROOT/t7-plan.md"
write_plan "$plan7" "P007" "risk: low" "Handler authenticate() and verify_token() added to auth flow."

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan7" --project-root "$proj7" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "risk: low plan with high-risk patterns still fails gate (evidence missing)"
else
  fail "risk: low plan with high-risk patterns should fail gate (pattern wins over risk:low)" "got exit=0, output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 8: Missing plan file returns non-zero with I/O error
# ---------------------------------------------------------------------------
run_test "Missing plan file returns non-zero exit"

gate_exit=0
bash "$GATE_SCRIPT" --plan "/nonexistent/plan.md" 2>/dev/null || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "missing plan file returns non-zero exit"
else
  fail "missing plan file returns non-zero exit" "got exit=0"
fi

# ---------------------------------------------------------------------------
# TEST 9: Missing --plan argument returns exit 2
# ---------------------------------------------------------------------------
run_test "Missing --plan argument returns exit 2"

gate_exit=0
bash "$GATE_SCRIPT" 2>/dev/null || gate_exit=$?

if [[ "$gate_exit" -eq 2 ]]; then
  pass "missing --plan argument returns exit 2"
else
  fail "missing --plan argument returns exit 2" "got exit=$gate_exit"
fi

# ---------------------------------------------------------------------------
# TEST 10: Only some evidence files present — gate fails listing missing ones
# ---------------------------------------------------------------------------
run_test "Only partial evidence present — gate fails with missing file list"

proj10="$(make_project_root "t10")"
plan10="$TMPDIR_ROOT/t10-plan.md"
write_plan "$plan10" "P010" "risk: high" "Uses stripe for payment processing."

ev10="$(make_evidence_dir "$proj10" "P010")"
# Only write 2 of 4 required files
cat > "${ev10}/cp1-lens-security.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: high
EOF
cat > "${ev10}/cp1-lens-correctness.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: medium
EOF
# Missing: cp1-lens-architectural.md and cp1-adjudicator.md

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan10" --project-root "$proj10" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "partial evidence causes gate failure"
else
  fail "partial evidence causes gate failure" "got exit=0"
fi

if echo "$gate_out" | grep -q "cp1-lens-architectural.md"; then
  pass "error output names the missing architectural lens file"
else
  fail "error output names the missing architectural lens file" "output: $gate_out"
fi

if echo "$gate_out" | grep -q "cp1-adjudicator.md"; then
  pass "error output names the missing adjudicator file"
else
  fail "error output names the missing adjudicator file" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo ""

if [[ "$TESTS_FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
