#!/usr/bin/env bash
# =============================================================================
# test-plan-diff.sh — behavioral RED regression for aid-plan-diff.sh's AC
# extraction (P058 Step 4).
#
# aid-plan-diff.sh:~131 extracts Acceptance Criteria with the awk range
#   /^## Acceptance Criteria/,/^## [^A]/
# which only ever activates when the plan literally has a
# "## Acceptance Criteria" heading. P052-P058-style plans instead put their
# verification_pattern-bearing AC bullets under "## Success Criteria" — a
# heading that never opens the range (there is no "## Acceptance Criteria"
# line to match at all), so aid-plan-diff.sh silently produces ac_count: 0
# and a "skipped" verdict for every one of those plans (false-green: the
# gate looks like "nothing to verify" instead of "8 ACs, go verify them").
#
# This test is DELIBERATELY RED today: it feeds aid-plan-diff.sh a minimal,
# self-contained plan.md fixture (built inline via heredoc — mktemp
# isolation, no on-disk fixture file per this step's allowed_paths) with a
# "## Success Criteria" section containing real "- [ ] AC" bullets +
# verification_pattern blocks, and asserts ac_count > 0. It fails today
# (ac_count comes back 0) and will only go green once Step 6 of this same
# plan replaces the awk range in aid-plan-diff.sh with a flag-based block
# that also recognizes "## Success Criteria". Do NOT "fix" aid-plan-diff.sh
# here — that is explicitly out of scope for this step (per plan D3/Step 6).
#
# Usage: ./test-plan-diff.sh
# Exit: 0 if ac_count > 0 (bug fixed / green), 1 if ac_count == 0 (red, as
#       expected today).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PLAN_DIFF="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-plan-diff.sh"

PASS=0
FAIL=0
_pass() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "  FAIL: $1"; FAIL=$(( FAIL + 1 )); }

if [[ ! -f "$PLAN_DIFF" ]]; then
  echo "ERROR: aid-plan-diff.sh not found: $PLAN_DIFF" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Isolation: fresh subprocess-local tmpdir, cleaned up on exit.
# ---------------------------------------------------------------------------
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FIXTURE_PLAN="$TMPDIR_ROOT/success-criteria-fixture-plan.md"
EVIDENCE_DIR="$TMPDIR_ROOT/evidence"
mkdir -p "$EVIDENCE_DIR"

cat > "$FIXTURE_PLAN" <<'PLANMD'
---
id: P-TEST-PLANDIFF
status: draft
---

# Plan: aid-plan-diff Success Criteria repro (test fixture)

## Goal

Standalone fixture for test-plan-diff.sh — proves aid-plan-diff.sh's AC
extraction does (or does not) parse a "## Success Criteria" section, the
heading P052-P058-style plans actually use for their verification_pattern
bullets.

## Success Criteria

- [ ] AC1: A trivially-true shell command exits 0.
```yaml
verification_pattern:
  type: cmd
  cmd: "true"
  expected_exit: 0
```
- [ ] AC2: A trivially-false shell command exits non-zero.
```yaml
verification_pattern:
  type: cmd
  cmd: "false"
  expected_exit: 1
```
- [ ] AC3: This exact fixture file exists on disk once written.
```yaml
verification_pattern:
  type: must_not_exist
  cmd: "/nonexistent/path/that/must/not/exist/for/this/test"
```

## Notes

No "## Acceptance Criteria" heading exists anywhere in this fixture on
purpose — that is the whole point of the repro.
PLANMD

echo "=== test-plan-diff.sh ==="
echo "Script under test: $PLAN_DIFF"
echo "Fixture: $FIXTURE_PLAN"
echo ""

echo "TEST: aid-plan-diff.sh over a '## Success Criteria' plan must find its ACs (ac_count > 0)"
{
  bash "$PLAN_DIFF" --plan "$FIXTURE_PLAN" --evidence-dir "$EVIDENCE_DIR" --base-commit HEAD \
    >"$TMPDIR_ROOT/stdout.log" 2>"$TMPDIR_ROOT/stderr.log"
  plan_diff_exit=$?

  diff_json="$EVIDENCE_DIR/plan-diff.json"
  if [[ ! -f "$diff_json" ]]; then
    _fail "plan-diff.json was not produced (exit=${plan_diff_exit})"
  else
    ac_count="$(jq -r '.ac_count // 0' "$diff_json" 2>/dev/null || echo 0)"
    verdict="$(jq -r '.overall_verdict // ""' "$diff_json" 2>/dev/null || echo "")"

    if [[ "$ac_count" -gt 0 ]]; then
      _pass "ac_count=${ac_count} (> 0) — '## Success Criteria' bullets were parsed (verdict=${verdict})"
    else
      _fail "ac_count=0, overall_verdict='${verdict}' — aid-plan-diff.sh returned ac_count=0 for a plan with 3 real AC bullets under '## Success Criteria' (its awk range /^## Acceptance Criteria/,/^## [^A]/ never opens without that exact heading — RED, expected until Step 6 fixes the awk range; see file header)"
    fi
  fi
}

echo ""
echo "=========================================="
TOTAL=$(( PASS + FAIL ))
echo "Results: ${PASS}/${TOTAL} passed"

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAIL: ${FAIL} test(s) failed (expected RED today — see file header; Step 6 fixes this)"
  exit 1
fi

echo "PASS: aid-plan-diff.sh correctly parses '## Success Criteria' AC bullets"
exit 0
