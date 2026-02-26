---
id: quality-gates-runner
title: "Quality Gates Runner Agent"
sidebar_label: "Quality Gates Runner Agent"
description: "Run the 6-gate pre-commit quality protocol autonomously before any git commit."
---

# Quality Gates Runner Agent

The Quality Gates Runner agent runs all six quality gates and reports results before any git commit. It is a utility agent that does not modify files — it reads, checks, and reports.

## Role

The Quality Gates Runner is a **utility agent**. It autonomously executes the pre-commit quality protocol, producing a structured report with PASS/FAIL per gate, a list of blocking issues that must be fixed before committing, and a list of warnings that should be addressed.

## When Dispatched

- Before any git commit to ensure all quality standards are met
- Used interactively when the developer wants to verify code quality before committing

## The Six Quality Gates

### Gate 1: Log Analysis and UI Smoke Test

- **Backend:** runs the test suite and checks for ERROR/WARNING in output
- **Frontend:** runs the build tool (e.g., `npx vite build`) and checks for TypeScript errors
- **UI Smoke Test (only if UI files changed):** navigates to the relevant page using Playwright, checks browser console for JS errors, verifies page renders

### Gate 2: Documentation Impact

- Identifies changed files from `git diff --name-only`
- Checks whether each changed file requires documentation updates: DB schema changes → database docs; API endpoint changes → API docs; business logic changes → system overview; UI component changes → component docs
- Verifies docs are updated in the same commit

### Gate 3: Code Cleanup

- Checks changed files for: `console.log()` in TypeScript/JavaScript, `print()` in Python (use logging instead), `TODO` or `FIXME` without an issue reference, hardcoded secrets or API keys, commented-out code blocks

### Gate 4: Git Status

- Runs `git status` to verify the correct files are staged
- Checks that `.env`, `node_modules/`, `__pycache__/`, `.pyc` files are not staged
- Flags unrelated files accidentally staged

### Gate 5: Commit Message Format

- Verifies the proposed commit message matches: `type(scope): description (YYYY-MM-DD HH:MM TZ)`
- Valid types: feat, fix, docs, refactor, test, chore, style, perf, ci, build, revert
- Checks: imperative mood, lowercase, no period, max 72 characters, timestamp mandatory

### Gate 6: Tests

- **Backend:** runs the full test suite
- **Frontend:** runs the build (implicit type check)
- All tests must pass

## Tools Available

Read-only bash commands and file reads. Uses Playwright MCP for UI smoke testing when available. Uses `git diff`, `git status`, and test/build commands.

## Key Behaviors

- **Does not run destructive commands.**
- **Does not modify any files** — only reads and reports.
- **If a gate cannot be run** (e.g., no test suite, Playwright unavailable), marks it as SKIP with an explanation.
- **Specific about failures** — includes file:line references.
- Reads `.aid-o/04-engine/command-history.md` before running to find the correct project-specific build and test commands.

## Related

- [Gate Fixer Agent](./gate-fixer)
- [Quality Gates](../skills/quality-gates)
- [Gates Engine Skill](../skills/gates-engine)
