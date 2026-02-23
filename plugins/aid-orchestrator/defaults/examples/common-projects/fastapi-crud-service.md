---
type: example
archetype: "crud-api-service"
frameworks: [fastapi, sqlalchemy, alembic, pydantic, postgresql, docker]
complexity: medium
description: "Production-ready FastAPI REST API with async CRUD, PostgreSQL, Alembic migrations, Docker Compose"
platforms: []
ui: none
---

# Example EPIC: FastAPI CRUD Service

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building a standard REST API over a relational database (PostgreSQL)
- Need full CRUD lifecycle: create, read (list + detail), update, delete
- Project requires async I/O for high concurrent request volume
- OpenAPI/Swagger documentation is expected by API consumers
- Want a production-ready containerized service with health checks and migrations

### When NOT to use
- Event-driven architecture requiring message brokers (use Kafka/RabbitMQ + outbox pattern)
- Real-time subscriptions with sub-second updates (use WebSockets or SSE)
- Read-heavy analytics workloads (consider materialized views or a data warehouse)
- Highly dynamic schema without relational constraints (use a document store)
- Simple prototyping where SQLite + sync is sufficient

Tech stack: FastAPI 0.115+ + SQLAlchemy 2.0+ (async) + Alembic + Pydantic v2 + PostgreSQL 16 + Docker.
Greenfield: new `{backend_dir}/app/{resource}/` module following existing module structure.
Pattern: Repository pattern with service layer, Annotated dependency injection, async throughout.

## Goal

When complete, API consumers can perform full CRUD operations on `{resource}`
via versioned REST endpoints. Requests are validated by Pydantic v2 schemas with
`model_config = ConfigDict(from_attributes=True)`, data persists via async
SQLAlchemy 2.0, schema migrations are managed by Alembic, and all endpoints are
covered by unit and integration tests. The service runs in Docker with health
checks and auto-restarts.

## Scope

### Allowed files/paths
- `{backend_dir}/app/{resource}/` (new module)
  - `{backend_dir}/app/{resource}/__init__.py`
  - `{backend_dir}/app/{resource}/models.py` — SQLAlchemy 2.0 async ORM model
  - `{backend_dir}/app/{resource}/schemas.py` — Pydantic v2 request/response schemas
  - `{backend_dir}/app/{resource}/repository.py` — async DB queries (repository pattern)
  - `{backend_dir}/app/{resource}/service.py` — business logic layer
  - `{backend_dir}/app/{resource}/routes.py` — FastAPI APIRouter
  - `{backend_dir}/app/{resource}/dependencies.py` — Annotated dependency definitions
- `{backend_dir}/alembic/versions/` (new migration file only)
- `{backend_dir}/tests/test_{resource}/`
- `{project_root}/docs/api/{resource}.md`
- `{project_root}/docker-compose.yml`
- `{project_root}/Dockerfile`
- `{project_root}/CHANGELOG.md`

### Forbidden zones
- `{backend_dir}/app/core/` (shared DB session, auth, base models — import only)
- `{backend_dir}/app/users/` (separate bounded context)
- `{backend_dir}/alembic/env.py` (migration environment — do not modify)
- `{backend_dir}/app/main.py` (only add router include, do not restructure)

## Artifacts

- endpoint: POST /api/v1/{resource} (create, returns 201)
- endpoint: GET /api/v1/{resource} (paginated list with offset/limit, returns total count)
- endpoint: GET /api/v1/{resource}/{id} (detail, returns 404 if not found)
- endpoint: PATCH /api/v1/{resource}/{id} (partial update with `model_dump(exclude_unset=True)`)
- endpoint: DELETE /api/v1/{resource}/{id} (soft delete, returns 204)
- endpoint: GET /api/v1/health (liveness + readiness probe)
- model: `{resource}` table (id UUID, fields..., is_deleted bool, created_at, updated_at, created_by)
- migration: Alembic revision for `{resource}` table
- doc: `docs/api/{resource}.md`, OpenAPI spec auto-generated, `CHANGELOG.md`

## Constraints

- Tenant-safe: yes (all queries scoped by tenant_id via Annotated dependency injection)
- Audit trail: yes (created_at, updated_at, created_by columns)
- Structured outputs: yes (Pydantic v2 strict mode)
- Budget: $10 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- security_scan_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] POST /api/v1/{resource} returns 201 with id and created_at fields
- [ ] [backend] POST /api/v1/{resource} returns 422 for missing required fields with Pydantic v2 error details
- [ ] [backend] GET /api/v1/{resource} returns 200 with `items` array and `total` count; supports `?limit=` (default 20, max 100) and `?offset=` params
- [ ] [backend] GET /api/v1/{resource}/{id} returns 404 with `{"detail": "..."}` for unknown UUID
- [ ] [backend] PATCH /api/v1/{resource}/{id} updates only provided fields using `model_dump(exclude_unset=True)`
- [ ] [backend] DELETE /api/v1/{resource}/{id} returns 204 and sets `is_deleted=True` (soft delete)
- [ ] [backend] Deleted items excluded from GET list response; `?include_deleted=true` overrides for admin role
- [ ] [backend] All endpoints return 401 without valid auth token
- [ ] [backend] Alembic migration runs cleanly: `alembic upgrade head` succeeds on fresh DB
- [ ] [qa] Unit tests cover repository layer with async SQLite in-memory (no external DB required)
- [ ] [qa] Integration tests use `httpx.AsyncClient` with `ASGITransport` and cover all 5 CRUD endpoints
- [ ] [qa] Test coverage >= 80% for `app/{resource}/` module
- [ ] [security] No IDOR: user A cannot read/update/delete user B's resources (tenant_id enforced)
- [ ] [docs] `docs/api/{resource}.md` includes example curl commands and response shapes
- [ ] [infra] `docker compose up` starts API + PostgreSQL with health checks passing within 30s

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design OpenAPI contracts for all 5 endpoints + database schema ADR + project structure (repository pattern, Annotated DI, Pydantic v2 ConfigDict) | — | — |
| 2 | backend | Implement SQLAlchemy 2.0 async model with `mapped_column()` + Alembic migration + repository class with create/get/list/update/soft-delete methods using `async with session.begin()` | 1 | — |
| 3 | backend | Implement FastAPI router with all 5 CRUD routes + Pydantic v2 schemas (Base/Create/Update/Public split) + service layer + Annotated `SessionDep` dependency + structured error handling | 2 | — |
| 4 | qa | Write unit tests for repository layer (async in-memory SQLite) + integration tests for all 5 endpoints via `httpx.AsyncClient` with `ASGITransport` | 3 | group-verify |
| 5 | security | Review AuthZ: verify tenant scoping on all queries, check for IDOR, validate input sanitization, run SAST on routes.py | 3 | group-verify |
| 6 | devops | Create Dockerfile (multi-stage, Python 3.12-slim) + docker-compose.yml with PostgreSQL 16, health checks, volume mounts | 3 | group-verify |
| 7 | docs | Write API documentation (docs/api/{resource}.md) with curl examples + update CHANGELOG.md | 4, 5, 6 | — |

## Docker Compose

```yaml
version: "3.9"

services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: fastapi-crud-api
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql+asyncpg://app_user:app_password@db:5432/app_db
      SECRET_KEY: ${SECRET_KEY:-change-me-in-production}
      ENVIRONMENT: development
      LOG_LEVEL: info
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    volumes:
      - ./app:/code/app
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    container_name: fastapi-crud-db
    environment:
      POSTGRES_USER: app_user
      POSTGRES_PASSWORD: app_password
      POSTGRES_DB: app_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app_user -d app_db"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

volumes:
  postgres_data:
```

## Notes

- **Pydantic v2 patterns:** Use `model_config = ConfigDict(from_attributes=True)` for ORM mode.
  Split schemas into `{Resource}Base`, `{Resource}Create`, `{Resource}Update` (all Optional),
  and `{Resource}Public` (with `id`, `created_at`).
- **SQLAlchemy 2.0:** Use `mapped_column()` declarative style, `async with session.begin()`
  for transactions, `select()` construct instead of legacy Query API.
- **Annotated DI:** Define `SessionDep = Annotated[AsyncSession, Depends(get_session)]` for
  clean dependency injection throughout routes.
- **Testing:** Use `httpx.AsyncClient` with `ASGITransport(app=app)` instead of the deprecated
  `TestClient` for async endpoint testing. Repository tests use async SQLite in-memory.
- **Soft delete:** Add `is_deleted: Mapped[bool] = mapped_column(default=False)` column.
  Filter in repository `list()` and `get()` by default; expose `include_deleted` param for admin.
- **Alternative:** For simpler projects, consider SQLModel (combines SQLAlchemy + Pydantic)
  with `Hero.model_validate()` pattern as shown in FastAPI docs.
