---
id: P012
type: plan
status: done
created: 2026-02-26
author: PM + AI
---

# Plan: Orchestration Quality — Security, Planner & Maintainability

## Context

AID orchestration engine has security gaps, planner inefficiencies, and maintainability issues. Dispatch prompt templates embed EPIC descriptions and PM-supplied content without `<untrusted_content>` tags (prompt injection risk per CWE-77/OWASP LLM01). The security deny-list uses substring matching that's bypassable by flag reordering (`rm -r -f /` bypasses `rm -rf /` pattern). The planner separates backend and frontend into sequential sessions instead of parallelizing them, and creates coarse-grained steps that prevent early parallelization.

Additionally, `epic-orchestration.md` has grown to 2100+ lines with auto-mode conditionals embedded inline, and the DONE state release logic is duplicated between `epic-orchestration.md` and `auto-done-state.md`.

## Goal

Dispatch prompts are injection-safe, deny-list catches destructive command variants, planner maximizes parallelism, PLAN_REVIEW gives PM actionable detail, the orchestration skill file is modular and maintainable, and instruction files are audited for quality and clarity.

## Scope

**In scope:**
- Add `<untrusted_content>` tags to all dispatch prompt templates (IMP-028)
- Improve security deny-list: allowlist approach for Bash destructive commands (IMP-042)
- Split `epic-orchestration.md` into focused modules (IMP-036/037) — prerequisite for P013
- Enrich PLAN_REVIEW template with per-step detail (IMP-011)
- Planner parallel strategy: parallelize backend + frontend after architect/domain (IMP-012)
- Finer step granularity in planner (IMP-013)
- Consolidate DONE state release logic to single source (IMP-036)

**Out of scope:**
- Token optimization (P013 — depends on the split done here)
- First AID fixes (P011)
- GUI changes (P009)
- DX/housekeeping (P010)

## Approach

### Option A: Single EPIC, security-first (Chosen)

Security fixes (prompt injection, deny-list) first, then planner improvements, then maintainability refactoring. One EPIC, ~8 steps.

**Pros:**
- Security gaps closed immediately
- Planner improvements benefit all subsequent EPICs
- Split is prerequisite for P013 — unblocks flow optimization

**Cons:**
- Planner changes affect all future plan generation — needs thorough testing

### Decision

**Chosen:** Option A
**Rationale:** Security is highest priority (prompt injection is a real risk in multi-agent dispatch). Planner improvements have high leverage — every future EPIC benefits. The split enables P013.

## High-Level Steps

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | Dispatch prompt sanitization | Wrap all untrusted interpolations in `<untrusted_content>` tags in `aid-run-epic.md` dispatch templates | M |
| 2 | Security deny-list hardening | Supplement substring matching with allowlist approach for Bash destructive commands. Document in `permission-sandwich.md`. | M |
| 3 | Split epic-orchestration.md | Extract into: `epic-state-machine.md` (core FSM), `dispatch-protocol.md` (agent dispatch), `gate-evaluation.md` (quality gates), `first-aid-controller.md` (auto-mode conditionals). Main file becomes orchestrator with references. | M |
| 4 | PLAN_REVIEW rich template | Define template requiring per-step: files to create/modify, technologies used, AC count, estimated output size, dependencies. Update `epic-orchestration.md` (or new `dispatch-protocol.md`). | S |
| 5 | Planner parallel strategy | Rewrite session split rules: after architect+domain, parallelize backend + frontend. Update `planner.md` parallelism rules. | M |
| 6 | Finer step granularity | Update planner to split large domain steps by layer (data-layer → schemas → routers) for earlier parallelization. Add granularity heuristics to `planner.md`. | M |
| 7 | DONE state consolidation | Refactor `epic-orchestration.md` DONE state to delegate all auto-mode release behavior to `auto-done-state.md` as single source of truth. | S |
| 8 | Instruction file quality audit | Add conditional `/aid-audit` section (only when `plugins/aid-orchestrator/` exists): check every skill/command/agent for intro explaining WHAT and WHY, no TODO/FIXME/placeholders, consistent frontmatter and sections, cross-references resolve to existing files, file length warning above 800 lines. | M |

## Constraints

- All changes in `plugins/aid-orchestrator/` (skills, commands)
- Split must preserve all existing behavior — pure refactoring, no logic changes
- Planner changes must be backwards-compatible (existing EPICs still valid)
- Security fixes must not break legitimate Bash usage

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Split introduces broken cross-references | medium | medium | Grep all references before and after split; automated cross-reference check |
| Planner parallelism causes file conflicts in generated plans | medium | high | File ownership validation in plan generation; test with 3+ real EPIC specs |
| Allowlist approach blocks legitimate commands | low | medium | Start with narrow allowlist for known-destructive patterns only; log blocked commands |

## Success Criteria

- All dispatch prompts wrap untrusted content in `<untrusted_content>` tags
- `rm -r -f /`, `find / -delete`, `rm --recursive --force /` all caught by deny-list
- `epic-orchestration.md` split into 4+ focused files, each < 600 lines
- PLAN_REVIEW shows files, technologies, AC count for each step
- Planner generates parallel groups for independent backend + frontend steps
- DONE state release logic exists in exactly one file
- `/aid-audit` in AID repo reports instruction file quality (intro, no TODOs, cross-refs valid, length warnings)

## Next Steps

- [ ] Create EPIC for P012
- [ ] Generate execution plan
- [ ] Run EPIC (P012 step 3 unblocks P013)

---

**Last Updated:** 2026-02-26
