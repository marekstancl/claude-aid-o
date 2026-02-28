---
status: active
plan_ref: null             # REQUIRED when EPIC comes from a plan (set to plan filename)
                           # null ONLY for standalone EPICs (no source plan)
plan_epics_total: null     # copied from plan for quick reference (null for standalone)
runs_total: 1          # from Run Breakdown (1 = single run)
runs_completed: 0      # incremented at each run DONE
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
<!-- SCOPE GRANULARITY GUIDANCE:
     Prefer file-level paths (e.g. `src/api/auth.ts`) over broad directory paths
     (e.g. `src/api/`). FIRST AID parallel detection checks scope overlap between
     EPICs to determine if they can run concurrently. Broad directory paths cause
     false overlaps — two EPICs touching different files under `src/api/` will be
     treated as conflicting if both declare the directory. File-level paths enable
     accurate independence detection and better cross-EPIC parallelism.

     Good:  `backend/app/tasks/models.py`, `backend/app/tasks/routes.py`
     Avoid: `backend/app/tasks/` (unless the EPIC truly owns the entire directory)
-->
- <!-- Specific files (preferred for parallel detection): -->
  - <!-- backend/app/tasks/models.py -->
  - <!-- backend/app/tasks/routes.py -->
  - <!-- backend/app/tasks/schemas.py -->
- <!-- Directories (only when the EPIC owns the entire directory): -->
  - <!-- backend/app/tasks/ -->

### Forbidden zones
<!-- SPECIFICITY GUIDANCE:
     Be specific with forbidden zones too. Declaring a broad directory as forbidden
     (e.g. `src/`) blocks any EPIC whose allowed paths fall within it from running
     in parallel, even if the actual conflict is limited to a single file.
     Narrow forbidden zones reduce false positives in parallel detection.

     Good:  `backend/app/core/auth.py`, `backend/app/core/config.py`
     Avoid: `backend/app/core/` (unless the entire directory is truly off-limits)
-->
- <!-- e.g. backend/app/core/auth.py (specific shared file) -->
- <!-- e.g. backend/app/core/ (entire shared directory — use only when needed) -->

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

### Internal (same plan)
<!-- Auto-generated: previous phases from this plan -->

### External (other plans/EPICs)
<!-- From plan Dependencies section — cross-plan deps -->

### Queue Implications
depends_on: []

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

## Run Breakdown

<!-- For multi-run EPICs, plan the run split -->

### Run 1: <Topic>
**Goal:** ...
**Deliverables:** ...

### Run 2: <Topic>
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
