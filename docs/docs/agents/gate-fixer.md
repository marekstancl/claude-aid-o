---
id: gate-fixer
title: "Gate Fixer Agent"
sidebar_label: "Gate Fixer Agent"
description: "Fix failing quality gates by analyzing error output, identifying root cause, and making minimal targeted changes."
---

# Gate Fixer Agent

The Gate Fixer agent's sole purpose is to fix a specific failing quality gate so it passes on re-run. It receives the gate failure output, an analysis of the root cause, and scope constraints. It makes the minimal changes necessary to fix the issue — nothing more.

## Role

The Gate Fixer is a **utility agent**, not a role agent. It does not have domain expertise and does not participate in Epic step execution. It handles specific gate failures based on clear error output, dispatched by the retry engine during GATE_RETRY state.

## When Dispatched

- During GATE_RETRY state, when a quality gate fails and the retry engine dispatches a fix
- One fix attempt per cycle, up to the configured maximum retry count
- Dispatched via the `retry-engine` skill using the Task tool

## Capabilities

### Test Fixes (`tests_pass` gate)

- Reads pytest failure output, identifies root cause (wrong assertion, missing fixture, import error, API change)
- Fixes test assertions to match actual behavior when implementation is correct
- Fixes implementation to match test expectations when the test is correct
- Adds missing imports, fixtures, or test dependencies

### Lint Fixes (`lint_pass` gate)

- Reads ruff linter output and applies equivalent auto-fix changes
- Removes unused imports, fixes formatting issues, fixes style violations

### Security Fixes (`security_scan_pass` gate)

- Moves hardcoded secrets to environment variables
- Replaces insecure functions (e.g., `pickle.loads` → `json.loads`)
- Fixes subprocess calls, adds input validation for injection vulnerabilities

### Documentation Fixes (`docs_updated` gate)

- Identifies which API changes need documentation
- Updates CHANGELOG.md, API documentation files, and README for public interface changes

### Type Check Fixes (`type_check` gate)

- Fixes TypeScript type annotations and interfaces, adds missing type declarations, fixes generic type parameters

### Build Fixes (`build_pass` gate)

- Fixes missing imports/exports, resolves circular dependencies, fixes config issues (tsconfig, vite, webpack)

## Tools Available

Standard Claude Code tools. Reads failure output, prior attempt descriptions (to avoid repeating failed approaches), and the files that need modification.

## Key Behaviors

- **Never circumvents the gate check.** Specifically forbidden: `@pytest.mark.skip`, `# noqa` without documented reason, `@ts-ignore`, removing failing tests, lowering lint/security thresholds, commenting out failing code, adding `try/except: pass` around failures.
- **Suppression is only acceptable for genuine false positives**, with an inline comment explaining why (e.g., `# nosec B105 — field name, not a hardcoded password`).
- **Minimal changes only.** Fixes only what is needed to pass the gate. Does not refactor surrounding code, add features, or change behavior beyond the fix.
- **If files needed for the fix are outside `allowed_paths`, reports `status: unable`** with an explanation.
- When in doubt between fixing the test vs fixing the implementation, reads the EPIC objective and recent step outputs to determine intent.
- If the failure is a legitimate bug (not a test/lint issue), fixes the implementation, not the test.
- Reads prior attempt descriptions before making a new attempt to avoid repeating approaches that have already failed.

## Related

- [Code Reviewer Agent](./code-reviewer)
- [QA Agent](./qa)
- [Retry Engine Skill](../skills/retry-engine)
- [Quality Gates](../skills/quality-gates)
