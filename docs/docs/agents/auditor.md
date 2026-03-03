---
sidebar_position: 4
title: "Auditor Agent"
description: "Post-Epic comprehensive project health assessment across 8 categories with scoring and trend tracking."
---

# Auditor Agent

The Auditor agent runs once per completed Epic, after the final merge. It performs a comprehensive project health audit across up to 8 categories (5 mandatory + 3 conditional), produces a scored report with per-finding recommendations, tracks trends against the previous audit, and delivers the report to the pipeline. It does not modify code — it only observes, analyzes, scores, and reports.

## Role

The Auditor is a **specialist agent**. It does not participate in Epic step execution. Its output drives the project's continuous improvement cycle: critical findings become backlog items via the [Curator](./curator) agent.

## When Dispatched

- After Epic DONE state is reached and the code is merged
- Triggered by the pipeline from the DONE state (see [Pipeline](../skills/pipeline))
- Runs exactly once per completed Epic

## Audit Categories

### Mandatory (always run)

| Category | What It Checks |
|----------|---------------|
| **Code** | Quality patterns, complexity hotspots, duplication, naming conventions, dead code, circular dependencies |
| **Security** | OWASP Top 10, hardcoded secrets, dependency CVEs, auth/authz, input validation, security headers |
| **Documentation** | API doc drift, README accuracy, missing docs for new features, broken links, CHANGELOG, inline doc coverage |
| **Process** | EPIC lifecycle state, evidence completeness (13 checks across 5 sub-categories), cross-reference validation, timeline integrity |
| **Token Efficiency** | Per-role token breakdown vs baseline, 2x alert threshold, efficiency score (advisory only, 0% weight) |

### Conditional

| Category | Condition | What It Checks |
|----------|-----------|---------------|
| **Frontend** | Frontend framework detected or `.tsx/.jsx/.vue/.svelte` files in `src/` | Accessibility, bundle size, performance patterns, component structure |
| **Database** | Migration files, ORM config, or DB in `project.yaml` | Migration consistency, index coverage, N+1 patterns, schema docs |
| **Instruction Quality** | `plugins/aid-orchestrator/` exists (AID repo only) | Frontmatter, intro presence, TODO/FIXME markers, cross-references, file length |

## Scoring

Each category starts at 100 and deducts per finding: Critical (-15), High (-10), Medium (-5), Low (-2). Minimum score is 0. Bonus: +5 for categories with zero findings (capped at 100).

Overall score is a weighted average: Code 30%, Security 30%, Documentation 25%, Process 15%. Frontend, Database, and Instruction Quality each add 10% when applicable. Token Efficiency has 0% weight (advisory only).

## Trend Tracking

Loads the previous audit from `evidence/<previous_epic_id>/audit-report.md`, compares scores per category, classifies findings as new/resolved/persistent, and determines trend direction: `improving` (delta > +5), `declining` (delta < -5), or `stable`.

## Output

Two artifacts stored in `evidence/<epic_id>/`:
- `audit-report.yaml` — machine-readable, consumed by pipeline and Curator
- `audit-report.md` — human-readable summary for PM review

## Key Behaviors

- **Read-only.** Never modifies source code, configuration, or project files.
- **All 5 mandatory audits always run.** Conditional audits run when their condition is met (errs on the side of running).
- **Scores are reproducible.** Same codebase + same methodology = same score.
- **Every finding includes:** area, audit_type, finding, recommendation, effort estimate.
- **Model:** sonnet

## Related

- [Curator Agent](./curator)
- [Pipeline Skill](../skills/pipeline)
- [Quality Gates Skill](../skills/quality-gates)
