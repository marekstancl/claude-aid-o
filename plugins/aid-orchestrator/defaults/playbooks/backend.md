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
