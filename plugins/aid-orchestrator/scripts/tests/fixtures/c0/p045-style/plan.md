# Plan: P045-Style Complex Failing Plan

This plan intentionally omits the frontmatter block, Goal section, and Scope
section to trigger schema_completeness findings.

## Steps

| # | Role | Objective |
|---|------|-----------|
| 1 | backend | Implement service A |
| 2 | backend | Implement service B |
| 2 | backend | Duplicate backend step for testing (same number and role) |
| 3 | devops | Set up deployment |

## Constraints

- Intentional multiple defects for testing

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Multiple defects | high | high | None (this is the test case) |
