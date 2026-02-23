---
name: analytics
description: Analyze orchestration metrics from Qdrant to identify performance patterns, bottlenecks, and optimization opportunities across EPICs and projects.
---

# Analytics Skill

## Purpose

Query Qdrant metric entries (type: "metric") and produce actionable reports
on agent performance, gate efficiency, and orchestration health.

## Metric Types Available

These are stored by the orchestration engine in `aid-memory` collection:

| metric_kind | Stored at | Contains |
|---|---|---|
| `agent_execution` | PHASE_CHECK | Per-step: duration, complexity, bottleneck, errors, files touched |
| `epic_summary` | DONE | Per-EPIC: total duration, step count, slowest step, gate retries |
| `gate_result` | DONE | Per-gate: pass/fail, retries, duration |
| `token_profile` | DONE | Per-EPIC: total tokens estimated, model distribution, active compute |
| `step_token_profile` | DONE | Per-step: model, dispatch tokens, execution tokens, tool operations |

All metrics include `project_name`, `epic_id`, and `timestamp`.

## Report Types

### 1. EPIC Report (single EPIC)

Query: all metrics where `epic_id` = {target}

Output:
- Timeline: step-by-step execution with duration bars
- Bottleneck analysis: which steps took longest and WHY (from self-report)
- Error summary: what went wrong and how it was resolved
- Gate performance: which gates failed, retry count, time cost of retries
- Token profile: model usage distribution, per-step token estimates
- Recommendation: specific actionable suggestions (e.g., "Step 3 spent 45%
  of time -- consider splitting into 2 smaller steps")

### 2. Project Trends (across EPICs in one project)

Query: all metrics where `project_name` = {target}

Output:
- Trend chart: average EPIC duration over time (improving or regressing?)
- Common bottlenecks: which agent roles are consistently slowest
- Error hotspots: recurring error patterns across EPICs
- Gate efficiency: which gates cause the most retries
- Token trends: are costs going up or down per EPIC?
- Recommendation: systemic improvements (e.g., "tests_pass gate fails in 60%
  of EPICs -- improve pre-lint or test generation quality")

### 3. Cross-Project Comparison

Query: all `epic_summary` metrics across all projects

Output:
- Project ranking: by avg EPIC duration, error rate, gate pass rate
- Best practices: what the fastest projects do differently
- Knowledge transfer: lessons from fast projects applicable to slow ones
- Token comparison: which projects are most/least efficient

### 4. Improvement Pipeline (included in EPIC and Project reports)

**EPIC-level section** (appended to EPIC Report):

Query: `stage_log` entries with `state=CURATOR_RESOLVE` for `{epic_id}` + `backlog.md` entries with `epic_ref={epic_id}`

Output:
- Curator Activity: proposals generated, auto-approved, auto-rejected, PM overrides
- Lessons Extracted: new lessons, new gotchas, duplicates skipped, cross-project matches
- Fix Effectiveness: fixes implemented, files modified, fix agent models used

**Project-level section** (appended to Project Trends):

Query: all `backlog.md` entries + Qdrant `curator_decision` entries for `{project_name}`

Output:
- Backlog Health: total/active/implemented/rejected/deferred counts, implementation rate
- Recurring Issues: top hotspot areas, proposals persisting 3+ EPICs
- Learning Progress: auto-rules count, Qdrant decisions, auto-resolve accuracy (PM override rate)
- Lessons Trends: per-EPIC lesson/gotcha/duplicate counts

## How to Query Qdrant

Use the memory-mcp search tool:

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

For trends, omit `epic_id` filter and include `project_name`:

```json
{
  "collection_name": "aid-memory",
  "query": "performance metrics for {project_name}",
  "filter": {
    "must": [
      {"key": "type", "match": {"value": "metric"}},
      {"key": "project_name", "match": {"value": "{project_name}"}}
    ]
  },
  "limit": 100
}
```

For cross-project comparison:

```json
{
  "collection_name": "aid-memory",
  "query": "epic summary metrics across all projects",
  "filter": {
    "must": [
      {"key": "type", "match": {"value": "metric"}},
      {"key": "metric_kind", "match": {"value": "epic_summary"}}
    ]
  },
  "limit": 100
}
```

For curator auto-evaluate decisions (Improvement Pipeline):

```json
{
  "collection_name": "aid-memory",
  "query": "curator auto-evaluate decisions for {project_name}",
  "filter": {
    "must": [
      {"key": "type", "match": {"value": "curator_decision"}},
      {"key": "project_name", "match": {"value": "{project_name}"}}
    ]
  },
  "limit": 100
}
```

## Output Format

Present results as:
1. **Executive Summary** -- 3-5 bullet points with key findings
2. **Detailed Metrics Table** -- tabular data with all numbers
3. **Bottleneck Analysis** -- ranked list with WHY explanation
4. **Recommendations** -- numbered, specific, actionable items
5. **Comparison** (if applicable) -- before/after or cross-project

### Sample Output

```
Analytics Report: EPIC E-20260219-v030
====================================

Executive Summary:
  - 9 steps completed in 47 minutes (5.2 min/step avg)
  - Bottleneck: step_6_backend (14 min, 30% of total)
  - Gate retries: 2 (lint_pass failed twice, auto-fixed)
  - Token estimate: ~85K tokens, 78% agent execution

Detailed Metrics:
  | Step | Role | Duration | Complexity | Errors | Bottleneck |
  |------|------|----------|------------|--------|------------|
  | 1    | architect | 3m 12s | medium | 0 | — |
  | 2    | domain | 2m 45s | low | 0 | — |
  | 3    | backend | 8m 30s | high | 1 | test integration |
  ...

Bottleneck Analysis:
  1. step_6_backend (14m) — HIGH: Writing integration tests required
     reading 4 existing test files for patterns. Consider providing
     test patterns in playbook.
  2. step_7_qa (6m) — MEDIUM: E2E test setup took 3 min.

Recommendations:
  1. [HIGH confidence] Split step_6 into implementation + test steps
  2. [MEDIUM confidence] Add test pattern examples to backend playbook
  3. [LOW confidence] Consider parallelizing QA + Security (currently sequential)
```

## Important

- If Qdrant has no metrics yet, inform PM and suggest running an EPIC first
- Always include sample size (N EPICs analyzed, N steps analyzed)
- Mark recommendations with confidence: HIGH (clear pattern), MEDIUM (emerging
  pattern), LOW (insufficient data)
- Never fabricate metrics. If data is unavailable, state "No data available for
  this dimension" rather than estimating
- Cross-project comparison requires Qdrant with multi-project data. If only
  one project's data exists, suggest running EPICs in other projects first

---

## Reference Files

- `skills/memory-mcp.md` -- memory protocol, Qdrant query functions
- `skills/epic-orchestration.md` -- metric storage at PHASE_CHECK and DONE states
- `skills/cost-optimization.md` -- token estimation methodology
- `commands/aid-analytics.md` -- user-facing command that invokes this skill
