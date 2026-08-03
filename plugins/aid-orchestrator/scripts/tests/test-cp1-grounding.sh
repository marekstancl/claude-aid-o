#!/usr/bin/env bash
# =============================================================================
# test-cp1-grounding.sh — Smoke test for CP1 grounding sub-checks 17a–17d
#
# Verifies the extraction logic for the 4 new Completeness Gate sub-checks
# (P035 Phase 2, plan-writing.md Step 6) on a deliberately-broken test plan.
#
# Strategy: variant (a) from the plan — exercise the regex/glob extraction
# patterns themselves, not LLM verification. Verifier dispatch in production
# uses these same patterns; if extraction works correctly here, the verifier
# will receive the right inputs.
#
# Exit codes: 0 = all 4 categories extracted as expected, 1 = extraction gap
# =============================================================================
set -euo pipefail

# ─── P072 Step 9: canonical result line for the aggregate collector ─────────
#
# This suite is exit-code driven: it has no per-case counters, so it reports at
# SUITE granularity — 1/1 on success, 0/1 on failure. That is honest about what
# it knows, and it is the difference between "this suite passed" and the `0/0`
# the collector used to record, which was indistinguishable from a suite that
# crashed before running anything.
#
# Emitted from the EXIT trap so every exit path is covered. Where the suite
# already has an EXIT trap for cleanup, this COMPOSES with it — a shell has
# exactly one EXIT trap, and installing a second silently discards the first,
# which would leak every temp directory these suites create.
_p072_emit_results() {
  # errexit OFF for the duration: a failing `echo` (closed stdout, full disk)
  # would otherwise abort the trap before the cleanup that follows it.
  # Reporting is best-effort; cleanup is not optional.
  set +e
  local rc="${1:-$?}"
  if [[ "$rc" -eq 0 ]]; then
    echo "Results: 1/1 passed, 0 failed"
  else
    echo "Results: 0/1 passed, 1 failed"
  fi
  return 0
}


TEST_DIR=$(mktemp -d)
trap '_p072_rc=$?; _p072_emit_results "$_p072_rc"; rm -rf "$TEST_DIR"' EXIT

# Verify required POSIX tools present (no fd dependency by design).
command -v find >/dev/null || { echo "FAIL: find not available"; exit 1; }
command -v grep >/dev/null || { echo "FAIL: grep not available"; exit 1; }

# ─── Setup: deliberately-broken test plan touching all 4 sub-checks ──────

cat > "$TEST_DIR/test-plan.md" <<'EOF'
---
id: P999
type: plan
status: draft
---

# Plan: Test Plan with Broken Grounding (P999)

## Implementation Steps

### Step 1: Sample broken step (fixture for sub-checks 17a-17d)

**Files:**
- Modify: tests/integration/test_canonical_view.py — add new test case
- Test: tests/integration/test_canonical_view.py

**Implementation Detail:**

Update the Session.validation_warnings field — fix automatically recomputes
for existing sessions after deploy.

Related backlog: T-132, T-133

**Acceptance Criteria:**
- [ ] delete ui/src/lib/legacy-helper.ts (no longer needed)
- [ ] verify must_not_exist: legacy-helper.ts after fix
EOF

# ─── Sub-check 17a: backlog ID extraction (whole-plan body, regex \bT-[0-9]+\b) ─

EXTRACTED_BACKLOG=$(grep -oE '\bT-[0-9]+\b' "$TEST_DIR/test-plan.md" | sort -u | paste -sd ',' -)

[[ "$EXTRACTED_BACKLOG" == *"T-132"* ]] || { echo "FAIL 17a: T-132 not extracted"; exit 1; }
[[ "$EXTRACTED_BACKLOG" == *"T-133"* ]] || { echo "FAIL 17a: T-133 not extracted"; exit 1; }
echo "PASS 17a: backlog IDs extracted ($EXTRACTED_BACKLOG)"

# ─── Sub-check 17b: test directory paths extraction ──────────────────────

EXTRACTED_TEST_PATHS=$(grep -oE 'tests/[a-z]+/[a-z_]+\.(py|ts|bats)' "$TEST_DIR/test-plan.md" | sort -u)

[[ "$EXTRACTED_TEST_PATHS" == *"tests/integration/test_canonical_view.py"* ]] || {
  echo "FAIL 17b: test path not extracted from plan"; exit 1;
}
echo "PASS 17b: test paths extracted ($EXTRACTED_TEST_PATHS)"

# Verify the 17b verification command itself (POSIX find, no fd) is well-formed
# by running it on a no-op fixture (no tests/ dir → no output, exit 0).
mkdir -p "$TEST_DIR/tests/unit" "$TEST_DIR/tests/integration"
touch "$TEST_DIR/tests/unit/test_canonical_view.py"
FOUND=$(find "$TEST_DIR/tests/" -type f \( -name "*.py" -o -name "*.ts" -o -name "*.bats" \) -name "*test_canonical_view*")
[[ -n "$FOUND" ]] || { echo "FAIL 17b: find command did not locate test fixture"; exit 1; }
[[ "$FOUND" == *"tests/unit/test_canonical_view.py"* ]] || {
  echo "FAIL 17b: find command located wrong file: $FOUND"; exit 1;
}
echo "PASS 17b: POSIX find detects analog in sibling test dir"

# ─── Sub-check 17c: DB-field reference extraction ─────────────────────────

EXTRACTED_DB_FIELDS=$(grep -oE '[A-Z][a-zA-Z]+\.[a-z_]+' "$TEST_DIR/test-plan.md" | sort -u)

[[ "$EXTRACTED_DB_FIELDS" == *"Session.validation_warnings"* ]] || {
  echo "FAIL 17c: DB field reference not extracted"; exit 1;
}
echo "PASS 17c: DB field references extracted ($EXTRACTED_DB_FIELDS)"

# ─── Sub-check 17d: file removal claim extraction ─────────────────────────

EXTRACTED_FILE_REMOVALS=$(grep -E 'delete |must_not_exist' "$TEST_DIR/test-plan.md")

[[ -n "$EXTRACTED_FILE_REMOVALS" ]] || { echo "FAIL 17d: file removal claim not extracted"; exit 1; }
echo "PASS 17d: file removal claims extracted"

# ─── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "=========================================================="
echo "test-cp1-grounding: PASS — all 4 sub-check extractions work"
echo "=========================================================="
echo ""
echo "Extracted from deliberately-broken test plan:"
echo "  17a backlog IDs:       $EXTRACTED_BACKLOG"
echo "  17b test paths:        $EXTRACTED_TEST_PATHS"
echo "  17c DB fields:         $EXTRACTED_DB_FIELDS"
echo "  17d file removals:     (1 line — see grep output above)"
echo ""
echo "Verification commands (POSIX-only, no fd dependency):"
echo "  17a: git log --since='24 hours ago' --grep='T-NNN' --all"
echo "  17b: find tests/ -type f \\( -name '*.py' -o -name '*.ts' -o -name '*.bats' \\) -name '*<basename>*'"
echo "  17c: grep '<field>' <project>/db/models.py"
echo "  17d: ls <path>"
exit 0
