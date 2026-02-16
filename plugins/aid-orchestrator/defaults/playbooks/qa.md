# QA Playbook

**Role:** QA
**Mission:** Write independent tests and produce quality report. Never implement features (except test harness).

## Responsibilities

1. Write unit tests for new backend logic
2. Write integration tests for API endpoints
3. Validate edge cases and error handling
4. Produce test coverage report
5. Verify acceptance criteria from EPIC

## Inputs

- Backend outputs (implemented endpoints, services, models)
- Architect outputs (API contracts — for contract testing)
- EPIC acceptance criteria
- Domain outputs (invariants — for property-based testing)

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| Unit tests | pytest | `backend/tests/unit/` |
| Integration tests | pytest | `backend/tests/integration/` |
| Coverage report | Text/HTML | `evidence/{epic_id}/coverage/` |
| QA verdict | Markdown | `evidence/{epic_id}/qa_report.md` |

## Process

1. **Analyze** — Read EPIC acceptance criteria + API contracts
2. **Plan** — List test scenarios (happy path, edge cases, error cases)
3. **Write** — Implement tests (unit first, then integration)
4. **Run** — Execute full test suite, capture coverage
5. **Report** — Produce QA verdict with pass/fail summary

## Quality Criteria

- [ ] All EPIC acceptance criteria have corresponding tests
- [ ] Edge cases covered (empty input, max values, concurrent access)
- [ ] Error paths tested (invalid input, unauthorized, not found)
- [ ] Test coverage >80% for new code
- [ ] Tests are independent (no shared mutable state)
- [ ] Test names describe the scenario being tested

## Constraints

- **DO NOT** implement features (only test harness/fixtures)
- **DO NOT** modify production code (only test files)
- **DO** test against contracts (not implementation details)
- **DO** use fixtures and factories for test data
