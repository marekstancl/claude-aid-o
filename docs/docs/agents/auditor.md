---
id: auditor
title: "Auditor Agent"
sidebar_label: "Auditor Agent"
description: "Post-Epic comprehensive project health assessment, scoring, and trend tracking."
---

# Auditor Agent

The Auditor agent runs once per completed Epic, after the final merge. It performs a comprehensive project health audit across up to six categories, produces a scored report with per-finding recommendations, tracks trends against the previous audit, and delivers the report to the Orchestrator. It does not modify code — it only observes, analyzes, scores, and reports.

## Role

The Auditor is a **specialist agent**, not a role agent. It does not participate in Epic step execution. Its output drives the project's continuous improvement cycle: critical findings become backlog items via the Curator agent. The Markdown summary it produces is concise enough to present in a Slack message.

## When Dispatched

- After Epic DONE state is reached and the code is merged
- Triggered by the `epic-orchestration` skill from the DONE state, post-merge
- Runs exactly once per completed Epic

## Capabilities

### Four Mandatory Audits

- **Code Audit** — code quality patterns, cyclomatic complexity hotspots, duplication, naming conventions, dead code, circular dependencies
- **Security Audit** — OWASP Top 10 checklist, hardcoded secrets scan, dependency CVEs, auth/authz review, input validation coverage, security headers
- **Documentation Audit** — API doc drift detection, README accuracy, missing docs for new features, broken links, CHANGELOG completeness, inline doc coverage
- **Process Audit** — EPIC lifecycle state verification, evidence artifact completeness, cross-reference validation, stage log integrity

### Two Conditional Audits

- **Frontend Audit** — accessibility patterns, bundle size analysis, performance patterns, component structure consistency. Runs only when a frontend framework is detected or `.tsx/.jsx/.vue/.svelte` files exist in `src/`.
- **Database Audit** — migration consistency, index coverage for common query patterns, N+1 query patterns, schema documentation. Runs only when migration files exist, ORM config is detected, or a database is listed in `project-profile.yaml`.

### Scoring

Each category starts at 100 and deducts per finding: Critical (-15), High (-10), Medium (-5), Low (-2). Minimum score is 0. A bonus of +5 applies for categories with zero findings. The overall score is a weighted average: Code quality 30%, Security 30%, Documentation 25%, Process 15%. Frontend and Database each add 10% when applicable, redistributing weight proportionally from the always-run categories.

### Trend Tracking

Loads the previous audit from `evidence/{previous_epic_id}/audit-report.md`, compares scores per category, classifies findings as new/resolved/persistent, and determines trend direction: `improving` (overall delta > +5), `declining` (delta < -5), or `stable`.

## Tools Available

Read-only access to all project files. Writes only to `evidence/{epic_id}/`:
- `audit-report.yaml` — machine-readable, consumed by the Orchestrator and Curator
- `audit-report.md` — human-readable summary for PM review

## Key Behaviors

- **Read-only.** Never modifies source code, configuration, tests, or any project file. Never creates branches, commits, or pull requests.
- **All four mandatory audits always run.** Code, Security, Documentation, and Process audits are never skipped.
- **Conditional audits run when their condition is met.** When borderline (e.g., a single `.jsx` file in a test fixture), errs on the side of running the audit — false negatives are worse than a redundant audit.
- **Scores are reproducible.** The same codebase and the same methodology always produce the same score. No subjective adjustments.
- **Critical findings are always reported.** They must never be omitted or downgraded.
- **Every finding includes:** area, audit_type, finding description, actionable recommendation, and effort estimate (`small` under 1h, `medium` 1–4h, `large` 4h+).
- When critical findings match escalation triggers in `decision-policies.yaml`, the Orchestrator escalates to the PM before the next EPIC begins.

## Related

- [Curator Agent](./curator)
- [Quality Gates](../skills/quality-gates)
- [Epic Orchestration Skill](../skills/epic-orchestration)
