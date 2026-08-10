# P030 — AID Enforcement Improvements (Post-Monitoring)

**Status:** DONE
**Source:** Vulcan monitoring report (8h, 28 EPICs, P9-P14)
**Created:** 2026-03-19

## Context

8-hour monitoring of Vulcan development (P9-P14, 28 EPICs) revealed systematic gaps between AID protocol and agent behavior. Bash enforcement works perfectly where it exists (100% FSM compliance, increment-step blocking). But instruction-level rules degrade between sessions and agents find the minimum that passes checks.

## Scope

4 mechanical enforcement improvements — all in bash scripts or pipeline docs.

### In scope
1. Plan-level DONE gate (hard stop between plans)
2. step-verify content validation (stronger regex)
3. plan.json init validation (reject empty steps)
4. Pipeline docs update (dispatch per E, validate per P)

### Out of scope
- Curator/Auditor as part of GATES (too invasive, changes FSM semantics)
- Per-EPIC synchronous C+A wait (kills parallelism)
- UI/frontend changes

## Approach

All changes are **mechanical (bash)** — no instruction-level fixes. Based on monitoring evidence: instruction-level rules degrade between sessions, bash enforcement works 100%.

---

## Phase A: Bash Enforcement (Steps 1-3)

### Step 1: Plan-level DONE gate in `aid-fsm.sh init`

**Objective:** `aid-fsm.sh init` refuses to initialize a new run if the previous plan has unprocessed Curator/Auditor reports (findings not reviewed).

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — `cmd_init()` function

**Architecture Context:** Currently `cmd_init()` only validates arguments and creates state.yaml. It has no awareness of previous runs or plans.

**Implementation Detail:**

Add to `cmd_init()` after argument validation, before state.yaml creation:

```bash
# Plan-level DONE gate: check if previous plan's C+A reports need review
# Find all state.yaml files in evidence that are in DONE/review
if [[ -d ".aid-o/work/evidence" ]]; then
  local current_plan_prefix
  current_plan_prefix=$(echo "$epic_id" | grep -oP '^P\d+' || true)

  while IFS= read -r prev_state; do
    local prev_epic prev_plan_prefix prev_done_phase
    prev_epic=$(grep '^epic_id:' "$prev_state" | awk '{print $2}')
    prev_plan_prefix=$(echo "$prev_epic" | grep -oP '^P\d+' || true)
    prev_done_phase=$(grep '^done_phase:' "$prev_state" | awk '{print $2}')

    # Only check EPICs from DIFFERENT plans (not same plan — those run in parallel)
    if [[ -n "$prev_plan_prefix" && -n "$current_plan_prefix" && \
          "$prev_plan_prefix" != "$current_plan_prefix" && \
          "$prev_done_phase" == "review" ]]; then

      # Check if C+A reports exist but have no review marker
      local prev_dir
      prev_dir=$(dirname "$prev_state")
      local has_unreviewed=false

      # Look for audit-report without corresponding review-complete marker
      if [[ -f "${prev_dir}/audit-report.md" && ! -f "${prev_dir}/ca-review-complete" ]]; then
        has_unreviewed=true
      fi

      if [[ "$has_unreviewed" == "true" ]]; then
        echo "PRECONDITION FAIL: Plan $prev_plan_prefix has unreviewed Curator/Auditor findings." >&2
        echo "Previous EPIC $prev_epic has audit-report but no ca-review-complete marker." >&2
        echo "Review findings, apply fixes, then: touch ${prev_dir}/ca-review-complete" >&2
        exit 1
      fi
    fi
  done < <(find .aid-o/work/evidence -name "fsm-state.yaml" 2>/dev/null)
fi
```

**Marker file:** `ca-review-complete` — created by orchestrator after reading all C+A reports and applying fixes for a plan. Simple touch file, no content needed.

**Edge cases:**
- First run ever (no previous evidence) → passes
- Same plan (P9-E001 → P9-E002) → passes (only cross-plan check)
- `--force` bypass → allowed with audit log

**Acceptance Criteria:**
- [ ] `init` blocked when previous plan has unreviewed C+A (different plan prefix)
- [ ] `init` passes for same-plan EPICs
- [ ] `init` passes when no previous evidence exists
- [ ] `--force` bypasses with audit log
- [ ] `ca-review-complete` marker unblocks

**Effort:** M
**AID Role:** backend
**Dependencies:** none

---

### Step 2: step-verify content validation in `aid-fsm.sh increment-step`

**Objective:** `increment-step` rejects step-verify.md files that contain only `## Result: PASS` without actual AC checklist and commit reference. Prevents "letter of the law" compliance.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — `cmd_increment_step()` function

**Architecture Context:** Currently checks: (1) file exists, (2) contains `## Result: PASS`. Agent learned to write minimal files that pass both checks.

**Implementation Detail:**

Add after the existing `## Result: PASS` check (line 323):

```bash
# Validate content quality — must contain AC checklist and commit reference
local ac_count commit_found
ac_count=$(grep -c '\- \[x\]' "$verify_file" 2>/dev/null || echo "0")
commit_found=$(grep -cP '[a-f0-9]{7,}' "$verify_file" 2>/dev/null || echo "0")

if [[ "$ac_count" -lt 1 ]]; then
  echo "PRECONDITION FAIL: Step verification has no acceptance criteria checklist." >&2
  echo "File: ${verify_file}" >&2
  echo "Must contain at least one '- [x] ...' item matching plan AC." >&2
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="verify_no_ac_checklist"
  exit 1
fi

if [[ "$commit_found" -lt 1 ]]; then
  echo "PRECONDITION FAIL: Step verification has no commit reference." >&2
  echo "File: ${verify_file}" >&2
  echo "Must contain at least one commit hash (7+ hex chars)." >&2
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="verify_no_commit_ref"
  exit 1
fi
```

**Edge cases:**
- Multi-step commit (step 1 references step 0 commit) → passes (has a hash)
- Steps without git changes (docs-only) → agent writes N/A hash or references parent commit
- `--force` bypass → allowed

**Acceptance Criteria:**
- [ ] Reject verify with only `## Result: PASS` (no `- [x]`, no hash)
- [ ] Accept verify with 1+ `- [x]` items and 1+ commit hash
- [ ] `--force` bypasses
- [ ] Failure logged to timeline.jsonl with reason

**Effort:** S
**AID Role:** backend
**Dependencies:** none

---

### Step 3: plan.json init validation

**Objective:** `aid-fsm.sh init` validates that plan.json steps have meaningful content (at least `objective` field), preventing empty skeleton plan.json files.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — `cmd_init()` function

**Architecture Context:** `cmd_init()` receives plan.json path. Currently doesn't validate content.

**Implementation Detail:**

Add after state.yaml creation in `cmd_init()`:

```bash
# Validate plan.json step content
local plan_json="${evidence_dir}/plan.json"
if [[ -f "$plan_json" ]]; then
  local empty_steps
  empty_steps=$(python3 -c "
import json, sys
d = json.load(open('$plan_json'))
steps = d.get('steps', [])
empty = [s['id'] for s in steps if 'objective' not in s or not s['objective']]
if empty:
    print(','.join(empty))
" 2>/dev/null || true)

  if [[ -n "$empty_steps" ]]; then
    echo "WARNING: plan.json has steps without 'objective' field: $empty_steps" >&2
    echo "Steps should have objective, acceptance_criteria, and role for quality dispatch." >&2
    # Warning only — not blocking (plan.json format varies between run-level and plan-level)
  fi
fi
```

**Note:** WARNING, not ERROR — plan.json format varies and we don't want to block valid but minimal plans. The warning is logged and visible to the orchestrator.

**Acceptance Criteria:**
- [ ] Warning printed when steps lack `objective`
- [ ] Does not block init (warning only)
- [ ] No warning when steps have `objective`
- [ ] Handles missing plan.json gracefully

**Effort:** S
**AID Role:** backend
**Dependencies:** none

---

## Phase B: Pipeline Documentation (Step 4)

### Step 4: Update pipeline.md §7 — dispatch per E, validate per P

**Objective:** Rewrite DONE state documentation to reflect the new model: C+A dispatch per EPIC (background OK), but mandatory review+fix checkpoint on plan boundaries. All findings (S+M+L) must be addressed.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — §7 DONE State
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` — DONE state section + MECHANICAL ENFORCEMENT PROTOCOL

**Implementation Detail:**

Replace current §7 DONE sub-phases with:

**Per-EPIC (background, non-blocking):**
- Steps 1-4 (run file, archive, active.md, final_report) — same as now
- Step 5: Dispatch C+A as background agents — OK to continue to next EPIC
- done_phase stays "review"

**Per-Plan checkpoint (HARD STOP after last EPIC):**
- After last EPIC of a plan completes:
  1. Wait for ALL pending C+A reports from all EPICs in this plan
  2. Read all reports, compile findings
  3. Apply ALL fixes (S+M+L) — not just S+M. L findings from monitoring were often trivial.
  4. CP4 verifier on fixes
  5. Create `ca-review-complete` marker in each EPIC's evidence dir
  6. PM Summary with MERGE/FIX/ABORT
  7. Only then can next plan's EPICs start (enforced by Step 1's init gate)

**Add to MECHANICAL ENFORCEMENT PROTOCOL:**
- Rule 13: `aid-fsm.sh init` blocks new plan if previous plan has unreviewed C+A findings
- Rule 14: Per-plan checkpoint — all C+A findings (S+M+L) must be addressed before next plan

**Acceptance Criteria:**
- [ ] §7 clearly separates per-EPIC (background C+A) from per-Plan (hard stop + fix)
- [ ] MECHANICAL ENFORCEMENT PROTOCOL has rules 13-14
- [ ] aid-run.md DONE section updated to match
- [ ] Explicitly states S+M+L (not just S+M)

**Effort:** M
**AID Role:** docs
**Dependencies:** Steps 1-3 (references the mechanical checks)

---

## Phase C: CHANGELOG + Version (Step 5)

### Step 5: CHANGELOG entry

**Objective:** Add entries to both CHANGELOGs for the enforcement improvements.

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `plugins/aid-orchestrator/CHANGELOG.md`

**Acceptance Criteria:**
- [ ] Both CHANGELOGs identical
- [ ] Entries under v2.7.0 Added section

**Effort:** S
**AID Role:** docs
**Dependencies:** Steps 1-4

---

## Testing Strategy

### Per-step testing (bash)
- Step 1: Create mock evidence dirs with/without ca-review-complete, test init blocking
- Step 2: Create minimal verify files, test rejection; create proper verify files, test acceptance
- Step 3: Create plan.json with/without objectives, test warning output

### End-to-end dry run
- Simulate 2-plan pipeline: Plan A (2 EPICs) → Plan B (1 EPIC)
- Verify Plan B init blocked until Plan A C+A review complete
- Verify marker file unblocks

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| step-verify regex too strict | Medium | Medium | `--force` bypass, only require 1 `[x]` and 1 hash |
| Plan-level gate false positive | Low | High | Same-plan EPICs exempt, `--force` available |
| python3 not available for plan.json check | Low | Low | Warning only, graceful fallback |

## Backward Compatibility

- Step 1: New behavior only — existing projects without evidence pass (no previous plans)
- Step 2: Existing verify files that already have AC + hash → pass. Minimal ones → fail (intentional)
- Step 3: Warning only — never blocks
- Step 4: Documentation change — no runtime impact

## Summary

| Step | What | Effort | Type |
|------|------|--------|------|
| 1 | Plan-level DONE gate (`init` blocks cross-plan) | M | Bash |
| 2 | step-verify content validation (AC + hash) | S | Bash |
| 3 | plan.json init warning | S | Bash |
| 4 | Pipeline docs (per E dispatch, per P validate) | M | Docs |
| 5 | CHANGELOG | S | Docs |
| **Total** | | **M** | 3 bash + 2 docs |
