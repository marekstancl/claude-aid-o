---
status: active
plan_ref: .aid-o/plans/P005-C-aid-gui-backend-post-prototype.md
plan_epics_total: 4
runs_total: 1
runs_completed: 0
---

# EPIC: E-005-1_4 — AID GUI Foundation: Cleanup, Structure, Types & Parsers

## Context

Tech stack: TypeScript + Express + Vite (existing AI Studio scaffold, currently standalone AID-GUI repo).
Brownfield: Transforming an AI Studio prototype with mock data into a real project structure.

## Goal

Move AID-GUI into `ai-orchestrator/packages/aid-gui/`, establish a clean, well-structured project foundation for the AID GUI backend.

## Scope

### Allowed files/paths
- packages/aid-gui/server/
- packages/aid-gui/tests/

### Forbidden zones
- packages/aid-gui/src/
- plugins/

## Artifacts

- model: server/types.ts — TypeScript interfaces for all .aid-o/ entities
- endpoint: server/parsers/ — YAML, JSONL, Markdown, JSON parsers

## Constraints

- Runtime: Node.js >= 18
- Language: TypeScript strict mode
- Defensive parsing: parsers must handle malformed input gracefully

## DoD Gates

- tests_pass
- lint_pass
- type_check

## Acceptance Criteria

- [ ] [backend] server/ directory exists with index.ts, types.ts, parsers/ subdirectory
- [ ] [domain] server/types.ts defines all required interfaces
- [x] [backend] YAML parser handles valid and malformed YAML
- [ ] [qa] Unit tests cover each parser with real .aid-o/ fixture files
- [ ] [qa] All parser tests pass

## Dependencies

- No external EPIC dependencies (first EPIC in P005-C chain)

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design server directory layout and type contracts | — | — |
| 2 | backend | Execute cleanup and create server/ structure | architect | — |
| 3 | domain | Implement TypeScript type definitions | architect | — |
| 4 | backend | Implement shared parsers | domain | — |
| 5 | qa | Write and run unit tests for all parsers | backend | — |

## Hints

- expected_steps: 6
- complexity: medium
- notes: "Step 0 is the monorepo migration prerequisite"
