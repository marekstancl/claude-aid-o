<!--
  Fixture for parseStepsTable (EPIC E-047-2_7, Step 2).
  Steps table copied verbatim from .aid-o/tasks/E-047-2_7-aid-cockpit-mvp1.md
  ("Steps (Role Pipeline)") plus the archived E-047-1_7 table, which uses the
  "Parallel Group `---`" / "Depends On `---`" sentinel convention. The trailing
  ragged row exercises the "fewer than 3 cells -> skip without throwing" path.
-->

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Wire packages as a root npm-workspaces monorepo | --- | --- |
| 2 | backend | Establish the snake_case raw contract layer | 1 | --- |
| 3 | backend | Define the camelCase API-surface view types | 2 | core |
| 4 | backend | Define the Rev 3/4 managerial read-model types | 3 | core |
| 5 | backend | Define the canonical STATUS table and dictionary | 3 | — |
| 6 | backend | Reserve the MVP2 seam contracts | 3 | - |
| 7 | qa | Compile aid-contract with tsc and assert invariants | 4, 5, 6 | --- |
| 8 | backend | Multi-dep step with mixed separators | backend:2; frontend:3 |  |
| 9 | backend |
