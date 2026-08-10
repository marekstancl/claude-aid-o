---
id: P011
type: plan
status: done
created: 2026-02-26
author: PM + AI
---

# Plan: First AID Hardening

## Context

First AID (autonomous orchestration mode, `/aid-first-aid`) has bugs that can cause work loss, security issues, or silent failures. RESUME_SESSION skips in-progress EPICs because `next()` filters only `status=="queued"` (a running EPIC is lost), PM_APPROVAL guardrail reads an audit report that hasn't been generated yet (logic error), permission patterns are inconsistent between skill and policy files, and there's no disclaimer warning users that autonomous mode is experimental. After First AID completes, full permissions remain active instead of being reset to safe defaults.

These issues were identified via QA (E-20260224-fa01) and PM feedback during live First AID sessions.

## Goal

First AID mode is safe, recoverable, and transparent: interrupted EPICs resume correctly, permissions reset after completion, users see clear warnings, and all internal logic references are consistent.

## Scope

**In scope:**
- Fix RESUME_SESSION to pick up running EPICs (IMP-033)
- Fix PM_APPROVAL audit trend to read previous EPIC's report (IMP-040)
- Fix `su` pattern inconsistency between skill and policy (IMP-034)
- Add permission grant tracking to auto-mode-state.yaml (IMP-041)
- Add disclaimer/warning for autonomous mode
- Multi-agent First AID queue (spawn parallel agents for multiple EPICs)
- Permission reset after First AID completion
- Setup: add MCP tool permissions to full permissions preset

**Out of scope:**
- Orchestration engine refactoring (P012)
- GUI changes (P009)
- Token optimization (P013)

## Approach

### Option A: Single EPIC, critical-first (Chosen)

Fix the 3 critical bugs first (resume, audit, permissions), then add safety features (disclaimer, reset, multi-agent). One EPIC, ~6-8 steps.

**Pros:**
- Critical bugs fixed first — immediately safer
- Safety features build on fixed foundation
- Testable after each step

**Cons:**
- Multi-agent queue is a feature, not a fix — adds complexity

### Decision

**Chosen:** Option A
**Rationale:** The 3 bugs (IMP-033, IMP-040, IMP-034) are real data-loss and logic-error risks. Fix those first, then layer safety features on top.

## High-Level Steps

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | RESUME_SESSION fix | In `aid-first-aid.md`, add step after 3c: check `epic-queue.yaml` for `status: running`, reset to `queued` before `next()` call | S |
| 2 | PM_APPROVAL audit fix | Clarify guardrail to read previous EPIC's `audit-report.md`, not current (which doesn't exist yet) | S |
| 3 | Permission pattern fix | Standardize `"Bash(su:*)"` (no space) in `permission-sandwich.md` Sections 3.1 and 7 to match `permissions-auto.yaml` | S |
| 4 | Disclaimer | Add warning block to `/aid-first-aid` command output: "Autonomous mode is experimental. AI will execute commands, modify files, and make git commits without asking. Use at your own risk." | S |
| 5 | Permission reset | After First AID completes (all queue processed or stopped), restore permissions to pre-First-AID state from saved snapshot | M |
| 6 | Permission grant tracking | Add `permissions.grant_log` to `auto-mode-state.yaml` — log each grant with source, actor, step ref, timestamp | S |
| 7 | Multi-agent queue | Enable spawning parallel First AID agents for independent EPICs in queue (respects dependency ordering) | M |
| 8 | Setup MCP permissions | Add MCP tool patterns to full permissions preset in setup wizard | S |

## Constraints

- All changes in `plugins/aid-orchestrator/` (skills, commands, defaults)
- Must not break existing manual-mode orchestration
- Permission reset must be atomic (either fully restored or not at all)
- Multi-agent queue must respect EPIC dependencies

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Permission reset removes PM-intended grants | medium | medium | Snapshot pre-First-AID permissions, restore only those — not a hard reset |
| Multi-agent parallel dispatch causes file conflicts | medium | high | Only parallelize EPICs with non-overlapping file scopes |
| Disclaimer scares away users | low | low | Frame as "experimental" not "dangerous"; emphasize `/aid-stop` availability |

## Success Criteria

- `/aid-first-aid --resume` picks up interrupted (status: running) EPIC
- PM_APPROVAL guardrail reads correct (previous) audit report
- `su` deny pattern catches all variants (su, su-l, su root)
- First AID shows disclaimer before starting
- Permissions restored to pre-First-AID state after completion
- Grant log tracks all permission changes during autonomous mode
- Parallel First AID agents run without file conflicts

## Next Steps

- [ ] Create EPIC for P011
- [ ] Generate execution plan
- [ ] Run EPIC

---

**Last Updated:** 2026-02-26
