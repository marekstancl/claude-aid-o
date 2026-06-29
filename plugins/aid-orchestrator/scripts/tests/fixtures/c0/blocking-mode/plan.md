# Plan: C0 Blocking Mode Test Plan

This plan intentionally omits the frontmatter block, Goal section, and Scope
section to trigger schema_completeness findings when running in blocking mode.

## Steps

| # | Role | Objective |
|---|------|-----------|
| 1 | backend | Implement service A |
| 2 | backend | Implement service B |
| 2 | backend | Duplicate backend step for testing (same number and role) |
| 3 | devops | Set up deployment |

## Constraints

- Intentional defects for blocking-mode testing
