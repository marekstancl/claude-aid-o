# EPIC: TEST-0001 — Add Health Check Endpoint

## Context

Smoke test EPIC for validating the AID orchestrator pipeline end-to-end.
Simple scope: one backend endpoint, minimal frontend, basic tests.

## Goal

Add a `/api/v1/health` endpoint that returns system health status including
database connectivity and version info.

## Scope

### Allowed files/paths
- backend/app/api/health.py
- backend/app/services/health_service.py
- backend/tests/test_health.py
- frontend/components/HealthBadge.tsx
- docs/api/health.md

### Forbidden zones
- backend/app/core/
- backend/app/models/
- frontend/pages/

## Artifacts

- GET /api/v1/health endpoint
- HealthBadge UI component
- API documentation
- Unit tests

## Constraints

- Tenant-safe: no
- Audit trail: no
- Outbox pattern: no
- Structured outputs: yes
- Budget: $5 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- security_scan_pass
- docs_updated

## Acceptance Criteria

- [ ] GET /api/v1/health returns 200 with JSON { "status": "ok", "version": "x.y.z", "db": "connected" }
- [ ] Endpoint responds in < 500ms
- [ ] HealthBadge component shows green/red based on status
- [ ] Unit tests cover happy path and DB failure scenario
- [ ] API docs updated with endpoint description

## Dependencies

- None (standalone feature)

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Define /health API contract (OpenAPI) | — | — |
| 2 | domain | Define health check model (status, version, db) | architect | — |
| 3 | backend | Implement health endpoint + service | domain | group-1 |
| 4 | frontend | Implement HealthBadge component | architect | group-1 |
| 5 | qa | Write unit + integration tests | backend | group-2 |
| 6 | security | Verify no sensitive data in health response | backend | group-2 |
| 7 | docs | Update API docs with /health endpoint | backend | — |

## Session Breakdown

### Session 1 (this EPIC fits in a single session)
**Goal:** Complete all steps end-to-end
**Deliverables:** Working endpoint, component, tests, docs

## Notes

- This is a smoke test EPIC — intentionally simple
- Used to validate the Controller state machine flow end-to-end
