---
sidebar_position: 3
title: "Quality Gates"
description: "The two-layer gate system: 6 pre-commit gates and the configurable post-EPIC gates engine."
---

# Quality Gates

AID has two distinct gate layers that operate at different points in the development cycle. Understanding both is important — they serve different purposes and are enforced by different mechanisms.

## Two Gate Layers

| Layer | When | Config | Skill |
|-------|------|--------|-------|
| **Pre-commit gates** | Before every commit | Built into `quality-gates.md` playbook | `skills/quality-gates.md` |
| **Post-EPIC gates** | After all EPIC steps complete (GATES state) | `gates.yaml` in `.aid-o/03-config/policies/` | `skills/gates-engine.md` |

The pre-commit gates are enforced by every agent before committing work. The post-EPIC gates are enforced by the Controller in the GATES state of the orchestration pipeline.

---

## Pre-Commit Gates (6 Gates)

Every agent runs all 6 gates before every commit. There are no exceptions. A failed gate means fix first, then re-run from Gate 1. All 6 must pass before a commit is allowed.

**Time investment:** 3-5 minutes per commit.

### Gate 1: Log Analysis + UI Smoke Test

**Purpose:** Verify changes do not break runtime and the UI renders correctly.

**Process:**
1. Start the frontend server (or backend, depending on what changed) and watch logs for 30 seconds.
2. Check for any ERROR in logs, server crashes, or build failures. Pre-existing warnings are documented as known, not treated as failures.
3. If UI files changed: run a Playwright browser smoke test — navigate to affected pages, check console for JS errors, take a screenshot as visual evidence.

**Playwright fallback:** If the Playwright MCP server is unavailable, a manual QA proposal is generated for the PM to confirm.

### Gate 2: Documentation Impact Analysis

**Purpose:** Keep documentation synchronized with code changes.

**Process:**
1. Run `git diff --name-only` to list changed files.
2. For each changed file, determine documentation impact using the impact table:
   - Database models affect ERD and schema docs.
   - API endpoints affect API docs and integration guides.
   - Core business logic affects system overview and architecture docs.
   - Any `feat:` or `fix:` commit requires a CHANGELOG.md update.
   - Breaking changes require a migration guide.
3. Update all affected documentation.
4. Stage documentation changes: `git add {docs path}`.

If it is unclear which docs need updating, the agent escalates to the PM with a list of changed files and potentially affected docs. Guessing is not permitted.

### Gate 3: Code Cleanup

**Purpose:** Remove temporary artifacts, debug code, and sensitive data before committing.

**Checks:**
- Temporary files: `*.tmp`, `*.bak`, `*.swp`
- Debug statements: `console.log`, `print()`, `debugger`, `pdb.set_trace()`
- Large commented code blocks (version control handles history)
- TODO/FIXME comments in production code (move to `bugs.md` or the run file)
- Hardcoded credentials: literals for `password`, `api_key`, `secret`
- Test data in production code (move to `tests/fixtures/`)

### Gate 4: Git Status Check

**Purpose:** Verify the correct files are staged and no secrets are accidentally included.

**Checks:**
- All code and documentation changes are staged.
- Files that must never be committed are not staged: `.env`, `node_modules/`, `__pycache__/`, `dist/`, `*.log`.
- Review staged diff: `git diff --cached`.

### Gate 5: Commit Message Format

**Purpose:** Maintain a clean, searchable git history.

**Required format:**
```
type(scope): description (YYYY-MM-DD HH:MM timezone)
```

Valid types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `style`, `perf`, `ci`.

Rules: imperative mood, lowercase start, no trailing period, max 72 characters for the first line, timestamp with timezone is mandatory.

### Gate 6: Testing

**Purpose:** Prevent regressions and verify new functionality.

**When to run:** Code changes, features, bug fixes, refactoring, schema changes.

**Requirements:**
- All existing tests must pass (100% pass rate).
- New features require unit and integration tests with more than 80% coverage for new code.
- Bug fixes require a regression test that reproduces the bug and passes after the fix.
- Flaky tests (fail sometimes but pass on re-run) are re-run 3 times. If still flaky, they are documented and a bug ticket is created.

**Skip conditions (PM approval required):** Docs-only changes, styling-only changes, config-only changes.

---

## Post-EPIC Gates Engine

After all EPIC steps complete, the Controller enters the GATES state and runs the gate definitions from `.aid-o/03-config/policies/gates.yaml`. These gates validate the EPIC output as a whole — integration tests, security scans, build verification, and documentation checks.

### Gate Types

**Command gates** execute a shell command and evaluate the exit code:

```yaml
tests_pass:
  description: "All tests must pass"
  required: true
  command: "pytest -q --tb=short"
  timeout_seconds: 300
  pass_criteria: "exit code 0"
```

**Rule gates** evaluate a logical condition by inspecting files and git history rather than running a command:

```yaml
docs_updated:
  description: "Documentation must be updated if public API changed"
  required: true
  rule: "{project.docs.path} or CHANGELOG.md must be updated if code changes affect public API"
  pass_criteria: "manual or automated check that relevant docs are current"
```

**Conditional gates** only execute when a `when` condition is met. If the condition is false, the gate is marked `skip` — not a failure:

```yaml
type_check:
  description: "TypeScript type check"
  required: false
  command: "npx tsc --noEmit"
  when: "frontend files changed"
  pass_criteria: "exit code 0"
```

### Gate Classification

All gates are classified into three categories before execution:

```
REQUIRED gates     required: true, no `when` clause
                   Must execute and must pass.

CONDITIONAL gates  required: false, has `when` clause
                   Condition evaluated first.
                   If condition false → status: SKIP
                   If condition true but fails → WARNING (non-blocking)

SKIPPED gates      Conditional gate where `when` condition is false.
                   Status: SKIP. Not executed.
```

Only required gates affect the overall pass/fail result. Conditional gate failures are warnings.

### Gate Execution Order

Gates execute in the order they appear in `gates.yaml`. For each gate:

1. Log start to `stage_log.jsonl`.
2. For command gates: execute via Bash with the configured timeout. Capture exit code, stdout, and stderr.
3. Evaluate against `pass_criteria`.
4. Write raw output to `evidence/{epic_id}/{run_id}/gates/{gate_name}.txt`.
5. Record result in `gates_report.json`.
6. Log completion to `stage_log.jsonl`.

### Retry Logic

When a required gate fails and the retry budget is not exhausted:

1. The Controller transitions to GATE_RETRY.
2. A gate-fixer agent is dispatched with the failure output as context.
3. The fixer applies a code or configuration change.
4. The gate is re-executed.
5. The retry attempt is appended to the `attempts` array in `gates_report.json`.

The maximum number of retries is configured per gate in `gates.yaml`. When the retry budget is exhausted, the Controller escalates to the PM.

### Gates Report

After all gates execute, `gates_report.json` is generated:

```json
{
  "epic_id": "E-20260224-fa01",
  "run_id": "20260224T140000Z",
  "gates": [
    {
      "name": "tests_pass",
      "type": "command",
      "required": true,
      "status": "pass",
      "command": "pytest -q --tb=short",
      "exit_code": 0,
      "output_summary": "45 passed in 3.2s",
      "duration_seconds": 3.2,
      "attempts": [
        {
          "attempt": 1,
          "status": "pass",
          "output_summary": "45 passed in 3.2s",
          "fix_applied": null
        }
      ]
    },
    {
      "name": "type_check",
      "type": "command",
      "required": false,
      "status": "skip",
      "justification": "Condition not met: frontend files changed",
      "attempts": []
    }
  ],
  "summary": {
    "total": 6,
    "passed": 4,
    "failed": 0,
    "skipped": 2,
    "errors": 0,
    "warnings": 0
  },
  "overall": "pass",
  "next_action": "proceed_to_pm_approval"
}
```

### Gate Status Values

| Status | Meaning |
|--------|---------|
| `pass` | Gate passed on this attempt |
| `fail` | Gate failed (required gate — blocking) |
| `skip` | Conditional gate, condition was not met |
| `error` | Gate execution error (timeout, command not found) |
| `skipped_by_pm` | PM explicitly skipped this gate during escalation |

### Overall Result Calculation

```
IF any required gate has status "fail" or "error":
  → overall: "fail"
ELSE:
  → overall: "pass"

Conditional gates (required: false) and PM-skipped gates
do NOT affect the overall result.
```

### Auto-Fix Behavior

The gate-fixer agent handles common failures automatically without PM intervention:

| Gate failure | Auto-fix approach |
|--------------|-------------------|
| Lint failures (style) | Run `ruff check --fix` or equivalent auto-formatter |
| Minor type errors | Fix type annotations in affected files |
| Formatting violations | Apply auto-formatter |

Failures that require logic changes or security remediation are not auto-fixed — they escalate to the PM.

### Evidence Files

```
.aid-o/04-engine/evidence/{epic_id}/{run_id}/
  gates_report.json         # Structured results for all gates
  gates/
    tests_pass.txt          # Raw command output
    lint_pass.txt
    security_scan_pass.txt
    docs_updated.txt        # Rule evaluation log
    type_check.txt          # Conditional gate output (only if executed)
    retry_lint_pass_1.md    # Gate-fixer output for attempt 1
    retry_lint_pass_2.md    # Gate-fixer output for attempt 2
```

Retry evidence is never deleted — every attempt is preserved. Gate output files are overwritten on re-run (only the latest output matters).

### Error Handling

| Error | Response |
|-------|----------|
| `gates.yaml` not found | FAIL: "Gates config not found. Run `/aid-init` first." |
| Command not found (e.g., pytest not installed) | Status: `error`. Message includes the missing tool and a suggestion to install it or update `gates.yaml`. |
| Timeout exceeded | Status: `error`. Message includes the configured timeout duration. |
| Permission denied | Status: `error`. Message notes the permission issue. |

The gates engine never modifies `gates.yaml` during execution. That file is PM-owned configuration.
