---
name: planner
description: Plan → EPIC → plan.json conversion — the deterministic two-script pipeline, the EPIC Steps table contract, and the two judgment calls the LLM owns
user_invocable: false
---

# Planner — Plan → EPIC → plan.json

**Skill:** planner
**Dependencies:** pipeline, plan-writing

---

## Purpose

The "Planner" is **not an intelligent agent** — it is a **deterministic two-script
pipeline** that turns a written Plan into an executable `plan.json`. All parsing,
dependency-graph construction, and cycle detection happen in bash. The LLM's job is
narrow and clear: (1) make sure the Plan is written in the format the scripts parse,
(2) validate the generated output is sensible, (3) interpret script errors for the PM.

The LLM never hand-generates `plan.json`. It runs the scripts and reviews their output.

---

## The pipeline (full chain)

```
Plan.md ──(aid-plan-to-epic.sh)──► EPIC.md ──(aid-epic-to-json.sh)──► plan.json
   ▲ written per plan-writing.md      ▲ Steps (Role Pipeline) table     ▲ steps/deps/
   │ (### Step N + AID Role + deps)   │                                 │ parallel_groups/gates
```

### Stage 1 — `aid-plan-to-epic.sh` (Plan.md → EPIC.md)

```bash
aid-plan-to-epic.sh \
  --plan <plan.md> --phase <N> --total <T> \
  --epic-template <path> --output-dir <path> --counter-yaml <path>
```

Reads the Plan's `### Step N:` subsections (written per `plan-writing.md` §Implementation
Steps) and **generates the EPIC's `## Steps (Role Pipeline)` table** — one row per step in
the phase. From each Plan step it extracts:

| EPIC table column | Source in the Plan step |
|---|---|
| `#` | a **phase-relative counter** (1, 2, 3… restarting each phase) — equals the `### Step N:` number for single-phase plans and for **phase 1** of any plan; from **phase 2 on** it restarts at 1 and diverges from the original numbering |
| `Role` | the `**AID Role:**` line (defaults to `backend` if absent) |
| `Objective` | the `**Objective:**` line (or the step-header text) |
| `Depends On` | the `**Dependencies:** → Depends on: Step X` line (cross-phase deps are stripped to the current phase) |
| `Parallel Group` | written as `---` (the generator does not auto-assign groups) |

**The Plan format is the contract.** If a Plan step omits `**AID Role:**` or writes
dependencies in some other shape, the table degrades (role falls back to `backend`,
deps may be lost). This is why `plan-writing.md` is a hard dependency of this skill.

> **Multi-phase caveat:** dependencies pointing OUTSIDE the current phase are stripped out
> entirely. What remains are the Plan's original (in-phase) step numbers — which still align
> with the phase-relative `#` in **phase 1**, but from **phase 2 on** can diverge (original
> numbers continue, `#` restarts at 1), so Stage 2 may fail to resolve them. Single-phase plans
> (`--total 1`) are always safe; for later phases, keep deps within the phase and watch the numbering.

### Stage 2 — `aid-epic-to-json.sh` (EPIC.md → plan.json)

```bash
aid-epic-to-json.sh \
  --epic <epic.md> --schema <plan.schema.json> --output-dir <path> \
  [--plan-source <plan.md>]
```

`--schema` is **required** — the script aborts if the schema file is missing, then runs a
hard-coded structural `jq` check (it does not validate against the passed schema field-by-field).
Reads the EPIC's `## Steps (Role Pipeline)` table and produces:

- **`plan.json`** — written into the run's evidence dir.
- **a JSON manifest on stdout** — `{ plan_json, run_id, evidence_dir }`.

It does **not** write `execution.yaml` or `run.md`. Those come later: `aid-json-to-run.sh`
writes `run.md` and initialises the FSM state (`fsm-state.yaml`); `execution.yaml` (the gates
config) is a separate `.aid-o/config/` file consumed by `aid-run-gates.sh`. See `pipeline.md` §2.

---

## Input: the EPIC Steps table

The unit `aid-epic-to-json.sh` parses is a markdown **table** in the
`## Steps (Role Pipeline)` section:

```markdown
## Steps (Role Pipeline)

| # | Role      | Objective                        | Depends On | Parallel Group |
|---|-----------|----------------------------------|------------|----------------|
| 1 | architect | Design API contracts + ADR       | ---        | ---            |
| 2 | domain    | Domain model + invariants        | 1          | ---            |
| 3 | backend   | Implement API + DB                | 2          | group-1        |
| 4 | frontend  | Implement UI against contracts   | 1          | group-1        |
| 5 | qa        | Integration tests                 | 3          | group-2        |
```

- **`Depends On`** references either a step **number** (`1`, `2`) **or a role name**
  (`architect`, `backend` — resolved to the **last** step with that role if several share it).
  Comma-separated for
  multiple (`1, 2`); `---` for none. Anything that resolves to neither → hard error.
- **`Parallel Group`** is a label (`group-1`) or `---`. Steps sharing a label are emitted
  as one `parallel_groups` entry (only groups of 2+). There is **no level/wave algorithm** —
  grouping is exactly what this column says.
- The script generates each step's ID as **`step_{N}_{role}`** from the `#` and `Role`
  columns.

---

## Output: plan.json

Full schema: `defaults/templates/plan.schema.json`. The script (Step 13) emits these
**top-level fields**: `epic_id, source_plan, version, created_at, steps, dependencies,
parallel_groups, analysis_groups, gates, budget`.

```json
{
  "epic_id": "E-019-1_3",
  "source_plan": ".aid-o/plans/P-019.md",
  "version": 1,
  "created_at": "2026-06-02T12:00:00Z",
  "steps": [
    { "id": "step_1_architect", "role": "architect",
      "objective": "Design API contracts + ADR",
      "inputs": ["EPIC specification"], "outputs": [], "constraints": [],
      "allowed_paths": ["contracts/", "docs/adr/"], "forbidden_paths": [],
      "acceptance_criteria": ["..."] }
  ],
  "dependencies": [ { "before": "step_1_architect", "after": "step_2_domain", "reason": "..." } ],
  "parallel_groups": [ ["step_3_backend", "step_4_frontend"] ],
  "analysis_groups": [],
  "gates": ["tests_pass", "lint_pass"],
  "budget": { "max_retries_per_gate": 3 }
}
```

- **A step object has:** `id, role, objective, inputs, outputs, constraints, allowed_paths,
  forbidden_paths, acceptance_criteria`. It has **no `depends_on`** (dependencies live in the
  top-level `dependencies[]` as `{before, after, reason}`) and **no `model`** field.
- **`model` is NOT in plan.json.** The script never reads `role-cards.md` or writes a model.
  The model is chosen at **dispatch time** (EXECUTE) by the controller from `skills/role-cards.md`
  per the step's `role` (see `pipeline.md` §4). `dispatch-config.yaml` no longer exists.
- **No `waves[]` field.** Ordering is derived at execution time from `dependencies`;
  parallelism is `parallel_groups`.
- **`analysis_groups`** are auto-generated read-only review groups (multiple agents review the
  SAME completed step from different angles — e.g. security/db/contract) — distinct from
  `parallel_groups` (different work in parallel). **`budget`** holds gate-retry limits
  (currently `{"max_retries_per_gate": 3}`) — not a token budget.

---

## What the scripts compute deterministically

1. Parse the table rows → `(num, role, objective, depends_on, parallel_group)`.
2. Generate step IDs `step_{N}_{role}`; resolve each `Depends On` token (number **or** role)
   → step IDs for `dependencies[]` (`{before, after, reason}`).
3. **Cycle detection — Kahn's topological sort.** If fewer nodes sort than exist, a cycle
   is reported with its member steps (hard error).
4. Emit `parallel_groups[]` (groups of 2+) directly from the `Parallel Group` column.
5. Extract per-step `inputs/outputs/constraints/allowed_paths/forbidden_paths/acceptance_criteria`
   from the EPIC's Scope / Acceptance Criteria / Artifacts / Constraints sections.
6. Auto-generate `analysis_groups[]` from built-in rules (security / db / contract / complexity
   reviews) and compute the `budget` block.

What it does **not** do: no level assignment, no wave reorganisation, no auto-splitting of runs,
no model assignment.

---

## The LLM's job (the only judgment calls)

1. **Before running:** confirm the EPIC has a `## Steps (Role Pipeline)` table with data
   rows and that roles are valid. If generating the EPIC from a Plan, ensure the Plan steps
   carry `**AID Role:**`, `**Objective:**`, and `**Dependencies:**` (per `plan-writing.md`).
2. **After running:** sanity-check the output the script cannot judge from syntax —
   dependencies that are *logically* wrong, or parallel steps (same `Parallel Group`) whose
   `allowed_paths` overlap (they would write the same files; flag to PM, do not run them
   in parallel).
3. **On error:** surface the script's message to the PM (see Error Handling).

---

## Run splitting

Multi-run EPICs are split **by the plan author**, written into the EPIC's
`## Run Breakdown` section (Run 1 / Run 2 …). **No script computes a split** and there is
no automatic "more than N steps" heuristic. If there is no `## Run Breakdown`, the EPIC
is a single run.

---

## Error Handling

| Script error | LLM action |
|---|---|
| Missing `## Steps (Role Pipeline)` section | EPIC is malformed — show the PM, fix EPIC generation |
| Steps table has no data rows | Same — the table header exists but no `\| N \| role \| …` rows |
| Missing `--epic` / `--schema` / `--output-dir` | Invocation bug — fix the call (these are required) |
| Schema file not found | The `--schema` path is wrong — point it at `plan.schema.json` |
| Invalid role (not in the role enum) | Show the bad role; correct the Plan/EPIC |
| Objective too short (< 10 chars) | Step objective fails schema check — write a real objective |
| No valid steps parsed | Table rows are malformed — check the `\| # \| role \| …` shape |
| Unresolvable dependency (number or role matches no step) | Show the bad `Depends On` token; correct the table |
| Circular dependency (Kahn) | Report the cycle members; ask PM to fix `Depends On` |
| EPIC ID could not be extracted | EPIC heading/frontmatter malformed — fix the EPIC title |
| `aid-plan-to-epic.sh`: missing step headers | Plan lacks `### Step N:` — fix per `plan-writing.md` |
| `aid-plan-to-epic.sh`: missing args / phase out of range | Stage-1 invocation bug — fix `--phase`/`--total` |

---

## Reference Files

- `skills/plan-writing.md` — **the Plan step format this pipeline consumes** (`### Step N:`,
  `**AID Role:**`, `**Objective:**`, `**Dependencies:**`)
- `commands/aid-plan.md` — `/aid-plan epic` invokes Stage 1 + Stage 2
- `{plugin_path}/scripts/aid-plan-to-epic.sh` — Stage 1 (Plan → EPIC)
- `{plugin_path}/scripts/aid-epic-to-json.sh` — Stage 2 (EPIC → plan.json)
- `{plugin_path}/scripts/aid-auto-pipeline.sh` — master orchestrator chaining both stages
- `defaults/templates/plan.schema.json` — full plan.json schema
- `skills/role-cards.md` — model tier per role
- `skills/pipeline.md` §2 — PRE-FLIGHT references this pipeline

---

**Last Updated:** 2026-06-03
