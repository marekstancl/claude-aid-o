---
id: P024
type: plan
status: done
created: 2026-03-13
author: PM + Claude Opus 4.6
source: Brainstorming session — plugin path resolution bug, brainstorming compliance, doc gate
version: v2.5.0
---

# Plan: v2.5.0 — Plugin Path Resolution, Brainstorming Compliance, Doc Gate

## Context

v2.4.0 revealed a critical architectural issue: dispatched LLM agents cannot find plugin scripts. Commands reference `scripts/aid-fsm.sh` as relative paths, but the scripts live in the plugin installation directory (`~/.claude/plugins/marketplaces/claude-aid-o/plugins/aid-orchestrator/scripts/`), not in the target project. This causes `/aid-run` to skip FSM, curator, auditor — effectively breaking the pipeline.

Additionally:
- Brainstorming skill has recommendation rules but no format example → LLM ignores them
- No mandatory documentation step after EPIC completion
- Superpowers skills bypass AID pipeline — conflict defined but not enforced in CLAUDE.md
- Brainstorming handoff lacks summary and direct execution options

---

## Change A: Plugin Path Discovery (Critical)

### Problem

10+ files reference `scripts/aid-*.sh` as bare relative paths. LLM runs them in project CWD → file not found. Affected: `aid-run.md`, `aid-plan.md`, `aid-status.md`, `aid-help.md`, `pipeline.md`, `quality-gates.md`, `run-management.md`, `planner.md`.

### Solution: Single Protocol + Config

Add ONE "Script Execution Protocol" to `agent-core.md` that all agents learn. Store path in separate `config/plugin.yaml`.

1. `/aid-init` discovers plugin path via glob, writes to `.aid-o/config/plugin.yaml`
2. `agent-core.md` gets "Script Execution Protocol" section (4-step resolution)
3. `/aid-run` PRE-FLIGHT and `/aid-do` Step 1 verify plugin_path (cache invalidation)
4. `agent-protocol.md` dispatch context includes `plugin_path`

### Files

| File | Change |
|------|--------|
| `commands/aid-init.md` | Plugin discovery step + `config/plugin.yaml` to lazy-created table |
| `skills/agent-core.md` | Script Execution Protocol section |
| `skills/agent-protocol.md` | `plugin_path` in dispatch context YAML |
| `commands/aid-run.md` | PRE-FLIGHT plugin_path verification |
| `commands/aid-do.md` | Step 1 plugin_path verification |

---

## Change B: Brainstorming Recommendation Format

### Problem

Rules 2 and 8 mandate recommendations but LLM doesn't comply — no format template.

### Solution

1. Update Rule 8 — add Effort/Risk requirement
2. Add Question Format Template after Rule 11
3. Add concrete webhook example

### Files

| File | Change |
|------|--------|
| `skills/brainstorming.md` | Rule 8 update + format template + example |

---

## Change C: Documentation Gate

### Problem

No step mandates docs update. `docs_updated` gate verifies but doesn't enforce.

### Solution: Path-pattern correlation

Only fail when API-relevant paths (`routes/`, `api/`, `endpoints/`, `models/`) changed without docs update. Targeted reminder for backend/frontend steps. Auditor escalates missing API docs to high severity.

### Files

| File | Change |
|------|--------|
| `defaults/execution.yaml` | Path-pattern correlation for docs_updated |
| `skills/pipeline.md` §4 | Targeted docs reminder for backend/frontend steps |
| `agents/auditor.md` | Missing API docs = high severity |

---

## Change D: Bug Fix — aid-plan.md Step Denominators

Steps 1-7 show `/8` but should be `/9` (CP1 added Step 9). 7 lines need fixing.

### Files

| File | Change |
|------|--------|
| `commands/aid-plan.md` | `/8` → `/9` in Steps 1-7 (lines 66-90) |

---

## Change E: Superpowers Override in CLAUDE.md

### Problem

`superpowers:brainstorming` bypasses AID. Conflict in `orchestration.yaml` but not in CLAUDE.md.

### Solution

Add Superpowers conflict resolution table to `setup/claude-md.md` template. Add 2 new `skill_conflicts` entries to `orchestration.yaml`.

### Files

| File | Change |
|------|--------|
| `skills/setup/claude-md.md` | Superpowers conflict section in CLAUDE.md template |
| `defaults/orchestration.yaml` | 2 new skill_conflicts (writing-plans, executing-plans) |

---

## Change F: Enhanced Brainstorming Handoff

### Problem

Handoff has 4 sparse options, no summary, references deleted `/aid-plan-epic`.

### Solution

Replace handoff with summary block + 6 options (including `/aid-run --auto` with prerequisite warning). Fix `/aid-plan-epic` → `/aid-plan --epic`. `plan-writing.md` is authoritative source.

### Files

| File | Change |
|------|--------|
| `skills/brainstorming.md` | Handoff references plan-writing; fix stale command |
| `skills/plan-writing.md` | Summary + 6 options handoff; fix stale command |

---

## Implementation Order

| # | Change | Files | Depends on |
|---|--------|-------|-----------|
| 1 | D: Bug fix | aid-plan.md | — |
| 2 | A: Plugin discovery | aid-init.md, agent-core.md, agent-protocol.md, aid-run.md, aid-do.md | — |
| 3 | B: Brainstorming format | brainstorming.md | — |
| 4 | F: Brainstorming handoff | brainstorming.md, plan-writing.md | after B |
| 5 | E: Superpowers override | claude-md.md, orchestration.yaml | — |
| 6 | C: Documentation gate | execution.yaml, pipeline.md, auditor.md | — |
| 7 | CHANGELOGs + version bump | 6 files | 1-6 |

**Total: ~14 files + version/changelog files**

---

## Verification

1. `aid-init.md` has plugin discovery + `config/plugin.yaml` in lazy-created table
2. `agent-core.md` has Script Execution Protocol (4-step resolution)
3. `agent-protocol.md` dispatch YAML has `plugin_path`
4. `aid-run.md` PRE-FLIGHT has plugin_path verification
5. `brainstorming.md` has format template + webhook example
6. No `/aid-plan-epic` references anywhere (replaced with `/aid-plan --epic`)
7. `plan-writing.md` handoff has summary + 6 options + `autonomous_mode` warning
8. `setup/claude-md.md` has Superpowers conflict table
9. `orchestration.yaml` has 3 skill_conflicts
10. `execution.yaml` has path-pattern correlation for docs_updated
11. `auditor.md` — missing API docs = high severity
12. `aid-plan.md` — all steps show `/9`
13. Review agent validates cross-reference consistency

---

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Plugin path stale after update | M | M | Cache invalidation in PRE-FLIGHT |
| Glob matches multiple plugin installs | L | L | Use first match, warn PM |
| Existing projects miss Superpowers override | M | M | Works on next `/aid-setup claude-md` |
| Path-pattern correlation misses custom API dirs | M | L | Configurable `api_paths` in execution.yaml |
