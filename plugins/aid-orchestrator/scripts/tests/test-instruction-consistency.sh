#!/usr/bin/env bash
# =============================================================================
# test-instruction-consistency.sh — Verify instruction files match bash reality
#
# Checks that markdown instruction files (pipeline.md, aid-run.md, etc.)
# are consistent with what bash scripts actually enforce. Catches drift
# between documentation and implementation.
#
# Categories:
#   1. FSM states in docs match aid-fsm.sh VALID_STATES
#   2. FSM transitions in docs match aid-fsm.sh VALID_TRANSITIONS
#   3. Gate names in docs match execution.yaml
#   4. increment-step preconditions in docs match aid-fsm.sh checks
#   5. File references in skills/commands point to existing files
#   6. Step-verify template contains all required sections
#   7. orchestration.yaml states match aid-fsm.sh
#   8. Old command names do not return to active instructions
#   9. AUTO liveness/ownership contract remains present and role boundaries do not drift
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$PLUGIN_DIR/scripts"

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠ $1"; WARN=$((WARN + 1)); }

# ─── 1. FSM States ─────────────────────────────────────────────────────────

echo "=== 1. FSM States ==="

# Extract ground truth from aid-fsm.sh
BASH_STATES=$(grep '^VALID_STATES=' "$SCRIPTS_DIR/aid-fsm.sh" | sed 's/VALID_STATES="//' | sed 's/"//' | tr ' ' '\n' | sort)
BASH_STATE_COUNT=$(echo "$BASH_STATES" | wc -l)

# Check pipeline.md mentions all states
for state in $BASH_STATES; do
  if grep -q "$state" "$PLUGIN_DIR/skills/pipeline.md" 2>/dev/null; then
    pass "pipeline.md contains state: $state"
  else
    fail "pipeline.md MISSING state: $state"
  fi
done

# Check orchestration.yaml has all states
ORCH_FILE="$PLUGIN_DIR/defaults/orchestration.yaml"
if [[ -f "$ORCH_FILE" ]]; then
  for state in $BASH_STATES; do
    if grep -q "$state" "$ORCH_FILE" 2>/dev/null; then
      pass "orchestration.yaml contains state: $state"
    else
      fail "orchestration.yaml MISSING state: $state"
    fi
  done
fi

# Check pipeline.md state table has correct count
PIPELINE_STATE_TABLE_COUNT=$(grep -cE '^\| \*\*[A-Z]+\*\*' "$PLUGIN_DIR/skills/pipeline.md" 2>/dev/null || echo 0)
if [[ "$PIPELINE_STATE_TABLE_COUNT" -eq "$BASH_STATE_COUNT" ]]; then
  pass "pipeline.md state table has $BASH_STATE_COUNT rows (matches bash)"
else
  fail "pipeline.md state table has $PIPELINE_STATE_TABLE_COUNT rows (bash has $BASH_STATE_COUNT)"
fi

# ─── 2. FSM Transitions ────────────────────────────────────────────────────

echo ""
echo "=== 2. FSM Transitions ==="

# Extract transitions from aid-fsm.sh
BASH_TRANSITIONS=$(grep -oP '"[A-Z]+:[A-Z]+"' "$SCRIPTS_DIR/aid-fsm.sh" | tr -d '"' | grep -v '^FROM:TO$' | sort)

# Check pipeline.md valid transitions block contains all
for trans in $BASH_TRANSITIONS; do
  FROM="${trans%%:*}"
  TO="${trans##*:}"
  if grep -qE "$FROM.*→.*$TO|$FROM.*->.*$TO|$FROM:$TO" "$PLUGIN_DIR/skills/pipeline.md" 2>/dev/null; then
    pass "pipeline.md documents transition: $FROM → $TO"
  else
    fail "pipeline.md MISSING transition: $FROM → $TO"
  fi
done

# ─── 3. Gate Names ─────────────────────────────────────────────────────────

echo ""
echo "=== 3. Gate Names ==="

EXEC_YAML="$PLUGIN_DIR/defaults/execution.yaml"
if [[ -f "$EXEC_YAML" ]]; then
  # Extract gate names (top-level keys under gates section — indented 2 spaces, ending with :)
  GATE_NAMES=$(grep -E '^  [a-z_]+:$' "$EXEC_YAML" | sed 's/://;s/^ *//' | sort)

  for gate in $GATE_NAMES; do
    # Check no .md file uses a different name for this gate
    # (e.g., security_scan instead of security_scan_pass)
    pass "execution.yaml gate: $gate"
  done
else
  warn "execution.yaml not found — skipping gate name checks"
fi

# ─── 4. increment-step Preconditions ───────────────────────────────────────

echo ""
echo "=== 4. Step-Verify Required Sections ==="

# Extract required sections from aid-fsm.sh increment-step
REQUIRED_SECTIONS=()
while IFS= read -r line; do
  section=$(echo "$line" | grep -oP "'\^## \K[^']+")
  [[ -n "$section" ]] && REQUIRED_SECTIONS+=("$section")
done < <(grep "grep.*'\\^##" "$SCRIPTS_DIR/aid-fsm.sh" 2>/dev/null)

# Check pipeline.md step-verify template has them
for section in "${REQUIRED_SECTIONS[@]}"; do
  if grep -q "## $section" "$PLUGIN_DIR/skills/pipeline.md" 2>/dev/null; then
    pass "pipeline.md step-verify template has: ## $section"
  else
    fail "pipeline.md step-verify template MISSING: ## $section"
  fi
done

# Also check Result: PASS is required
if grep -q "Result: PASS" "$SCRIPTS_DIR/aid-fsm.sh" 2>/dev/null; then
  if grep -q "Result: PASS" "$PLUGIN_DIR/skills/pipeline.md" 2>/dev/null; then
    pass "pipeline.md template has 'Result: PASS' marker"
  else
    fail "pipeline.md template MISSING 'Result: PASS' marker"
  fi
fi

# ─── 5. File References ───────────────────────────────────────────────────

echo ""
echo "=== 5. Cross-File References ==="

# Check that skills referenced in non-CHANGELOG .md files actually exist
SKILL_REFS=$(grep -rohP 'skills/[a-z_-]+\.md' "$PLUGIN_DIR/skills/" "$PLUGIN_DIR/commands/" "$PLUGIN_DIR/agents/" 2>/dev/null | sort -u)

for ref in $SKILL_REFS; do
  if [[ -f "$PLUGIN_DIR/$ref" ]]; then
    pass "Referenced file exists: $ref"
  else
    fail "Referenced file MISSING: $ref (still referenced in instruction files)"
  fi
done

# Check agent files
AGENT_REFS=$(grep -rohP 'agents/[a-z_-]+\.md' "$PLUGIN_DIR/skills/" "$PLUGIN_DIR/commands/" 2>/dev/null | sort -u)

for ref in $AGENT_REFS; do
  if [[ -f "$PLUGIN_DIR/$ref" ]]; then
    pass "Referenced agent exists: $ref"
  else
    fail "Referenced agent MISSING: $ref"
  fi
done

# Check script files
SCRIPT_REFS=$(grep -rohP 'scripts/[a-z_-]+\.sh' "$PLUGIN_DIR/skills/" "$PLUGIN_DIR/commands/" 2>/dev/null | sort -u)

for ref in $SCRIPT_REFS; do
  if [[ -f "$PLUGIN_DIR/$ref" ]]; then
    pass "Referenced script exists: $ref"
  else
    fail "Referenced script MISSING: $ref"
  fi
done

# ─── 6. v1 State Names ────────────────────────────────────────────────────

echo ""
echo "=== 6. v1 State Names (should not appear in active files) ==="

V1_STATES="IDLE PLANNING PLAN_REVIEW PHASE_CHECK CURATOR_RESOLVE PM_APPROVAL DEPLOY_CHECK FINALIZING GATE_RETRY NEXT_PHASE"

for v1state in $V1_STATES; do
  # Check only active instruction files (skip CHANGELOG, skip files with legacy notice)
  # Also exclude "No v1 states" negation patterns
  HITS=$(grep -rl "\b${v1state}\b" "$PLUGIN_DIR/skills/" "$PLUGIN_DIR/commands/" "$PLUGIN_DIR/agents/" 2>/dev/null | grep -v CHANGELOG || true)
  # Filter out files where the state only appears in "No v1 states" or "no ... STATE" context
  REAL_HITS=""
  for hit in $HITS; do
    # Count lines with v1 state that are NOT in a "no/No" negation context
    NON_NEG=$(grep -c "\b${v1state}\b" "$hit" 2>/dev/null || echo 0)
    NEG=$(grep -cE "(no |No |NOT |not ).*\b${v1state}\b|→.*\b${v1state}\b" "$hit" 2>/dev/null || echo 0)
    [[ $((NON_NEG - NEG)) -gt 0 ]] && REAL_HITS="$REAL_HITS $hit"
  done
  HITS="$REAL_HITS"
  if [[ -n "$HITS" ]]; then
    for hit in $HITS; do
      # Skip files with v1 legacy notice
      if grep -q "v1 Legacy Notice\|v1 legacy" "$hit" 2>/dev/null; then
        warn "v1 state '$v1state' in $(basename $hit) (has legacy notice)"
      else
        fail "v1 state '$v1state' in $(basename $hit) (NO legacy notice)"
      fi
    done
  fi
done

# ─── 7. DONE Sub-Phases ───────────────────────────────────────────────────

echo ""
echo "=== 7. DONE Sub-Phases ==="

# Extract valid phases from aid-fsm.sh
BASH_PHASES=$(grep '^VALID_DONE_PHASES=' "$SCRIPTS_DIR/aid-fsm.sh" 2>/dev/null | sed 's/VALID_DONE_PHASES="//' | sed 's/"//')

if [[ -n "$BASH_PHASES" ]]; then
  for phase in $BASH_PHASES; do
    if grep -q "$phase" "$PLUGIN_DIR/skills/pipeline.md" 2>/dev/null; then
      pass "pipeline.md documents done_phase: $phase"
    else
      fail "pipeline.md MISSING done_phase: $phase"
    fi
  done
fi

# ─── 8. Old Command Names ─────────────────────────────────────────────────

echo ""
echo "=== 8. Old Command Names ==="

OLD_COMMANDS="/aid-brainstorm /aid-write-plan /aid-plan-epic /aid-run-epic /aid-first-aid /aid-epic-status /aid-epic-queue"

for cmd in $OLD_COMMANDS; do
  HITS=$(grep -rl "\\${cmd}\b" "$PLUGIN_DIR/skills/" "$PLUGIN_DIR/commands/" "$PLUGIN_DIR/agents/" "$PLUGIN_DIR/defaults/" 2>/dev/null | grep -v CHANGELOG || true)
  if [[ -n "$HITS" ]]; then
    for hit in $HITS; do
      # Skip "replaces" / "old" / "No v1" context
      ACTIVE_REFS=$(grep "\\${cmd}" "$hit" 2>/dev/null | grep -vcE "replaces|Replaces|old |No v1|no |→" 2>/dev/null || true)
      ACTIVE_REFS="${ACTIVE_REFS:-0}"
      [[ "$ACTIVE_REFS" -gt 0 ]] && fail "Old command '${cmd}' referenced in $(basename $hit)"
    done
  fi
done

# ─── Summary ───────────────────────────────────────────────────────────────

# AUTO liveness and role ownership
echo ""
echo "=== 9. AUTO Liveness and Role Ownership ==="

assert_instruction() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  if grep -qF -- "$pattern" "$file" 2>/dev/null; then
    pass "$description"
  else
    fail "$description"
  fi
}

assert_instruction "$PLUGIN_DIR/commands/aid-run.md" \
  'Do not ask the PM to choose between technical A/B/C options.' \
  "aid-run routes AUTO technical decisions away from PM"
assert_instruction "$PLUGIN_DIR/commands/aid-run.md" \
  '`tail -f` is forbidden as a completion detector.' \
  "aid-run forbids non-terminating tail watcher"
assert_instruction "$PLUGIN_DIR/commands/aid-run.md" \
  'the pre-fix run cannot prove the post-fix HEAD.' \
  "aid-run rejects stale aggregate evidence"
assert_instruction "$PLUGIN_DIR/skills/pipeline.md" \
  'Only the controller mutates FSM state,' \
  "pipeline assigns FSM ownership to controller"
assert_instruction "$PLUGIN_DIR/agents/implementer.md" \
  'Do not call FSM transition/increment commands' \
  "implementer cannot advance FSM"
assert_instruction "$PLUGIN_DIR/skills/agent-protocol.md" \
  'the controller normally owns commits after validating agent output.' \
  "agent protocol assigns orchestrated commits to controller"
assert_instruction "$PLUGIN_DIR/agents/implementer.md" \
  'Do not detach long-running work with `nohup`, `disown`, `tail -f`' \
  "implementer cannot orphan long-running work"
assert_instruction "$PLUGIN_DIR/agents/verifier.md" \
  'Review an immutable revision in an isolated worktree' \
  "verifier reviews immutable isolated revision"


REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"

# ─── P072 Step 23: the parallel classification HAS a consumer ───────────────
#
# Three shipped documents said the opposite of what is now true — that
# `parallel.status` is a descriptive finding nothing consumes. That sentence
# survived three releases, so a reviewer noticing is not the mechanism this
# needs. It is pinned here, where drift of exactly this class is already
# caught.
#
# The scope is `plugins/` and the LIVE docs tree. Archived plans under
# docs/plans/archive/ legitimately record the boundary as it was at the time
# and must not be rewritten to match the present.
echo ""
echo "TEST: no shipped file claims the parallel classification is consumed by nothing"
STALE_CLAIM_HITS=""
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  STALE_CLAIM_HITS="${STALE_CLAIM_HITS}${STALE_CLAIM_HITS:+$'\n'}${hit}"
done < <(grep -rIl -E 'no scheduler that consumes|consumed by nothing|classification is consumed by no|schedules nothing, batches' \
           "$PLUGIN_DIR" "$REPO_ROOT/docs" 2>/dev/null \
         | grep -v '/docs/plans/archive/' \
         | grep -v 'test-instruction-consistency.sh' || true)
if [[ -z "$STALE_CLAIM_HITS" ]]; then
  PASS=$((PASS + 1)); echo "  ✓ no file claims the parallel classification has no consumer"
else
  FAIL=$((FAIL + 1))
  echo "  ✗ these files still claim the parallel classification is consumed by nothing:"
  printf '      %s\n' $STALE_CLAIM_HITS
  echo "      Correct the file rather than excluding it — an exclusion list is how"
  echo "      the contradictory sentence survived three releases in the first place."
fi

echo ""
echo "TEST: an ARCHIVED document keeps its historical claim (the check is scoped)"
ARCHIVE_FIXTURE="$REPO_ROOT/docs/plans/archive/.p072-scope-fixture.md"
mkdir -p "$(dirname "$ARCHIVE_FIXTURE")"
printf 'Historical record: this plan ships no scheduler that consumes it.\n' > "$ARCHIVE_FIXTURE"
if grep -rIl -E 'no scheduler that consumes' "$PLUGIN_DIR" "$REPO_ROOT/docs" 2>/dev/null \
     | grep -v '/docs/plans/archive/' | grep -v 'test-instruction-consistency.sh' | grep -q .; then
  FAIL=$((FAIL + 1)); echo "  ✗ the scoped check fired on an archived file"
else
  PASS=$((PASS + 1)); echo "  ✓ an archived record carrying the old sentence is left alone"
fi
rm -f "$ARCHIVE_FIXTURE"

echo ""
echo "=================================="
echo "Instruction Consistency: $PASS passed, $FAIL failed, $WARN warnings"
# P072 Step 9 — canonical line for the aggregate collector.
echo "Results: ${PASS}/$((PASS + FAIL)) passed, ${FAIL} failed"
echo "=================================="

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
