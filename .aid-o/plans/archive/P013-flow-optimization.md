---
id: P013
type: plan
status: done
created: 2026-02-26
author: PM + AI
---

# Plan: Flow Optimization & Token Efficiency

## Context

AID orchestration pipeline consumes excessive tokens per EPIC run. `epic-orchestration.md` (2100+ lines) and `brainstorming.md` (1450 lines) are loaded in full for every agent dispatch, even when the agent only needs a fraction of the content. All agents use the same model (opus) regardless of task complexity — a docs step that writes CHANGELOG costs the same as an architect step designing API contracts. KNOWLEDGE CONTEXT and MEMORY CONTEXT are injected into every agent regardless of relevance. There's no per-step usage tracking, so optimization is blind.

Information overload also degrades output quality — agents receiving 5000+ tokens of irrelevant context produce worse results than agents with focused, relevant context.

## Goal

Reduce token cost per EPIC by 40-60%, reduce execution time by 20-30%, and maintain or improve output quality. Establish permanent monitoring and guardrails to prevent regression.

## Scope

**In scope:**
- Baseline token usage audit on real EPIC
- Skill file splitting (brainstorming.md → core + workflow + subagent template)
- Model tiering policy (dispatch-config.yaml: haiku/sonnet/opus per role)
- Selective context injection (KNOWLEDGE/MEMORY only when needed)
- Prompt trimming (step-scoped dispatch, not full EPIC)
- Per-step usage tracking in stage_log.jsonl
- Context budget and alerting
- Before/after comparison measurement
- Automated efficiency guardrail in `/aid-audit`

**Out of scope:**
- The split of epic-orchestration.md (done in P012 step 3 as prerequisite)
- GUI token dashboard (will be in P009 Phase 3b Pipeline Theater)
- Agent SDK migration (separate concern)

**Dependencies:**
- P012 step 3 (split epic-orchestration.md) should complete first — smaller files are the foundation for selective loading

## Approach

### Option A: Measure → Optimize → Measure → Guard (Chosen)

Two runs. Run 1: baseline audit + biggest wins (splitting, tiering). Run 2: selective context + trimming + tracking + guardrail. Each run produces measurable improvement.

**Pros:**
- Data-driven — no blind optimization
- Biggest wins first (splitting + tiering = estimated -50% alone)
- Guardrail prevents regression permanently
- Two runs allow course correction between phases

**Cons:**
- Requires running a "benchmark EPIC" twice (before and after)

### Decision

**Chosen:** Option A
**Rationale:** Without baseline measurement, we don't know where the bloat is. Splitting + tiering give the biggest immediate bang. The guardrail ensures optimizations stick permanently.

## High-Level Steps

### Run 1: Measure & Big Wins

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | Baseline audit | Run a standard EPIC (P010 or similar), capture per-step: input tokens, output tokens, model, duration, context sources injected. Produce baseline report. | M |
| 2 | Skill file splitting | Split `brainstorming.md` (1450 lines) → `brainstorming-core.md` (core flow, ~400 lines), `brainstorming-workflow.md` (workflow detection + Docker/MCP rules, ~400 lines), `brainstorming-epic-template.md` (EPIC subagent prompt, ~300 lines). Update all references. Agent loads only what it needs. | M |
| 3 | Model tiering policy | Create `defaults/policies/dispatch-config.yaml` with model assignments per role: haiku for docs/config, sonnet for backend/frontend/qa, opus for architect/security/domain. Planner reads this and assigns model per step in plan.json. Dispatcher uses step's assigned model. | M |

### Run 2: Fine-Tuning & Guardrails

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 4 | Selective context injection | Add rules to dispatch protocol: inject KNOWLEDGE CONTEXT only for steps that list `knowledge_needed: true` in plan.json. Inject MEMORY CONTEXT only for architect/domain/security roles. Docs/config steps get no extra context. | M |
| 5 | Prompt trimming | Dispatch prompt builder sends only: step objective, step allowed_paths, step AC, direct dependency outputs — not full EPIC spec or full plan.json. Reduce dispatch prompt from ~3000 tokens to ~800. | M |
| 6 | Per-step usage tracking | Log `input_tokens`, `output_tokens`, `model`, `context_sources[]`, `duration_ms` per step in `stage_log.jsonl`. Aggregate totals in `plan_progress.json` under `usage` key. | S |
| 7 | Context budget & alerts | Define max token budget per step type in `dispatch-config.yaml` (e.g., docs: 5K input, backend: 15K input). Exceeding budget → warning in stage_log (not hard fail). | S |
| 8 | Re-measure & compare | Re-run the same benchmark EPIC from step 1. Compare: total tokens, per-step tokens, duration, retries, gate failures. Produce comparison report. | M |
| 9 | Automated efficiency guardrail | Extend `/aid-audit` with "Token Efficiency" section: compare current EPIC's usage with baseline averages. Alert if any step exceeds 2x baseline. Curator logs cost metrics in lessons-learned. | M |

## Constraints

- P012 step 3 (split epic-orchestration.md) should complete before Run 1 step 2
- Model tiering must be configurable per-project (some projects may need opus for all steps)
- Usage tracking must not add latency to agent dispatch (async logging)
- Context budget is advisory (warning), not enforcement (hard fail) — to avoid blocking legitimate complex steps
- Guardrail runs automatically in `/aid-audit`, no manual invocation needed

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Model tiering reduces quality for complex backend steps | medium | medium | Start conservative: opus for architect/security/domain, sonnet for backend/frontend, haiku only for docs. Tune based on retry rates. |
| Selective context removes info the agent actually needed | medium | medium | Track retry rates per step after context reduction. If retries increase, widen context for that role. |
| Usage tracking adds overhead to stage_log | low | low | Async writes, batch logging. Token counts come from API response headers — zero extra cost. |
| Baseline EPIC isn't representative | low | medium | Use at least 2 different EPICs for baseline (one small, one medium) |

## Success Criteria

- Token cost per EPIC reduced by 40-60% vs. baseline
- Execution time reduced by 20-30% vs. baseline
- Retry rate does not increase (quality maintained)
- Gate failure rate does not increase
- Per-step usage visible in stage_log.jsonl
- `/aid-audit` reports token efficiency score
- Efficiency guardrail alerts on regression automatically

## Next Steps

- [ ] Wait for P012 step 3 (split orchestration.md) to complete
- [ ] Create EPIC for P013 Run 1
- [ ] After Run 1: create EPIC for P013 Run 2
- [ ] After Run 2: verify guardrail is active, close plan

---

**Last Updated:** 2026-02-26
