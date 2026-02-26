---
sidebar_position: 18
title: "Quality Gates"
description: "The pre-commit 6-gate protocol that every agent must pass before committing: log analysis, documentation impact, code cleanup, git status, commit message format, and tests."
---

# Quality Gates

The quality gates skill defines the six-gate protocol that every AID agent must complete before making a commit. All six gates must pass — if any gate fails, the agent fixes the issue and re-runs all gates from the beginning. This skill applies to individual agents doing single-run work; for post-EPIC step gates, see the [Gates Engine](../skills/gates-engine).

## Purpose

Commits without quality checks accumulate problems that compound over time: broken startup logs that nobody notices, outdated documentation that misleads, debug statements that slip into production, credentials that get accidentally committed. The 6-gate protocol catches all of these before they enter the repository.

The time investment is 3-5 minutes per commit. That is the cost. The benefit is a consistently clean repository where every commit is verifiably safe to merge.

## When Used

- Before every commit that includes code, configuration, refactoring, bug fixes, or features
- Enforced by the `quality-gates-runner` utility agent
- Referenced in `agent-core` as Absolute Rule #2
- The `gates-engine` skill runs a separate, configurable set of gates after EPIC steps complete (different scope)

## Key Concepts

### Gate Ordering

Gates must run in order. If any gate fails, fix the issue and restart from Gate 1:

```
Code ready → Gate 1 → Gate 2 → Gate 3 → Gate 4 → Gate 5 → Gate 6 → Commit
                 ↑_____________if any fails, restart from Gate 1____________|
```

### Gate 1: Log Analysis and UI Smoke Test (CRITICAL)

Verify changes do not break runtime and UI renders correctly.

**Backend and frontend log check**: start the frontend dev server and the backend server, watch logs for 30 seconds each. Fail if any new ERRORs appear or the server crashes. Pre-existing known warnings are documented in the run file, not treated as failures.

**Playwright UI smoke test** (only for UI changes): navigate to affected pages, check browser console for JavaScript errors, verify key elements are visible in the accessibility snapshot, take a screenshot as visual evidence. Skip for backend-only, config-only, and docs-only changes.

### Gate 2: Documentation Impact Analysis (CRITICAL)

Run `git diff --name-only` and for each changed file, determine which documentation is affected:

| Code Change | Usually Affects |
|---|---|
| Database models | ERD, schema docs |
| API endpoints | API docs, integration guides |
| Core business logic | System overview, architecture |
| UI components | Component docs, UI guide |
| Any `feat:` or `fix:` commit | CHANGELOG.md |
| Breaking changes | Migration guide |

Update all affected documentation and stage the changes. If uncertain which docs need updating, escalate to PM with the list of changed files — do not guess.

### Gate 3: Code Cleanup (HIGH)

Check for and remove: temporary files (`*.tmp`, `*.bak`), debug statements (`console.log`, `print()`, `debugger`, `pdb.set_trace()`), large commented-out code blocks, TODO/FIXME comments in production code (move to backlog), hardcoded credentials (replace with environment variables), and test data in production code (move to fixtures).

### Gate 4: Git Status Check (HIGH)

Review `git status` and `git diff --cached`. Verify that all code files with changes are staged, documentation is staged, and the CHANGELOG and run file are staged if appropriate. Verify that `.env` files, `node_modules/`, `__pycache__/`, `dist/`, and build artifacts are not staged.

### Gate 5: Commit Message Format (MEDIUM)

Verify the commit message follows the project format: `type(scope): description (YYYY-MM-DD HH:MM TZ)`. Valid types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`. The description must be specific enough to understand without reading the diff.

### Gate 6: Tests Pass (CRITICAL)

Run the project's test suite and verify all tests pass. If tests were added as part of this change, they must also pass. Use the project's configured test command from `project-profile.yaml`. A test failure at this gate means fixing the implementation or the test, then re-running all gates from Gate 1.

## How It Works

The agent runs each gate sequentially, documenting results in the run file. Any failure stops the sequence: the agent fixes the issue (without committing) and restarts at Gate 1. Only when all six gates pass is the commit allowed.

The `quality-gates-runner` utility agent automates this sequence. It is invoked by the `agent-core` Absolute Rule #2 before every commit during EPIC execution.

## Configuration

Gate commands adapt to the project's tech stack using `project-profile.yaml`:
- Frontend test command: from `project.paths.frontend` and `project.tech_stack`
- Backend test command: from `project.paths.backend` and `project.tech_stack`
- Docs build command: from `project.docs.platform` and `project.docs.path`

## Related

- [Agent Core](../skills/agent-core)
- [Gates Engine](../skills/gates-engine)
- [Run Management](../skills/run-management)
