---
id: P002
type: plan
status: done
created: 2026-02-23
author: PM + AID
depends_on: null
---

# Plan: Core Structure Refactoring

## Context

AID Orchestrator has grown organically through 11+ EPIC runs and 8+ versions. Several
structural issues have accumulated that need resolution before further feature development:

1. **Terminology:** "SESSION" is misleading — it evokes user sessions, not pipeline execution runs.
2. **Information gap:** EPIC contains ~400 lines while PLAN has ~2000 lines. Agents only receive
   the EPIC during execution, losing 80% of implementation context. The `plan_ref` field exists
   but agents never actually read the source plan.
3. **ID scheme:** Current UIDs (`P-20260223-05aa`) are non-sequential, hard to reference in
   conversation, and don't encode relationships between PLAN/EPIC/RUN.
4. **Cost/budget references:** Budget estimates appear in EPIC templates and brainstorming skill
   despite being inaccurate and unhelpful.
5. **Dead evidence directories:** 5 of 7 evidence subdirectories (`analysis/`, `discovered_issues/`,
   `parallel_groups/`, `prompts/`, `reviews/`) are empty across all 11 runs. The Controller
   creates them but never writes to them because instructions are buried and deprioritized.

This refactoring is a **prerequisite** for Clusters C1, C3, C5, and future work. Changing
the structure after building on top of it would be significantly more expensive.

## Goal

Refactor AID's core file structure, terminology, ID scheme, and evidence architecture to
create a clean, consistent foundation for v1.0.0 features.

## Scope

**In scope:**
- Rename SESSION → RUN across all files (skills, commands, agents, templates, defaults)
- Implement sequential autoincrement ID scheme: `P001`, `E-001-1_3`, `R-001-1_3-1`
- Add plan_ref content injection in Controller dispatch (agent receives relevant PLAN section)
- Flatten evidence structure: merge all subdirs into `steps/step_N_role/`
- Update Controller instructions to make evidence writing mandatory (not optional)
- Update Auditor to detect incomplete evidence as a finding
- Remove all budget/cost/price references from templates and skills
- Migrate existing plans, EPICs, and evidence to new structure
- Create `counter.yaml` for autoincrement tracking

**Out of scope:**
- Content changes to existing plans or EPICs (only structural migration)
- New features or capabilities
- GUI changes (GUI plan will adapt to new structure later)
- Release protocol changes (handled by P001)

## Approach

**Chosen: Single coordinated refactoring EPIC**

All changes are interdependent — renaming SESSION→RUN affects the same files as ID scheme
changes, which affect the same files as evidence restructuring. Doing them separately would
mean touching the same 30+ files multiple times.

**Rejected alternatives:**
- *Incremental changes (one per EPIC)* — Would require 4-5 separate EPICs touching overlapping
  files. Each EPIC would need to handle partial migration state. More total effort.
- *Automated migration script* — AID is a markdown-only plugin. No executable code to write
  migration scripts. All changes are manual (AI agent edits).

## Decision

Single EPIC with two phases:
- Phase 1: Audit + decision confirmation (verify all changes, identify all affected files)
- Phase 2: Implementation (execute all changes in coordinated manner)

## High-Level Steps

**Priority note:** Step 1 (plan_ref injection) is the highest priority — it directly improves
agent output quality by closing the 80% information gap. Documentation updates are last.

1. **Implement plan_ref content injection** — Modify `epic-orchestration.md` dispatch template
   to include: "Read plan_ref, extract section matching current step's Plan Task reference,
   include as implementation context in agent prompt." This closes the 80% information gap
   between PLAN (2000 lines) and EPIC (400 lines). Agents receive the full design context
   for their specific step.
   Effort: S

2. **Audit all affected files** — Scan every file in `plugins/aid-orchestrator/` and `.aid-o/`
   for references to: "session" (as terminology), UID patterns, budget/cost, evidence subdirectory
   creation. Produce a complete change manifest.
   Effort: S

3. **Implement counter.yaml and ID generation logic** — Create `.aid-o/03-config/counter.yaml`
   with current counters. Define ID generation rules in a new section of `epic-orchestration.md`.
   ID format: `P001`, `E-001-1_3`, `R-001-1_3-1`. Ad-hoc EPICs: `E-002`. Single-phase: `E-001-1_1`.
   Effort: S

4. **Rename SESSION → RUN** — All skills, commands, agents, templates, defaults. Update file
   references, variable names, section headers, documentation text. Rename `sessions/` directory
   to `runs/`. Update `session-management.md` → `run-management.md` (or equivalent).
   Effort: M

5. **Flatten evidence structure** — Remove creation of `analysis/`, `discovered_issues/`,
   `parallel_groups/`, `prompts/`, `reviews/` from `aid-run-epic.md`. All evidence goes into
   `steps/step_N_role/` (output.md, gate_result.md, prompt.md, review.md as needed).
   Update Controller instructions to write prompt and review artifacts into step directories.
   Make evidence writing a mandatory checklist item in dispatch flow.
   Effort: S

6. **Update Auditor for evidence completeness** — Add finding type: "evidence_incomplete" —
   Auditor checks that each completed step has at minimum `output.md` in its step directory.
   Flag empty step directories or missing outputs.
   Effort: XS

7. **Remove budget/cost references** — Remove from: EPIC template, brainstorming skill
   (EPIC subagent template budget estimate), any other occurrences found in Step 2 audit.
   Effort: XS

8. **Migrate existing data** — Rename existing session files, update evidence directory structure
   for historical runs (or archive as-is with a note). Update existing plan/EPIC IDs in
   frontmatter to new scheme. This is a one-time migration.
   Effort: S

9. **Verification and documentation** — Walk through a complete `/aid-run-epic` flow mentally
   against the updated instructions. Verify: ID generation works, plan_ref injection is in
   dispatch, evidence lands in correct directories, RUN terminology is consistent, no orphaned
   references. Update any remaining documentation references.
   Effort: S

## Constraints

- All changes are to markdown files (skills, commands, agents, templates) — no executable code
- Must not break current `/aid-run-epic` flow during migration
- Historical evidence can be archived as-is (no requirement to restructure old runs)
- Counter must handle concurrent sessions gracefully (though unlikely in single-user context)
- New ID scheme must be backwards-traceable (mapping from old UIDs to new IDs documented)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Missed references (SESSION still appears somewhere) | Medium | Low | Step 1 audit produces exhaustive manifest; Step 9 verification catches stragglers |
| plan_ref injection bloats agent context | Low | Medium | Inject only the relevant section (one High-Level Step), not the entire plan |
| Counter.yaml corruption/race condition | Very Low | Medium | Single-user tool; counter is simple increment; backup before write |
| Migration breaks active EPIC | Low | High | Complete all active EPICs before starting this refactoring |
| Auditor false positives on evidence | Medium | Low | Tune detection: only flag completed steps, not in-progress |

## Success Criteria

- [ ] Zero occurrences of "session" (as AID terminology) in `plugins/aid-orchestrator/` — all replaced with "run"
- [ ] `counter.yaml` exists and tracks sequential IDs for plans, EPICs, and runs
- [ ] New plans/EPICs/runs use autoincrement IDs: `P001`, `E-001-1_3`, `R-001-1_3-1`
- [ ] Agent dispatch includes relevant PLAN section content (plan_ref injection working)
- [ ] Evidence structure is flat: only `steps/step_N_role/` under each run directory
- [ ] Controller instructions include mandatory evidence write checklist
- [ ] Auditor detects and reports incomplete evidence
- [ ] Zero budget/cost/price references in templates and skills
- [ ] Existing data migrated or archived with mapping document

## Next Steps

- [ ] Create EPIC from this plan
- [ ] Complete all active EPICs before starting execution
- [ ] Run via `/aid-run-epic`
