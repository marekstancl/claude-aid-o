---
sidebar_position: 5
title: "Code Reviewer Agent"
description: "Review completed implementation against the plan and project coding standards."
---

# Code Reviewer Agent

The Code Reviewer agent reviews completed implementation against the execution plan and the project's coding standards. It operates in two modes: a full plan-alignment review for major completed steps, and a step acceptance review dispatched by the Controller during PHASE_CHECK to validate whether a step's acceptance criteria are met.

## Role

The Code Reviewer is a **specialist agent**. It does not execute plan steps. It evaluates the work produced by implementation agents and either approves it, requests changes with specific feedback, or flags it for discussion. It adapts its review criteria to the detected technology stack from `project-profile.yaml`.

## When Dispatched

- During PHASE_CHECK when the Controller needs to validate a completed step before accepting it
- When a major project step has been completed and needs formal review
- Runs as part of the step acceptance validation loop (up to the configured maximum review/fix cycles)

## Capabilities

### Plan Alignment Review

- Verifies all planned items are implemented
- Identifies deviations — distinguishes justified improvements from scope violations
- Checks that scope was not expanded beyond what the plan specified

### Coding Standards Review

- **Python/Backend:** type hints on all function signatures, Pydantic schemas for API models, logging instead of print, async for I/O, correct HTTP status codes
- **TypeScript/Frontend:** interfaces for all data structures (no `any`), API calls through service layer (not direct fetch in components), functional components with hooks, proper error handling

### Security Review

- No hardcoded credentials, API keys, or secrets
- Parameterized SQL queries (no string concatenation)
- Input validation at API boundaries
- No sensitive data in error messages or logs

### Architecture Review

- Proper separation of concerns (API → Service → Repository)
- No business logic in route handlers
- Database operations in the appropriate layer
- Frontend components following existing patterns

### Test Coverage Review

- New code has corresponding tests
- Tests are meaningful (not just asserting true)
- Edge cases covered
- Test naming follows project conventions

## Tools Available

Standard Claude Code tools. Reads plan files, git diff, and changed source files. Does not modify any files — produces a structured report only.

## Key Behaviors

- **Always acknowledges what was done well before listing issues.** Constructive review builds trust.
- **Every issue includes a file:line reference, an explanation of why it matters, and a suggested fix.**
- **For step acceptance reviews:** each FAIL must have actionable feedback the implementing agent can act on in the next cycle.
- **Does not reject for issues outside the step's acceptance criteria.** Scope is bounded to what the step was asked to do.
- **If a criterion is ambiguous:** marks as PASS with a note rather than auto-failing.
- **Distinguishes project convention violations from general best practices.** Enforces project-specific rules, not personal preferences.
- Reads `skills/agent-core.md` for project-specific coding rules before reviewing.

## Related

- [Backend Agent](./backend)
- [Frontend Agent](./frontend)
- [QA Agent](./qa)
- [Gate Fixer Agent](./gate-fixer)
- [Quality Gates](../skills/quality-gates)
