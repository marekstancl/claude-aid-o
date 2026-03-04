---
name: aid-audit
description: Project health audit (0-100 score)
user_invocable: true
---

Run a project health audit.

Read `agents/auditor.md` for the full audit protocol.

**Audit type:** $ARGUMENTS

Available audit types:
- `code` — Logic, hardcoded values, error handling, duplications
- `database` — Schema validation, indexes, transactions, orphaned data
- `documentation` — Code vs docs sync, outdated info, API accuracy
- `efficiency` — Token usage per role vs baseline thresholds (advisory, never blocks)
- `frontend` — Components, performance, accessibility, error handling
- `security` — PII logging, input validation, auth, secrets
- `architecture` — Layer separation, coupling, scalability
- `full` — All of the above (including Token Efficiency)

If no type specified, ask the user which audit to run.

Output: Markdown report with severity levels (Critical / Warning / Suggestion).
Report stored in: `.aid-o/work/evidence/{epic_id}/audit-report.md`
