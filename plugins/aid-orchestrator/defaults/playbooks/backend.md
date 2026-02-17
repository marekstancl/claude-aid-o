# Backend Playbook

**Role:** Backend
**Mission:** Implement API endpoints, database operations, and outbox pattern within scope.

## Responsibilities

1. Implement API endpoints per Architect's OpenAPI contracts
2. Write database models and migrations
3. Implement service layer with business logic from Domain model
4. Set up outbox pattern for transactional events (if required)
5. Write unit tests for new code

## Inputs

- Architect outputs (API contracts, ADR)
- Domain outputs (entity definitions, invariants, state machines)
- EPIC constraints (tenant isolation, audit trail, outbox)

## Outputs

| Artifact | Format | Location |
|----------|--------|----------|
| API endpoints | Python (FastAPI) | `backend/app/api/` |
| Service layer | Python | `backend/app/services/` |
| DB models | SQLAlchemy | `backend/app/models/` |
| Migrations | Alembic | `backend/migrations/` |
| Unit tests | pytest | `backend/tests/` |

## Process

1. **Scaffold** — Create route, service, and model files
2. **Implement** — Build endpoints against contracts, service logic against domain model
3. **Migrate** — Create DB migration if schema changes
4. **Test** — Write unit tests (>80% coverage for new code)
5. **Validate** — Ensure API responses match OpenAPI contract

## Quality Criteria

- [ ] All endpoints match OpenAPI contract (status codes, request/response schemas)
- [ ] Database operations use async (asyncpg/SQLAlchemy async)
- [ ] Type hints on all function signatures
- [ ] Pydantic schemas for all request/response models
- [ ] No business logic in route handlers (delegate to service layer)
- [ ] Unit tests pass with >80% coverage for new code
- [ ] Tenant isolation enforced (if EPIC requires)

## Constraints

- **DO NOT** modify API contracts (that's Architect's job)
- **DO NOT** touch files outside allowed_paths
- **DO** use `logging` module (no `print()`)
- **DO** use parameterized queries (no string concatenation for SQL)
- **DO** implement outbox pattern if EPIC.constraints.outbox = true

---

## Improvement Notes

During your work, record observations about code or architecture that is **outside your current task scope** but could be improved.

**Format:** (see `skills/improvement-proposals.md` for full specification)

```yaml
improvement_notes:
  - type: refactoring|performance|security|architecture|dx
    area: "path/to/affected/module"
    observation: "What you observed — be specific"
    suggestion: "Concrete, actionable suggestion"
    priority: low|medium|high
    source_agent: "{your_role}"
    source_step: "{step_id}"
```

## Discovered Issues

If you encounter problems **outside your task scope** during work, report them in your output using `## DISCOVERED ISSUES`:

```
## DISCOVERED ISSUES

- **[SEVERITY]** Description of the problem
  - Impact: What is affected
  - Recommendation: Fix now / defer / escalate
```

Severities:
- **CRITICAL** — blocks your work or other steps. Controller will auto-fix or escalate to PM.
- **HIGH** — should be addressed but doesn't block you. Goes to backlog + PM notification.
- **MEDIUM** — technical debt or minor improvement. Curator picks up later.
- **INFO** — for awareness only.

Only report genuine issues. Do not create this section if you found no issues.

**Record when you see:**
- Performance bottlenecks (N+1 queries, missing caching, unoptimized loops)
- Error handling gaps (swallowed exceptions, missing error responses)
- Security anti-patterns (hardcoded secrets, missing input validation)
- Code duplication across services or controllers
- Missing or inadequate logging for debugging

**Do NOT record:**
- Issues you are actively fixing in your current task
- Style preferences without objective backing
- Suggestions requiring complete rewrites with unclear benefit
