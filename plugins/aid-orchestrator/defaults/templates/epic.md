---
status: active
plan_ref: null             # REQUIRED when EPIC comes from a plan (set to plan filename)
                           # null ONLY for standalone EPICs (no source plan)
plan_epics_total: null     # copied from plan for quick reference (null for standalone)
sessions_total: 1          # from Session Breakdown (1 = single session)
sessions_completed: 0      # incremented at each session DONE
---

<!-- plan_ref: Links this EPIC to its source plan in .aid-o/01-plans/.
     When set, the execution pipeline reads the source plan for implementation detail.
     Agents receive relevant plan sections alongside EPIC step definitions.
     This is Variant B: EPIC = structured spec, Plan = implementation guide, both read during execution. -->

# EPIC: <ID> — <Title>

## Context

<!-- REQUIRED for planner quality: -->
<!-- - Tech stack (e.g. FastAPI + React + PostgreSQL) -->
<!-- - Greenfield (new module) vs. brownfield (modifying existing) -->
<!-- - Existing patterns to follow (e.g. "follows same structure as users/ module") -->
<!-- - Prior work this builds on (e.g. "extends auth from EPIC-003") -->

## Goal

<!-- 1-3 sentences: what must be true when this EPIC is complete -->

## Scope

### Allowed files/paths
- <!-- Directories: backend/app/tasks/ -->
- <!-- Specific files (helps planner scope agents): -->
  - <!-- backend/app/tasks/models.py -->
  - <!-- backend/app/tasks/routes.py -->
  - <!-- backend/app/tasks/schemas.py -->

### Forbidden zones
- <!-- e.g. backend/app/core/ (shared infrastructure) -->
- <!-- e.g. other module directories -->

## Artifacts

<!-- Type each artifact for planner layer detection: -->
<!-- endpoint: POST /api/v1/tasks, GET /api/v1/tasks, ... -->
<!-- model: tasks table (id, title, status, tenant_id, timestamps) -->
<!-- component: TaskBoard, TaskCard, TaskForm -->
<!-- config: deployment config, env vars -->
<!-- doc: API docs, ADR, CHANGELOG -->
- endpoint:
- model:
- component:
- doc:

## Constraints

- Tenant-safe: yes/no
- Audit trail: yes/no
- Outbox pattern: yes/no
- Structured outputs: yes/no
- Budget: $XX max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- security_scan_pass
- docs_updated

## Acceptance Criteria

<!-- Specific, testable criteria that define "done" -->
<!-- Prefix with [role] where applicable: [backend], [frontend], [qa], [security], [docs] -->
- [ ] <!-- e.g. [backend] POST /api/v1/invoices returns 201 with valid payload -->
- [ ] <!-- e.g. [frontend] Invoice list page renders with pagination -->
- [ ] <!-- e.g. [qa] Unit test coverage > 80% for new code -->

## Dependencies

<!-- External dependencies: other EPICs, services, libraries -->
-

## Steps (Role Pipeline)

<!-- OPTIONAL: If you define steps, the Planner treats them as constraints. -->
<!-- If omitted, the Planner generates steps from Artifacts + AC + Scope. -->
<!-- Tip: For complex EPICs (7+ expected steps), define at least the critical path. -->

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design API contracts + ADR | — | — |
| 2 | domain | Domain model + invariants | architect | — |
| 3 | backend | Implement API + DB + outbox | domain | group-1 |
| 4 | frontend | Implement UI against contracts | architect | group-1 |
| 5 | qa | Unit + integration tests | backend | group-2 |
| 6 | security | AuthZ + SAST review | backend | group-2 |
| 7 | observability | OTel instrumentation | backend | group-2 |
| 8 | docs | Update documentation + changelog | backend | group-3 |
| 9 | release | Deployment config + smoke tests | qa, security | group-3 |

## Session Breakdown

<!-- For multi-session EPICs, plan the session split -->

### Session 1: <Topic>
**Goal:** ...
**Deliverables:** ...

### Session 2: <Topic>
**Goal:** ...
**Deliverables:** ...

## Hints (Optional)

<!-- Help the planner make better decisions: -->
- expected_steps: <!-- e.g. 5-8 -->
- complexity: <!-- low | medium | high -->
- parallelism_potential: <!-- low | medium | high -->
- notes: <!-- e.g. "backend and frontend are fully independent" -->

## Notes

<!-- Additional context, decisions, risks -->
