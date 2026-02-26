---
sidebar_position: 2
title: "/aid-audit"
description: "Run a project health audit and receive a scored report"
---

# /aid-audit

Run a project health audit and receive a scored report (0–100) with findings categorized by severity: Critical, Warning, and Suggestion.

## Usage

```bash
/aid-audit [type]
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `type` | string | No | Audit type to run. If omitted, you are asked to choose. |

## Audit Types

| Type | What It Checks |
|------|----------------|
| `code` | Logic errors, hardcoded values, error handling, code duplication |
| `database` | Schema validation, indexes, transactions, orphaned data |
| `documentation` | Code vs docs sync, outdated information, API accuracy |
| `frontend` | Components, performance, accessibility, error handling |
| `security` | PII logging, input validation, authentication, secrets |
| `architecture` | Layer separation, coupling, scalability |
| `full` | All of the above |

## Examples

```bash
# Run a security audit
/aid-audit security

# Run a complete project health check
/aid-audit full

# No type specified — prompted to choose
/aid-audit
```

## How It Works

The command loads the auditor agent protocol and executes the selected audit type against the current codebase. Each finding is tagged with a severity level:

- **Critical** — blocks release; must be fixed
- **Warning** — should be addressed soon
- **Suggestion** — recommended improvement

## Output

A Markdown report is saved to `.aid-o/04-engine/evidence/{epic_id}/audit-report.md` and also presented in chat.

## Related

- [`/aid-analytics`](./aid-analytics) — performance metrics for past EPIC runs
- [`/aid-epic-status`](./aid-epic-status) — live pipeline status during a run
