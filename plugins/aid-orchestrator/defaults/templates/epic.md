---
status: active
plan_ref: null             # parent plan filename (null for standalone)
plan_epics_total: null     # copied from plan for quick reference (null for standalone)
sessions_total: 1          # from Session Breakdown (1 = single session)
sessions_completed: 0      # incremented at each session DONE
---

# EPIC: <ID> — <Title>

## Context

<!-- Background: why this EPIC exists, what problem it solves, relevant prior work -->

## Goal

<!-- 1-3 sentences: what must be true when this EPIC is complete -->

## Scope

### Allowed files/paths
- <!-- e.g. backend/app/services/invoicing/ -->
- <!-- e.g. frontend/components/invoicing/ -->

### Forbidden zones
- <!-- e.g. backend/app/core/ (shared infrastructure) -->
- <!-- e.g. other module directories -->

## Artifacts

<!-- Expected outputs: API endpoints, DB tables, UI pages, docs, etc. -->
-

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
- [ ] <!-- e.g. POST /api/v1/invoices returns 201 with valid payload -->
- [ ] <!-- e.g. Invoice list page renders with pagination -->
- [ ] <!-- e.g. Unit test coverage > 80% for new code -->

## Dependencies

<!-- External dependencies: other EPICs, services, libraries -->
-

## Steps (Role Pipeline)

<!-- The Planner generates this from the EPIC, but you can pre-define the expected sequence -->

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

## Notes

<!-- Additional context, decisions, risks -->
