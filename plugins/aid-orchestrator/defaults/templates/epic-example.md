# EPIC: EXAMPLE-0001 — Task Management Module

> **NOTE:** This is a reference example, not a real EPIC. It demonstrates
> the expected format, level of detail, and conventions for writing EPICs
> that the AID Orchestrator can process through `/plan-epic` and `/run-epic`.

## Context

The project needs a task management module with CRUD API endpoints, a frontend
list/detail view, and proper observability. This is a greenfield feature within
an existing FastAPI + React + PostgreSQL stack. No existing task management code
exists — this is a new bounded context.

## Goal

When complete, authenticated users can create, list, update, and delete tasks
via REST API. The React frontend renders a task board with filtering, and all
operations produce structured audit logs and OpenTelemetry traces.

## Scope

### Allowed files/paths
- `backend/app/tasks/` (new module)
- `backend/app/tasks/models.py`
- `backend/app/tasks/routes.py`
- `backend/app/tasks/schemas.py`
- `backend/app/tasks/service.py`
- `backend/tests/test_tasks/`
- `frontend/src/features/tasks/`
- `frontend/src/features/tasks/components/`
- `frontend/src/features/tasks/hooks/`
- `docs/api/tasks.md`
- `docs/architecture/adr/`
- `CHANGELOG.md`

### Forbidden zones
- `backend/app/core/` (shared infrastructure — auth, database, base models)
- `backend/app/users/` (separate bounded context)
- `frontend/src/shared/` (shared components — use but don't modify)
- `alembic/` (migrations managed separately)

## Artifacts

- 4 REST endpoints: POST, GET (list + detail), PATCH, DELETE `/api/v1/tasks`
- PostgreSQL table: `tasks` with tenant isolation
- React components: `TaskBoard`, `TaskCard`, `TaskForm`, `TaskFilter`
- OpenAPI spec: `openapi_tasks.yaml`
- ADR: `ADR-015-task-state-machine.md`
- Updated: `CHANGELOG.md`, `docs/api/tasks.md`

## Constraints

- Tenant-safe: yes (all queries scoped by tenant_id)
- Audit trail: yes (created_by, updated_by, timestamps)
- Outbox pattern: no (not event-driven)
- Structured outputs: yes
- Budget: $15 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- security_scan_pass
- docs_updated
- type_check

## Acceptance Criteria

- [ ] POST /api/v1/tasks returns 201 with valid JSON payload
- [ ] GET /api/v1/tasks returns paginated list (default 20 per page)
- [ ] GET /api/v1/tasks/{id} returns 404 for non-existent task
- [ ] PATCH /api/v1/tasks/{id} updates only specified fields
- [ ] DELETE /api/v1/tasks/{id} returns 204 (soft delete)
- [ ] All endpoints require authentication (401 without token)
- [ ] Tenant isolation: user A cannot see user B's tasks
- [ ] TaskBoard component renders with loading, empty, and data states
- [ ] TaskForm validates required fields (title, status) client-side
- [ ] Unit test coverage > 80% for backend/app/tasks/
- [ ] No HIGH/CRITICAL findings in security scan
- [ ] OpenTelemetry spans on all API endpoints
- [ ] API docs page builds without errors

## Dependencies

- Authentication module must be deployed (provides JWT middleware)
- PostgreSQL schema migration for `tasks` table (created separately)

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design API contracts (OpenAPI) + ADR for task state machine | -- | -- |
| 2 | domain | Define Task entity, value objects, invariants | 1 | -- |
| 3 | backend | Implement API endpoints + DB models + service layer | 2 | group-impl |
| 4 | frontend | Build TaskBoard, TaskCard, TaskForm, TaskFilter components | 1 | group-impl |
| 5 | qa | Write unit + integration tests for backend + frontend | 3, 4 | group-verify |
| 6 | security | AuthZ review + SAST scan of new endpoints | 3 | group-verify |
| 7 | observability | Add OTel instrumentation to API endpoints | 3 | group-verify |
| 8 | docs | Update API docs + CHANGELOG + architecture overview | 3, 4 | -- |
| 9 | release | Deployment config + smoke test definition | 5, 6 | -- |

## Session Breakdown

This EPIC fits in a single orchestrated run (no session split needed).

### Session 1: Full Implementation
**Goal:** Complete task management module end-to-end.
**Deliverables:** All artifacts listed above.

## Notes

- Task states: `draft`, `open`, `in_progress`, `done`, `archived`
- The state machine is simple (no complex transitions) — ADR should justify this choice
- Frontend uses existing `useAuth()` hook from shared components
- Observability uses existing OTel setup in `backend/app/core/telemetry.py`
- Security focus: ensure no IDOR vulnerabilities on task endpoints
