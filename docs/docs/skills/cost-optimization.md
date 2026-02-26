---
sidebar_position: 8
title: "Cost Optimization"
description: "Reduces EPIC execution time and token consumption through model selection, agent file scoping, and dispatch prompt trimming — targeting a 30-50% speed improvement."
---

# Cost Optimization

The cost optimization skill defines how to reduce wall-clock time and token consumption during EPIC execution. On a flat-rate plan, speed is the primary optimization target. The skill provides four concrete levers: model selection per agent role, explicit file scope in dispatch prompts, trimmed dispatch prompt sizes, and per-EPIC token consumption tracking in Qdrant.

## Purpose

The baseline measurement (BMK-001) shows a 6-step EPIC consuming ~3.5M tokens in 140 minutes of active compute, with 89% of tokens consumed inside agent execution. Optimization must target where the time actually goes, not the 3.3% in dispatch prompts. This skill provides concrete, measurable changes to each cost axis.

## When Used

- Applied by the Planner when generating `relevant_files` lists per step
- Applied by the Controller when building dispatch prompts (summary vs. full EPIC, deps-only vs. all outputs)
- Applied by the Orchestrator when selecting agent models for each step
- Token tracking executes at DONE state and stores metrics to Qdrant

## Key Concepts

### Axis 1: Model Selection (Highest Impact — Speed)

Assign the fastest model capable of each task's complexity. On a MAX plan, Sonnet produces output 2-3x faster than Opus:

| Agent | Recommended Model | Rationale |
|---|---|---|
| architect, backend, frontend | opus | Complex code generation and architectural decisions |
| domain, qa, security, docs-writer, code-reviewer, curator, auditor, observability, release | sonnet | Analysis, review, and structured writing — fast and sufficient |
| gate-fixer, lessons-extractor, run-validator, quality-gates-runner | haiku | Utility tasks: extract, validate, format |

Moving QA, Security, and Docs from Opus to Sonnet on a BMK-001 scenario yields an estimated 30-40% speed improvement for those steps.

### Axis 2: Agent File Scoping (Highest Impact — Speed + Tokens)

Agents spend significant time on Glob/Grep/Read operations discovering project structure. Providing an explicit `relevant_files` list in the dispatch eliminates this exploration overhead.

Each step in `plan.json` already defines `allowed_paths`. The Planner extends this with `relevant_files` — an explicit list of files the agent should read first, annotated with what each file contains and which prior step produced it:

```json
{
  "step_id": "step_3_backend",
  "allowed_paths": ["app/routers/", "app/services/"],
  "relevant_files": [
    "app/models/bookmark.py (ORM model — from step_2)",
    "app/schemas/bookmark.py (Pydantic schemas — from step_2)"
  ]
}
```

Agents read all listed files before any Glob or Grep operations. Estimated impact: 50-70% reduction in exploratory tool calls, saving 30K-100K tokens per agent.

### Axis 3: Dispatch Prompt Trimming (Medium Impact)

Four trimming rules reduce dispatch prompt size by ~57%:

1. **Playbook summary, not full playbook** — 50 tokens instead of 875, with a pointer to the full playbook
2. **Dependency outputs only** — include only direct-dependency step outputs, not all prior outputs
3. **EPIC summary, not full EPIC** — goal, constraints, and this step's acceptance criteria only
4. **Memory search top_k = 3** — fewer Qdrant results means less context and faster first response

### Axis 4: Token Tracking

At DONE state, the Controller stores a token profile to Qdrant for cross-project analysis:
- Total tokens estimated, model distribution, estimated cost
- Per-step: model, dispatch tokens, execution tokens, tool operations, duration

Estimates use the BMK-001 baseline: `duration_seconds / 60 * 3 ops/min * 2600 tokens/op`. These are approximations for trend analysis, not exact billing figures.

## How It Works

The combined effect of all four axes on a BMK-001 scenario:

| Optimization | Token Reduction | Speed Impact |
|---|---|---|
| Model selection (Sonnet/Haiku for appropriate agents) | — | ~2-3x faster output for those agents |
| Agent file scoping | ~100K-400K | -20-40% duration |
| Dispatch prompt trimming | ~65K | -5-10% |
| Token tracking | ~0 (overhead) | ~0 |
| **Combined** | **~165K-465K** | **-30-50% faster** |

For BMK-001 (140 min active compute), the optimized estimate is 70-100 minutes.

## Configuration

Model assignments are defined in each agent's frontmatter in `agents/*.md`. The Planner generates `relevant_files` automatically as part of the plan JSON. Policy files (project-profile.yaml, gates.yaml, decision-policies.yaml) are read once at IDLE to avoid repeated reads per state transition.

## Related

- [Agent Core](../skills/agent-core)
- [Epic Orchestration](../skills/epic-orchestration)
- [Parallel Dispatch](../skills/parallel-dispatch)
- [Planner](../skills/planner)
- [Analytics](../skills/analytics)
