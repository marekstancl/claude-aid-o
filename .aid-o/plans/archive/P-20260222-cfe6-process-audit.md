---
id: P-20260222-cfe6
type: plan
status: done
created: 2026-02-22
author: PM + AID
depends_on: P-20260223-a8f1
---

# Plan: Process Audit — Auditor Self-Audit Extension

## Context

The AID Orchestrator auditor currently audits EPIC *outputs* (plugin files, changelogs, versions,
code quality, security) but has a blind spot: it does not audit the *orchestration process itself*.
Discovered during EPIC E-20260221-91c4 when the EPIC's `status: completed` frontmatter update was
not committed (`.aid-o/` is gitignored) and the auditor did not flag it. A second gap emerged:
the Wave table in `final_report.md` had an inaccuracy (L4 finding) that a process cross-validation
would have caught automatically.

The auditor cannot audit itself — this plan closes that gap.

**Dependency on P-20260223-a8f1 (Curator Resolve Pipeline):** That plan adds a CURATOR_RESOLVE
state between GATES and PM_APPROVAL, producing new evidence artifacts (`curator_resolve_report.json`,
`curator_fixes/` directory, CURATOR_RESOLVE stage_log entries). This plan must run AFTER P-a8f1
so that process audit checks cover the full state machine including CURATOR_RESOLVE.

## Goal

Extend `agents/auditor.md` with a `process` audit type that verifies EPIC lifecycle state,
evidence completeness, cross-validation consistency, and stage log integrity after every EPIC run.

## Scope

**In scope:**
- New `process` audit type in `agents/auditor.md` (ALWAYS-run)
- 17 checks across 5 categories: EPIC lifecycle, evidence completeness, cross-validation, stage log integrity, CURATOR_RESOLVE pipeline
- Process score (0-100) with deduction-based scoring
- Updated weight redistribution: Code 30%, Security 30%, Documentation 25%, Process 15%
- Updated Score Overview template in audit-report.md output format

**Out of scope:**
- New agent or separate file for process audit
- Changes to `run-epic.md` dispatch logic
- Changes to `epic-orchestration.md`
- Automated test infrastructure
- Auditing the auditor's own output (meta-audit)

## Approach

**Chosen: Extend auditor.md directly**

Add `process` as a 6th audit type inside the existing `agents/auditor.md`. The auditor already
reads `evidence_dir` and `epic_file` — process checks use the same inputs. No new dispatch,
no new files, no new architecture.

**Rejected alternatives:**
- *Separate `process-auditor.md` agent* — over-engineering for 13 mechanical checks; adds dispatch
  complexity in DONE state and requires merging two audit reports.
- *Extend documentation audit* — wrong separation of concerns; would distort documentation scoring.

## Decision

Extend `agents/auditor.md` with `process` audit type. Single file change, YAGNI-compliant,
consistent with existing auditor architecture.

## High-Level Steps

1. **Read and analyze `agents/auditor.md`** — understand current structure, Audit Conditions table,
   Weight Redistribution section, Score Overview template format. Identify exact insertion points.
   Effort: XS

2. **Add Process Audit section to `auditor.md`** — insert `## Process Audit` section with:
   - Audit Conditions entry: `Process Audit: ALWAYS — run`
   - 5 categories, 17 checks with severity (High/Medium/Low) and deduction values
   - Scoring formula and deduction table
   - Cross-validation logic for step count, gate results, discovered issues
   - Stage log timestamp chronology check
   - CURATOR_RESOLVE pipeline checks (see below)
   Effort: S

   **Category 5: CURATOR_RESOLVE Pipeline** (4 checks, added by P-20260223-a8f1 dependency):

   | # | Check | Severity | Deduction | Description |
   |---|-------|----------|-----------|-------------|
   | 14 | `curator_resolve_report.json` exists | High | -10 | Evidence file must exist in `evidence/{epic_id}/{run_id}/` when CURATOR_RESOLVE state was entered |
   | 15 | Proposal count matches backlog | Medium | -5 | Number of proposals in `curator_resolve_report.json` must match new/updated entries in `backlog.md` for this EPIC |
   | 16 | Fix evidence completeness | Medium | -5 | Each approved+implemented proposal must have a corresponding `curator_fixes/fix_{IMP_id}/` directory with at least one file |
   | 17 | CURATOR_RESOLVE stage_log entries | High | -10 | Stage log must contain `dispatch_parallel`, at least one `auto_evaluate` (if proposals > 0), and `transition` entries for CURATOR_RESOLVE state |

   **Graceful handling:** If the EPIC ran on a pre-CURATOR_RESOLVE version (no CURATOR_RESOLVE
   entries in stage_log), skip checks 14-17 entirely — not a finding. Only flag when
   CURATOR_RESOLVE was entered but evidence is incomplete.

3. **Update weight redistribution and Score Overview template** — change from 3 always-run types
   (code, security, documentation) to 4 (+ process), update percentage weights, add Process row
   to the `audit-report.md` Score Overview table template.
   Effort: XS

4. **Verify with existing evidence** — run a conceptual walkthrough against
   `E-20260221-91c4/run_20260221_d7b6/` to confirm the 13 checks would produce expected results
   (Process score ≥ 90 for a clean run, High finding for `epic.status` if it were `active`).
   Effort: XS

## Constraints

- Only `agents/auditor.md` is modified — no other files
- Process checks must be mechanically described (file exists? field matches? count equals?)
  so the auditor agent can execute them deterministically
- Deductions must not allow negative scores (floor at 0)
- `gates_report.json` absence is not a finding (gates may be legitimately skipped)
- Timestamp validation tolerates sub-second variance — compare at minute granularity

## Risks

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Auditor prompt too long → agent skips process section | Low | Process section at end with TL;DR header |
| False positives on timestamp validation | Medium | Compare at minute granularity only |
| `gates_report.json` absent for skip-only runs | Medium | Skip check 11 when file absent — not a finding |
| Evidence paths change in future version | Low | Paths are parametrized via `{run_id}` in prompt |

## Success Criteria

- [ ] `agents/auditor.md` contains `## Process Audit` section with all 5 categories and 17 checks
- [ ] Audit Conditions table includes `Process Audit: ALWAYS`
- [ ] Weight redistribution updated: Code 30%, Security 30%, Documentation 25%, Process 15%
- [ ] Score Overview template includes `| Process | X | STATUS |` row
- [ ] Conceptual walkthrough against E-20260221-91c4 evidence produces Process score ≥ 90
- [ ] Today's gap (epic.status not committed) would produce a High finding in process audit
- [ ] CURATOR_RESOLVE checks (14-17) validate: report existence, proposal↔backlog consistency, fix evidence, stage_log entries
- [ ] Pre-CURATOR_RESOLVE EPICs gracefully skip checks 14-17 (no false positives on old evidence)

## Next Steps

- [ ] Wait for P-20260223-a8f1 (Curator Resolve Pipeline) to complete
- [ ] Create EPIC from this plan and run via `/aid-run-epic`
