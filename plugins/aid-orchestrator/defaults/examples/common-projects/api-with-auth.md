---
type: example
archetype: "api-with-auth"
frameworks: [fastapi, sqlalchemy, postgresql, redis]
complexity: medium
description: "REST API with JWT authentication, role-based access control, rate limiting, and OpenAPI docs"
platforms: []
ui: none
---

# Example EPIC: REST API with Authentication

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Building a backend API that other services or frontends consume
- Need JWT-based authentication with refresh token rotation
- Role-based access control (admin, user, readonly roles)
- Rate limiting to protect against abuse
- OpenAPI/Swagger documentation auto-generated

### When NOT to use
- Server-rendered web application (use Next.js or similar full-stack framework)
- GraphQL API (use Strawberry or Ariadne instead of REST)
- Microservices with service-to-service auth (use mTLS or API gateway)
- Simple internal tool with no external access (skip auth complexity)

Tech stack: FastAPI 0.100+ + SQLAlchemy 2.0 (async) + PostgreSQL + Redis + Alembic.
Greenfield: new project with `{backend_dir}/app/` structure.
Pattern: repository pattern, dependency injection, JWT with refresh tokens.

## Goal

When complete, the API provides user registration, login (JWT access + refresh
tokens), role-based route protection, per-user rate limiting via Redis, and
auto-generated OpenAPI documentation. All endpoints return consistent error
responses with proper HTTP status codes.

## Scope

### Allowed files/paths
- `{backend_dir}/app/`
  - `{backend_dir}/app/auth/` — JWT creation/validation, password hashing, dependencies
  - `{backend_dir}/app/users/` — User model, schemas, repository, routes
  - `{backend_dir}/app/core/` — config, database session, security utilities
  - `{backend_dir}/app/middleware/` — rate limiter, CORS, error handlers
  - `{backend_dir}/app/main.py` — FastAPI app factory
- `{backend_dir}/alembic/` (migrations)
- `{backend_dir}/tests/`
- `{project_root}/docs/`

### Forbidden zones
- None (greenfield project)

## Artifacts

- endpoint: POST /api/v1/auth/register (create account)
- endpoint: POST /api/v1/auth/login (returns access + refresh tokens)
- endpoint: POST /api/v1/auth/refresh (rotate refresh token)
- endpoint: GET /api/v1/users/me (current user profile)
- endpoint: GET /api/v1/users (admin only — list all users)
- endpoint: PATCH /api/v1/users/{id}/role (admin only — change user role)
- model: User table (id UUID, email, hashed_password, role, is_active, timestamps)
- middleware: rate_limiter (Redis-backed, per-user, configurable limits)
- config: OpenAPI auto-generated at /docs

## Constraints

- Tenant-safe: no (single-tenant)
- Audit trail: yes (created_at, updated_at, last_login)
- Budget: $12 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- type_check
- security_scan_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] POST /register creates user with hashed password (bcrypt), returns 201
- [ ] [backend] POST /login returns JWT access token (15min) + refresh token (7 days)
- [ ] [backend] POST /refresh rotates refresh token and returns new access token
- [ ] [backend] Protected endpoints return 401 without valid token, 403 without required role
- [ ] [backend] Rate limiter: 100 requests/min per user, 20/min for unauthenticated, returns 429
- [ ] [backend] PATCH /users/{id}/role restricted to admin role
- [ ] [backend] All error responses follow consistent schema: {detail, status_code}
- [ ] [security] Passwords hashed with bcrypt, JWT signed with RS256 or HS256
- [ ] [security] Refresh token stored in DB, revocable per user
- [ ] [qa] Unit tests: auth flow, RBAC middleware, rate limiter
- [ ] [qa] Integration tests: register → login → access protected route → refresh token
- [ ] [docs] OpenAPI spec accessible at /docs with all endpoints documented

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design auth flow (JWT + refresh), DB schema, rate limiting strategy, error response contract | — | — |
| 2 | backend | Implement core: config, async DB session, SQLAlchemy base model, Alembic setup | 1 | — |
| 3 | backend | Implement User model + repository + Alembic migration | 2 | — |
| 4 | backend | Implement auth: JWT creation/validation, password hashing, login/register/refresh endpoints | 3 | — |
| 5 | backend | Implement RBAC dependency + rate limiter middleware (Redis) + CORS + error handlers | 4 | — |
| 6 | security | Review auth flow: token storage, RBAC enforcement, password handling, rate limiter bypass | 5 | group-verify |
| 7 | qa | Write tests for auth flow, RBAC, rate limiter | 5 | group-verify |
| 8 | docs | API documentation + setup guide | 6, 7 | — |

## Docker Compose

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: api
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: api
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U api"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  api:
    build:
      context: ./{backend_dir}
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      DATABASE_URL: postgresql+asyncpg://api:${POSTGRES_PASSWORD}@postgres:5432/api
      REDIS_URL: redis://redis:6379
      JWT_SECRET_KEY: ${JWT_SECRET_KEY}
      JWT_ALGORITHM: HS256
      ACCESS_TOKEN_EXPIRE_MINUTES: 15
      REFRESH_TOKEN_EXPIRE_DAYS: 7
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started

volumes:
  postgres_data:
  redis_data:
```

## Notes

- Use SQLAlchemy 2.0 async style: `async with session.begin()` for transactions
- Repository pattern keeps routes thin and business logic testable
- JWT refresh token rotation: on each /refresh, invalidate old token, issue new pair
- Redis rate limiter: use sliding window counter pattern per user ID
- FastAPI dependency injection for auth: `current_user = Depends(get_current_user)`
- For production: use RS256 (asymmetric) JWT signing for microservice architectures
- Pydantic v2: `model_config = ConfigDict(from_attributes=True)` for ORM mode
