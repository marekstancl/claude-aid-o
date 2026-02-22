---
type: example
archetype: "crud-api"
frameworks: [fastapi, sqlalchemy, alembic]
complexity: medium
description: "REST API with CRUD operations, database models, and async SQLAlchemy"
---

# Example EPIC: FastAPI CRUD Service

> **NOTE:** This is a community example EPIC. Adapt resource names, paths, and
> database configuration to your project. Replace all `{placeholder}` values
> with your actual project paths and resource names.

## Context

### When to use
- Building a standard REST API over a relational database (PostgreSQL, SQLite)
- Need full CRUD lifecycle: create, read (list + detail), update, delete
- Project requires async I/O (high concurrent request volume)
- OpenAPI/Swagger documentation is expected by consumers

### When NOT to use
- Event-driven architecture (use Kafka/RabbitMQ + outbox pattern instead)
- Real-time subscriptions (use WebSockets or SSE)
- Read-heavy analytics (OLAP queries; consider materialized views or a data warehouse)
- No relational data model (use a document store if schema is highly dynamic)

Tech stack: FastAPI 0.100+ + SQLAlchemy 2.0+ (async) + Alembic + PostgreSQL.
Greenfield: new `{backend_dir}/app/{resource}/` module following existing module
structure. Auth middleware assumed available from core module.

## Goal

When complete, API consumers can perform full CRUD operations on `{resource}`
via versioned REST endpoints. Requests are validated by Pydantic schemas, data
persists via async SQLAlchemy, schema migrations are managed by Alembic, and
all endpoints are covered by unit and integration tests.

## Scope

### Allowed files/paths
- `{backend_dir}/app/{resource}/` (new module)
  - `{backend_dir}/app/{resource}/models.py` — SQLAlchemy ORM model
  - `{backend_dir}/app/{resource}/schemas.py` — Pydantic request/response schemas
  - `{backend_dir}/app/{resource}/repository.py` — async DB queries (repository pattern)
  - `{backend_dir}/app/{resource}/service.py` — business logic layer
  - `{backend_dir}/app/{resource}/routes.py` — FastAPI router
- `{backend_dir}/alembic/versions/` (new migration file only)
- `{backend_dir}/tests/test_{resource}/`
- `{project_root}/docs/api/{resource}.md`
- `{project_root}/CHANGELOG.md`

### Forbidden zones
- `{backend_dir}/app/core/` (shared DB session, auth, base models — import only)
- `{backend_dir}/app/users/` (separate bounded context)
- `{backend_dir}/alembic/env.py` (migration environment — do not modify)

## Artifacts

- endpoint: POST /api/v1/{resource} (create, returns 201)
- endpoint: GET /api/v1/{resource} (paginated list with cursor or offset)
- endpoint: GET /api/v1/{resource}/{id} (detail, returns 404 if not found)
- endpoint: PATCH /api/v1/{resource}/{id} (partial update)
- endpoint: DELETE /api/v1/{resource}/{id} (soft delete, returns 204)
- model: `{resource}` table (id UUID, fields..., is_deleted bool, created_at, updated_at)
- migration: Alembic revision for `{resource}` table
- doc: `docs/api/{resource}.md`, OpenAPI spec auto-generated, `CHANGELOG.md`

## Constraints

- Tenant-safe: yes (all queries scoped by tenant_id via dependency injection)
- Audit trail: yes (created_at, updated_at, created_by columns)
- Outbox pattern: no
- Structured outputs: yes
- Budget: $10 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- security_scan_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] POST /api/v1/{resource} returns 201 with id and created_at fields
- [ ] [backend] POST /api/v1/{resource} returns 422 for missing required fields
- [ ] [backend] GET /api/v1/{resource} returns 200 with items array and total count
- [ ] [backend] GET /api/v1/{resource} supports ?limit= and ?offset= query params (default limit=20, max=100)
- [ ] [backend] GET /api/v1/{resource}/{id} returns 404 with error detail for unknown id
- [ ] [backend] PATCH /api/v1/{resource}/{id} updates only provided fields (partial update)
- [ ] [backend] DELETE /api/v1/{resource}/{id} returns 204 and soft-deletes (is_deleted=true)
- [ ] [backend] Deleted items excluded from GET /api/v1/{resource} list response
- [ ] [backend] All endpoints return 401 without valid auth token
- [ ] [backend] Alembic migration runs cleanly: `alembic upgrade head` succeeds
- [ ] [qa] Unit tests cover repository layer with in-memory SQLite (no external DB)
- [ ] [qa] Integration tests use FastAPI TestClient and cover all 5 endpoints
- [ ] [qa] Test coverage >= 80% for `app/{resource}/` module
- [ ] [security] No IDOR: user A cannot read/update/delete user B's resources
- [ ] [docs] `docs/api/{resource}.md` includes example requests and response shapes

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design OpenAPI contracts for all 5 endpoints + database schema ADR + project structure decision (repository vs. active record) | — | — |
| 2 | backend | Implement SQLAlchemy async model + Alembic migration + repository class with create/get/list/update/soft-delete methods | 1 | — |
| 3 | backend | Implement FastAPI router with all 5 CRUD routes + Pydantic schemas + service layer + structured error handling (HTTPException with detail) | 2 | — |
| 4 | qa | Write unit tests for repository layer (in-memory SQLite) + integration tests for all 5 endpoints via TestClient | 3 | group-verify |
| 5 | security | Review AuthZ: verify tenant scoping on all queries, check for IDOR, run SAST on routes.py | 3 | group-verify |
| 6 | docs | Write API documentation (docs/api/{resource}.md) + update CHANGELOG.md | 4, 5 | — |

## Session Breakdown

This EPIC fits in a single orchestrated run.

### Session 1: Full CRUD Implementation
**Goal:** Complete models, migrations, routes, tests, security review, and docs.
**Deliverables:** All 5 endpoints, Alembic migration, pytest suite green, docs written.

## Hints

- expected_steps: 6
- complexity: medium
- parallelism_potential: medium (steps 4 and 5 can run in parallel after step 3)
- notes: >
    Repository pattern preferred over direct session usage in routes — keeps
    routes thin and service layer testable. Use SQLAlchemy 2.0 style
    (`async with session.begin()`). For soft delete, add `is_deleted` bool column
    and filter it in `list()` and `get()` repository methods. Pydantic v2 style:
    use `model_config = ConfigDict(from_attributes=True)` for ORM mode.
    TestClient tests should use an in-memory SQLite URL via pytest fixture override.
