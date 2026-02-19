---
name: aid-analytics
description: Analyze orchestration performance metrics and get optimization recommendations
user_invocable: true
---

# /aid-analytics

## Usage

```
/aid-analytics [scope]
```

Where scope is one of:
- `{epic_id}` -- analyze a specific EPIC (e.g., `/aid-analytics E-20260219-v030`)
- `project` -- analyze trends across all EPICs in current project
- `global` -- compare across all projects (requires Qdrant with multi-project data)
- (no argument) -- defaults to the most recently completed EPIC

## Prerequisites

- Qdrant must be configured and accessible (see `/aid-setup`)
- At least one EPIC must have been completed with metrics
- For `project` scope: multiple completed EPICs provide better analysis
- For `global` scope: multiple projects with completed EPICs in Qdrant

## Process

1. Load the `analytics` skill (`skills/analytics.md`)
2. Determine scope from argument:
   - If `{epic_id}` provided: EPIC Report
   - If `project`: Project Trends report
   - If `global`: Cross-Project Comparison report
   - If no argument: find most recent `epic_summary` metric in Qdrant for
     current project, use its `epic_id` for EPIC Report
3. Check Qdrant availability:
   - If Qdrant unavailable: inform PM and exit
     ```
     Qdrant is not available. Analytics requires Qdrant for metric storage.
     Run /aid-setup to configure Qdrant, then complete an EPIC to generate metrics.
     ```
4. Query Qdrant for relevant metrics (per analytics skill query patterns)
5. Generate report with findings and recommendations
6. Present to PM in chat

## Output

Structured report with:
- Executive summary (3-5 key findings)
- Detailed metrics table
- Bottleneck analysis with root causes
- Actionable recommendations with confidence levels (HIGH / MEDIUM / LOW)

## Examples

```
/aid-analytics E-20260219-v030
  → EPIC Report: timeline, bottlenecks, gate retries, token profile

/aid-analytics project
  → Project Trends: duration trends, common bottlenecks, gate efficiency

/aid-analytics global
  → Cross-Project: project ranking, best practices, knowledge transfer

/aid-analytics
  → Defaults to most recently completed EPIC in current project
```

## Reference Files

- `skills/analytics.md` -- analytics skill with report types and query patterns
- `skills/memory-mcp.md` -- Qdrant query protocol
- `skills/epic-orchestration.md` -- metric storage (PHASE_CHECK, DONE states)
