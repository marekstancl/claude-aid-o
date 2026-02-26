---
sidebar_position: 1
title: "/aid-analytics"
description: "Analyze orchestration performance metrics and get optimization recommendations"
---

# /aid-analytics

Analyze orchestration performance metrics across EPICs, projects, or globally, and receive actionable optimization recommendations with confidence levels.

## Usage

```bash
/aid-analytics [scope]
```

Where `scope` is one of:

| Scope | Description |
|-------|-------------|
| `{epic_id}` | Analyze a specific EPIC (e.g., `E-20260219-v030`) |
| `project` | Analyze trends across all EPICs in the current project |
| `global` | Compare across all projects (requires Qdrant with multi-project data) |
| _(no argument)_ | Defaults to the most recently completed EPIC |

## Prerequisites

- Qdrant must be configured and accessible (see [`/aid-setup`](./aid-setup))
- At least one EPIC must have been completed with metrics
- For `project` scope: multiple completed EPICs provide better analysis
- For `global` scope: multiple projects with completed EPICs in Qdrant

## Examples

```bash
# Analyze a specific EPIC
/aid-analytics E-20260219-v030

# Analyze project-wide trends
/aid-analytics project

# Cross-project comparison
/aid-analytics global

# Default: most recently completed EPIC
/aid-analytics
```

## How It Works

1. Loads the `analytics` skill
2. Determines scope from the argument (EPIC Report, Project Trends, or Cross-Project Comparison)
3. Checks Qdrant availability — if Qdrant is unavailable, prompts you to configure it and exits
4. Queries Qdrant for relevant metrics using the analytics skill query patterns
5. Generates a structured report and presents it in chat

## Output

The report includes:

- **Executive summary** — 3-5 key findings
- **Detailed metrics table** — timing, step counts, gate retries, token usage
- **Bottleneck analysis** — root causes of slowdowns or failures
- **Actionable recommendations** — with confidence levels (HIGH / MEDIUM / LOW)

## Related

- [`/aid-setup`](./aid-setup) — configure Qdrant for metric storage
- [`/aid-run-epic`](./aid-run-epic) — generates metrics during EPIC execution
- [`/aid-epic-status`](./aid-epic-status) — view live pipeline status
