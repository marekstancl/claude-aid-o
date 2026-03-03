---
sidebar_position: 6
title: "/aid-audit"
description: "Run a project health audit and receive a scored report (0-100)"
---

# /aid-audit

Run a project health audit and receive a scored report (0--100) with findings categorized by severity: Critical, Warning, and Suggestion.

## Usage

```bash
/aid-audit [type]
```

### Examples

```bash
# Run a security audit
/aid-audit security

# Run a complete project health check
/aid-audit full

# No type specified — prompted to choose
/aid-audit
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
| `efficiency` | Token usage per role vs baseline thresholds (advisory, never blocks) |
| `frontend` | Components, performance, accessibility, error handling |
| `security` | PII logging, input validation, authentication, secrets |
| `architecture` | Layer separation, coupling, scalability |
| `full` | All of the above (including Token Efficiency) |

## How It Works

The command loads the auditor agent protocol and executes the selected audit type against the current codebase. Each finding is tagged with a severity level:

- **Critical** -- blocks release; must be fixed
- **Warning** -- should be addressed soon
- **Suggestion** -- recommended improvement

## Output

A Markdown report is saved to `.aid-o/work/evidence/{task_id}/audit-report.md` and also presented in chat. The report includes an overall score (0--100), per-category breakdowns, and actionable recommendations.

## Related Commands

- [`/aid-status`](./aid-status) -- pipeline status and task overview
- [`/aid-run`](./aid-run) -- execute tasks (audit can run post-completion)
