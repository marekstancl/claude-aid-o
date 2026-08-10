---
id: P008
type: plan
status: done
created: 2026-02-25
author: PM + AI (brainstorming session)
---

# P008 — FIRST AID Pipeline Fixes: Curator, Qdrant, Resilience, Wiring & Animations

## Context

Post-mortem analysis of FIRST AID session FA-20260225T140000Z (4 EPICs, 23 steps, 314 tests)
revealed 6 issues ranging from bugs to missing features. The session completed successfully
but with degraded quality: Curator never ran (bug), Qdrant metrics never stored (config),
one agent ran out of credits mid-task (no resilience), parallel steps left shared files
unwired (no wiring step), FIRST AID banners lack the designed ASCII art animations,
and completed EPICs/plans are not archived.

## Goal

Fix all 6 identified issues in a single EPIC so the next FIRST AID session runs with
full Curator integration, Qdrant metric storage, credit exhaustion resilience, automatic
wiring of parallel outputs, themed ASCII art animations, and proper archival of completed
work.

## Scope

### In-Scope

- Fix GATES → CURATOR_RESOLVE state transition in epic-orchestration.md
- Add auto-mode conditionals for CURATOR_RESOLVE in aid-first-aid.md
- Add Curator findings section to FIRST AID completion report
- Unify memory config (single source of truth in memory-config.yaml)
- Add Qdrant startup probe and config validation
- Add credit exhaustion detection + auto-pause in PHASE_CHECK
- Add interrupted step resume in FIRST AID --resume flow
- Add automatic wiring step generation in planner.md wave assembly
- Add wiring step recognition in epic-orchestration.md EXECUTING state
- Redesign FIRST AID startup banner (ASCII art stříkačka → injekce → power-up)
- Redesign FIRST AID completion banner (depleted theme + Curator findings)
- Add EPIC archival after DONE state (move to archive/)
- Add plan archival after all plan EPICs complete

### Out-of-Scope

- CC credit check API integration (waiting for upstream feature)
- Qdrant infrastructure changes (MCP server already configured)
- Frontend/GUI changes
- New orchestration states beyond fixing existing flow

## Approach

**Chosen: Depth-first (Option A)** — each fix is a dedicated step with full audit and
cross-reference validation. A final cross-validation step ensures all fixes work together.

**Rejected alternatives:**
- Quick-patch (Option B): Too shallow — Curator fix without audit may have edge cases
- Feature-grouped (Option C): Batch steps too large for single agent

## Decision

Single EPIC, 7 steps (6 fixes + cross-validation), depth-first approach. All changes
are .md skill/command files in the same plugin — no production code, low risk.

## High-Level Steps

### Step 1: Curator Fix — GATES Transition + Auto-Mode (effort: M)
**Files:** `epic-orchestration.md`, `aid-first-aid.md`

1. Fix GATES state: change transition target from PM_APPROVAL to CURATOR_RESOLVE
2. Audit CURATOR_RESOLVE state definition for consistency with state machine diagram
3. Add auto-mode conditional block to CURATOR_RESOLVE:
   - Auto-evaluate proposals via 3-tier algorithm (YAML rules → Qdrant similarity → default)
   - APPROVED + effort S → dispatch fix agent inline
   - APPROVED + effort M/L → defer to backlog with urgency tag
   - REJECTED → log reason
   - Auto-defer on inline fix failure (non-blocking)
4. Add Curator findings section to FIRST_AID_COMPLETE report:
   - All proposals listed with decision + reason
   - Deferred items with urgency recommendation (HIGH/MEDIUM/LOW)
   - Icons: [OK] implemented, [!!] deferred-review, [..] deferred-low, [--] rejected
5. Add curator_resolve_report.json to evidence artifacts

### Step 2: Qdrant Config Unification (effort: S)
**Files:** `memory-config.yaml`, `project-profile.yaml`, `epic-orchestration.md`

1. Change memory-config.yaml: `enabled: false` → `enabled: true`
2. Remove `memory.enabled` from project-profile.yaml (keep provider/collection/url as reference)
3. Add startup probe in IDLE state of epic-orchestration.md:
   - If enabled: probe qdrant-store tool availability
   - If tool missing: WARN (non-blocking)
   - If disabled: LOG info
4. Audit all qdrant-store/memory_store() call sites for consistency with memory-mcp.md

### Step 3: Credit Exhaustion Auto-Pause (effort: M)
**Files:** `epic-orchestration.md`, `aid-first-aid.md`

1. Add AGENT_OUTPUT_VALIDATION block in PHASE_CHECK (before normal evaluation):
   - Empty/null output → INCOMPLETE
   - Output contains CC credit error strings → CREDIT_EXHAUSTED
   - Output < 20% expected length → POSSIBLY_TRUNCATED (warning only)
2. On CREDIT_EXHAUSTED:
   - Save state: plan_progress (status: interrupted), interrupted_step_context.json, git stash
   - Set auto-mode-state: mode=paused, reason=credit_exhaustion
   - STOP gracefully
3. Extend RESUME_SESSION in aid-first-aid.md:
   - Detect interrupted_step_context.json
   - git stash pop + re-dispatch agent with saved context
4. Add known limitation entry to lessons-learned.md

### Step 4: Wiring Step in Planner (effort: M)
**Files:** `planner.md`, `plan.schema.json`, `epic-orchestration.md`

1. Add POST_WAVE_WIRING_CHECK in planner.md wave assembly:
   - Collect allowed_paths from all steps in each parallel wave
   - Find shared files (appearing in 2+ steps)
   - If found: auto-generate wiring step with context (shared_files, contributing_steps, expected_actions)
   - Insert after parallel wave
2. Add `wiring` boolean + `wiring_context` object to plan.schema.json step schema
3. Add wiring step recognition in epic-orchestration.md EXECUTING state:
   - Agent prompt includes wiring_context
   - Instructions: integrate, don't rewrite; run type-check to validate

### Step 5: FIRST AID Animations (effort: M)
**Files:** `aid-first-aid.md`

1. Redesign startup banner (Section 10):
   - ASCII art: stříkačka with "AID" label → injection into "CLAUDE CODE" → power-up/enlarge effect
   - 4 sequential frames (Controller outputs progressively)
   - Final frame: static tuned AID logo + session info + queue summary (EPIC list with descriptions)
   - Max width: 72 chars (80-col terminal with 2-space indent)
2. Redesign completion banner (FIRST_AID_COMPLETE Section 3):
   - "Depleted" variant (empty syringe / smaller logo)
   - Curator findings section
   - Queue results table
   - Closing: "Steroids depleted. Patient survived. {N}/{N} EPICs completed."
3. Update resume banner for consistency ("Re-injecting..." variant)
4. Creative brief in EPIC for agent: constraints, theme description, PM approval of art

### Step 6: EPIC & Plan Archival (effort: S)
**Files:** `epic-orchestration.md`, `aid-first-aid.md`

1. Add archival step in DONE state (after merge, before QUEUE_ADVANCE):
   - Move completed EPIC file from `.aid-o/02-epics/{epic}.md` to `.aid-o/02-epics/archive/{epic}.md`
   - Log: "Archived EPIC {epic_id}"
2. Add plan archival in FIRST_AID_COMPLETE / QUEUE_ADVANCE:
   - After all EPICs from a plan complete: check if plan has remaining queued EPICs
   - If none: move plan from `.aid-o/01-plans/{plan}.md` to `.aid-o/01-plans/archive/{plan}.md`
   - Log: "Archived plan {plan_id} — all EPICs completed"
3. Ensure archive/ directories exist (mkdir -p)
4. Update aid-first-aid.md completion report to show archival status

### Step 7: Cross-Validation (effort: S)
**Files:** all modified files

1. Read all modified files end-to-end
2. Verify state machine consistency: GATES → CURATOR_RESOLVE → PM_APPROVAL
3. Verify auto-mode conditionals exist at all PM decision points
4. Verify Qdrant store calls are present at PHASE_CHECK and DONE
5. Verify credit detection doesn't conflict with normal PHASE_CHECK flow
6. Verify wiring step schema matches planner output
7. Verify animation banners fit in 72-char frame
8. Verify archival doesn't break any file path references

## Constraints

- All changes are markdown skill/command files — no production code
- Must preserve backwards compatibility with manual (non-auto) mode
- ASCII art must render correctly in standard 80-column terminals
- Curator inline fixes limited to effort:S to minimize risk
- Credit detection is string-matching (no CC API available)
- Qdrant MCP server must be running for metrics to work (graceful degradation if not)

## Risks

| # | Risk | Probability | Impact | Mitigation |
|---|------|-------------|--------|------------|
| 1 | Curator inline fix breaks code | Low | High | Effort guardrail (S only), auto-defer on failure |
| 2 | Credit detection false positive | Very low | Medium | Match specific CC error strings only |
| 3 | Wiring step unnecessary (agents self-wire) | Medium | Low | Wiring step verifies + complements, no-op if OK |
| 4 | Qdrant unavailable after enabling | Low | Low | Startup probe + graceful degradation |
| 5 | GATES→CURATOR_RESOLVE breaks manual mode | Low | Medium | CURATOR_RESOLVE defined for both modes |
| 6 | ASCII art renders badly in some terminals | Medium | Low | Basic box-drawing + ASCII only, test in 80-col |
| 7 | Resume finds inconsistent state after credit crash | Low | High | interrupted_step_context.json + git stash |

## Success Criteria

- [ ] Next FIRST AID session runs CURATOR_RESOLVE for every EPIC (non-zero proposals in report)
- [ ] Qdrant metrics stored at PHASE_CHECK and DONE (verifiable via qdrant-find)
- [ ] Credit exhaustion during test triggers auto-pause + successful resume
- [ ] Plan with parallel wave + shared files generates wiring step in plan.json
- [ ] FIRST AID startup shows ASCII art animation with stříkačka theme
- [ ] FIRST AID completion shows depleted theme + Curator findings
- [ ] Completed EPICs are in archive/ directory after DONE
- [ ] Completed plans are in archive/ after all EPICs done

## Next Steps

- Generate EPIC from this plan
- Queue for execution via /aid-first-aid or /aid-run-epic
