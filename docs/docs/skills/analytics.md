---
sidebar_position: 4
title: "Analytics"
description: "Queries Qdrant metric entries to produce performance reports on agent execution, gate efficiency, and orchestration health across EPICs and projects."
---

# Analytics

The analytics skill queries Qdrant metric entries and produces actionable reports on agent performance, gate efficiency, token usage, and orchestration health. It surfaces bottlenecks, error hotspots, and optimization opportunities for a single EPIC, a project over time, or across multiple projects.

## Purpose

EPICs produce detailed execution data — per-step durations, gate retry counts, token estimates, error types, and bottleneck descriptions. Without a way to aggregate and interpret this data, patterns remain invisible and the same bottlenecks recur. The analytics skill makes orchestration history actionable.

## When Used

- Invoked by the `/aid-analytics` command
- Called by the `auditor` agent during post-EPIC audits
- Referenced by `auto-done-state` when generating session-level reports
- Used to verify improvement proposals have had measurable impact

## Key Concepts

### Metric Types

All metrics are stored in the `aid-memory` Qdrant collection with `type: "metric"`. The available metric kinds are:

| Metric Kind | Stored At | Contains |
|---|---|---|
| `agent_execution` | PHASE_CHECK | Per-step duration, complexity, bottleneck, errors, files touched |
| `epic_summary` | DONE | Per-EPIC total duration, step count, slowest step, gate retries |
| `gate_result` | DONE | Per-gate pass/fail, retries, duration |
| `token_profile` | DONE | Per-EPIC total tokens estimated, model distribution, active compute |
| `step_token_profile` | DONE | Per-step model, dispatch tokens, execution tokens, tool operations |

All metrics include `project_name`, `epic_id`, and `timestamp` for filtering.

### Report Types

**EPIC Report** — analyzes a single EPIC: step timeline, bottleneck analysis with WHY explanations (from agent self-reports), error summary, gate performance, token profile, and specific recommendations.

**Project Trends** — analyzes all EPICs in one project over time: trend charts for EPIC duration, recurring bottleneck agents, error hotspots, gate efficiency, and token trends.

**Cross-Project Comparison** — compares multiple projects using `epic_summary` metrics: project rankings by duration and error rate, best practices from fast projects, and knowledge transfer suggestions.

**Improvement Pipeline** (included in EPIC and Project reports) — reports on Curator activity (proposals generated, auto-approved, auto-rejected, PM overrides), lessons extracted, and fix effectiveness.

### Recommendation Confidence

Recommendations are tagged with confidence levels:
- **HIGH** — clear repeating pattern across multiple EPICs or steps
- **MEDIUM** — emerging pattern, needs more data to confirm
- **LOW** — insufficient data, hypothesis only

## How It Works

The skill queries Qdrant using structured filters. For a single EPIC:

```json
{
  "collection_name": "aid-memory",
  "query": "agent execution metrics for {epic_id}",
  "filter": {
    "must": [
      {"key": "type", "match": {"value": "metric"}},
      {"key": "epic_id", "match": {"value": "{epic_id}"}}
    ]
  },
  "limit": 50
}
```

Results are presented as an executive summary (3-5 bullet points), a detailed metrics table, a ranked bottleneck analysis, numbered actionable recommendations, and an optional before/after comparison.

If Qdrant has no data yet, the skill informs the PM and suggests running an EPIC first. Metrics are never fabricated — if a dimension has no data, the report states "No data available for this dimension."

## Configuration

Analytics reads from the `aid-memory` Qdrant collection. The collection name can be overridden in `.aid-o/03-config/policies/memory-config.yaml`.

No additional configuration is required. Metric storage happens automatically during EPIC execution at PHASE_CHECK and DONE states.

## Related

- [Memory MCP](../skills/memory-mcp)
- [Epic Orchestration](../skills/epic-orchestration)
- [Cost Optimization](../skills/cost-optimization)
- [Auto Done State](../skills/auto-done-state)
