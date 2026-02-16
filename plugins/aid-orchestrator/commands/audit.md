Run a project health audit.

Read `.claude/skills/project-audit/instructions.md` and follow the audit protocol.

**Audit type:** $ARGUMENTS

Available audit types:
- `code` — Logic, hardcoded values, error handling, duplications
- `database` — Schema validation, indexes, transactions, orphaned data
- `documentation` — Code vs docs sync, outdated info, API accuracy
- `frontend` — Components, performance, accessibility, error handling
- `security` — PII logging, input validation, auth, secrets
- `architecture` — Layer separation, coupling, scalability
- `full` — All of the above

If no type specified, ask the user which audit to run.

Output: Markdown report with severity levels (Critical / Warning / Suggestion).
Templates: `.claude/skills/project-audit/templates/`
