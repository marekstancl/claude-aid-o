#!/usr/bin/env bash
# =============================================================================
# test-force-init-passthrough.sh — PM-authorized, audited cross-plan force-init
#
# Covers the v2.57.2 sanctioned override that waives ONLY the plan-level DONE
# gate (the false-positive cross-plan ca-review-complete precondition raised
# when a DIFFERENT plan is intentionally in progress):
#
#   FSM level (aid-fsm.sh init):
#     F1  without --force → cross-plan gate still BLOCKS
#     F2  with a valid (>=20 char) --force --reason → init PASSES
#     F3  a fsm_force_override timeline event is written with the SAME reason
#     F4  the cross-EPIC audit-log gets a fsm_force_override entry, same reason
#     F5  a waiver artifact is written with the SAME reason
#     F6  a short (<20 char) reason FAILS (audit-grade reason enforced)
#     F7  other init checks stay ACTIVE under --force (dirty tree still blocks)
#
#   Pipeline flag plumbing (aid-json-to-run.sh --force-init-reason):
#     E1  WITHOUT the flag, a cross-plan-blocked init fails the run generation
#     E2  WITH a valid --force-init-reason, run generation succeeds
#
# Each test runs in its own throwaway git repo so the real repo's .aid-o/ and
# branch state are never touched. The cross-plan gate only fires for numeric
# plan ids, so the fixtures use P900 (under test) blocked by P901 (prior).
#
# Exit codes: 0=all passed, 1=one or more tests failed
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
FSM="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-fsm.sh"
JSON_TO_RUN="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-json-to-run.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEMPLATES_DIR="$REPO_ROOT/plugins/aid-orchestrator/defaults/templates"
RUN_TEMPLATE="$TEMPLATES_DIR/run-new-feature.md"
MINIMAL_PLAN="$FIXTURES_DIR/minimal-plan.json"
MINIMAL_EPIC="$FIXTURES_DIR/E-TEST-001-1_1-minimal-test-plan.md"

# A valid audit-grade reason (>=20 chars) mirroring the real P065/P061 waiver.
VALID_REASON="P901 intentionally in progress; P900 independent - waive only the false cross-plan ca-review-complete precondition"
SHORT_REASON="too short"

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
for f in "$FSM" "$JSON_TO_RUN" "$RUN_TEMPLATE" "$MINIMAL_PLAN" "$MINIMAL_EPIC"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: required file not found: $f" >&2
    exit 1
  fi
done

echo "=== test-force-init-passthrough.sh ==="
echo "FSM: $FSM"
echo ""

# ---------------------------------------------------------------------------
# Helper: create a fresh clean git repo with a PRIOR plan (P901) that has
# unreviewed Curator/Auditor findings (audit-report.md present, NO
# ca-review-complete marker). Echoes the repo path.
# ---------------------------------------------------------------------------
fresh_repo_with_prior() {
  local d; d="$(mktemp -d "$TMPDIR_ROOT/repo.XXXXXX")"
  (
    cd "$d"
    git init -q
    git config user.email t@t.io
    git config user.name T
    git checkout -q -b main 2>/dev/null || git branch -m main
    echo seed > .gitkeep
    git add -A
    git commit -q -m seed
    local pdir=".aid-o/work/evidence/E-901-1_1/R-901-1"
    mkdir -p "$pdir"
    {
      echo "epic_id: E-901-1_1"
      echo "run_id: R-901-1"
      echo "state: DONE"
      echo "done_phase: review"
    } > "$pdir/fsm-state.yaml"
    echo "# audit report (P901) — unreviewed" > "$pdir/audit-report.md"
    # Intentionally NO ca-review-complete marker: this is the blocking condition.
  )
  echo "$d"
}

UNDER_TEST_EPIC="E-900-1_1"
UNDER_TEST_RUN="R-900-1"
STATE_REL=".aid-o/work/evidence/${UNDER_TEST_EPIC}/${UNDER_TEST_RUN}/fsm-state.yaml"
EVID_REL=".aid-o/work/evidence/${UNDER_TEST_EPIC}/${UNDER_TEST_RUN}"

# ===========================================================================
# F1: without --force, the cross-plan gate BLOCKS init
# ===========================================================================
echo "TEST: F1 — cross-plan gate blocks init without --force"
{
  repo="$(fresh_repo_with_prior)"
  ec=0
  err="$( cd "$repo" && "$FSM" init "$UNDER_TEST_EPIC" "$UNDER_TEST_RUN" 2 full main "$(cd "$repo" && git rev-parse HEAD)" "$STATE_REL" 2>&1 >/dev/null )" || ec=$?
  if [[ "$ec" -ne 0 ]] && printf '%s' "$err" | grep -q "PRECONDITION FAIL" && [[ ! -f "$repo/$STATE_REL" ]]; then
    _pass "F1 — init blocked (exit $ec, PRECONDITION FAIL, no fsm-state written)"
  else
    _fail "F1 — expected block; got exit=$ec, state_exists=$([[ -f "$repo/$STATE_REL" ]] && echo yes || echo no), err=$(printf '%s' "$err" | tr '\n' '|' | head -c 200)"
  fi
}

# ===========================================================================
# F2–F5: with a valid reason, init PASSES and writes audited override artifacts
# ===========================================================================
echo "TEST: F2–F5 — valid --force --reason passes + audited artifacts"
{
  repo="$(fresh_repo_with_prior)"
  ec=0
  ( cd "$repo" && "$FSM" init "$UNDER_TEST_EPIC" "$UNDER_TEST_RUN" 2 full main "$(cd "$repo" && git rev-parse HEAD)" "$STATE_REL" --force --reason "$VALID_REASON" >/dev/null 2>&1 ) || ec=$?

  # F2: init passed, fsm-state written
  if [[ "$ec" -eq 0 && -f "$repo/$STATE_REL" ]]; then
    _pass "F2 — init passed with valid reason (exit 0, fsm-state written)"
  else
    _fail "F2 — expected pass; got exit=$ec, state_exists=$([[ -f "$repo/$STATE_REL" ]] && echo yes || echo no)"
  fi

  # F3: timeline fsm_force_override event with same reason
  tl="$repo/$EVID_REL/timeline.jsonl"
  if [[ -f "$tl" ]] && grep -q '"fsm_force_override"' "$tl" && grep -Fq "$VALID_REASON" "$tl"; then
    _pass "F3 — timeline has fsm_force_override with the same reason"
  else
    _fail "F3 — timeline missing fsm_force_override/reason (file_exists=$([[ -f "$tl" ]] && echo yes || echo no))"
  fi

  # F4: cross-EPIC audit-log entry with same reason
  al="$repo/.aid-o/work/audit-log.jsonl"
  if [[ -f "$al" ]] && grep -q '"fsm_force_override"' "$al" && grep -Fq "$VALID_REASON" "$al"; then
    _pass "F4 — audit-log has fsm_force_override with the same reason"
  else
    _fail "F4 — audit-log missing fsm_force_override/reason (file_exists=$([[ -f "$al" ]] && echo yes || echo no))"
  fi

  # F5: waiver artifact with same reason
  waiver="$(ls "$repo/$EVID_REL"/waiver-*.json 2>/dev/null | head -1)"
  if [[ -n "$waiver" && -f "$waiver" ]] && grep -Fq "$VALID_REASON" "$waiver"; then
    _pass "F5 — waiver artifact written with the same reason ($(basename "$waiver"))"
  else
    _fail "F5 — waiver artifact missing/without reason (found=${waiver:-none})"
  fi
}

# ===========================================================================
# F6: a short (<20 char) reason FAILS (audit-grade reason enforced)
# ===========================================================================
echo "TEST: F6 — short reason fails"
{
  repo="$(fresh_repo_with_prior)"
  ec=0
  err="$( cd "$repo" && "$FSM" init "$UNDER_TEST_EPIC" "$UNDER_TEST_RUN" 2 full main "$(cd "$repo" && git rev-parse HEAD)" "$STATE_REL" --force --reason "$SHORT_REASON" 2>&1 >/dev/null )" || ec=$?
  if [[ "$ec" -ne 0 ]] && printf '%s' "$err" | grep -qi "min 20 characters" && [[ ! -f "$repo/$STATE_REL" ]]; then
    _pass "F6 — short reason rejected (exit $ec, min-20 enforced, no fsm-state)"
  else
    _fail "F6 — expected rejection; got exit=$ec, state_exists=$([[ -f "$repo/$STATE_REL" ]] && echo yes || echo no)"
  fi
}

# ===========================================================================
# F7: other init checks stay ACTIVE under --force (dirty tree still blocks).
# The force flag waives ONLY the plan-level DONE gate, not the clean-worktree
# guard, so a dirty tracked file must still abort even with a valid reason.
# ===========================================================================
echo "TEST: F7 — dirty worktree still blocks under --force"
{
  repo="$(fresh_repo_with_prior)"
  ( cd "$repo" && echo "dirty change" >> .gitkeep )  # modify a TRACKED file
  ec=0
  err="$( cd "$repo" && "$FSM" init "$UNDER_TEST_EPIC" "$UNDER_TEST_RUN" 2 full main "$(cd "$repo" && git rev-parse HEAD)" "$STATE_REL" --force --reason "$VALID_REASON" 2>&1 >/dev/null )" || ec=$?
  if [[ "$ec" -ne 0 ]] && printf '%s' "$err" | grep -q "Uncommitted changes"; then
    _pass "F7 — clean-worktree guard NOT masked by --force (exit $ec, Uncommitted changes)"
  else
    _fail "F7 — expected clean-tree block; got exit=$ec, err=$(printf '%s' "$err" | tr '\n' '|' | head -c 200)"
  fi
}

# ===========================================================================
# E1/E2: aid-json-to-run.sh --force-init-reason flag plumbs through to init.
# Uses a numeric-epic plan.json (E-900-1_1) so the cross-plan gate fires.
# ===========================================================================
echo "TEST: E1/E2 — aid-json-to-run.sh --force-init-reason plumbing"
{
  repo="$(fresh_repo_with_prior)"
  plan900="$repo/plan-900.json"
  jq '.epic_id = "E-900-1_1"' "$MINIMAL_PLAN" > "$plan900"
  out_dir="$repo/run-out"
  mkdir -p "$out_dir"

  # E1: WITHOUT the flag → cross-plan gate blocks → generation fails
  ec=0
  ( cd "$repo" && "$JSON_TO_RUN" \
      --plan-json "$plan900" --run-template "$RUN_TEMPLATE" \
      --epic "$MINIMAL_EPIC" --output-dir "$out_dir" --run-id "$UNDER_TEST_RUN" \
      >/dev/null 2>&1 ) || ec=$?
  if [[ "$ec" -ne 0 && ! -f "$repo/$STATE_REL" ]]; then
    _pass "E1 — json-to-run without flag is blocked by cross-plan gate (exit $ec)"
  else
    _fail "E1 — expected block; got exit=$ec, state_exists=$([[ -f "$repo/$STATE_REL" ]] && echo yes || echo no)"
  fi

  # E2: WITH a valid --force-init-reason → generation succeeds
  repo2="$(fresh_repo_with_prior)"
  plan900b="$repo2/plan-900.json"
  jq '.epic_id = "E-900-1_1"' "$MINIMAL_PLAN" > "$plan900b"
  out_dir2="$repo2/run-out"
  mkdir -p "$out_dir2"
  ec=0
  run_path="$( cd "$repo2" && "$JSON_TO_RUN" \
      --plan-json "$plan900b" --run-template "$RUN_TEMPLATE" \
      --epic "$MINIMAL_EPIC" --output-dir "$out_dir2" --run-id "$UNDER_TEST_RUN" \
      --force-init-reason "$VALID_REASON" 2>/dev/null )" || ec=$?
  if [[ "$ec" -eq 0 && -f "$repo2/$STATE_REL" && -n "$run_path" && -f "$run_path" ]]; then
    _pass "E2 — json-to-run --force-init-reason forwards override; generation succeeds"
  else
    _fail "E2 — expected success; got exit=$ec, state_exists=$([[ -f "$repo2/$STATE_REL" ]] && echo yes || echo no), run_path=${run_path:-none}"
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total=$((PASS + FAIL))
echo ""
echo "Results: $total/$total run, $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
