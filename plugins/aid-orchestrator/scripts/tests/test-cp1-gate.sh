#!/usr/bin/env bash
# aid-tier: t2
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
#   5. a light-band fixture (documentation-only Files) passes gate unchanged
#   6. plan that declares NO Files block is full-band (fail-closed) even without
#      a frontmatter risk tag — P084 replaced the prose-pattern scan these two
#      cases were originally written for
#   7. the same, with `risk: low` present: a frontmatter value never lowers a band
#   8. missing plan file returns non-zero
#   9. missing --plan argument returns exit 2
#  10. only partial evidence present — gate fails with missing file list
#  11. empty evidence files — gate rejects even when all 4 files exist
#  12. lens file with content but missing stop_rule_blockers: field fails gate
#  13. adjudicator missing verdict: field fails gate
#
# P065 E-065-7_7 Step 20 additions (C0 cross-provider review + CP1 ledger gate):
#  14. c0-plan-review.json missing → gate fails even with clean CP1-deep evidence
#  15. c0-plan-review.json review_status=unverifiable → gate fails
#  16. c0-plan-review.json blocking_findings=true → gate fails
#  17. aid-c0-plan-review.sh verify failure (stubbed) → gate fails even though the
#      report's own fields look clean (proves the shell-out is load-bearing)
#  18. a fabricated-but-field-clean c0-plan-review.json with NO real supporting
#      dispatch evidence fails the REAL (unstubbed) verify() → gate blocks
#      (proves the DEFAULT wiring genuinely shells out, not just a test seam)
#  19. CP1 ledger missing while CP1-deep evidence is present → fail-closed block
#  20. CP1 ledger budget exhausted (attempts>=max, no pm_override) → gate fails
#  21. CP1 ledger pm_override.present=true is honored by the gate ONLY when
#      corroborated by a genuine, matching claim_artifact/claim_sha256 (a
#      real .consumed-<epoch> file aid-cp1-ledger.sh's cmd_increment
#      produced) — DONE-review #5 fix: a bare hand-edit of present/ref
#      alone (no matching artifact) is now REJECTED, not honored; see
#      21b for the legitimate flow (a real override claimed via a genuine
#      ledger increment) still passing
#  22. PM-escalation override artifact bypasses a missing c0-plan-review.json → PASS
#  23. the PM-escalation override is consumed (renamed) after one bypass — a
#      second gate run without a fresh override blocks again
#  24. full success path: complete CP1-deep evidence + verified clean C0 review
#      (stubbed verify=ok) + available ledger budget → PASS with no override needed
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
TESTS_PASSED_UNIQUE=0
TESTS_FAILED_UNIQUE=0
CURRENT_TEST_OPEN=0
CURRENT_TEST_FAILED=0
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
# P072 Step 9 — assertions and TESTS are different units, and the aggregate's
# "Tests" total must receive tests. `pass`/`fail` count assertions (one test
# calls pass() several times); `run_test` counts tests. Reporting assertions in
# a fraction whose denominator was tests produced `54/28`; reporting assertions
# on both sides would still inflate the portfolio's own test count from 28 to
# 54. A test is failed when ANY assertion inside it failed.
pass() {
  TESTS_PASSED=$(( TESTS_PASSED + 1 ))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$(( TESTS_FAILED + 1 ))
  CURRENT_TEST_FAILED=1
  echo "  FAIL: $1 -- $2"
}

# _close_current_test — fold the finished test into the TEST-level tally.
_close_current_test() {
  [[ "${CURRENT_TEST_OPEN:-0}" -eq 1 ]] || return 0
  if [[ "${CURRENT_TEST_FAILED:-0}" -eq 1 ]]; then
    TESTS_FAILED_UNIQUE=$(( TESTS_FAILED_UNIQUE + 1 ))
  else
    TESTS_PASSED_UNIQUE=$(( TESTS_PASSED_UNIQUE + 1 ))
  fi
  CURRENT_TEST_OPEN=0
}

run_test() {
  _close_current_test
  TESTS_RUN=$(( TESTS_RUN + 1 ))
  CURRENT_TEST_OPEN=1
  CURRENT_TEST_FAILED=0
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
  cat > "${ev_dir}/cp1-lens-L1-behavior.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: high
EOF
  cat > "${ev_dir}/cp1-lens-L2-feasibility.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: high
EOF
  cat > "${ev_dir}/cp1-lens-L3-enforcement.md" <<'EOF'
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
# P065 E-065-7_7 Step 20 helpers — C0 review + CP1 ledger fixtures
# ---------------------------------------------------------------------------
LEDGER_SCRIPT="$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-cp1-ledger.sh"

# plan_evidence_root_of <cp1_deep_evidence_dir>  — the plan evidence ROOT is
# one level ABOVE cp1-deep/ (same convention aid-c0-plan-review.sh and
# aid-cp1-gate.sh's own Step 20 code both use).
plan_evidence_root_of() {
  dirname "$1"
}

# write_passing_c0_review <plan_evidence_root>
#   A clean, non-blocking c0-plan-review.json. On its own this only satisfies
#   the gate's FIELD checks — pair with stub_c0_verify_ok (or a real
#   dispatched+verified evidence trail) to also satisfy the verify() shell-out.
write_passing_c0_review() {
  local root="$1"
  mkdir -p "$root"
  cat > "${root}/c0-plan-review.json" <<'EOF'
{
  "schema_version": "aid-2.0",
  "artifact_type": "c0_plan_review",
  "review_status": "pass",
  "blocking_findings": false,
  "findings": []
}
EOF
}

write_unverifiable_c0_review() {
  local root="$1"
  mkdir -p "$root"
  cat > "${root}/c0-plan-review.json" <<'EOF'
{
  "schema_version": "aid-2.0",
  "artifact_type": "c0_plan_review",
  "review_status": "unverifiable",
  "blocking_findings": false,
  "findings": [],
  "unverifiable_reasons": ["codex unavailable"]
}
EOF
}

write_blocking_c0_review() {
  local root="$1"
  mkdir -p "$root"
  cat > "${root}/c0-plan-review.json" <<'EOF'
{
  "schema_version": "aid-2.0",
  "artifact_type": "c0_plan_review",
  "review_status": "findings",
  "blocking_findings": true,
  "findings": [
    {"severity":"high","area":"feasibility","finding":"Named resource does not exist.",
     "recommendation":"Add a Create step.","action_owner":"implementer"}
  ]
}
EOF
}

# stub_c0_verify <dir> <ok|fail>
#   Installs a stand-in for aid-c0-plan-review.sh (AID_CP1_GATE_C0_REVIEW_BIN
#   test seam) that always succeeds/fails, so most tests can prove the GATE's
#   own logic without a full git+fake-codex dispatch fixture. The seam is
#   never set in production — see test 18 below for a REAL (unstubbed)
#   verify() proving the default wiring is load-bearing.
stub_c0_verify() {
  local dir="$1" mode="$2"
  mkdir -p "$dir"
  local stub="$dir/stub-c0-verify.sh"
  if [[ "$mode" == "ok" ]]; then
    cat > "$stub" <<'EOF'
#!/usr/bin/env bash
echo "verified — stub ok"
exit 0
EOF
  else
    cat > "$stub" <<'EOF'
#!/usr/bin/env bash
echo "verify: NOT verified — stub tamper" >&2
exit 2
EOF
  fi
  chmod +x "$stub"
  AID_CP1_GATE_C0_REVIEW_BIN="$stub"
  export AID_CP1_GATE_C0_REVIEW_BIN
}

unstub_c0_verify() {
  unset AID_CP1_GATE_C0_REVIEW_BIN
}

# init_ledger_available <project_root> <plan_id>
#   Bootstraps a ledger with budget available. --pre-enforcement is required
#   here because these fixtures always write CP1-deep evidence FIRST (an
#   already-in-flight plan from the ledger's point of view — see
#   aid-cp1-ledger.sh's own init contract), never a provably-new plan.
init_ledger_available() {
  local proj="$1" plan_id="$2"
  bash "$LEDGER_SCRIPT" init --pre-enforcement --project-root "$proj" "$plan_id" >/dev/null
}

# init_ledger_exhausted <project_root> <plan_id>  — attempts == max, no override.
init_ledger_exhausted() {
  local proj="$1" plan_id="$2"
  init_ledger_available "$proj" "$plan_id"
  local ledger_file="${proj}/.aid-o/work/cp1-ledger/${plan_id}.yaml"
  yq -i '.attempts = .max' "$ledger_file"
}

# set_ledger_pm_override <project_root> <plan_id> [ref]
set_ledger_pm_override() {
  local proj="$1" plan_id="$2" ref="${3:-PM approved additional attempt 2026-07-18}"
  local ledger_file="${proj}/.aid-o/work/cp1-ledger/${plan_id}.yaml"
  yq -i ".pm_override.present = true | .pm_override.ref = \"${ref}\"" "$ledger_file"
}

# write_pm_override <plan_evidence_root> [ref]
#   The gate's OWN one-shot PM-escalation override artifact (distinct from
#   the ledger's pm_override field) — see aid-cp1-gate.sh's
#   _cp1_check_pm_override / _cp1_claim_pm_override.
write_pm_override() {
  local root="$1" ref="${2:-PM approved bypass 2026-07-18 review}"
  mkdir -p "$root"
  jq -n --arg ref "$ref" \
    '{schema_version:"aid-2.0", artifact_type:"cp1_pm_escalation_override", pm_ref:$ref, created_at:"2026-07-18T00:00:00Z"}' \
    > "${root}/cp1-pm-escalation-override.json"
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
proot2="$(plan_evidence_root_of "$ev2")"
write_passing_c0_review "$proot2"
stub_c0_verify "$TMPDIR_ROOT/t2-stub" ok
init_ledger_available "$proj2" "P002"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan2" --project-root "$proj2" 2>&1)" || gate_exit=$?
unstub_c0_verify

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
# TEST 5: a `light` plan passes the gate without evidence
#
# P084 Step 1 moved the band from a whole-document grep to the paths the plan
# DECLARES, so this fixture now declares them: a documentation-only step. The
# `risk: low` frontmatter is kept to prove what it is worth — nothing on its
# own, since a band is only ever lowered by what the plan touches. The band
# taxonomy itself lives in bats/test-cp1-gate-risk.bats (t0); this case only
# asserts the gate's behaviour once the band is light.
# ---------------------------------------------------------------------------
run_test "Light-band plan (documentation-only Files) passes gate without any evidence files"

proj5="$(make_project_root "t5")"
plan5="$TMPDIR_ROOT/t5-plan.md"
write_plan "$plan5" "P005" "risk: low" "Update the README file and add documentation.

**Files:**
- Modify: \`plugins/aid-orchestrator/commands/aid-help.md\` — documentation only"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan5" --project-root "$proj5" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -eq 0 ]]; then
  pass "light-band plan passes gate without evidence (exit=0)"
else
  fail "light-band plan passes gate without evidence" "got exit=$gate_exit, output: $gate_out"
fi

if echo "$gate_out" | grep -qi "not required\|band=light"; then
  pass "output confirms CP1-deep not required for a light-band plan"
else
  fail "output confirms CP1-deep not required for a light-band plan" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 6: Plan with high-risk pattern in body (no frontmatter tag) is high-risk
# ---------------------------------------------------------------------------
run_test "Plan with no declared Files is full-band (fail-closed), tag or no tag"

proj6="$(make_project_root "t6")"
plan6="$TMPDIR_ROOT/t6-plan.md"
# No risk: field, but body contains auth pattern
# No **Files:** block at all -> `no_files_declared` -> full, fail-closed.
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
proot6="$(plan_evidence_root_of "$ev6")"
write_passing_c0_review "$proot6"
stub_c0_verify "$TMPDIR_ROOT/t6-stub" ok
init_ledger_available "$proj6" "P006"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan6" --project-root "$proj6" 2>&1)" || gate_exit=$?
unstub_c0_verify

if [[ "$gate_exit" -eq 0 ]]; then
  pass "plan with high-risk body pattern passes gate when evidence present"
else
  fail "plan with high-risk body pattern passes gate when evidence present" "got exit=$gate_exit, output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 7: risk: low in frontmatter does NOT exempt plan when body has high-risk patterns
# Pattern match wins — risk: low only exempts when no patterns are found.
# ---------------------------------------------------------------------------
run_test "risk: low does not lower a band — an unclassifiable plan still owes CP1-deep"

proj7="$(make_project_root "t7")"
plan7="$TMPDIR_ROOT/t7-plan.md"
# `risk: high` raises a band; no frontmatter value lowers one. This plan
# declares nothing, so it is full regardless of the `risk: low` tag.
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
cat > "${ev10}/cp1-lens-L1-behavior.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: high
EOF
cat > "${ev10}/cp1-lens-L2-feasibility.md" <<'EOF'
findings: []
stop_rule_blockers: []
confidence: medium
EOF
# Missing: cp1-lens-L3-enforcement.md and cp1-adjudicator.md

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan10" --project-root "$proj10" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "partial evidence causes gate failure"
else
  fail "partial evidence causes gate failure" "got exit=0"
fi

if echo "$gate_out" | grep -q "cp1-lens-L3-enforcement.md"; then
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
# TEST 11: Empty evidence files — gate must reject even when all 4 files exist
# ---------------------------------------------------------------------------
run_test "Empty evidence files cause gate failure even when all 4 are present"

proj11="$(make_project_root "t11")"
plan11="$TMPDIR_ROOT/t11-plan.md"
write_plan "$plan11" "P011" "risk: high" "authenticate() handler added to user login flow."

ev11="$(make_evidence_dir "$proj11" "P011")"
# Create all 4 files but leave them empty
touch "${ev11}/cp1-lens-L1-behavior.md"
touch "${ev11}/cp1-lens-L2-feasibility.md"
touch "${ev11}/cp1-lens-L3-enforcement.md"
touch "${ev11}/cp1-adjudicator.md"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan11" --project-root "$proj11" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "empty evidence files cause gate failure"
else
  fail "empty evidence files cause gate failure" "got exit=0 — gate accepted empty files"
fi

if echo "$gate_out" | grep -qi "empty\|stop_rule_blockers\|verdict"; then
  pass "error output explains content requirement"
else
  fail "error output explains content requirement" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 12: Lens with content but missing stop_rule_blockers: field fails gate
# ---------------------------------------------------------------------------
run_test "Lens file with content but missing stop_rule_blockers: field fails gate"

proj12="$(make_project_root "t12")"
plan12="$TMPDIR_ROOT/t12-plan.md"
write_plan "$plan12" "P012" "risk: high" "authenticate() handler added."

ev12="$(make_evidence_dir "$proj12" "P012")"
# Write lens files without stop_rule_blockers:
printf "findings: []\nconfidence: high\n" > "${ev12}/cp1-lens-L1-behavior.md"
printf "findings: []\nstop_rule_blockers: []\nconfidence: high\n" > "${ev12}/cp1-lens-L2-feasibility.md"
printf "findings: []\nstop_rule_blockers: []\nconfidence: high\n" > "${ev12}/cp1-lens-L3-enforcement.md"
printf "verdict: pass\naccepted_blockers: []\n" > "${ev12}/cp1-adjudicator.md"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan12" --project-root "$proj12" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "lens missing stop_rule_blockers: field causes gate failure"
else
  fail "lens missing stop_rule_blockers: field causes gate failure" "got exit=0"
fi

# ---------------------------------------------------------------------------
# TEST 13: Adjudicator without verdict: field fails gate
# ---------------------------------------------------------------------------
run_test "Adjudicator file missing verdict: field fails gate"

proj13="$(make_project_root "t13")"
plan13="$TMPDIR_ROOT/t13-plan.md"
write_plan "$plan13" "P013" "risk: high" "authenticate() handler added."

ev13="$(make_evidence_dir "$proj13" "P013")"
write_passing_evidence "$ev13"
# Overwrite adjudicator without verdict: field
printf "accepted_blockers: []\nrejected_blockers: []\nrevision_count: 0\n" > "${ev13}/cp1-adjudicator.md"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan13" --project-root "$proj13" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "adjudicator missing verdict: field causes gate failure"
else
  fail "adjudicator missing verdict: field causes gate failure" "got exit=0"
fi

# ---------------------------------------------------------------------------
# TEST 14: c0-plan-review.json missing → gate fails even with clean CP1-deep evidence
# ---------------------------------------------------------------------------
run_test "c0-plan-review.json missing fails gate even with clean CP1-deep evidence"

proj14="$(make_project_root "t14")"
plan14="$TMPDIR_ROOT/t14-plan.md"
write_plan "$plan14" "P014" "risk: high" "authenticate() handler added."

ev14="$(make_evidence_dir "$proj14" "P014")"
write_passing_evidence "$ev14"
proot14="$(plan_evidence_root_of "$ev14")"
init_ledger_available "$proj14" "P014"
# Deliberately no c0-plan-review.json written.

unstub_c0_verify
gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan14" --project-root "$proj14" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "missing c0-plan-review.json fails gate"
else
  fail "missing c0-plan-review.json fails gate" "got exit=0"
fi
if echo "$gate_out" | grep -qi "c0-plan-review.json missing\|cross-provider plan review"; then
  pass "error output explains the missing C0 review requirement"
else
  fail "error output explains the missing C0 review requirement" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 15: c0-plan-review.json review_status=unverifiable → gate fails
# ---------------------------------------------------------------------------
run_test "c0-plan-review.json review_status=unverifiable fails gate"

proj15="$(make_project_root "t15")"
plan15="$TMPDIR_ROOT/t15-plan.md"
write_plan "$plan15" "P015" "risk: high" "authenticate() handler added."

ev15="$(make_evidence_dir "$proj15" "P015")"
write_passing_evidence "$ev15"
proot15="$(plan_evidence_root_of "$ev15")"
write_unverifiable_c0_review "$proot15"
init_ledger_available "$proj15" "P015"

unstub_c0_verify
gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan15" --project-root "$proj15" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "unverifiable c0-plan-review.json fails gate"
else
  fail "unverifiable c0-plan-review.json fails gate" "got exit=0"
fi
if echo "$gate_out" | grep -qi "unverifiable"; then
  pass "error output mentions unverifiable"
else
  fail "error output mentions unverifiable" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 16: c0-plan-review.json blocking_findings=true → gate fails
# ---------------------------------------------------------------------------
run_test "c0-plan-review.json with surviving blocking_findings fails gate"

proj16="$(make_project_root "t16")"
plan16="$TMPDIR_ROOT/t16-plan.md"
write_plan "$plan16" "P016" "risk: high" "authenticate() handler added."

ev16="$(make_evidence_dir "$proj16" "P016")"
write_passing_evidence "$ev16"
proot16="$(plan_evidence_root_of "$ev16")"
write_blocking_c0_review "$proot16"
init_ledger_available "$proj16" "P016"

unstub_c0_verify
gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan16" --project-root "$proj16" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "c0-plan-review.json with blocking_findings=true fails gate"
else
  fail "c0-plan-review.json with blocking_findings=true fails gate" "got exit=0"
fi
if echo "$gate_out" | grep -qi "blocking_findings"; then
  pass "error output mentions blocking_findings"
else
  fail "error output mentions blocking_findings" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 17: aid-c0-plan-review.sh verify failure (stubbed) fails gate even
# though the report's own top-level fields look clean.
# ---------------------------------------------------------------------------
run_test "stubbed verify() failure fails gate despite clean top-level fields"

proj17="$(make_project_root "t17")"
plan17="$TMPDIR_ROOT/t17-plan.md"
write_plan "$plan17" "P017" "risk: high" "authenticate() handler added."

ev17="$(make_evidence_dir "$proj17" "P017")"
write_passing_evidence "$ev17"
proot17="$(plan_evidence_root_of "$ev17")"
write_passing_c0_review "$proot17"
init_ledger_available "$proj17" "P017"
stub_c0_verify "$TMPDIR_ROOT/t17-stub" fail

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan17" --project-root "$proj17" 2>&1)" || gate_exit=$?
unstub_c0_verify

if [[ "$gate_exit" -ne 0 ]]; then
  pass "stubbed verify() failure fails gate"
else
  fail "stubbed verify() failure fails gate" "got exit=0 — clean top-level fields alone should not be enough"
fi
if echo "$gate_out" | grep -qi "verify failed"; then
  pass "error output mentions the verify failure"
else
  fail "error output mentions the verify failure" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 18: a fabricated-but-field-clean c0-plan-review.json with NO real
# supporting dispatch evidence fails the REAL (default, unstubbed) verify()
# — proves the shell-out to aid-c0-plan-review.sh is genuinely load-bearing
# in the DEFAULT production wiring, not merely a test seam.
# ---------------------------------------------------------------------------
run_test "fabricated c0-plan-review.json with no real evidence fails the REAL verify()"

proj18="$(make_project_root "t18")"
plan18="$TMPDIR_ROOT/t18-plan.md"
write_plan "$plan18" "P018" "risk: high" "authenticate() handler added."

ev18="$(make_evidence_dir "$proj18" "P018")"
write_passing_evidence "$ev18"
proot18="$(plan_evidence_root_of "$ev18")"
write_passing_c0_review "$proot18"
init_ledger_available "$proj18" "P018"
unstub_c0_verify

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan18" --project-root "$proj18" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -ne 0 ]]; then
  pass "fabricated c0-plan-review.json without real dispatch evidence fails the real verify()"
else
  fail "fabricated c0-plan-review.json without real dispatch evidence fails the real verify()" "got exit=0"
fi
if echo "$gate_out" | grep -qi "verify failed\|required artifact missing\|not verified"; then
  pass "error output shows the real verify() rejected the fabricated report"
else
  fail "error output shows the real verify() rejected the fabricated report" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 19: CP1 ledger missing while CP1-deep evidence is present → fail-closed
# ---------------------------------------------------------------------------
run_test "missing CP1 ledger with CP1-deep evidence present fails gate (fail-closed)"

proj19="$(make_project_root "t19")"
plan19="$TMPDIR_ROOT/t19-plan.md"
write_plan "$plan19" "P019" "risk: high" "authenticate() handler added."

ev19="$(make_evidence_dir "$proj19" "P019")"
write_passing_evidence "$ev19"
proot19="$(plan_evidence_root_of "$ev19")"
write_passing_c0_review "$proot19"
stub_c0_verify "$TMPDIR_ROOT/t19-stub" ok
# Deliberately no ledger init.

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan19" --project-root "$proj19" 2>&1)" || gate_exit=$?
unstub_c0_verify

if [[ "$gate_exit" -ne 0 ]]; then
  pass "missing ledger with CP1-deep evidence present fails gate"
else
  fail "missing ledger with CP1-deep evidence present fails gate" "got exit=0"
fi
if echo "$gate_out" | grep -qi "ledger"; then
  pass "error output mentions the ledger"
else
  fail "error output mentions the ledger" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 20: CP1 ledger budget exhausted (attempts>=max, no pm_override) fails gate
# ---------------------------------------------------------------------------
run_test "exhausted CP1 ledger budget (no pm_override) fails gate"

proj20="$(make_project_root "t20")"
plan20="$TMPDIR_ROOT/t20-plan.md"
write_plan "$plan20" "P020" "risk: high" "authenticate() handler added."

ev20="$(make_evidence_dir "$proj20" "P020")"
write_passing_evidence "$ev20"
proot20="$(plan_evidence_root_of "$ev20")"
write_passing_c0_review "$proot20"
stub_c0_verify "$TMPDIR_ROOT/t20-stub" ok
init_ledger_exhausted "$proj20" "P020"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan20" --project-root "$proj20" 2>&1)" || gate_exit=$?
unstub_c0_verify

if [[ "$gate_exit" -ne 0 ]]; then
  pass "exhausted ledger budget fails gate"
else
  fail "exhausted ledger budget fails gate" "got exit=0"
fi
if echo "$gate_out" | grep -qi "exhausted"; then
  pass "error output mentions exhausted budget"
else
  fail "error output mentions exhausted budget" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 21: DONE-review #5 fix — a bare hand-edited ledger pm_override.present=
#           true (no corroborating claim artifact) must NOT pass the gate
# ---------------------------------------------------------------------------
run_test "a bare hand-edited ledger pm_override.present=true (no matching claim artifact) does NOT pass the gate"

proj21="$(make_project_root "t21")"
plan21="$TMPDIR_ROOT/t21-plan.md"
write_plan "$plan21" "P021" "risk: high" "authenticate() handler added."

ev21="$(make_evidence_dir "$proj21" "P021")"
write_passing_evidence "$ev21"
proot21="$(plan_evidence_root_of "$ev21")"
write_passing_c0_review "$proot21"
stub_c0_verify "$TMPDIR_ROOT/t21-stub" ok
init_ledger_exhausted "$proj21" "P021"
# Set pm_override.present = true in the ledger (simulating a hand-edit) —
# NO claim_artifact/claim_sha256, exactly the DONE-review #5 finding's
# repro: a bare boolean+string with nothing corroborating it.
set_ledger_pm_override "$proj21" "P021"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan21" --project-root "$proj21" 2>&1)" || gate_exit=$?
unstub_c0_verify

# DESIGN EVOLUTION (3 live-audit rounds on this same field, all within
# E-065-7_7): round 4/5 first closed a dead/unvalidated bypass. A LATER
# audit (3rd DONE-review) found that fix went too far once
# aid-cp1-ledger.sh's own cmd_increment gained a REAL, atomically-consumed,
# single-use override-claim path — check-budget ignoring pm_override.present
# entirely broke the documented "PM override permits one more attempt"
# promise end-to-end. A 5th audit then found THAT re-enable itself went too
# far the OTHER way: check-budget trusted the bare boolean with no
# corroborating evidence, so a hand-edit (this test's own technique) granted
# the exact same bypass as a genuine claim — this test previously asserted
# gate_exit -eq 0 (PASS) here, i.e. it codified the bypass the audit flagged
# as a real, unauthenticated authorization gap. The fix binds
# pm_override.present to claim_artifact/claim_sha256, which check-budget now
# verifies against a genuine, matching .consumed-<epoch> file on disk before
# trusting it (see aid-cp1-ledger.sh's cmd_check_budget) — a bare hand-edit
# has no such file, so it is now correctly REJECTED, and this test asserts
# the INVERSE of what it used to.
if [[ "$gate_exit" -ne 0 ]]; then
  pass "a bare hand-edited pm_override.present does NOT pass the gate (DONE-review #5 fix)"
else
  fail "a bare hand-edited pm_override.present does NOT pass the gate (DONE-review #5 fix)" "got exit=0 (expected non-zero), output: $gate_out"
fi
if echo "$gate_out" | grep -qi "exhausted"; then
  pass "gate's failure reason still mentions exhausted budget (not a silent/opaque block)"
else
  fail "gate's failure reason still mentions exhausted budget (not a silent/opaque block)" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 21b: the LEGITIMATE PM-override flow (a real cp1-pm-escalation-
#           override.json, atomically claimed via a genuine
#           aid-cp1-ledger.sh increment call) still lets the gate PASS —
#           proves the DONE-review #5 fix did not break the real path while
#           closing the hand-edit bypass above.
# ---------------------------------------------------------------------------
run_test "a genuine PM-escalation override, claimed via a real ledger increment, DOES pass the gate"

proj21b="$(make_project_root "t21b")"
plan21b="$TMPDIR_ROOT/t21b-plan.md"
write_plan "$plan21b" "P021b" "risk: high" "authenticate() handler added."

ev21b="$(make_evidence_dir "$proj21b" "P021b")"
write_passing_evidence "$ev21b"
proot21b="$(plan_evidence_root_of "$ev21b")"
write_passing_c0_review "$proot21b"
stub_c0_verify "$TMPDIR_ROOT/t21b-stub" ok
init_ledger_exhausted "$proj21b" "P021b"

# Write the REAL, shared single-use override artifact and claim it via a
# genuine `aid-cp1-ledger.sh increment` call (exactly what aid-c0-plan-
# review.sh's cmd_dispatch does in production) — this is what legitimately
# populates claim_artifact/claim_sha256, not a hand-edit.
write_pm_override "$proot21b" "PM approved additional attempt 2026-07-19 review"
bash "$LEDGER_SCRIPT" increment --project-root "$proj21b" "P021b" "sha256:$(printf 'p021b-new-hash' | sha256sum | cut -d' ' -f1)" >/dev/null

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan21b" --project-root "$proj21b" 2>&1)" || gate_exit=$?
unstub_c0_verify

if [[ "$gate_exit" -eq 0 ]]; then
  pass "a genuinely claimed PM override still passes the gate"
else
  fail "a genuinely claimed PM override still passes the gate" "got exit=$gate_exit (expected 0), output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 22: gate's own PM-escalation override artifact bypasses a missing
# c0-plan-review.json
# ---------------------------------------------------------------------------
run_test "gate PM-escalation override bypasses a missing c0-plan-review.json"

proj22="$(make_project_root "t22")"
plan22="$TMPDIR_ROOT/t22-plan.md"
write_plan "$plan22" "P022" "risk: high" "authenticate() handler added."

ev22="$(make_evidence_dir "$proj22" "P022")"
write_passing_evidence "$ev22"
proot22="$(plan_evidence_root_of "$ev22")"
init_ledger_available "$proj22" "P022"
write_pm_override "$proot22"
# Deliberately no c0-plan-review.json.

unstub_c0_verify
gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan22" --project-root "$proj22" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -eq 0 ]]; then
  pass "PM-escalation override bypasses missing c0-plan-review.json"
else
  fail "PM-escalation override bypasses missing c0-plan-review.json" "got exit=$gate_exit, output: $gate_out"
fi
if echo "$gate_out" | grep -qi "WARNING.*override\|PM-escalation override"; then
  pass "output records the override was used (never a silent pass)"
else
  fail "output records the override was used (never a silent pass)" "output: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 23: the PM-escalation override is consumed after one bypass — a
# second gate run without a fresh override blocks again ("exactly one more
# attempt").
# ---------------------------------------------------------------------------
run_test "PM-escalation override is single-use (consumed after one bypass)"

override_path="${proot22}/cp1-pm-escalation-override.json"
if [[ ! -f "$override_path" ]]; then
  pass "override artifact was archived (renamed) after being consumed"
else
  fail "override artifact was archived (renamed) after being consumed" "still present at $override_path"
fi
consumed_count="$(find "$proot22" -maxdepth 1 -name 'cp1-pm-escalation-override.json.consumed-*' 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "$consumed_count" -ge 1 ]]; then
  pass "a .consumed-* archive of the override exists"
else
  fail "a .consumed-* archive of the override exists" "none found under $proot22"
fi

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan22" --project-root "$proj22" 2>&1)" || gate_exit=$?
if [[ "$gate_exit" -ne 0 ]]; then
  pass "second gate run without a fresh override blocks again"
else
  fail "second gate run without a fresh override blocks again" "got exit=0 — override was reusable"
fi

# ---------------------------------------------------------------------------
# TEST 24: full success path — complete CP1-deep evidence + verified clean C0
# review (stubbed verify=ok) + available ledger budget → PASS, no override needed
# ---------------------------------------------------------------------------
run_test "full success path passes without needing any PM-escalation override"

proj24="$(make_project_root "t24")"
plan24="$TMPDIR_ROOT/t24-plan.md"
write_plan "$plan24" "P024" "risk: high" "authenticate() handler added."

ev24="$(make_evidence_dir "$proj24" "P024")"
write_passing_evidence "$ev24"
proot24="$(plan_evidence_root_of "$ev24")"
write_passing_c0_review "$proot24"
stub_c0_verify "$TMPDIR_ROOT/t24-stub" ok
init_ledger_available "$proj24" "P024"

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan24" --project-root "$proj24" 2>&1)" || gate_exit=$?
unstub_c0_verify

if [[ "$gate_exit" -eq 0 ]]; then
  pass "full success path passes gate"
else
  fail "full success path passes gate" "got exit=$gate_exit, output: $gate_out"
fi
if echo "$gate_out" | grep -qi "WARNING"; then
  fail "no override warning printed on the clean success path" "unexpected WARNING in output: $gate_out"
else
  pass "no override warning printed on the clean success path"
fi
# The override artifact was never written for this plan — nothing to consume.
if [[ ! -f "${proot24}/cp1-pm-escalation-override.json" ]]; then
  pass "no override artifact needed/created on the clean success path"
else
  fail "no override artifact needed/created on the clean success path" "unexpectedly present"
fi

# ---------------------------------------------------------------------------
# TEST 25: a live DONE-review audit (E-065-7_7, finding c3-E-065-7_7-0) found
# an earlier design consumed a present, valid PM-escalation override even on
# a run where NEITHER the C0 review nor the ledger check would have failed —
# violating "Available + clean gate should remain Available". Prove the fix:
# a genuinely clean run with a valid override SITTING PRESENT must leave it
# completely untouched (not renamed, not consumed) for a later run that
# might actually need it.
# ---------------------------------------------------------------------------
run_test "a clean pass leaves a present-but-unneeded PM-escalation override completely unconsumed"

proj25="$(make_project_root "t25")"
plan25="$TMPDIR_ROOT/t25-plan.md"
write_plan "$plan25" "P025" "risk: high" "authenticate() handler added."

ev25="$(make_evidence_dir "$proj25" "P025")"
write_passing_evidence "$ev25"
proot25="$(plan_evidence_root_of "$ev25")"
write_passing_c0_review "$proot25"
stub_c0_verify "$TMPDIR_ROOT/t25-stub" ok
init_ledger_available "$proj25" "P025"
write_pm_override "$proot25"   # present but NOT needed — everything else is clean

gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan25" --project-root "$proj25" 2>&1)" || gate_exit=$?
unstub_c0_verify

if [[ "$gate_exit" -eq 0 ]]; then
  pass "clean pass with an unneeded override present still passes gate"
else
  fail "clean pass with an unneeded override present still passes gate" "got exit=$gate_exit, output: $gate_out"
fi
if [[ -f "${proot25}/cp1-pm-escalation-override.json" ]]; then
  pass "override artifact is STILL PRESENT, untouched (not consumed on a clean pass)"
else
  fail "override artifact is STILL PRESENT, untouched (not consumed on a clean pass)" "override was consumed despite no failure needing it"
fi
consumed_count25="$(find "$proot25" -maxdepth 1 -name 'cp1-pm-escalation-override.json.consumed-*' 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "$consumed_count25" -eq 0 ]]; then
  pass "no .consumed-* archive was created on the clean pass"
else
  fail "no .consumed-* archive was created on the clean pass" "found $consumed_count25 archive(s)"
fi

# ---------------------------------------------------------------------------
# TEST 26: the same audit found `_cp1_claim_pm_override`'s old implementation
# trusted `mv -n`'s bare exit code as proof of ownership — but `mv -n` ALSO
# exits 0 (without moving anything) when the destination already exists (a
# stale `.consumed-<epoch>` sibling from an earlier consumption landing on
# the same epoch second). Prove the fix fails closed in that exact collision:
# the override must remain unconsumed (and the gate must correctly refuse to
# treat a pre-existing collision as authorization) rather than falsely
# reporting success while silently leaving the source reusable.
# ---------------------------------------------------------------------------
run_test "a pre-existing .consumed-<epoch> collision does not falsely authorize a bypass"

proj26="$(make_project_root "t26")"
plan26="$TMPDIR_ROOT/t26-plan.md"
write_plan "$plan26" "P026" "risk: high" "authenticate() handler added."

ev26="$(make_evidence_dir "$proj26" "P026")"
write_passing_evidence "$ev26"
proot26="$(plan_evidence_root_of "$ev26")"
init_ledger_available "$proj26" "P026"
write_pm_override "$proot26"
# Deliberately no c0-plan-review.json — the gate NEEDS the override this time.

# Pre-create every plausible .consumed-<epoch> destination for the next ~8
# seconds (generous margin against test-execution timing jitter) so the real
# claim attempt is virtually guaranteed to collide with an already-existing
# (unrelated, stale) destination name.
now_epoch="$(date -u +%s)"
for offset in 0 1 2 3 4 5 6 7 8; do
  touch "${proot26}/cp1-pm-escalation-override.json.consumed-$((now_epoch + offset))"
done

unstub_c0_verify
gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan26" --project-root "$proj26" 2>&1)" || gate_exit=$?

if [[ -f "${proot26}/cp1-pm-escalation-override.json" ]]; then
  pass "override source remains present after a destination collision (fail-closed, not falsely consumed)"
else
  fail "override source remains present after a destination collision (fail-closed, not falsely consumed)" "source vanished despite a pre-existing destination collision"
fi
if [[ "$gate_exit" -ne 0 ]]; then
  pass "gate correctly refuses to authorize a bypass on a destination collision"
else
  fail "gate correctly refuses to authorize a bypass on a destination collision" "got exit=0 — collision falsely authorized a bypass: $gate_out"
fi

# ---------------------------------------------------------------------------
# TEST 27: BOTH the C0 review AND the ledger budget fail in the SAME run,
# with a single valid PM-escalation override present. CP3 code-review noted
# this is the one path where the round-3 "claim once, reuse for both checks"
# logic (_cp1_ensure_override_claimed) actually does something — previously
# verified only by manual trace, not a test. Prove: the gate passes (both
# failures bypassed by the SAME override), the output warns about BOTH, and
# exactly ONE .consumed-<epoch> archive is created (not two — a single
# override must not be claimed twice in the same run).
# ---------------------------------------------------------------------------
run_test "a single PM-escalation override covers BOTH a C0 failure and a ledger failure in the same run (claimed exactly once)"

proj27="$(make_project_root "t27")"
plan27="$TMPDIR_ROOT/t27-plan.md"
write_plan "$plan27" "P027" "risk: high" "authenticate() handler added."

ev27="$(make_evidence_dir "$proj27" "P027")"
write_passing_evidence "$ev27"
proot27="$(plan_evidence_root_of "$ev27")"
# Deliberately no c0-plan-review.json (C0 check fails) AND an exhausted
# ledger (ledger check fails) — both in the same run.
init_ledger_exhausted "$proj27" "P027"
write_pm_override "$proot27"

unstub_c0_verify
gate_exit=0
gate_out="$(bash "$GATE_SCRIPT" --plan "$plan27" --project-root "$proj27" 2>&1)" || gate_exit=$?

if [[ "$gate_exit" -eq 0 ]]; then
  pass "gate passes when a single override bypasses both a C0 and a ledger failure"
else
  fail "gate passes when a single override bypasses both a C0 and a ledger failure" "got exit=$gate_exit, output: $gate_out"
fi
if echo "$gate_out" | grep -qi "WARNING.*C0 plan-review"; then
  pass "output warns about the bypassed C0 requirement"
else
  fail "output warns about the bypassed C0 requirement" "output: $gate_out"
fi
if echo "$gate_out" | grep -qi "WARNING.*ledger"; then
  pass "output warns about the bypassed ledger requirement"
else
  fail "output warns about the bypassed ledger requirement" "output: $gate_out"
fi
consumed_count27="$(find "$proot27" -maxdepth 1 -name 'cp1-pm-escalation-override.json.consumed-*' 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "$consumed_count27" -eq 1 ]]; then
  pass "exactly one .consumed-* archive exists (claimed once, not twice)"
else
  fail "exactly one .consumed-* archive exists (claimed once, not twice)" "found $consumed_count27 archive(s)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
# The canonical line reports TESTS, matching what the aggregate's "Tests"
# total means. Assertion counts stay visible on their own line, where they
# inform a reader without inflating a portfolio-wide number.
_close_current_test
echo "Results: ${TESTS_PASSED_UNIQUE}/${TESTS_RUN} passed, ${TESTS_FAILED_UNIQUE} failed"
echo "  (${TESTS_PASSED} passing assertions, ${TESTS_FAILED} failing)"
echo ""

if [[ "$TESTS_FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
